import { useCallback, useEffect, useRef, useState } from "react";
import type { MusicApi } from "../api/client";
import type { CollectionsSnapshot, MusicCollection, Track } from "../api/types";
import {
  applyCollectionOperations,
  claimLegacyCollectionImport,
  collectionFavoriteTrackIds,
  collectionPlaylists,
  collectionsFromSnapshot,
  createDeleteOperation,
  createFavoriteOperation,
  createImportOperation,
  createPlaylistOperation,
  createPlaylistTrackOperation,
  markLegacyCollectionImportComplete,
  readCollectionCache,
  replaceCollectionId,
  writeCollectionCache,
  type CollectionCache,
  type CollectionOutboxOperation,
} from "../utils/collectionState";

interface UseCollectionsOptions {
  api: MusicApi;
  userKey?: string;
}

const RETRYABLE_OUTBOX_STATUSES = new Set([408, 409, 429]);

export function isRetryableCollectionOutboxError(error: unknown): boolean {
  if (!error || typeof error !== "object") {
    return true;
  }
  const status = (error as { status?: unknown }).status;
  if (typeof status !== "number" || !Number.isFinite(status)) {
    return true;
  }
  return (
    status < 400 ||
    status >= 500 ||
    RETRYABLE_OUTBOX_STATUSES.has(status)
  );
}

function makeLocalPlaylist(name: string): MusicCollection {
  return {
    id: `local-playlist-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
    kind: "playlist",
    name,
    track_ids: [],
    created_at: new Date().toISOString(),
  };
}

function applySnapshot(
  snapshot: CollectionsSnapshot,
  pending: CollectionOutboxOperation[],
): CollectionCache {
  return {
    revision: snapshot.revision,
    collections: applyCollectionOperations(
      collectionsFromSnapshot(snapshot),
      pending,
    ),
    pending,
  };
}

export function useCollections({ api, userKey }: UseCollectionsOptions) {
  const [collections, setCollections] = useState<MusicCollection[]>([]);
  const [syncing, setSyncing] = useState(false);
  const cacheRef = useRef<CollectionCache>({
    revision: 0,
    collections: [],
    pending: [],
  });
  const userKeyRef = useRef<string | undefined>(userKey);
  const flushingRef = useRef(false);

  const persist = useCallback(
    (cache: CollectionCache) => {
      cacheRef.current = cache;
      if (userKeyRef.current) {
        writeCollectionCache(userKeyRef.current, cache);
      }
      setCollections(cache.collections);
    },
    [],
  );

  const flushOutbox = useCallback(async () => {
    const activeUserKey = userKeyRef.current;
    if (!activeUserKey || flushingRef.current) {
      return;
    }
    flushingRef.current = true;
    setSyncing(true);

    try {
      while (userKeyRef.current === activeUserKey) {
        const operation = cacheRef.current.pending[0];
        if (!operation) {
          return;
        }

        try {
          let snapshot: CollectionsSnapshot;
          if (operation.type === "import") {
            snapshot = await api.importCollections(operation.payload);
          } else if (operation.type === "create") {
            snapshot = await api.createPlaylist({
              id: operation.playlist.id,
              name: operation.playlist.name,
            });
          } else if (operation.type === "favorite") {
            snapshot = operation.add
              ? await api.addFavorite(operation.trackId)
              : await api.removeFavorite(operation.trackId);
          } else if (operation.type === "rename") {
            snapshot = await api.updatePlaylist(
              operation.playlistId,
              operation.name,
            );
          } else if (operation.type === "playlist-track") {
            snapshot = operation.add
              ? await api.addPlaylistTrack(operation.playlistId, operation.trackId)
              : await api.removePlaylistTrack(
                  operation.playlistId,
                  operation.trackId,
                );
          } else {
            snapshot = await api.deletePlaylist(operation.collectionId);
          }

          if (userKeyRef.current !== activeUserKey) {
            return;
          }

          let nextCache = cacheRef.current;
          if (operation.type === "create") {
            const created = collectionsFromSnapshot(snapshot)
              .find((collection) => collection.id === operation.playlist.id);
            if (!created) {
              return;
            }
            nextCache = replaceCollectionId(
              cacheRef.current,
              operation.playlist.id,
              created,
            );
          }

          const pending = nextCache.pending.filter(
            (item) => item.id !== operation.id,
          );
          persist(applySnapshot(snapshot, pending));
          if (operation.type === "import") {
            markLegacyCollectionImportComplete(activeUserKey);
          }
        } catch (error) {
          if (
            userKeyRef.current !== activeUserKey ||
            isRetryableCollectionOutboxError(error)
          ) {
            return;
          }

          const pending = cacheRef.current.pending.filter(
            (item) => item.id !== operation.id,
          );
          try {
            const remote = await api.listCollections();
            if (userKeyRef.current !== activeUserKey) {
              return;
            }
            persist(applySnapshot(remote, pending));
          } catch {
            if (userKeyRef.current !== activeUserKey) {
              return;
            }
            persist({ ...cacheRef.current, pending });
          }
        }
      }
    } finally {
      flushingRef.current = false;
      if (userKeyRef.current === activeUserKey) {
        setSyncing(false);
      }
    }
  }, [api, persist]);

  const refresh = useCallback(async () => {
    const activeUserKey = userKeyRef.current;
    if (!activeUserKey) {
      return;
    }
    setSyncing(true);
    try {
      const remote = await api.listCollections();
      if (userKeyRef.current !== activeUserKey) {
        return;
      }
      persist(applySnapshot(remote, cacheRef.current.pending));
      await flushOutbox();
    } catch {
      // Cached state and the outbox remain available while the service is offline.
    } finally {
      if (userKeyRef.current === activeUserKey) {
        setSyncing(false);
      }
    }
  }, [api, flushOutbox, persist]);

  useEffect(() => {
    userKeyRef.current = userKey;
    flushingRef.current = false;
    if (!userKey) {
      cacheRef.current = { revision: 0, collections: [], pending: [] };
      setCollections([]);
      return;
    }

    const cache = readCollectionCache(userKey);
    const legacy = claimLegacyCollectionImport(userKey);
    const importOperation =
      legacy && !cache.pending.some((operation) => operation.type === "import")
        ? createImportOperation({ ...legacy, revision: cache.revision })
        : null;
    const nextCache =
      importOperation
        ? {
            ...cache,
            collections:
              cache.collections.length > 0
                ? cache.collections
                : applyCollectionOperations([], [importOperation]),
            pending: [...cache.pending, importOperation],
          }
        : cache;
    persist(nextCache);
    void refresh();
  }, [persist, refresh, userKey]);

  useEffect(() => {
    if (!userKey) {
      return;
    }
    const retry = () => void flushOutbox();
    window.addEventListener("online", retry);
    const timer = window.setInterval(retry, 30_000);
    return () => {
      window.removeEventListener("online", retry);
      window.clearInterval(timer);
    };
  }, [flushOutbox, userKey]);

  const toggleFavorite = useCallback(
    (track: Track) => {
      const add = !collectionFavoriteTrackIds(cacheRef.current.collections).includes(
        track.id,
      );
      const operation = createFavoriteOperation(track.id, add);
      persist({
        ...cacheRef.current,
        collections: applyCollectionOperations(cacheRef.current.collections, [
          operation,
        ]),
        pending: [...cacheRef.current.pending, operation],
      });
      void flushOutbox();
    },
    [flushOutbox, persist],
  );

  const createPlaylist = useCallback(
    (name: string) => {
      const trimmedName = name.trim();
      if (!trimmedName) {
        return false;
      }
      const playlist = makeLocalPlaylist(trimmedName);
      const operation = createPlaylistOperation(playlist);
      persist({
        ...cacheRef.current,
        collections: applyCollectionOperations(cacheRef.current.collections, [
          operation,
        ]),
        pending: [...cacheRef.current.pending, operation],
      });
      void flushOutbox();
      return true;
    },
    [flushOutbox, persist],
  );

  const addTrackToPlaylist = useCallback(
    (track: Track, playlistId: string) => {
      const playlist = cacheRef.current.collections.find(
        (collection) =>
          collection.id === playlistId && collection.kind === "playlist",
      );
      if (!playlist || playlist.track_ids.includes(track.id)) {
        return false;
      }
      const operation = createPlaylistTrackOperation(playlistId, track.id, true);
      persist({
        ...cacheRef.current,
        collections: applyCollectionOperations(cacheRef.current.collections, [
          operation,
        ]),
        pending: [...cacheRef.current.pending, operation],
      });
      void flushOutbox();
      return true;
    },
    [flushOutbox, persist],
  );

  const deletePlaylist = useCallback(
    (playlistId: string) => {
      const playlist = cacheRef.current.collections.find(
        (collection) =>
          collection.id === playlistId && collection.kind === "playlist",
      );
      if (!playlist) {
        return;
      }
      const operation = createDeleteOperation(playlistId);
      persist({
        ...cacheRef.current,
        collections: applyCollectionOperations(cacheRef.current.collections, [
          operation,
        ]),
        pending: [...cacheRef.current.pending, operation],
      });
      void flushOutbox();
    },
    [flushOutbox, persist],
  );

  return {
    collections,
    favoriteTrackIds: collectionFavoriteTrackIds(collections),
    playlists: collectionPlaylists(collections),
    pendingCount: cacheRef.current.pending.length,
    syncing,
    refresh,
    toggleFavorite,
    createPlaylist,
    addTrackToPlaylist,
    deletePlaylist,
  };
}
