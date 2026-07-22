import {
  isPlayMode,
  type PlayMode,
} from "./playback";

export interface SavedPlaylist {
  id: string;
  name: string;
  trackIds: string[];
  createdAt: string;
}

export interface SavedQueue {
  trackIds: string[];
  currentIndex: number;
}

const FAVORITES_KEY = "harmony-music.favorites";
const PLAYLISTS_KEY = "harmony-music.playlists";
const PLAY_MODE_KEY = "harmony-music.play-mode";
const QUEUE_KEY = "harmony-music.queue";

function storage(): Storage | null {
  return typeof window === "undefined" ? null : window.localStorage;
}

function uniqueTrackIds(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return [...new Set(value.filter((item): item is string => typeof item === "string"))];
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

export function readFavoriteIds(): string[] {
  return uniqueTrackIds(readJson(FAVORITES_KEY));
}

export function saveFavoriteIds(trackIds: string[]) {
  writeJson(FAVORITES_KEY, uniqueTrackIds(trackIds));
}

export function readPlaylists(): SavedPlaylist[] {
  const saved = readJson(PLAYLISTS_KEY);
  if (!Array.isArray(saved)) {
    return [];
  }

  return saved.flatMap((item) => {
    if (
      !item ||
      typeof item !== "object" ||
      !("id" in item) ||
      !("name" in item) ||
      typeof item.id !== "string" ||
      typeof item.name !== "string"
    ) {
      return [];
    }
    return [
      {
        id: item.id,
        name: item.name,
        trackIds: uniqueTrackIds(
          "trackIds" in item ? item.trackIds : undefined,
        ),
        createdAt:
          "createdAt" in item && typeof item.createdAt === "string"
            ? item.createdAt
            : new Date(0).toISOString(),
      },
    ];
  });
}

export function savePlaylists(playlists: SavedPlaylist[]) {
  writeJson(PLAYLISTS_KEY, playlists);
}

export function readPlayMode(): PlayMode {
  const mode = storage()?.getItem(PLAY_MODE_KEY);
  return isPlayMode(mode) ? mode : "list-loop";
}

export function savePlayMode(mode: PlayMode) {
  storage()?.setItem(PLAY_MODE_KEY, mode);
}

export function readQueue(): SavedQueue {
  const saved = readJson(QUEUE_KEY);
  if (!saved || typeof saved !== "object") {
    return { trackIds: [], currentIndex: -1 };
  }
  const trackIds = uniqueTrackIds(
    "trackIds" in saved ? saved.trackIds : undefined,
  );
  const currentIndex =
    "currentIndex" in saved &&
    typeof saved.currentIndex === "number" &&
    Number.isInteger(saved.currentIndex) &&
    saved.currentIndex >= 0 &&
    saved.currentIndex < trackIds.length
      ? saved.currentIndex
      : -1;
  return { trackIds, currentIndex };
}

export function saveQueue(queue: SavedQueue) {
  const trackIds = uniqueTrackIds(queue.trackIds);
  writeJson(QUEUE_KEY, {
    trackIds,
    currentIndex:
      queue.currentIndex >= 0 && queue.currentIndex < trackIds.length
        ? queue.currentIndex
        : -1,
  });
}
