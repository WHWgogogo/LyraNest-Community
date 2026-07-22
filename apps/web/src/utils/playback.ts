export const PLAY_MODES = [
  "order",
  "list-loop",
  "single-loop",
  "shuffle",
] as const;

export type PlayMode = (typeof PLAY_MODES)[number];

export const playModeLabels: Record<PlayMode, string> = {
  order: "顺序播放",
  "list-loop": "列表循环",
  "single-loop": "单曲循环",
  shuffle: "随机播放",
};

export function isPlayMode(value: unknown): value is PlayMode {
  return typeof value === "string" && PLAY_MODES.includes(value as PlayMode);
}

export function nextPlayMode(mode: PlayMode): PlayMode {
  const index = PLAY_MODES.indexOf(mode);
  return PLAY_MODES[(index + 1) % PLAY_MODES.length] ?? "order";
}

interface QueueIndexOptions {
  queueLength: number;
  currentIndex: number;
  mode: PlayMode;
  direction?: 1 | -1;
  random?: () => number;
}

export function getRelativeQueueIndex({
  queueLength,
  currentIndex,
  mode,
  direction = 1,
  random = Math.random,
}: QueueIndexOptions): number | null {
  if (queueLength <= 0) {
    return null;
  }

  const safeCurrentIndex =
    currentIndex >= 0 && currentIndex < queueLength
      ? currentIndex
      : direction > 0
        ? 0
        : queueLength - 1;

  if (mode === "single-loop") {
    return safeCurrentIndex;
  }

  if (mode === "shuffle") {
    if (queueLength === 1) {
      return safeCurrentIndex;
    }
    const offset = Math.floor(random() * (queueLength - 1)) + 1;
    return (safeCurrentIndex + offset) % queueLength;
  }

  const candidate = safeCurrentIndex + direction;
  if (candidate >= 0 && candidate < queueLength) {
    return candidate;
  }

  if (mode === "list-loop") {
    return direction > 0 ? 0 : queueLength - 1;
  }

  return null;
}
