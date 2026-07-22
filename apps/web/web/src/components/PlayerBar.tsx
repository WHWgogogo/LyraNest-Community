import type { CSSProperties } from "react";
import type { Track } from "../api/types";
import {
  displayAlbum,
  displayArtist,
  formatDuration,
} from "../utils/format";
import { AlbumArt } from "./AlbumArt";
import { Icon, type IconName } from "./Icon";
import { playModeLabels, type PlayMode } from "../utils/playback";

interface PlayerBarProps {
  track: Track | null;
  isPlaying: boolean;
  loading: boolean;
  currentTime: number;
  duration: number;
  volume: number;
  muted: boolean;
  onToggle(): void;
  onPrevious(): void;
  onNext(): void;
  onSeek(value: number): void;
  onVolume(value: number): void;
  onToggleMute(): void;
  onOpenLyrics(): void;
  playMode: PlayMode;
  queueLength: number;
  onCyclePlayMode(): void;
  onOpenQueue(): void;
}

const playModeIcons: Record<PlayMode, IconName> = {
  order: "order",
  "list-loop": "listLoop",
  "single-loop": "singleLoop",
  shuffle: "shuffle",
};

export function PlayerBar({
  track,
  isPlaying,
  loading,
  currentTime,
  duration,
  volume,
  muted,
  onToggle,
  onPrevious,
  onNext,
  onSeek,
  onVolume,
  onToggleMute,
  onOpenLyrics,
  playMode,
  queueLength,
  onCyclePlayMode,
  onOpenQueue,
}: PlayerBarProps) {
  const safeDuration = Number.isFinite(duration) ? duration : 0;
  const progress = safeDuration > 0 ? (currentTime / safeDuration) * 100 : 0;
  const progressStyle = { "--value": `${progress}%` } as CSSProperties;
  const volumeStyle = {
    "--value": `${(muted ? 0 : volume) * 100}%`,
  } as CSSProperties;

  return (
    <footer className={`player-bar ${track ? "has-track" : ""}`}>
      <div className="player-bar__track">
        <AlbumArt size="medium" track={track} />
        <div className="player-bar__meta">
          <strong>{track?.title ?? "选择一首音乐开始播放"}</strong>
          <span>
            {track
              ? `${displayArtist(track)} · ${displayAlbum(track)}`
              : "准备就绪，选择一首音乐开始播放"}
          </span>
        </div>
        <button
          aria-label={`打开播放队列，当前 ${queueLength} 首`}
          className="icon-button icon-button--subtle player-bar__queue"
          onClick={onOpenQueue}
          title={`播放队列（${queueLength} 首）`}
          type="button"
        >
          <Icon name="queue" />
        </button>
        <button
          aria-label="查看歌词"
          className="icon-button icon-button--subtle player-bar__lyrics"
          disabled={!track}
          onClick={onOpenLyrics}
          title="查看歌词"
          type="button"
        >
          <Icon name="lyrics" />
        </button>
      </div>

      <div className="player-bar__center">
        <div className="player-controls">
          <button
            aria-label={`切换播放模式，当前${playModeLabels[playMode]}`}
            className="icon-button icon-button--subtle"
            onClick={onCyclePlayMode}
            title={playModeLabels[playMode]}
            type="button"
          >
            <Icon name={playModeIcons[playMode]} />
          </button>
          <button
            aria-label="上一首"
            className="icon-button icon-button--subtle"
            disabled={queueLength === 0}
            onClick={onPrevious}
            type="button"
          >
            <Icon name="previous" />
          </button>
          <button
            aria-label={isPlaying ? "暂停" : "播放"}
            className={`play-button ${loading ? "is-loading" : ""}`}
            disabled={!track && queueLength === 0}
            onClick={onToggle}
            type="button"
          >
            {loading ? (
              <span className="spinner spinner--light" />
            ) : (
              <Icon name={isPlaying ? "pause" : "play"} size={22} />
            )}
          </button>
          <button
            aria-label="下一首"
            className="icon-button icon-button--subtle"
            disabled={queueLength === 0}
            onClick={onNext}
            type="button"
          >
            <Icon name="next" />
          </button>
        </div>
        <div className="progress-control">
          <span>{formatDuration(currentTime)}</span>
          <label className="range-track" style={progressStyle}>
            <span className="sr-only">播放进度</span>
            <input
              disabled={!track || safeDuration <= 0}
              max={safeDuration || 1}
              min="0"
              onChange={(event) => onSeek(Number(event.target.value))}
              step="0.1"
              type="range"
              value={Math.min(currentTime, safeDuration || 0)}
            />
          </label>
          <span>{formatDuration(safeDuration)}</span>
        </div>
      </div>

      <div className="player-bar__volume">
        <button
          aria-label={muted ? "取消静音" : "静音"}
          className="icon-button icon-button--subtle"
          onClick={onToggleMute}
          type="button"
        >
          <Icon name={muted || volume === 0 ? "volumeOff" : "volume"} />
        </button>
        <label
          className="range-track range-track--volume"
          style={volumeStyle}
        >
          <span className="sr-only">音量</span>
          <input
            max="1"
            min="0"
            onChange={(event) => onVolume(Number(event.target.value))}
            step="0.01"
            type="range"
            value={muted ? 0 : volume}
          />
        </label>
        <span>{Math.round((muted ? 0 : volume) * 100)}</span>
      </div>
    </footer>
  );
}
