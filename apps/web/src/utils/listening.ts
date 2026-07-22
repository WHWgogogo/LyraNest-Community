import type {
  ListeningEventRequest,
  PlaybackEventType,
} from "../api/types";

export const MAX_CONTIGUOUS_PLAYBACK_GAP_SECONDS = 12;

export function playbackDelta(
  previousPosition: number,
  nextPosition: number,
): number {
  if (
    !Number.isFinite(previousPosition) ||
    !Number.isFinite(nextPosition)
  ) {
    return 0;
  }
  const delta = nextPosition - previousPosition;
  return delta > 0 && delta <= MAX_CONTIGUOUS_PLAYBACK_GAP_SECONDS
    ? delta
    : 0;
}

export function createListeningEvent(
  trackId: string,
  eventType: PlaybackEventType,
  listenedSeconds: number,
  _positionSeconds: number,
  _durationSeconds?: number,
): ListeningEventRequest | null {
  const listenedMS = Math.floor(listenedSeconds * 1_000);
  if (!trackId || listenedMS < 1_000) {
    return null;
  }
  return {
    event_id: newListeningEventID(),
    track_id: trackId,
    listened_ms: listenedMS,
    completed: eventType === "completed",
    played_at: new Date().toISOString(),
  };
}

function newListeningEventID(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `web-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}
