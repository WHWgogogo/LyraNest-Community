import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { MusicApi } from "../api/client";
import type {
  ListeningEventRequest,
  PlaybackEventType,
  Track,
} from "../api/types";
import {
  readPlayMode,
  readQueue,
  savePlayMode,
  saveQueue,
} from "../utils/libraryState";
import {
  getRelativeQueueIndex,
  nextPlayMode,
  type PlayMode,
} from "../utils/playback";
import {
  createListeningEvent,
  playbackDelta,
} from "../utils/listening";

interface UseAudioPlayerOptions {
  api: MusicApi;
  tracks: Track[];
  onError(message: string): void;
  onListeningEvent(event: ListeningEventRequest): void;
}

function uniqueTrackIds(tracks: Track[]): string[] {
  return [...new Set(tracks.map((track) => track.id))];
}

export function useAudioPlayer({
  api,
  tracks,
  onError,
  onListeningEvent,
}: UseAudioPlayerOptions) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const sourceUrlRef = useRef<string | null>(null);
  const streamRequestRef = useRef(0);
  const savedQueueRef = useRef(readQueue());
  const listeningTrackRef = useRef<Track | null>(null);
  const listenedSecondsRef = useRef(0);
  const lastPlaybackPositionRef = useRef<number | null>(null);
  const [currentTrack, setCurrentTrack] = useState<Track | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolumeState] = useState(0.82);
  const [muted, setMuted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [queueIds, setQueueIds] = useState<string[]>(
    savedQueueRef.current.trackIds,
  );
  const [queueIndex, setQueueIndex] = useState(
    savedQueueRef.current.currentIndex,
  );
  const [playMode, setPlayMode] = useState<PlayMode>(readPlayMode);

  const tracksById = useMemo(
    () => new Map(tracks.map((track) => [track.id, track])),
    [tracks],
  );
  const queue = useMemo(
    () =>
      queueIds.flatMap((trackId) => {
        const track = tracksById.get(trackId);
        return track ? [track] : [];
      }),
    [queueIds, tracksById],
  );

  useEffect(() => {
    saveQueue({ trackIds: queueIds, currentIndex: queueIndex });
  }, [queueIds, queueIndex]);

  useEffect(() => {
    savePlayMode(playMode);
  }, [playMode]);

  const resetListening = useCallback((track: Track, position = 0) => {
    listeningTrackRef.current = track;
    listenedSecondsRef.current = 0;
    lastPlaybackPositionRef.current = position;
  }, []);

  const accumulateListening = useCallback((position: number) => {
    const previousPosition = lastPlaybackPositionRef.current;
    if (previousPosition !== null) {
      listenedSecondsRef.current += playbackDelta(previousPosition, position);
    }
    lastPlaybackPositionRef.current = position;
  }, []);

  const flushListening = useCallback(
    (eventType: PlaybackEventType) => {
      const audio = audioRef.current;
      const track = listeningTrackRef.current;
      if (!track || !audio) {
        return;
      }
      accumulateListening(audio.currentTime);
      const event = createListeningEvent(
        track.id,
        eventType,
        listenedSecondsRef.current,
        audio.currentTime,
        Number.isFinite(audio.duration)
          ? audio.duration
          : track.duration_seconds,
      );
      if (event) {
        onListeningEvent(event);
      }
      listenedSecondsRef.current = 0;
      lastPlaybackPositionRef.current = audio.currentTime;
    },
    [accumulateListening, onListeningEvent],
  );

  const releaseAudioSource = useCallback(() => {
    const audio = audioRef.current;
    audio?.pause();
    audio?.removeAttribute("src");
    audio?.load();

    if (sourceUrlRef.current) {
      URL.revokeObjectURL(sourceUrlRef.current);
      sourceUrlRef.current = null;
    }
  }, []);

  useEffect(() => {
    streamRequestRef.current += 1;
    flushListening("skip");
    releaseAudioSource();
    listeningTrackRef.current = null;
    listenedSecondsRef.current = 0;
    lastPlaybackPositionRef.current = null;
    setCurrentTrack(null);
    setIsPlaying(false);
    setCurrentTime(0);
    setDuration(0);

    return () => {
      streamRequestRef.current += 1;
      flushListening("skip");
      releaseAudioSource();
    };
  }, [api, flushListening, releaseAudioSource]);

  useEffect(() => {
    if (audioRef.current) {
      audioRef.current.volume = volume;
      audioRef.current.muted = muted;
    }
  }, [muted, volume]);

  const startTrack = useCallback(
    async (track: Track) => {
      const audio = audioRef.current;
      if (!audio) {
        return;
      }

      if (currentTrack?.id !== track.id || !sourceUrlRef.current) {
        if (listeningTrackRef.current?.id !== track.id) {
          flushListening("skip");
          resetListening(track);
        }
        const requestId = streamRequestRef.current + 1;
        streamRequestRef.current = requestId;
        setCurrentTrack(track);
        setCurrentTime(0);
        setDuration(track.duration_seconds ?? 0);
        setLoading(true);
        try {
          const blob = await api.streamBlob(track.id);
          if (requestId !== streamRequestRef.current) {
            return;
          }

          const nextSource = URL.createObjectURL(blob);
          const previousSource = sourceUrlRef.current;
          sourceUrlRef.current = nextSource;
          audio.src = nextSource;
          audio.load();
          if (previousSource) {
            URL.revokeObjectURL(previousSource);
          }
        } catch (error) {
          if (requestId !== streamRequestRef.current) {
            return;
          }
          setLoading(false);
          setIsPlaying(false);
          onError(
            error instanceof Error
              ? error.message
              : "音频加载失败，请稍后重试",
          );
          return;
        }
      }

      setLoading(true);
      try {
        await audio.play();
      } catch {
        setIsPlaying(false);
        onError("浏览器未能开始播放，请重试或检查音频格式");
      } finally {
        setLoading(false);
      }
    },
    [api, currentTrack?.id, flushListening, onError, resetListening],
  );

  const playTrack = useCallback(
    async (track: Track, contextTracks?: Track[]) => {
      const nextQueueIds =
        contextTracks && contextTracks.length > 0
          ? uniqueTrackIds(contextTracks)
          : queueIds.includes(track.id)
            ? queueIds
            : [...queueIds, track.id];
      const nextIndex = nextQueueIds.indexOf(track.id);
      setQueueIds(nextQueueIds);
      setQueueIndex(nextIndex);
      await startTrack(track);
    },
    [queueIds, startTrack],
  );

  const playQueueIndex = useCallback(
    async (index: number) => {
      const trackId = queueIds[index];
      const track = trackId ? tracksById.get(trackId) : undefined;
      if (!track) {
        return;
      }
      setQueueIndex(index);
      await startTrack(track);
    },
    [queueIds, startTrack, tracksById],
  );

  const playRelative = useCallback(
    async (direction: 1 | -1) => {
      const nextIndex = getRelativeQueueIndex({
        queueLength: queueIds.length,
        currentIndex: queueIndex,
        mode: playMode,
        direction,
      });
      if (nextIndex !== null) {
        await playQueueIndex(nextIndex);
      }
    },
    [playMode, playQueueIndex, queueIds.length, queueIndex],
  );

  const togglePlayback = useCallback(async () => {
    const audio = audioRef.current;
    if (!audio) {
      return;
    }
    if (!currentTrack) {
      const initialIndex = getRelativeQueueIndex({
        queueLength: queueIds.length,
        currentIndex: queueIndex,
        mode: playMode,
      });
      if (initialIndex !== null) {
        await playQueueIndex(initialIndex);
      }
      return;
    }
    if (audio.paused) {
      try {
        setLoading(true);
        await audio.play();
      } catch {
        onError("无法继续播放，请检查服务器连接");
      } finally {
        setLoading(false);
      }
    } else {
      audio.pause();
    }
  }, [
    currentTrack,
    onError,
    playMode,
    playQueueIndex,
    queueIds.length,
    queueIndex,
  ]);

  const enqueue = useCallback((track: Track) => {
    setQueueIds((currentQueue) =>
      currentQueue.includes(track.id)
        ? currentQueue
        : [...currentQueue, track.id],
    );
  }, []);

  const enqueueNext = useCallback(
    (track: Track) => {
      const withoutTrack = queueIds.filter((id) => id !== track.id);
      const insertAt = Math.min(
        Math.max(queueIndex + 1, 0),
        withoutTrack.length,
      );
      const nextQueue = [
        ...withoutTrack.slice(0, insertAt),
        track.id,
        ...withoutTrack.slice(insertAt),
      ];
      setQueueIds(nextQueue);
      setQueueIndex(
        currentTrack
          ? nextQueue.indexOf(currentTrack.id)
          : queueIndex >= 0
            ? Math.min(queueIndex, nextQueue.length - 1)
            : -1,
      );
    },
    [currentTrack, queueIds, queueIndex],
  );

  const clearQueue = useCallback(() => {
    setQueueIds([]);
    setQueueIndex(-1);
  }, []);

  const seek = useCallback((nextTime: number) => {
    const audio = audioRef.current;
    if (!audio || !Number.isFinite(nextTime)) {
      return;
    }
    audio.currentTime = nextTime;
    setCurrentTime(nextTime);
  }, []);

  const setVolume = useCallback((nextVolume: number) => {
    const clamped = Math.max(0, Math.min(1, nextVolume));
    setVolumeState(clamped);
    setMuted(clamped === 0);
  }, []);

  const toggleMute = useCallback(() => {
    setMuted((value) => !value);
  }, []);

  return {
    audioRef,
    currentTrack,
    isPlaying,
    currentTime,
    duration,
    volume,
    muted,
    loading,
    queue,
    queueLength: queueIds.length,
    queueIndex,
    playMode,
    playTrack,
    togglePlayback,
    playPrevious: () => playRelative(-1),
    playNext: () => playRelative(1),
    enqueue,
    enqueueNext,
    clearQueue,
    cyclePlayMode: () => setPlayMode((mode) => nextPlayMode(mode)),
    seek,
    setVolume,
    toggleMute,
    audioElement: (
      <audio
        ref={audioRef}
        preload="metadata"
        onCanPlay={() => setLoading(false)}
        onDurationChange={(event) => {
          const nextDuration = event.currentTarget.duration;
          if (Number.isFinite(nextDuration)) {
            setDuration(nextDuration);
          }
        }}
        onEnded={() => {
          flushListening("completed");
          void playRelative(1);
        }}
        onError={() => {
          setLoading(false);
          setIsPlaying(false);
          onError("音频加载失败，曲目可能已移动或格式不受浏览器支持");
        }}
        onLoadStart={() => setLoading(true)}
        onPause={(event) => {
          if (!event.currentTarget.ended) {
            flushListening("pause");
          }
          setIsPlaying(false);
        }}
        onPlay={(event) => {
          lastPlaybackPositionRef.current = event.currentTarget.currentTime;
          setIsPlaying(true);
        }}
        onPlaying={() => setLoading(false)}
        onSeeking={(event) => {
          lastPlaybackPositionRef.current = event.currentTarget.currentTime;
        }}
        onTimeUpdate={(event) => {
          if (!event.currentTarget.paused) {
            accumulateListening(event.currentTarget.currentTime);
          }
          setCurrentTime(event.currentTarget.currentTime);
        }}
        onWaiting={() => setLoading(true)}
      />
    ),
  };
}
