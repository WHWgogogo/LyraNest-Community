import type { DiscoveryResponse, RankedTrack, Track } from "../api/types";
import { displayAlbum, displayArtist } from "../utils/format";
import { AlbumArt } from "../components/AlbumArt";
import { Icon } from "../components/Icon";

interface DiscoveryPageProps {
  data: DiscoveryResponse | null;
  error: string | null;
  loading: boolean;
  search: string;
  searchResults: Track[];
  currentTrackId?: string;
  isPlaying: boolean;
  onSearch(value: string): void;
  onSubmitSearch(): void;
  onRefresh(): void;
  onPlay(track: Track, contextTracks: Track[]): void;
}

export function DiscoveryPage({
  data,
  error,
  loading,
  search,
  currentTrackId,
  isPlaying,
  onSearch,
  onSubmitSearch,
  searchResults,
  onRefresh,
  onPlay,
}: DiscoveryPageProps) {
  const hasSearch = Boolean(search.trim());
  return (
    <div className="discovery-page">
      <section className="discovery-hero">
        <div>
          <span className="eyebrow">DISCOVER</span>
          <h1>
            今天，想听
            <em>什么？</em>
          </h1>
          <p>从你的聆听记录和曲库出发，发现下一首值得播放的音乐。</p>
        </div>
        <form
          className="discovery-search"
          onSubmit={(event) => {
            event.preventDefault();
            onSubmitSearch();
          }}
        >
          <Icon name="search" size={20} />
          <input
            aria-label="搜索发现内容"
            onChange={(event) => onSearch(event.target.value)}
            placeholder="搜索曲目、艺术家或专辑"
            type="search"
            value={search}
          />
          {hasSearch && (
            <button
              aria-label="清除搜索"
              className="icon-button icon-button--subtle"
              onClick={() => onSearch("")}
              type="button"
            >
              <Icon name="close" size={17} />
            </button>
          )}
          <button className="button button--primary button--compact" type="submit">
            搜索
          </button>
        </form>
      </section>

      {error && (
        <div className="inline-error">
          <Icon name="alert" />
          <div>
            <strong>发现内容加载失败</strong>
            <span>{error}</span>
          </div>
          <button
            className="button button--secondary button--compact"
            onClick={onRefresh}
            type="button"
          >
            重试
          </button>
        </div>
      )}

      {!error && loading && !data && <DiscoverySkeleton />}

      {!error && data && (
        <>
          {hasSearch && (
            <TrackShelf
              currentTrackId={currentTrackId}
              isPlaying={isPlaying}
              onPlay={onPlay}
              title={`“${search.trim()}”的搜索结果`}
              tracks={searchResults}
            />
          )}

          <TrackShelf
            currentTrackId={currentTrackId}
            description="根据你收藏、歌单和真实聆听记录整理。"
            isPlaying={isPlaying}
            onPlay={onPlay}
            title="猜你喜欢"
            tracks={data.for_you}
          />

          <TrackShelf
            currentTrackId={currentTrackId}
            description="今天的 30 首音乐，适合从第一首开始播放。"
            isPlaying={isPlaying}
            limit={30}
            onPlay={onPlay}
            title="每日 30 首"
            tracks={data.daily}
          />

          <RankedTrackShelf
            currentTrackId={currentTrackId}
            description="曲库中的热门选择。"
            isPlaying={isPlaying}
            onPlay={onPlay}
            title="排行榜"
            tracks={data.hot_tracks}
          />

          <TrackShelf
            currentTrackId={currentTrackId}
            description="从最近实际听过的音乐继续探索。"
            isPlaying={isPlaying}
            onPlay={onPlay}
            title="最近听歌推荐"
            tracks={data.recent_recommendations}
          />
        </>
      )}
    </div>
  );
}

function RankedTrackShelf({
  title,
  description,
  tracks,
  currentTrackId,
  isPlaying,
  onPlay,
}: {
  title: string;
  description?: string;
  tracks: RankedTrack[];
  currentTrackId?: string;
  isPlaying: boolean;
  onPlay(track: Track, contextTracks: Track[]): void;
}) {
  const contextTracks = tracks.map((item) => item.track);
  return (
    <section className="discovery-section">
      <div className="section-heading">
        <div>
          <h2>{title}</h2>
          {description && <p>{description}</p>}
        </div>
        <span className="section-count">{tracks.length} 首</span>
      </div>
      {tracks.length > 0 ? (
        <div className="discovery-track-grid">
          {tracks.slice(0, 8).map((item, index) => {
            const current = item.track.id === currentTrackId;
            return (
              <button
                className={`discovery-track ${current ? "is-current" : ""}`}
                key={item.track.id}
                onClick={() => onPlay(item.track, contextTracks)}
                type="button"
              >
                <span className="discovery-track__rank">{index + 1}</span>
                <AlbumArt size="medium" track={item.track} />
                <span className="discovery-track__meta">
                  <strong>{item.track.title}</strong>
                  <small>{displayArtist(item.track)}</small>
                  <em>{item.play_count} 次播放</em>
                </span>
                <span className="discovery-track__play">
                  <Icon name={current && isPlaying ? "pause" : "play"} size={17} />
                </span>
              </button>
            );
          })}
        </div>
      ) : (
        <div className="discovery-empty">暂无热门排行，开始听歌后会逐步生成。</div>
      )}
    </section>
  );
}

function TrackShelf({
  title,
  description,
  tracks,
  currentTrackId,
  isPlaying,
  onPlay,
  limit = 8,
}: {
  title: string;
  description?: string;
  tracks: Track[];
  currentTrackId?: string;
  isPlaying: boolean;
  onPlay(track: Track, contextTracks: Track[]): void;
  limit?: number;
}) {
  const visibleTracks = tracks.slice(0, limit);
  return (
    <section className="discovery-section">
      <div className="section-heading">
        <div>
          <h2>{title}</h2>
          {description && <p>{description}</p>}
        </div>
        <span className="section-count">{tracks.length} 首</span>
      </div>
      {visibleTracks.length > 0 ? (
        <div className="discovery-track-grid">
          {visibleTracks.map((track, index) => {
            const current = track.id === currentTrackId;
            return (
              <button
                className={`discovery-track ${current ? "is-current" : ""}`}
                key={track.id}
                onClick={() => onPlay(track, tracks)}
                type="button"
              >
                <AlbumArt size="medium" track={track} />
                <span className="discovery-track__meta">
                  <strong>{track.title}</strong>
                  <small>{displayArtist(track)}</small>
                  <em>{displayAlbum(track)}</em>
                </span>
                <span className="discovery-track__play">
                  <Icon name={current && isPlaying ? "pause" : "play"} size={17} />
                </span>
              </button>
            );
          })}
        </div>
      ) : (
        <div className="discovery-empty">
          暂无可展示的曲目，播放更多音乐后会逐步丰富。
        </div>
      )}
    </section>
  );
}

function DiscoverySkeleton() {
  return (
    <div className="discovery-skeleton" aria-label="正在加载发现内容">
      {Array.from({ length: 5 }, (_, index) => (
        <span key={index} />
      ))}
    </div>
  );
}
