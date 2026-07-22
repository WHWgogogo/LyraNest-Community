import { useState } from "react";
import type { Track } from "../api/types";
import type { SavedPlaylist } from "../utils/libraryState";
import {
  displayAlbum,
  displayArtist,
  displayGenres,
  formatBytes,
  formatDate,
  trackMetadataStatus,
} from "../utils/format";
import { AlbumArt } from "./AlbumArt";
import { Icon } from "./Icon";

interface TrackTableProps {
  tracks: Track[];
  currentTrackId?: string;
  isPlaying: boolean;
  favoriteTrackIds?: string[];
  playlists?: SavedPlaylist[];
  onPlay(track: Track, contextTracks?: Track[]): void;
  onLyrics(track: Track): void;
  onScrape(track: Track): void;
  onToggleFavorite?(track: Track): void;
  onEnqueue?(track: Track): void;
  onEnqueueNext?(track: Track): void;
  onAddToPlaylist?(track: Track, playlistId: string): void;
  onOpenAlbum?(track: Track): void;
  onOpenArtist?(track: Track): void;
}

export function TrackTable({
  tracks,
  currentTrackId,
  isPlaying,
  favoriteTrackIds = [],
  playlists = [],
  onPlay,
  onLyrics,
  onScrape,
  onToggleFavorite,
  onEnqueue,
  onEnqueueNext,
  onAddToPlaylist,
  onOpenAlbum,
  onOpenArtist,
}: TrackTableProps) {
  const [openMenuTrackId, setOpenMenuTrackId] = useState<string | null>(null);
  const favorites = new Set(favoriteTrackIds);

  function closeMenu() {
    setOpenMenuTrackId(null);
  }

  return (
    <div className="track-table-wrap">
      <table className="track-table">
        <thead>
          <tr>
            <th className="track-table__index">#</th>
            <th>曲目</th>
            <th>专辑</th>
            <th>文件</th>
            <th>元数据</th>
            <th>修改时间</th>
            <th>
              <span className="sr-only">操作</span>
            </th>
          </tr>
        </thead>
        <tbody>
          {tracks.map((track, index) => {
            const isCurrent = track.id === currentTrackId;
            const metadataStatus = trackMetadataStatus(track);
            return (
              <tr className={isCurrent ? "is-current" : ""} key={track.id}>
                <td className="track-table__index">
                  <button
                    aria-label={`${isCurrent && isPlaying ? "暂停" : "播放"} ${track.title}`}
                    className="row-play"
                    onClick={() => onPlay(track, tracks)}
                    type="button"
                  >
                    <span className="row-play__number">
                      {(index + 1).toString().padStart(2, "0")}
                    </span>
                    <Icon
                      name={isCurrent && isPlaying ? "pause" : "play"}
                      size={16}
                    />
                  </button>
                </td>
                <td>
                  <div className="track-cell">
                    <AlbumArt size="small" track={track} />
                    <div>
                      <strong>{track.title}</strong>
                      <span>{displayArtist(track)}</span>
                    </div>
                  </div>
                </td>
                <td>
                  <span className="table-primary">{displayAlbum(track)}</span>
                  <small>{displayGenres(track)}</small>
                </td>
                <td>
                  <span className="file-badge">
                    {track.extension.toUpperCase() || "音频"}
                  </span>
                  <small>{formatBytes(track.size_bytes)}</small>
                </td>
                <td className="metadata-status-cell">
                  <span
                    className={`metadata-status metadata-status--${metadataStatus.tone}`}
                    title={metadataStatus.title}
                  >
                    {metadataStatus.label}
                  </span>
                  <small
                    className="metadata-status__detail truncate"
                    title={metadataStatus.title ?? metadataStatus.detail}
                  >
                    {metadataStatus.detail}
                  </small>
                </td>
                <td>
                  <span className="table-primary">
                    {formatDate(track.modified)}
                  </span>
                  <small className="truncate" title={track.file_name}>
                    {track.file_name}
                  </small>
                </td>
                <td>
                  <div className="row-actions">
                    {onToggleFavorite && (
                      <button
                        aria-label={
                          favorites.has(track.id)
                            ? `取消收藏 ${track.title}`
                            : `收藏 ${track.title}`
                        }
                        className={`icon-button ${
                          favorites.has(track.id) ? "is-favorite" : ""
                        }`}
                        onClick={() => onToggleFavorite(track)}
                        title={favorites.has(track.id) ? "取消收藏" : "收藏"}
                        type="button"
                      >
                        <Icon
                          name={
                            favorites.has(track.id) ? "heartFilled" : "heart"
                          }
                          size={18}
                        />
                      </button>
                    )}
                    <button
                      aria-label={`查看 ${track.title} 的歌词`}
                      className="icon-button"
                      onClick={() => onLyrics(track)}
                      title="歌词"
                      type="button"
                    >
                      <Icon name="lyrics" size={18} />
                    </button>
                    <button
                      aria-label={`刮削 ${track.title} 的元数据`}
                      className="icon-button"
                      onClick={() => onScrape(track)}
                      title="刮削元数据"
                      type="button"
                    >
                      <Icon name="wand" size={18} />
                    </button>
                    <div className="track-menu-wrap">
                      <button
                        aria-expanded={openMenuTrackId === track.id}
                        aria-label={`打开 ${track.title} 的操作菜单`}
                        className="icon-button"
                        onClick={() =>
                          setOpenMenuTrackId((currentId) =>
                            currentId === track.id ? null : track.id,
                          )
                        }
                        title="更多操作"
                        type="button"
                      >
                        <Icon name="more" size={18} />
                      </button>
                      {openMenuTrackId === track.id && (
                        <div className="track-menu" role="menu">
                          <button
                            onClick={() => {
                              onPlay(track, tracks);
                              closeMenu();
                            }}
                            role="menuitem"
                            type="button"
                          >
                            <Icon name="play" size={16} />
                            立即播放
                          </button>
                          {onEnqueueNext && (
                            <button
                              onClick={() => {
                                onEnqueueNext(track);
                                closeMenu();
                              }}
                              role="menuitem"
                              type="button"
                            >
                              <Icon name="next" size={16} />
                              下一首播放
                            </button>
                          )}
                          {onEnqueue && (
                            <button
                              onClick={() => {
                                onEnqueue(track);
                                closeMenu();
                              }}
                              role="menuitem"
                              type="button"
                            >
                              <Icon name="queue" size={16} />
                              加入播放队列
                            </button>
                          )}
                          {onOpenAlbum && (
                            <button
                              onClick={() => {
                                onOpenAlbum(track);
                                closeMenu();
                              }}
                              role="menuitem"
                              type="button"
                            >
                              <Icon name="album" size={16} />
                              查看专辑
                            </button>
                          )}
                          {onOpenArtist && (
                            <button
                              onClick={() => {
                                onOpenArtist(track);
                                closeMenu();
                              }}
                              role="menuitem"
                              type="button"
                            >
                              <Icon name="artist" size={16} />
                              查看艺术家
                            </button>
                          )}
                          {onAddToPlaylist && playlists.length > 0 && (
                            <div className="track-menu__playlists">
                              <span>添加到歌单</span>
                              {playlists.map((playlist) => (
                                <button
                                  key={playlist.id}
                                  onClick={() => {
                                    onAddToPlaylist(track, playlist.id);
                                    closeMenu();
                                  }}
                                  role="menuitem"
                                  type="button"
                                >
                                  <Icon name="playlist" size={16} />
                                  {playlist.name}
                                </button>
                              ))}
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
