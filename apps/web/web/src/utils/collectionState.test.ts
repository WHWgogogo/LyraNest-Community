import { afterEach, describe, expect, it, vi } from "vitest";
import {
  applyCollectionOperations,
  claimLegacyCollectionImport,
  collectionFavoriteTrackIds,
  collectionPlaylists,
  createDeleteOperation,
  createFavoriteOperation,
  createPlaylistOperation,
  createPlaylistTrackOperation,
  readCollectionCache,
  writeCollectionCache,
  type CollectionCache,
} from "./collectionState";

function createStorage(): Storage {
  const values = new Map<string, string>();
  return {
    get length() {
      return values.size;
    },
    clear: () => values.clear(),
    getItem: (key) => values.get(key) ?? null,
    key: (index) => [...values.keys()][index] ?? null,
    removeItem: (key) => values.delete(key),
    setItem: (key, value) => values.set(key, String(value)),
  };
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("scoped collection cache", () => {
  it("keeps collections and pending mutations isolated per account", () => {
    vi.stubGlobal("window", { localStorage: createStorage() });
    const cache: CollectionCache = {
      revision: 4,
      collections: [
        {
          id: "favorites",
          kind: "favorites",
          name: "我的收藏",
          track_ids: ["track-1"],
          created_at: "2026-07-20T00:00:00.000Z",
        },
      ],
      pending: [createFavoriteOperation("track-2", true)],
    };

    writeCollectionCache("user-a", cache);
    expect(readCollectionCache("user-a").collections).toEqual(cache.collections);
    expect(readCollectionCache("user-b")).toEqual({
      revision: 0,
      collections: [],
      pending: [],
    });
  });

  it("claims unscoped legacy data for only the first authenticated account", () => {
    vi.stubGlobal("window", { localStorage: createStorage() });
    window.localStorage.setItem(
      "harmony-music.favorites",
      JSON.stringify(["track-1"]),
    );
    window.localStorage.setItem(
      "harmony-music.playlists",
      JSON.stringify([
        {
          id: "playlist-1",
          name: "通勤",
          trackIds: ["track-2"],
          createdAt: "2026-07-20T00:00:00.000Z",
        },
      ]),
    );

    expect(claimLegacyCollectionImport("user-a")).toMatchObject({
      favorite_track_ids: ["track-1"],
      playlists: [{ name: "通勤", track_ids: ["track-2"] }],
    });
    expect(claimLegacyCollectionImport("user-b")).toBeNull();
  });

  it("projects pending personal-data operations onto cached collections", () => {
    const source: CollectionCache["collections"] = [
      {
        id: "favorites",
        kind: "favorites",
        name: "我的收藏",
        track_ids: ["track-1"],
        created_at: "2026-07-20T00:00:00.000Z",
      },
      {
        id: "playlist-1",
        kind: "playlist",
        name: "旧歌单",
        track_ids: ["track-1"],
        created_at: "2026-07-20T00:00:00.000Z",
      },
    ];
    const projected = applyCollectionOperations(source, [
      createFavoriteOperation("track-2", true),
      createPlaylistTrackOperation("playlist-1", "track-1", false),
      createDeleteOperation("playlist-1"),
    ]);

    expect(collectionFavoriteTrackIds(projected)).toEqual(["track-1", "track-2"]);
    expect(collectionPlaylists(projected)).toEqual([]);
  });

  it("persists a client playlist id for offline creation retries", () => {
    vi.stubGlobal("window", { localStorage: createStorage() });
    const create = createPlaylistOperation({
      id: "local-playlist-123",
      kind: "playlist",
      name: "通勤",
      track_ids: [],
      created_at: "2026-07-20T00:00:00.000Z",
    });

    writeCollectionCache("user-a", {
      revision: 0,
      collections: [],
      pending: [create],
    });

    expect(readCollectionCache("user-a").pending).toEqual([create]);
  });
});
