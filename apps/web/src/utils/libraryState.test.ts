import { afterEach, describe, expect, it, vi } from "vitest";
import {
  readFavoriteIds,
  readPlayMode,
  readPlaylists,
  readQueue,
  saveFavoriteIds,
  savePlayMode,
  savePlaylists,
  saveQueue,
} from "./libraryState";

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

describe("playback mode defaults", () => {
  it("uses list-loop when no mode is saved", () => {
    vi.stubGlobal("window", { localStorage: createStorage() });

    expect(readPlayMode()).toBe("list-loop");
  });
});

describe("曲库本地状态", () => {
  it("持久化收藏与歌单，并在读取时去重", () => {
    vi.stubGlobal("window", { localStorage: createStorage() });

    saveFavoriteIds(["track-1", "track-1", "track-2"]);
    savePlaylists([
      {
        id: "playlist-1",
        name: "通勤",
        trackIds: ["track-1", "track-1", "track-2"],
        createdAt: "2026-07-19T00:00:00.000Z",
      },
    ]);

    expect(readFavoriteIds()).toEqual(["track-1", "track-2"]);
    expect(readPlaylists()).toEqual([
      {
        id: "playlist-1",
        name: "通勤",
        trackIds: ["track-1", "track-2"],
        createdAt: "2026-07-19T00:00:00.000Z",
      },
    ]);
  });

  it("持久化播放模式与队列，并丢弃无效索引", () => {
    vi.stubGlobal("window", { localStorage: createStorage() });

    savePlayMode("shuffle");
    saveQueue({ trackIds: ["track-1", "track-2"], currentIndex: 1 });
    expect(readPlayMode()).toBe("shuffle");
    expect(readQueue()).toEqual({
      trackIds: ["track-1", "track-2"],
      currentIndex: 1,
    });

    window.localStorage.setItem(
      "harmony-music.queue",
      JSON.stringify({ trackIds: ["track-1"], currentIndex: 5 }),
    );
    window.localStorage.setItem("harmony-music.play-mode", "unknown");
    expect(readQueue()).toEqual({ trackIds: ["track-1"], currentIndex: -1 });
    expect(readPlayMode()).toBe("list-loop");
  });
});
