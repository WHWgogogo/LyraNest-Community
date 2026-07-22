import { useEffect, useMemo, useRef, useState, type Ref } from "react";
import { ApiError, friendlyError, type MusicApi } from "../api/client";
import type { LyricsResponse, Track } from "../api/types";
import { displayAlbum, displayArtist } from "../utils/format";
import {
  activeLyricIndex,
  parseLyrics,
  type LyricLine as ParsedLyricLine,
} from "../utils/lyrics";
import { AlbumArt } from "./AlbumArt";
import { Icon } from "./Icon";

interface LyricsDrawerProps {
  track: Track | null;
  api: MusicApi;
  playingTrackId?: string;
  currentTime: number;
  onClose(): void;
  onPlay(track: Track): void;
  onSeek(time: number): void;
}

type LyricsState =
  | { status: "loading" }
  | { status: "ready"; lyrics: LyricsResponse }
  | { status: "empty" }
  | { status: "error"; message: string };

interface LyricLineProps {
  line: ParsedLyricLine;
  active: boolean;
  onSeek(time: number): void;
  activeLineRef?: Ref<HTMLButtonElement>;
}

export function LyricLine({
  line,
  active,
  onSeek,
  activeLineRef,
}: LyricLineProps) {
  const className = `lyrics-line${active ? " is-active" : ""}`;

  if (line.time === null) {
    return <p className={className}>{line.text}</p>;
  }

  return (
    <button
      aria-label={`跳转到 ${line.time} 秒`}
      className={`${className} lyrics-line--timed`}
      onClick={() => onSeek(line.time!)}
      ref={active ? activeLineRef : undefined}
      type="button"
    >
      {line.text}
    </button>
  );
}

export function LyricsDrawer({
  track,
  api,
  playingTrackId,
  currentTime,
  onClose,
  onPlay,
  onSeek,
}: LyricsDrawerProps) {
  const [state, setState] = useState<LyricsState>({ status: "loading" });
  const activeLineRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!track) {
      return;
    }
    let cancelled = false;
    setState({ status: "loading" });

    api
      .lyrics(track.id)
      .then((lyrics) => {
        if (!cancelled) {
          setState(
            lyrics.content.trim()
              ? { status: "ready", lyrics }
              : { status: "empty" },
          );
        }
      })
      .catch((error: unknown) => {
        if (cancelled) {
          return;
        }
        if (error instanceof ApiError && error.status === 404) {
          setState({ status: "empty" });
          return;
        }
        setState({ status: "error", message: friendlyError(error) });
      });

    return () => {
      cancelled = true;
    };
  }, [api, track]);

  const lines = useMemo(
    () => (state.status === "ready" ? parseLyrics(state.lyrics.content) : []),
    [state],
  );
  const synced = lines.some((line) => line.time !== null);
  const activeIndex =
    track?.id === playingTrackId && synced
      ? activeLyricIndex(lines, currentTime)
      : -1;

  useEffect(() => {
    activeLineRef.current?.scrollIntoView({
      behavior: "smooth",
      block: "center",
    });
  }, [activeIndex]);

  if (!track) {
    return null;
  }

  return (
    <div className="drawer-backdrop" onMouseDown={onClose}>
      <aside
        aria-labelledby="lyrics-title"
        className="drawer lyrics-drawer"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="drawer__header">
          <div>
            <small>歌词</small>
            <h2 id="lyrics-title">正在阅读</h2>
          </div>
          <button
            aria-label="关闭歌词"
            className="icon-button"
            onClick={onClose}
            type="button"
          >
            <Icon name="close" />
          </button>
        </div>

        <div className="lyrics-hero">
          <AlbumArt size="large" track={track} />
          <div>
            <h3>{track.title}</h3>
            <p>{displayArtist(track)}</p>
            <span>{displayAlbum(track)}</span>
          </div>
          {track.id !== playingTrackId && (
            <button
              aria-label="播放此曲"
              className="play-button play-button--small"
              onClick={() => onPlay(track)}
              type="button"
            >
              <Icon name="play" size={18} />
            </button>
          )}
        </div>

        <div className="lyrics-content">
          {state.status === "loading" && (
            <div className="drawer-state">
              <span className="spinner" />
              <strong>正在读取歌词</strong>
              <p>支持 UTF-8、GB18030 与 GBK 侧车歌词。</p>
            </div>
          )}
          {state.status === "empty" && (
            <div className="drawer-state drawer-state--empty">
              <span className="empty-orbit">
                <Icon name="lyrics" size={30} />
              </span>
              <strong>暂无歌词</strong>
              <p>没有找到同名的 .lrc 或 .txt 文件，播放不会受到影响。</p>
            </div>
          )}
          {state.status === "error" && (
            <div className="drawer-state drawer-state--error">
              <span className="empty-orbit">
                <Icon name="alert" size={28} />
              </span>
              <strong>歌词读取失败</strong>
              <p>{state.message}</p>
            </div>
          )}
          {state.status === "ready" && (
            <>
              <div className="lyrics-content__meta">
                <span>{state.lyrics.encoding}</span>
                <span>{synced ? "同步歌词" : "纯文本歌词"}</span>
              </div>
              <div className={`lyrics-lines ${synced ? "is-synced" : ""}`}>
                {lines.map((line, index) => (
                  <LyricLine
                    active={index === activeIndex}
                    activeLineRef={activeLineRef}
                    key={line.id}
                    line={line}
                    onSeek={onSeek}
                  />
                ))}
              </div>
            </>
          )}
        </div>
      </aside>
    </div>
  );
}
