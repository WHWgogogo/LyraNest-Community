import type {
  CollectionsImportRequest,
  CollectionsSnapshot,
  MusicCollection,
} from "../api/types";
import { readFavoriteIds, readPlaylists } from "./libraryState";

const CACHE_PREFIX = "harmony-music.collections.cache";
const OUTBOX_PREFIX = "harmony-music.collections.outbox";
const LEGACY_OWNER_KEY = "harmony-music.collections.legacy-import-owner";
const LEGACY_IMPORTED_PREFIX = "harmony-music.collections.legacy-imported";
const DATABASE_NAME = "harmony-music-client";
const DATABASE_STORE = "collections";

export interface SavedPlaylist {
  id: string;
  name: string;
  trackIds: string[];
  createdAt: string;
}

export type CollectionOutboxOperation =
  | {
      id: string;
      type: "create";
      playlist: MusicCollection;
    }
  | {
      id: string;
      type: "favorite";
      trackId: string;
      add: boolean;
    }
  | {
      id: string;
      type: "rename";
      playlistId: string;
      name: string;
    }
  | {
      id: string;
      type: "playlist-track";
      playlistId: string;
      trackId: string;
      add: boolean;
    }
  | {
      id: string;
      type: "delete";
      collectionId: string;
    }
  | {
      id: string;
      type: "import";
      payload: CollectionsImportRequest;
    };

export interface CollectionCache {
  revision: number;
  collections: MusicCollection[];
  pending: CollectionOutboxOperation[];
}

function storage(): Storage | null {
  return typeof window === "undefined" ? null : window.localStorage;
}

function scopedKey(prefix: string, userKey: string): string {
  return `${prefix}:${encodeURIComponent(userKey)}`;
}

function readJson(key: string): unknown {
  const value = storage()?.getItem(key);
  if (!value) {
    return null;
  }
  try {
    return JSON.parse(value) as unknown;
  } catch {
    return null;
  }
}

function writeJson(key: string, value: unknown) {
  storage()?.setItem(key, JSON.stringify(value));
}

function uniqueTrackIds(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return Array.from(
    new Set(
      value
        .filter((item): item is string => typeof item === "string")
        .map((item) => item.trim())
        .filter(Boolean),
    ),
  );
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)
    : {};
}

function isCollectionKind(value: unknown): value is MusicCollection["kind"] {
  return value === "favorites" || value === "playlist";
}

function normalizeCollection(value: unknown): MusicCollection | null {
  const record = asRecord(value);
  const id = typeof record.id === "string" ? record.id : "";
  const kind = isCollectionKind(record.kind)
    ? record.kind
    : id === "favorites"
      ? "favorites"
      : "playlist";
  const name =
    typeof record.name === "string" && record.name.trim()
      ? record.name.trim()
      : kind === "favorites"
        ? "我的收藏"
        : "未命名歌单";
  if (!id) {
    return null;
  }
  return {
    id,
    kind,
    name,
    track_ids: uniqueTrackIds(record.track_ids ?? record.trackIds),
    created_at:
      typeof record.created_at === "string"
        ? record.created_at
        : typeof record.createdAt === "string"
          ? record.createdAt
          : new Date(0).toISOString(),
    updated_at:
      typeof record.updated_at === "string"
        ? record.updated_at
        : typeof record.updatedAt === "string"
          ? record.updatedAt
          : undefined,
  };
}

function normalizeOperation(value: unknown): CollectionOutboxOperation | null {
  const record = asRecord(value);
  const id = typeof record.id === "string" ? record.id : "";
  if (!id || typeof record.type !== "string") {
    return null;
  }
  if (record.type === "create") {
    const playlist = normalizeCollection(record.playlist ?? record.collection);
    return playlist && playlist.kind === "playlist"
      ? { id, type: "create", playlist }
      : null;
  }
  if (
    record.type === "favorite" &&
    typeof record.trackId === "string" &&
    typeof record.add === "boolean"
  ) {
    return {
      id,
      type: "favorite",
      trackId: record.trackId,
      add: record.add,
    };
  }
  if (
    record.type === "rename" &&
    typeof record.playlistId === "string" &&
    typeof record.name === "string" &&
    record.name.trim()
  ) {
    return {
      id,
      type: "rename",
      playlistId: record.playlistId,
      name: record.name.trim(),
    };
  }
  if (
    record.type === "playlist-track" &&
    typeof record.playlistId === "string" &&
    typeof record.trackId === "string" &&
    typeof record.add === "boolean"
  ) {
    return {
      id,
      type: "playlist-track",
      playlistId: record.playlistId,
      trackId: record.trackId,
      add: record.add,
    };
  }
  if (record.type === "delete" && typeof record.collectionId === "string") {
    return { id, type: "delete", collectionId: record.collectionId };
  }
  if (record.type === "import") {
    const payload = asRecord(record.payload);
    return {
      id,
      type: "import",
      payload: {
        revision:
          typeof payload.revision === "number" &&
          Number.isFinite(payload.revision)
            ? Math.max(0, Math.floor(payload.revision))
            : 0,
        favorite_track_ids: uniqueTrackIds(
          payload.favorite_track_ids ?? payload.favoriteTrackIds,
        ),
        playlists: Array.isArray(payload.playlists)
          ? payload.playlists.flatMap((playlist) => {
              const value = asRecord(playlist);
              const name =
                typeof value.name === "string" ? value.name.trim() : "";
              return name
                ? [
                    {
                      id: typeof value.id === "string" ? value.id : undefined,
                      name,
                      track_ids: uniqueTrackIds(
                        value.track_ids ?? value.trackIds,
                      ),
                      created_at:
                        typeof value.created_at === "string"
                          ? value.created_at
                          : typeof value.createdAt === "string"
                            ? value.createdAt
                            : undefined,
                      updated_at:
                        typeof value.updated_at === "string"
                          ? value.updated_at
                          : typeof value.updatedAt === "string"
                            ? value.updatedAt
                            : undefined,
                    },
                  ]
                : [];
            })
          : [],
      },
    };
  }
  return null;
}

function normalizeCollections(value: unknown): MusicCollection[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const seen = new Set<string>();
  return value.flatMap((item) => {
    const collection = normalizeCollection(item);
    if (!collection || seen.has(collection.id)) {
      return [];
    }
    seen.add(collection.id);
    return [collection];
  });
}

function normalizeOutbox(value: unknown): CollectionOutboxOperation[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.flatMap((item) => {
    const operation = normalizeOperation(item);
    return operation ? [operation] : [];
  });
}

function cloneCollection(collection: MusicCollection): MusicCollection {
  return { ...collection, track_ids: [...collection.track_ids] };
}

function mirrorCollectionCache(userKey: string, cache: CollectionCache) {
  if (
    typeof window === "undefined" ||
    typeof window.indexedDB === "undefined"
  ) {
    return;
  }

  const request = window.indexedDB.open(DATABASE_NAME, 1);
  request.onupgradeneeded = () => {
    const database = request.result;
    if (!database.objectStoreNames.contains(DATABASE_STORE)) {
      database.createObjectStore(DATABASE_STORE);
    }
  };
  request.onsuccess = () => {
    const database = request.result;
    const transaction = database.transaction(DATABASE_STORE, "readwrite");
    transaction.objectStore(DATABASE_STORE).put(cache, userKey);
    transaction.oncomplete = () => database.close();
    transaction.onerror = () => database.close();
  };
}

export function readCollectionCache(userKey: string): CollectionCache {
  const rawCache = asRecord(readJson(scopedKey(CACHE_PREFIX, userKey)));
  return {
    revision:
      typeof rawCache.revision === "number" && Number.isFinite(rawCache.revision)
        ? Math.max(0, Math.floor(rawCache.revision))
        : 0,
    collections: normalizeCollections(
      Array.isArray(rawCache.collections)
        ? rawCache.collections
        : readJson(scopedKey(CACHE_PREFIX, userKey)),
    ),
    pending: normalizeOutbox(readJson(scopedKey(OUTBOX_PREFIX, userKey))),
  };
}

export function writeCollectionCache(userKey: string, cache: CollectionCache) {
  const normalized: CollectionCache = {
    revision:
      Number.isFinite(cache.revision) && cache.revision > 0
        ? Math.floor(cache.revision)
        : 0,
    collections: normalizeCollections(cache.collections),
    pending: normalizeOutbox(cache.pending),
  };
  writeJson(scopedKey(CACHE_PREFIX, userKey), {
    revision: normalized.revision,
    collections: normalized.collections,
  });
  writeJson(scopedKey(OUTBOX_PREFIX, userKey), normalized.pending);
  mirrorCollectionCache(userKey, normalized);
}

export function createPlaylistOperation(
  playlist: MusicCollection,
): CollectionOutboxOperation {
  return {
    id: `collection-create-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
    type: "create",
    playlist: cloneCollection(playlist),
  };
}

export function createFavoriteOperation(
  trackId: string,
  add: boolean,
): CollectionOutboxOperation {
  return {
    id: `collection-favorite-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
    type: "favorite",
    trackId,
    add,
  };
}

export function createPlaylistTrackOperation(
  playlistId: string,
  trackId: string,
  add: boolean,
): CollectionOutboxOperation {
  return {
    id: `collection-playlist-track-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
    type: "playlist-track",
    playlistId,
    trackId,
    add,
  };
}

export function createDeleteOperation(
  collectionId: string,
): CollectionOutboxOperation {
  return {
    id: `collection-delete-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
    type: "delete",
    collectionId,
  };
}

export function createImportOperation(
  payload: CollectionsImportRequest,
): CollectionOutboxOperation {
  return {
    id: `collection-import-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
    type: "import",
    payload,
  };
}

export function applyCollectionOperations(
  source: MusicCollection[],
  operations: CollectionOutboxOperation[],
): MusicCollection[] {
  return operations.reduce<MusicCollection[]>((collections, operation) => {
    if (operation.type === "create") {
      return [
        ...collections.filter((collection) => collection.id !== operation.playlist.id),
        cloneCollection(operation.playlist),
      ];
    }
    if (operation.type === "delete") {
      return collections.filter(
        (collection) => collection.id !== operation.collectionId,
      );
    }
    if (operation.type === "favorite") {
      const favorite = collections.find(
        (collection) => collection.kind === "favorites",
      );
      const trackIds = favorite?.track_ids ?? [];
      const nextTrackIds = operation.add
        ? uniqueTrackIds([...trackIds, operation.trackId])
        : trackIds.filter((trackId) => trackId !== operation.trackId);
      if (favorite) {
        return collections.map((collection) =>
          collection.id === favorite.id
            ? { ...collection, track_ids: nextTrackIds }
            : collection,
        );
      }
      return operation.add
        ? [
            ...collections,
            {
              id: "favorites",
              kind: "favorites",
              name: "我的收藏",
              track_ids: nextTrackIds,
              created_at: new Date().toISOString(),
            },
          ]
        : collections;
    }
    if (operation.type === "rename") {
      return collections.map((collection) =>
        collection.id === operation.playlistId
          ? {
              ...collection,
              name: operation.name,
              updated_at: new Date().toISOString(),
            }
          : collection,
      );
    }
    if (operation.type === "playlist-track") {
      return collections.map((collection) => {
        if (collection.id !== operation.playlistId) {
          return collection;
        }
        const trackIds = operation.add
          ? uniqueTrackIds([...collection.track_ids, operation.trackId])
          : collection.track_ids.filter((trackId) => trackId !== operation.trackId);
        return {
          ...collection,
          track_ids: trackIds,
          updated_at: new Date().toISOString(),
        };
      });
    }
    const imported = collectionStateFromLegacy(operation.payload);
    const existingIds = new Set(collections.map((collection) => collection.id));
    return [
      ...collections,
      ...imported.filter((collection) => !existingIds.has(collection.id)),
    ];
  }, normalizeCollections(source));
}

export function collectionFavoriteTrackIds(
  collections: MusicCollection[],
): string[] {
  return uniqueTrackIds(
    collections.find((collection) => collection.kind === "favorites")?.track_ids,
  );
}

export function collectionPlaylists(
  collections: MusicCollection[],
): SavedPlaylist[] {
  return collections
    .filter((collection) => collection.kind === "playlist")
    .map((collection) => ({
      id: collection.id,
      name: collection.name,
      trackIds: [...collection.track_ids],
      createdAt: collection.created_at,
    }));
}

export function collectionsFromSnapshot(
  snapshot: CollectionsSnapshot,
): MusicCollection[] {
  const collections: MusicCollection[] = [];
  if (snapshot.favorite_track_ids.length > 0) {
    collections.push({
      id: "favorites",
      kind: "favorites",
      name: "我的收藏",
      track_ids: uniqueTrackIds(snapshot.favorite_track_ids),
      created_at: new Date(0).toISOString(),
    });
  }
  snapshot.playlists.forEach((playlist) => {
    collections.push({
      id: playlist.id,
      kind: "playlist",
      name: playlist.name,
      track_ids: uniqueTrackIds(playlist.track_ids),
      created_at: playlist.created_at,
      updated_at: playlist.updated_at,
    });
  });
  return collections;
}

export function collectionStateFromLegacy(
  payload: CollectionsImportRequest,
): MusicCollection[] {
  const collections: MusicCollection[] = [];
  if (payload.favorite_track_ids.length > 0) {
    collections.push({
      id: "favorites",
      kind: "favorites",
      name: "我的收藏",
      track_ids: [...payload.favorite_track_ids],
      created_at: new Date().toISOString(),
    });
  }
  payload.playlists.forEach((playlist, index) => {
    collections.push({
      id: playlist.id || `legacy-playlist-${index}`,
      kind: "playlist",
      name: playlist.name,
      track_ids: [...playlist.track_ids],
      created_at: playlist.created_at ?? new Date().toISOString(),
    });
  });
  return collections;
}

export function claimLegacyCollectionImport(
  userKey: string,
): CollectionsImportRequest | null {
  const currentOwner = storage()?.getItem(LEGACY_OWNER_KEY);
  const importedKey = scopedKey(LEGACY_IMPORTED_PREFIX, userKey);
  if (
    storage()?.getItem(importedKey) === "true" ||
    (currentOwner && currentOwner !== userKey)
  ) {
    return null;
  }

  const favorite_track_ids = readFavoriteIds();
  const playlists = readPlaylists().map((playlist) => ({
    id: playlist.id,
    name: playlist.name,
    track_ids: playlist.trackIds,
    created_at: playlist.createdAt,
  }));
  if (favorite_track_ids.length === 0 && playlists.length === 0) {
    return null;
  }

  storage()?.setItem(LEGACY_OWNER_KEY, userKey);
  return { revision: 0, favorite_track_ids, playlists };
}

export function markLegacyCollectionImportComplete(userKey: string) {
  storage()?.setItem(scopedKey(LEGACY_IMPORTED_PREFIX, userKey), "true");
}

export function replaceCollectionId(
  cache: CollectionCache,
  fromId: string,
  toCollection: MusicCollection,
): CollectionCache {
  const replaceId = (id: string) => (id === fromId ? toCollection.id : id);
  return {
    revision: cache.revision,
    collections: cache.collections.map((collection) =>
      collection.id === fromId ? cloneCollection(toCollection) : collection,
    ),
    pending: cache.pending.map((operation) => {
      if (operation.type === "create" && operation.playlist.id === fromId) {
        return {
          ...operation,
          playlist: cloneCollection(toCollection),
        };
      }
      if (
        (operation.type === "rename" ||
          operation.type === "playlist-track" ||
          operation.type === "delete") &&
        (operation.type === "delete"
          ? operation.collectionId
          : operation.playlistId) === fromId
      ) {
        return operation.type === "delete"
          ? { ...operation, collectionId: replaceId(operation.collectionId) }
          : { ...operation, playlistId: replaceId(operation.playlistId) };
      }
      return operation;
    }),
  };
}
