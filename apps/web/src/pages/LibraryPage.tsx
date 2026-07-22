import { useMemo, useState } from "react";
import type { Track } from "../api/types";
import type { SavedPlaylist } from "../utils/libraryState";
import { displayAlbum, displayArtist, formatBytes } from "../utils/format";
import { AlbumArt } from "../components/AlbumArt";
import { Icon } from "../components/Icon";
import { TrackTable } from "../components/TrackTable";

export type TrackSort =
  | "title-asc"
  | "artist-asc"
  | "modified-desc"
  | "size-desc";

export type LibrarySection =
  | "all"
  | "favorites"
  | "playlists"
  | "albums"
  | "artists"
  | "queue";

interface LibraryPageProps {
  tracks: Track[];
  filteredTracks: Track[];
  loading: boolean;
  error: string | null;
  search: string;
  sort: TrackSort;
  currentTrackId?: string;
  isPlaying: boolean;
  activeSection: LibrarySection;
  favoriteTrackIds: string[];
  playlists: SavedPlaylist[];
  queue: Track[];
  queueLength: number;
  onSearch(value: string): void;
  onSort(value: TrackSort): void;
  onRefresh(): void;
  onSectionChange(section: LibrarySection): void;
  onPlay(track: Track, contextTracks?: Track[]): void;
  onLyrics(track: Track): void;
  onScrape(track: Track): void;
  onToggleFavorite(track: Track): void;
  onEnqueue(track: Track): void;
  onEnqueueNext(track: Track): void;
  onAddToPlaylist(track: Track, playlistId: string): void;
  onCreatePlaylist(name: string): void;
  onDeletePlaylist(playlistId: string): void;
  onClearQueue(): void;
}

interface Collection {
  name: string;
  tracks: Track[];
}

const librarySections: Array<{
  id: LibrarySection;
  label: string;
  icon: "library" | "heart" | "playlist" | "album" | "artist" | "queue";
}> = [
  { id: "all", label: "全部音乐", icon: "library" },
  { id: "favorites", label: "我的收藏", icon: "heart" },
  { id: "playlists", label: "歌单", icon: "playlist" },
  { id: "albums", label: "专辑", icon: "album" },
  { id: "artists", label: "艺术家", icon: "artist" },
  { id: "queue", label: "播放队列", icon: "queue" },
];

function groupTracks(
  tracks: Track[],
  label: (track: Track) => string,
): Collection[] {
  const groups = new Map<string, Track[]>();
  tracks.forEach((track) => {
    const name = label(track);
    groups.set(name, [...(groups.get(name) ?? []), track]);
  });
  return [...groups.entries()]
    .map(([name, groupedTracks]) => ({ name, tracks: groupedTracks }))
    .sort((left, right) => left.name.localeCompare(right.name, "zh-CN"));
}

export function LibraryPage({
  tracks,
  filteredTracks,
  loading,
  error,
  search,
  sort,
  currentTrackId,
  isPlaying,
  activeSection,
  favoriteTrackIds,
  playlists,
  queue,
  queueLength,
  onSearch,
  onSort,
  onRefresh,
  onSectionChange,
  onPlay,
  onLyrics,
  onScrape,
  onToggleFavorite,
  onEnqueue,
  onEnqueueNext,
  onAddToPlaylist,
  onCreatePlaylist,
  onDeletePlaylist,
  onClearQueue,
}: LibraryPageProps) {
  const [selectedPlaylistId, setSelectedPlaylistId] = useState<string | null>(
    null,
  );
  const [selectedAlbum, setSelectedAlbum] = useState<string | null>(null);
  const [selectedArtist, setSelectedArtist] = useState<string | null>(null);
  const [playlistName, setPlaylistName] = useState("");
  const favoriteIds = new Set(favoriteTrackIds);
  const tracksById = useMemo(
    () => new Map(tracks.map((track) => [track.id, track])),
    [tracks],
  );
  const favoriteTracks = filteredTracks.filter((track) =>
    favoriteIds.has(track.id),
  );
  const albums = useMemo(
    () => groupTracks(tracks, displayAlbum),
    [tracks],
  );
  const artists = useMemo(
    () => groupTracks(tracks, displayArtist),
    [tracks],
  );
  const selectedPlaylist =
    playlists.find((playlist) => playlist.id === selectedPlaylistId) ?? null;
  const selectedPlaylistTracks = selectedPlaylist
    ? selectedPlaylist.trackIds.flatMap((trackId) => {
        const track = tracksById.get(trackId);
        return track ? [track] : [];
      })
    : [];
  const selectedAlbumTracks = selectedAlbum
    ? tracks.filter((track) => displayAlbum(track) === selectedAlbum)
    : [];
  const selectedArtistTracks = selectedArtist
    ? tracks.filter((track) => displayArtist(track) === selectedArtist)
    : [];
  const artistCount = new Set(
    tracks.map((track) => track.artist?.trim()).filter(Boolean),
  ).size;
  const formatCount = new Set(
    tracks.map((track) => track.extension).filter(Boolean),
  ).size;
  const totalSize = tracks.reduce((sum, track) => sum + track.size_bytes, 0);

  const table = (tableTracks: Track[]) => (
    <TrackTable
      currentTrackId={currentTrackId}
      favoriteTrackIds={favoriteTrackIds}
      isPlaying={isPlaying}
      onAddToPlaylist={onAddToPlaylist}
      onEnqueue={onEnqueue}
      onEnqueueNext={onEnqueueNext}
      onLyrics={onLyrics}
      onOpenAlbum={(track) => {
        setSelectedAlbum(displayAlbum(track));
        onSectionChange("albums");
      }}
      onOpenArtist={(track) => {
        setSelectedArtist(displayArtist(track));
        onSectionChange("artists");
      }}
      onPlay={onPlay}
      onScrape={onScrape}
      onToggleFavorite={onToggleFavorite}
      playlists={playlists}
      tracks={tableTracks}
    />
  );

  function openPlaylist(playlistId: string) {
    setSelectedPlaylistId(playlistId);
    onSectionChange("playlists");
  }

  function showAllTracks() {
    if (error || filteredTracks.length === 0) {
      return null;
    }
    return table(filteredTracks);
  }

  function renderAllTracks() {
    return (
      <>
        <div className="section-heading">
          <div>
            <span className="eyebrow">全部曲目</span>
            <h2>全部音乐</h2>
          </div>
          <span className="section-count">
            {search ? `${filteredTracks.length} 个匹配` : `${tracks.length} 首`}
          </span>
        </div>

        <div className="library-toolbar">
          <label className="search-box">
            <Icon name="search" size={19} />
            <span className="sr-only">搜索曲库</span>
            <input
              onChange={(event) => onSearch(event.target.value)}
              placeholder="搜索标题、艺术家、专辑或文件名…"
              type="search"
              value={search}
            />
            {search && (
              <button
                aria-label="清除搜索"
                onClick={() => onSearch("")}
                type="button"
              >
                <Icon name="close" size={16} />
              </button>
            )}
          </label>
          <label className="sort-select">
            <span>排序</span>
            <select
              onChange={(event) => onSort(event.target.value as TrackSort)}
              value={sort}
            >
              <option value="title-asc">标题 A–Z</option>
              <option value="artist-asc">艺术家 A–Z</option>
              <option value="modified-desc">最近修改</option>
              <option value="size-desc">文件大小</option>
            </select>
          </label>
          <button
            aria-label="刷新曲库"
            className="icon-button toolbar-refresh"
            disabled={loading}
            onClick={onRefresh}
            title="刷新"
            type="button"
          >
            <Icon className={loading ? "spin" : ""} name="refresh" />
          </button>
        </div>

        {error && (
          <div className="inline-error">
            <Icon name="alert" />
            <div>
              <strong>曲库加载失败</strong>
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

        {!error && loading && tracks.length === 0 && (
          <div className="table-skeleton" aria-label="正在加载曲库">
            {Array.from({ length: 6 }, (_, index) => (
              <span key={index} />
            ))}
          </div>
        )}

        {!error && !loading && tracks.length === 0 && (
          <EmptyState
            icon="music"
            title="曲库还是空的"
            description="在服务器挂载音乐目录后执行扫描，曲目会出现在这里。"
          />
        )}

        {!error &&
          tracks.length > 0 &&
          filteredTracks.length === 0 &&
          search && (
            <EmptyState
              icon="search"
              title={`没有找到“${search}”`}
              description="试试艺术家、专辑名或文件扩展名。"
            />
          )}

        {showAllTracks()}
      </>
    );
  }

  function renderFavorites() {
    return (
      <CollectionSection
        count={favoriteTracks.length}
        eyebrow="我的音乐"
        title="我的收藏"
        description="收藏会同步到当前账号；离线时会安全保存在本机并在恢复连接后重试。"
      >
        {favoriteTracks.length > 0 ? (
          table(favoriteTracks)
        ) : (
          <EmptyState
            icon="heart"
            title="还没有收藏"
            description="在曲目右侧点亮爱心，把常听的音乐收进这里。"
          />
        )}
      </CollectionSection>
    );
  }

  function renderPlaylists() {
    if (selectedPlaylist) {
      return (
        <CollectionSection
          actions={
            <button
              className="button button--secondary button--compact"
              onClick={() => setSelectedPlaylistId(null)}
              type="button"
            >
              返回歌单
            </button>
          }
          count={selectedPlaylistTracks.length}
          eyebrow="歌单详情"
          title={selectedPlaylist.name}
          description="曲目顺序会作为播放队列顺序。"
        >
          <div className="collection-detail__actions">
            <button
              className="button button--primary"
              disabled={selectedPlaylistTracks.length === 0}
              onClick={() => {
                const firstTrack = selectedPlaylistTracks[0];
                if (firstTrack) {
                  onPlay(firstTrack, selectedPlaylistTracks);
                }
              }}
              type="button"
            >
              <Icon name="play" size={17} />
              播放歌单
            </button>
            <button
              className="button button--secondary"
              onClick={() => {
                onDeletePlaylist(selectedPlaylist.id);
                setSelectedPlaylistId(null);
              }}
              type="button"
            >
              <Icon name="trash" size={17} />
              删除歌单
            </button>
          </div>
          {selectedPlaylistTracks.length > 0 ? (
            table(selectedPlaylistTracks)
          ) : (
            <EmptyState
              icon="playlist"
              title="歌单还是空的"
              description="从曲目操作菜单中选择“添加到歌单”。"
            />
          )}
        </CollectionSection>
      );
    }

    return (
      <CollectionSection
        count={playlists.length}
        eyebrow="我的音乐"
        title="歌单"
        description="歌单会同步到当前账号，可从曲目操作菜单加入歌曲。"
      >
        <form
          className="playlist-create"
          onSubmit={(event) => {
            event.preventDefault();
            const name = playlistName.trim();
            if (!name) {
              return;
            }
            onCreatePlaylist(name);
            setPlaylistName("");
          }}
        >
          <Icon name="playlist" size={19} />
          <input
            aria-label="新歌单名称"
            onChange={(event) => setPlaylistName(event.target.value)}
            placeholder="输入歌单名称"
            value={playlistName}
          />
          <button className="button button--primary button--compact" type="submit">
            <Icon name="plus" size={16} />
            新建歌单
          </button>
        </form>
        {playlists.length > 0 ? (
          <div className="collection-grid">
            {playlists.map((playlist) => {
              const firstTrack = playlist.trackIds
                .map((trackId) => tracksById.get(trackId))
                .find(Boolean);
              return (
                <article className="collection-card" key={playlist.id}>
                  <button
                    className="collection-card__main"
                    onClick={() => openPlaylist(playlist.id)}
                    type="button"
                  >
                    <AlbumArt size="medium" track={firstTrack ?? null} />
                    <span>
                      <strong>{playlist.name}</strong>
                      <small>{playlist.trackIds.length} 首曲目</small>
                    </span>
                    <Icon name="chevron" size={18} />
                  </button>
                </article>
              );
            })}
          </div>
        ) : (
          <EmptyState
            icon="playlist"
            title="创建你的第一张歌单"
            description="新建歌单后，在曲目操作菜单中即可添加音乐。"
          />
        )}
      </CollectionSection>
    );
  }

  function renderCollections(
    type: "album" | "artist",
    collections: Collection[],
    selectedName: string | null,
    selectedTracks: Track[],
    onSelect: (name: string | null) => void,
  ) {
    const title = type === "album" ? "专辑" : "艺术家";
    const detailTitle = selectedName ?? title;
    if (selectedName) {
      return (
        <CollectionSection
          actions={
            <button
              className="button button--secondary button--compact"
              onClick={() => onSelect(null)}
              type="button"
            >
              返回{title}
            </button>
          }
          count={selectedTracks.length}
          eyebrow={`${title}详情`}
          title={detailTitle}
          description={
            type === "album"
              ? `收录 ${selectedTracks.length} 首曲目。`
              : `这位艺术家共有 ${selectedTracks.length} 首曲目。`
          }
        >
          <div className="collection-detail__actions">
            <button
              className="button button--primary"
              disabled={selectedTracks.length === 0}
              onClick={() => {
                const firstTrack = selectedTracks[0];
                if (firstTrack) {
                  onPlay(firstTrack, selectedTracks);
                }
              }}
              type="button"
            >
              <Icon name="play" size={17} />
              播放全部
            </button>
          </div>
          {selectedTracks.length > 0 ? (
            table(selectedTracks)
          ) : (
            <EmptyState
              icon={type}
              title={`没有找到这${type === "album" ? "张专辑" : "位艺术家"}的曲目`}
              description="曲库刷新后可再次查看。"
            />
          )}
        </CollectionSection>
      );
    }

    return (
      <CollectionSection
        count={collections.length}
        eyebrow="分类浏览"
        title={title}
        description={`按${title}整理曲库，点击即可查看基础详情和曲目列表。`}
      >
        {collections.length > 0 ? (
          <div className="collection-grid">
            {collections.map((collection) => (
              <article className="collection-card" key={collection.name}>
                <button
                  className="collection-card__main"
                  onClick={() => onSelect(collection.name)}
                  type="button"
                >
                  <AlbumArt size="medium" track={collection.tracks[0] ?? null} />
                  <span>
                    <strong>{collection.name}</strong>
                    <small>{collection.tracks.length} 首曲目</small>
                  </span>
                  <Icon name="chevron" size={18} />
                </button>
              </article>
            ))}
          </div>
        ) : (
          <EmptyState
            icon={type}
            title={`暂时没有${title}信息`}
            description="刷新曲库或补充曲目元数据后，会在这里显示。"
          />
        )}
      </CollectionSection>
    );
  }

  function renderQueue() {
    return (
      <CollectionSection
        actions={
          <button
            className="button button--secondary button--compact"
            disabled={queueLength === 0}
            onClick={onClearQueue}
            type="button"
          >
            <Icon name="trash" size={16} />
            清空队列
          </button>
        }
        count={queueLength}
        eyebrow="正在播放"
        title="播放队列"
        description="从曲目列表播放、加入队列或播放歌单时，都会明确更新这里的顺序。"
      >
        {queue.length > 0 ? (
          table(queue)
        ) : (
          <EmptyState
            icon="queue"
            title="播放队列为空"
            description="从曲目操作菜单选择“加入播放队列”，或直接播放一组曲目。"
          />
        )}
      </CollectionSection>
    );
  }

  return (
    <>
      {activeSection === "all" && (
        <>
          <section className="library-hero">
            <div className="library-hero__copy">
              <span className="eyebrow">你的私人歌单</span>
              <h1>
                让收藏
                <br />
                <em>重新响起来。</em>
              </h1>
              <p>
                浏览、播放并整理你的私人音乐库。音频始终来自你配置的
                LyraNest 音乐服务。
              </p>
              <div className="hero-actions">
                <button
                  className="button button--primary"
                  disabled={loading}
                  onClick={onRefresh}
                  type="button"
                >
                  {loading ? (
                    <span className="spinner spinner--light" />
                  ) : (
                    <Icon name="refresh" size={18} />
                  )}
                  刷新曲库
                </button>
                <span>支持 MP3 · FLAC · M4A · OGG · OPUS · WAV</span>
              </div>
            </div>
            <div className="hero-visual" aria-hidden="true">
              <div className="vinyl">
                <span className="vinyl__groove vinyl__groove--one" />
                <span className="vinyl__groove vinyl__groove--two" />
                <span className="vinyl__label">
                  <Icon name="music" size={34} />
                  <b>LYRANEST</b>
                  <small>A 面</small>
                </span>
              </div>
              <div className="hero-ticket">
                <small>正在播放</small>
                <strong>你的音乐库</strong>
                <span>{tracks.length.toString().padStart(3, "0")} 首曲目</span>
              </div>
            </div>
          </section>

          <section className="stats-grid" aria-label="曲库统计">
            <article>
              <span className="stat-index">01</span>
              <div>
                <strong>{tracks.length}</strong>
                <span>首曲目</span>
              </div>
            </article>
            <article>
              <span className="stat-index">02</span>
              <div>
                <strong>{artistCount}</strong>
                <span>位艺术家</span>
              </div>
            </article>
            <article>
              <span className="stat-index">03</span>
              <div>
                <strong>{formatCount}</strong>
                <span>种音频格式</span>
              </div>
            </article>
            <article>
              <span className="stat-index">04</span>
              <div>
                <strong>{formatBytes(totalSize)}</strong>
                <span>曲库体积</span>
              </div>
            </article>
          </section>
        </>
      )}

      <nav className="library-nav" aria-label="音乐库分类">
        {librarySections.map((section) => (
          <button
            className={activeSection === section.id ? "is-active" : ""}
            key={section.id}
            onClick={() => onSectionChange(section.id)}
            type="button"
          >
            <Icon name={section.icon} size={17} />
            {section.label}
            {section.id === "queue" && queueLength > 0 && (
              <em>{queueLength}</em>
            )}
          </button>
        ))}
      </nav>

      <section className="library-section">
        {activeSection === "all" && renderAllTracks()}
        {activeSection === "favorites" && renderFavorites()}
        {activeSection === "playlists" && renderPlaylists()}
        {activeSection === "albums" &&
          renderCollections(
            "album",
            albums,
            selectedAlbum,
            selectedAlbumTracks,
            setSelectedAlbum,
          )}
        {activeSection === "artists" &&
          renderCollections(
            "artist",
            artists,
            selectedArtist,
            selectedArtistTracks,
            setSelectedArtist,
          )}
        {activeSection === "queue" && renderQueue()}
      </section>
    </>
  );
}

function CollectionSection({
  eyebrow,
  title,
  description,
  count,
  actions,
  children,
}: {
  eyebrow: string;
  title: string;
  description: string;
  count: number;
  actions?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <>
      <div className="section-heading">
        <div>
          <span className="eyebrow">{eyebrow}</span>
          <h2>{title}</h2>
          <p>{description}</p>
        </div>
        <div className="section-heading__actions">
          <span className="section-count">{count} 首</span>
          {actions}
        </div>
      </div>
      {children}
    </>
  );
}

function EmptyState({
  icon,
  title,
  description,
}: {
  icon: "music" | "heart" | "playlist" | "album" | "artist" | "queue" | "search";
  title: string;
  description: string;
}) {
  return (
    <div className="empty-library">
      <span className="empty-orbit">
        <Icon name={icon} size={30} />
      </span>
      <strong>{title}</strong>
      <p>{description}</p>
    </div>
  );
}
