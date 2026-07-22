import { useCallback, useEffect, useRef } from "react";
import type { MusicApi } from "../api/client";
import type { ListeningEventRequest } from "../api/types";

const MAX_EVENT_BATCH_SIZE = 50;
const OUTBOX_PREFIX = "harmony-music.listening.outbox";

function storage(): Storage | null {
  return typeof window === "undefined" ? null : window.localStorage;
}

function outboxKey(userKey: string): string {
  return `${OUTBOX_PREFIX}:${encodeURIComponent(userKey)}`;
}

function normalizeEvents(value: unknown): ListeningEventRequest[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.flatMap((item) => {
    if (!item || typeof item !== "object") {
      return [];
    }
    const event = item as Partial<ListeningEventRequest>;
    if (
      typeof event.event_id !== "string" ||
      !event.event_id ||
      typeof event.track_id !== "string" ||
      !event.track_id ||
      typeof event.listened_ms !== "number" ||
      !Number.isFinite(event.listened_ms) ||
      event.listened_ms <= 0 ||
      typeof event.completed !== "boolean" ||
      typeof event.played_at !== "string"
    ) {
      return [];
    }
    return [
      {
        event_id: event.event_id,
        track_id: event.track_id,
        listened_ms: Math.floor(event.listened_ms),
        completed: event.completed,
        played_at: event.played_at,
      },
    ];
  });
}

function readOutbox(userKey: string): ListeningEventRequest[] {
  const raw = storage()?.getItem(outboxKey(userKey));
  if (!raw) {
    return [];
  }
  try {
    return normalizeEvents(JSON.parse(raw) as unknown);
  } catch {
    return [];
  }
}

function writeOutbox(userKey: string, events: ListeningEventRequest[]) {
  storage()?.setItem(outboxKey(userKey), JSON.stringify(events));
}

interface UseListeningEventsOptions {
  api: MusicApi;
  userKey?: string;
}

export function useListeningEvents({
  api,
  userKey,
}: UseListeningEventsOptions) {
  const userKeyRef = useRef<string | undefined>(userKey);
  const eventsRef = useRef<ListeningEventRequest[]>([]);
  const flushingRef = useRef(false);

  const flush = useCallback(async () => {
    const activeUserKey = userKeyRef.current;
    if (!activeUserKey || flushingRef.current) {
      return;
    }
    flushingRef.current = true;
    try {
      while (userKeyRef.current === activeUserKey) {
        const batch = eventsRef.current.slice(0, MAX_EVENT_BATCH_SIZE);
        if (batch.length === 0) {
          return;
        }
        try {
          await api.recordListeningEvents(batch);
        } catch {
          return;
        }
        if (userKeyRef.current !== activeUserKey) {
          return;
        }
        eventsRef.current = eventsRef.current.slice(batch.length);
        writeOutbox(activeUserKey, eventsRef.current);
      }
    } finally {
      flushingRef.current = false;
    }
  }, [api]);

  useEffect(() => {
    userKeyRef.current = userKey;
    eventsRef.current = userKey ? readOutbox(userKey) : [];
    if (userKey) {
      void flush();
    }
  }, [flush, userKey]);

  useEffect(() => {
    if (!userKey) {
      return;
    }
    const retry = () => void flush();
    window.addEventListener("online", retry);
    const timer = window.setInterval(retry, 30_000);
    return () => {
      window.removeEventListener("online", retry);
      window.clearInterval(timer);
    };
  }, [flush, userKey]);

  const record = useCallback(
    (event: ListeningEventRequest) => {
      const activeUserKey = userKeyRef.current;
      if (!activeUserKey) {
        return;
      }
      eventsRef.current = [...eventsRef.current, event];
      writeOutbox(activeUserKey, eventsRef.current);
      void flush();
    },
    [flush],
  );

  return { record, flush };
}
