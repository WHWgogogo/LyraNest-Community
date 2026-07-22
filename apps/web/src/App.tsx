import { useCallback, useEffect, useMemo, useState } from "react";
import { ApiError, createMusicApi, friendlyError } from "./api/client";
import type {
  AuthSessionResponse,
  AuthUser,
  DiscoveryResponse,
  ListeningReport,
  Track,
} from "./api/types";
import { AuthPage } from "./components/AuthPage";
import { Icon } from "./components/Icon";
import { LyricsDrawer } from "./components/LyricsDrawer";
import { PlayerBar } from "./components/PlayerBar";
import { ScrapeDrawer } from "./components/ScrapeDrawer";
import { Sidebar, type AppView } from "./components/Sidebar";
import { Toast, type ToastMessage } from "./components/Toast";
import { useAudioPlayer } from "./hooks/useAudioPlayer";
import { useCollections } from "./hooks/useCollections";
import {
  LibraryPage,
  type LibrarySection,
  type TrackSort,
} from "./pages/LibraryPage";
import { DiscoveryPage } from "./pages/DiscoveryPage";
import { ListeningReportPage } from "./pages/ListeningReportPage";
import { ManagementPage } from "./pages/ManagementPage";
import { SupportPage } from "./pages/SupportPage";
import {
  hasVisitedSupport,
  recordSupportVisit,
} from "./utils/supportVisit";

const TOKEN_KEY = "lyranest-community.auth-token";

type AuthView =
  | "checking"
  | "register"
  | "login"
  | "authenticated"
  | "error";

function readAuthToken(): string | null {
  return window.localStorage.getItem(TOKEN_KEY);
}

function saveAuthToken(token: string) {
  window.localStorage.setItem(TOKEN_KEY, token);
}

function clearAuthToken() {
  window.localStorage.removeItem(TOKEN_KEY);
}

function sortTracks(tracks: Track[], sort: TrackSort): Track[] {
  return [...tracks].sort((left, right) => {
    switch (sort) {
      case "artist-asc":
        return (left.artist || "未知艺术家").localeCompare(
          right.artist || "未知艺术家",
          "zh-CN",
        );
      case "modified-desc":
        return (
          new Date(right.modified).getTime() -
          new Date(left.modified).getTime()
        );
      case "size-desc":
        return right.size_bytes - left.size_bytes;
      default:
        return left.title.localeCompare(right.title, "zh-CN");
    }
  });
}

function viewContext(view: AppView): [string, string] {
  switch (view) {
    case "discovery":
      return ["音乐发现", "推荐与搜索"];
    case "report":
      return ["听歌报告", "年度聆听统计"];
    case "management":
      return ["音乐管理", "扫描与整理"];
    case "support":
      return ["关于 / 支持作者", "LyraNest · 律巢"];
    default:
      return ["曲目", "曲库浏览"];
  }
}

export default function App() {
  const [authView, setAuthView] = useState<AuthView>("checking");
  const [authUser, setAuthUser] = useState<AuthUser | null>(null);
  const [authError, setAuthError] = useState<string | null>(null);
  const [authRetry, setAuthRetry] = useState(0);
  const [view, setView] = useState<AppView>("library");
  const [showSupportNotice, setShowSupportNotice] = useState(
    () => !hasVisitedSupport(window.localStorage),
  );
  const [librarySection, setLibrarySection] =
    useState<LibrarySection>("all");
  const [health, setHealth] = useState<"checking" | "online" | "offline">(
    "checking",
  );
  const [tracks, setTracks] = useState<Track[]>([]);
  const [tracksLoading, setTracksLoading] = useState(true);
  const [tracksError, setTracksError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState<TrackSort>("title-asc");
  const [lyricsTrack, setLyricsTrack] = useState<Track | null>(null);
  const [scrapeTrack, setScrapeTrack] = useState<Track | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [discovery, setDiscovery] = useState<DiscoveryResponse | null>(null);
  const [discoverySearch, setDiscoverySearch] = useState("");
  const [discoveryLoading, setDiscoveryLoading] = useState(false);
  const [discoveryError, setDiscoveryError] = useState<string | null>(null);
  const [report, setReport] = useState<ListeningReport | null>(null);
  const [reportLoading, setReportLoading] = useState(false);
  const [reportError, setReportError] = useState<string | null>(null);

  const handleUnauthorized = useCallback(() => {
    if (!readAuthToken()) {
      return;
    }
    clearAuthToken();
    setAuthUser(null);
    setAuthView("login");
    setTracks([]);
    setLyricsTrack(null);
    setScrapeTrack(null);
    setDiscovery(null);
    setReport(null);
    setToast({
      id: Date.now(),
      tone: "error",
      message: "登录状态已失效，请重新登录。",
    });
  }, []);

  const api = useMemo(
    () =>
      createMusicApi(window.location.origin, {
        getToken: readAuthToken,
        onUnauthorized: handleUnauthorized,
      }),
    [handleUnauthorized],
  );

  useEffect(() => {
    document.title = "LyraNest Community ? 律巢社区版";
  }, []);

  const userKey =
    authView === "authenticated" && authUser
      ? authUser.id || authUser.username
      : undefined;
  const collections = useCollections({ api, userKey });

  const notify = useCallback(
    (message: string, tone: ToastMessage["tone"] = "info") => {
      setToast({ id: Date.now(), tone, message });
    },
    [],
  );

  useEffect(() => {
    if (!toast) {
      return;
    }
    const timer = window.setTimeout(() => setToast(null), 4_500);
    return () => window.clearTimeout(timer);
  }, [toast]);

  useEffect(() => {
    let cancelled = false;

    async function bootstrapAuth() {
      setAuthView("checking");
      setAuthError(null);
      try {
        const status = await api.authStatus();
        if (cancelled) {
          return;
        }
        if (!status.initialized) {
          clearAuthToken();
          setAuthUser(null);
          setAuthView("register");
          return;
        }
        if (!readAuthToken()) {
          setAuthView("login");
          return;
        }
        const user = await api.me();
        if (!cancelled) {
          setAuthUser(user);
          setAuthView("authenticated");
        }
      } catch (error) {
        if (cancelled) {
          return;
        }
        if (error instanceof ApiError && error.status === 401) {
          clearAuthToken();
          setAuthUser(null);
          setAuthView("login");
          return;
        }
        setAuthError(friendlyError(error));
        setAuthView("error");
      }
    }

    void bootstrapAuth();
    return () => {
      cancelled = true;
    };
  }, [api, authRetry]);

  const refreshTracks = useCallback(async () => {
    setTracksLoading(true);
    setTracksError(null);
    try {
      const result = await api.listTracks();
      setTracks(result.tracks);
    } catch (error) {
      setTracksError(friendlyError(error));
    } finally {
      setTracksLoading(false);
    }
  }, [api]);

  const checkHealth = useCallback(async () => {
    setHealth("checking");
    try {
      const result = await api.health();
      setHealth(result.status === "ok" ? "online" : "offline");
    } catch {
      setHealth("offline");
    }
  }, [api]);

  const refreshDiscovery = useCallback(async () => {
    setDiscoveryLoading(true);
    setDiscoveryError(null);
    try {
      setDiscovery(await api.discovery());
    } catch (error) {
      setDiscoveryError(friendlyError(error));
    } finally {
      setDiscoveryLoading(false);
    }
  }, [api]);

  const reportYear = new Date().getFullYear();
  const refreshReport = useCallback(async () => {
    setReportLoading(true);
    setReportError(null);
    try {
      setReport(await api.listeningReport(reportYear));
    } catch (error) {
      setReportError(friendlyError(error));
    } finally {
      setReportLoading(false);
    }
  }, [api, reportYear]);

  useEffect(() => {
    if (authView !== "authenticated") {
      return;
    }
    void Promise.all([checkHealth(), refreshTracks()]);
  }, [authView, checkHealth, refreshTracks]);

  useEffect(() => {
    if (authView === "authenticated" && view === "discovery") {
      void refreshDiscovery();
    }
  }, [authView, refreshDiscovery, view]);

  useEffect(() => {
    if (authView === "authenticated" && view === "report") {
      void refreshReport();
    }
  }, [authView, refreshReport, view]);

  const player = useAudioPlayer({
    api,
    tracks,
    onError: (message) => notify(message, "error"),
    onListeningEvent: () => undefined,
  });

  const filteredTracks = useMemo(() => {
    const query = search.trim().toLocaleLowerCase("zh-CN");
    const matches = query
      ? tracks.filter((track) =>
          [
            track.title,
            track.artist,
            track.album,
            track.file_name,
            track.extension,
          ].some((value) =>
            value?.toLocaleLowerCase("zh-CN").includes(query),
          ),
        )
      : tracks;
    return sortTracks(matches, sort);
  }, [search, sort, tracks]);

  const discoverySearchTracks = useMemo(() => {
    const query = discoverySearch.trim().toLocaleLowerCase("zh-CN");
    if (!query) {
      return [];
    }
    return tracks.filter((track) =>
      [track.title, track.artist, track.album, track.file_name].some((value) =>
        value?.toLocaleLowerCase("zh-CN").includes(query),
      ),
    );
  }, [discoverySearch, tracks]);

  async function authenticated(session: AuthSessionResponse) {
    saveAuthToken(session.token);
    try {
      const user = session.user ?? (await api.me());
      setAuthUser(user);
      setAuthView("authenticated");
      setView("discovery");
      notify("登录成功", "success");
    } catch (error) {
      clearAuthToken();
      setAuthUser(null);
      setAuthView("login");
      notify(friendlyError(error), "error");
    }
  }

  async function logout() {
    try {
      await api.logout();
    } catch (error) {
      if (readAuthToken()) {
        notify(friendlyError(error), "error");
      }
    } finally {
      clearAuthToken();
      setAuthUser(null);
      setAuthView("login");
      setTracks([]);
      setLyricsTrack(null);
      setScrapeTrack(null);
      setDiscovery(null);
      setReport(null);
    }
  }

  function playFromRow(track: Track, contextTracks = filteredTracks) {
    if (player.currentTrack?.id === track.id && player.isPlaying) {
      void player.togglePlayback();
    } else {
      void player.playTrack(track, contextTracks);
    }
  }

  function toggleFavorite(track: Track) {
    const isFavorite = collections.favoriteTrackIds.includes(track.id);
    collections.toggleFavorite(track);
    notify(isFavorite ? `已取消收藏《${track.title}》` : `已收藏《${track.title}》`, "success");
  }

  function createPlaylist(name: string) {
    if (collections.createPlaylist(name)) {
      notify(`已创建歌单《${name.trim()}》`, "success");
    }
  }

  function addTrackToPlaylist(track: Track, playlistId: string) {
    const playlist = collections.playlists.find((item) => item.id === playlistId);
    const added = collections.addTrackToPlaylist(track, playlistId);
    if (!playlist) {
      return;
    }
    notify(
      added
        ? `已添加到歌单《${playlist.name}》`
        : `《${track.title}》已在歌单《${playlist.name}》中`,
      added ? "success" : "info",
    );
  }

  function deletePlaylist(playlistId: string) {
    const playlist = collections.playlists.find((item) => item.id === playlistId);
    collections.deletePlaylist(playlistId);
    if (playlist) {
      notify(`已删除歌单《${playlist.name}》`);
    }
  }

  const navigate = useCallback((nextView: AppView) => {
    if (nextView === "support") {
      recordSupportVisit(window.localStorage);
      setShowSupportNotice(false);
    }
    setView(nextView);
  }, []);

  const [contextTitle, contextSubtitle] = viewContext(view);

  if (authView === "checking") {
    return (
      <main className="auth-shell auth-shell--loading">
        <div className="auth-loading" role="status">
          <span className="spinner spinner--light" />
          <strong>正在检查初始化状态…</strong>
        </div>
      </main>
    );
  }

  if (authView === "error") {
    return (
      <main className="auth-shell auth-shell--loading">
        <section className="auth-card auth-card--error">
          <Icon name="alert" size={30} />
          <h1>无法检查初始化状态</h1>
          <p>{authError}</p>
          <button
            className="button button--primary"
            onClick={() => setAuthRetry((value) => value + 1)}
            type="button"
          >
            <Icon name="refresh" size={18} />
            重试
          </button>
        </section>
      </main>
    );
  }

  if (authView === "register" || authView === "login") {
    return (
      <>
        <AuthPage
          api={api}
          mode={authView}
          onAuthenticated={(session) => void authenticated(session)}
        />
        <Toast onClose={() => setToast(null)} toast={toast} />
      </>
    );
  }

  return (
    <div className="app-shell">
      <Sidebar
        activeView={view}
        connected={health === "online"}
        onLogout={() => void logout()}
        onNavigate={navigate}
        showSupportNotice={showSupportNotice}
        trackCount={tracks.length}
        username={authUser?.display_name || authUser?.username || "管理员"}
      />

      <main className="app-main">
        <header className="topbar">
          <div className="topbar__context">
            <span>{contextTitle}</span>
            <i />
            <small>{contextSubtitle}</small>
          </div>
          <div className="topbar__account">
            <span
              className={`status-dot ${
                health === "online"
                  ? "is-online"
                  : health === "offline"
                    ? "is-offline"
                    : "is-checking"
              }`}
            />
            <span>
              <b>{authUser?.display_name || authUser?.username || "管理员"}</b>
              <small>
                {health === "online"
                  ? collections.syncing
                    ? "正在同步收藏与歌单"
                    : "服务已连接"
                  : health === "checking"
                    ? "正在连接服务"
                    : "服务未连接"}
              </small>
            </span>
          </div>
        </header>

        <div className="app-content">
          {view === "discovery" && (
            <DiscoveryPage
              currentTrackId={player.currentTrack?.id}
              data={discovery}
              error={discoveryError}
              isPlaying={player.isPlaying}
              loading={discoveryLoading}
              onPlay={playFromRow}
              onRefresh={() => void refreshDiscovery()}
              onSearch={setDiscoverySearch}
              onSubmitSearch={() => undefined}
              search={discoverySearch}
              searchResults={discoverySearchTracks}
            />
          )}
          {view === "support" && <SupportPage />}
          {view === "library" && (
            <LibraryPage
              activeSection={librarySection}
              currentTrackId={player.currentTrack?.id}
              error={tracksError}
              favoriteTrackIds={collections.favoriteTrackIds}
              filteredTracks={filteredTracks}
              isPlaying={player.isPlaying}
              loading={tracksLoading}
              onAddToPlaylist={addTrackToPlaylist}
              onClearQueue={() => {
                player.clearQueue();
                notify("已清空播放队列");
              }}
              onCreatePlaylist={createPlaylist}
              onDeletePlaylist={deletePlaylist}
              onEnqueue={(track) => {
                player.enqueue(track);
                notify(`已加入播放队列：《${track.title}》`);
              }}
              onEnqueueNext={(track) => {
                player.enqueueNext(track);
                notify(`下一首播放：《${track.title}》`);
              }}
              onLyrics={setLyricsTrack}
              onPlay={playFromRow}
              onRefresh={() => void refreshTracks()}
              onScrape={setScrapeTrack}
              onSearch={setSearch}
              onSectionChange={setLibrarySection}
              onSort={setSort}
              onToggleFavorite={toggleFavorite}
              playlists={collections.playlists}
              queue={player.queue}
              queueLength={player.queueLength}
              search={search}
              sort={sort}
              tracks={tracks}
            />
          )}
          {view === "report" && (
            <ListeningReportPage
              error={reportError}
              loading={reportLoading}
              onPlay={(trackId) => {
                const track = tracks.find((item) => item.id === trackId);
                if (track) {
                  playFromRow(track, tracks);
                }
              }}
              onRefresh={() => void refreshReport()}
              report={report}
            />
          )}
          {view === "management" && (
            <ManagementPage
              api={api}
              connected={health === "online"}
              onNotify={notify}
              onOpenScrape={setScrapeTrack}
              onRefreshTracks={refreshTracks}
              tracks={tracks}
            />
          )}
        </div>
      </main>

      {player.audioElement}
      <PlayerBar
        currentTime={player.currentTime}
        duration={player.duration}
        isPlaying={player.isPlaying}
        loading={player.loading}
        muted={player.muted}
        onNext={() => void player.playNext()}
        onOpenQueue={() => {
          setView("library");
          setLibrarySection("queue");
        }}
        onOpenLyrics={() =>
          player.currentTrack && setLyricsTrack(player.currentTrack)
        }
        onPrevious={() => void player.playPrevious()}
        onCyclePlayMode={player.cyclePlayMode}
        onSeek={player.seek}
        onToggle={() => void player.togglePlayback()}
        onToggleMute={player.toggleMute}
        onVolume={player.setVolume}
        playMode={player.playMode}
        queueLength={player.queueLength}
        track={player.currentTrack}
        volume={player.volume}
      />

      <LyricsDrawer
        api={api}
        currentTime={player.currentTime}
        onClose={() => setLyricsTrack(null)}
        onPlay={(track) => void player.playTrack(track)}
        onSeek={player.seek}
        playingTrackId={player.currentTrack?.id}
        track={lyricsTrack}
      />
      <ScrapeDrawer
        api={api}
        onApplied={(message) => {
          notify(message, "success");
          void refreshTracks();
        }}
        onClose={() => setScrapeTrack(null)}
        track={scrapeTrack}
      />
      <Toast onClose={() => setToast(null)} toast={toast} />
    </div>
  );
}
