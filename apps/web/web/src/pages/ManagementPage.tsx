import { useCallback, useEffect, useMemo, useState } from "react";
import { ApiError, friendlyError, type MusicApi } from "../api/client";
import type {
  LibraryScanResponse,
  LibraryStatusResponse,
  Track,
} from "../api/types";
import { displayArtist, formatDateTime } from "../utils/format";
import { AlbumArt } from "../components/AlbumArt";
import { Icon } from "../components/Icon";

interface ManagementPageProps {
  api: MusicApi;
  tracks: Track[];
  connected: boolean;
  onRefreshTracks(): Promise<void>;
  onOpenScrape(track: Track): void;
  onNotify(message: string, tone?: "success" | "error" | "info"): void;
}

export function ManagementPage({
  api,
  tracks,
  connected,
  onRefreshTracks,
  onOpenScrape,
  onNotify,
}: ManagementPageProps) {
  const [scanning, setScanning] = useState(false);
  const [scanResult, setScanResult] = useState<LibraryScanResponse | null>(null);
  const [libraryStatus, setLibraryStatus] =
    useState<LibraryStatusResponse | null>(null);
  const [statusLoading, setStatusLoading] = useState(true);
  const [statusError, setStatusError] = useState<string | null>(null);
  const [scanError, setScanError] = useState<{
    message: string;
    missingEndpoint: boolean;
  } | null>(null);
  const [scrapeSearch, setScrapeSearch] = useState("");
  const [selectedScrapeTrackId, setSelectedScrapeTrackId] = useState("");

  const refreshStatus = useCallback(async () => {
    setStatusLoading(true);
    setStatusError(null);
    try {
      setLibraryStatus(await api.libraryStatus());
    } catch (error) {
      setStatusError(friendlyError(error));
    } finally {
      setStatusLoading(false);
    }
  }, [api]);

  useEffect(() => {
    void refreshStatus();
  }, [refreshStatus]);

  async function scan() {
    setScanning(true);
    setScanError(null);
    setLibraryStatus((current) =>
      current ? { ...current, scanning: true } : current,
    );
    try {
      const result = await api.scanLibrary();
      setScanResult(result);
      await Promise.all([onRefreshTracks(), refreshStatus()]);
      onNotify(`音乐库扫描完成，共 ${result.total} 首`, "success");
    } catch (error) {
      setScanError({
        message: friendlyError(error),
        missingEndpoint:
          error instanceof ApiError &&
          (error.status === 404 || error.status === 405),
      });
      await refreshStatus();
    } finally {
      setScanning(false);
    }
  }

  const scanInProgress = scanning || libraryStatus?.scanning === true;
  const scrapeSearchTerm = scrapeSearch.trim().toLocaleLowerCase("zh-CN");
  const scrapeTracks = useMemo(
    () =>
      scrapeSearchTerm
        ? tracks.filter((track) =>
            [track.title, track.artist, track.album, track.file_name].some(
              (value) =>
                value?.toLocaleLowerCase("zh-CN").includes(scrapeSearchTerm),
            ),
          )
        : tracks,
    [scrapeSearchTerm, tracks],
  );
  const selectedScrapeTrack =
    tracks.find((track) => track.id === selectedScrapeTrackId) ?? null;

  return (
    <div className="management-page">
      <section className="page-title">
        <div>
          <span className="eyebrow">曲库操作</span>
          <h1>音乐管理</h1>
          <p>重新扫描服务器音乐目录，并为曲目检索更完整的元数据。</p>
        </div>
        <span className={`health-pill ${connected ? "is-online" : ""}`}>
          <i />
          {connected ? "服务正常" : "服务离线"}
        </span>
      </section>

      <div className="management-grid">
        <section className="management-card management-card--scan">
          <div className="management-card__icon">
            <Icon name="refresh" size={28} />
          </div>
          <div className="management-card__heading">
            <span>曲库扫描</span>
            <h2>重新扫描音乐库</h2>
            <p>
              扫描服务器配置的音乐目录，发现新增、更新或已移除的音频文件。
            </p>
          </div>
          <div className="scan-summary">
            <div>
              <span>当前曲目</span>
              <strong>{tracks.length}</strong>
            </div>
            <div>
              <span>服务器</span>
              <strong>{connected ? "在线" : "离线"}</strong>
            </div>
          </div>
          <button
            className="button button--primary button--wide"
            disabled={scanInProgress}
            onClick={() => void scan()}
            type="button"
          >
            {scanInProgress ? (
              <span className="spinner spinner--light" />
            ) : (
              <Icon name="refresh" size={18} />
            )}
            {scanning
              ? "正在扫描，请稍候…"
              : libraryStatus?.scanning
                ? "服务器正在扫描…"
                : "开始完整扫描"}
          </button>

          {scanError && (
            <div className="management-error">
              <Icon name="alert" />
              <div>
                <strong>扫描请求失败</strong>
                <span>{scanError.message}</span>
                {scanError.missingEndpoint && (
                  <small>
                    后端需实现 <code>POST /api/v1/library/scan</code>。
                  </small>
                )}
              </div>
            </div>
          )}
        </section>

        <section className="management-card management-card--status">
          <div className="management-card__title-row">
            <div className="management-card__heading">
              <span>曲库状态</span>
              <h2>音乐库状态</h2>
            </div>
            <button
              className="button button--secondary button--compact"
              disabled={statusLoading}
              onClick={() => void refreshStatus()}
              type="button"
            >
              <Icon
                className={statusLoading ? "spin" : undefined}
                name="refresh"
                size={16}
              />
              {statusLoading ? "刷新中" : "刷新"}
            </button>
          </div>

          {statusError ? (
            <div className="management-error">
              <Icon name="alert" />
              <div>
                <strong>状态读取失败</strong>
                <span>{statusError}</span>
                <small>
                  后端需实现 <code>GET /api/v1/library/status</code>。
                </small>
              </div>
            </div>
          ) : libraryStatus ? (
            <>
              <div
                className={`result-status ${
                  libraryStatus.scanning ? "is-scanning" : ""
                }`}
              >
                <span>
                  <Icon
                    className={libraryStatus.scanning ? "spin" : undefined}
                    name={libraryStatus.scanning ? "refresh" : "check"}
                  />
                </span>
                <div>
                  <strong>
                    {libraryStatus.scanning ? "正在扫描音乐库" : "扫描器空闲"}
                  </strong>
                  <small>
                    {libraryStatus.last_scanned_at
                      ? `最近扫描：${formatDateTime(
                          libraryStatus.last_scanned_at,
                        )}`
                      : "尚未完成扫描"}
                  </small>
                </div>
              </div>
              <div className="status-grid">
                <div>
                  <span>音乐目录</span>
                  <strong title={libraryStatus.directory}>
                    {libraryStatus.directory || "未配置"}
                  </strong>
                </div>
                <div>
                  <span>曲目数量</span>
                  <strong>{libraryStatus.track_count}</strong>
                </div>
              </div>
              {libraryStatus.last_error && (
                <div className="management-error">
                  <Icon name="alert" />
                  <div>
                    <strong>最近扫描错误</strong>
                    <span>{libraryStatus.last_error}</span>
                  </div>
                </div>
              )}
            </>
          ) : (
            <div className="result-empty">
              <span className="empty-orbit">
                <Icon className="spin" name="refresh" size={28} />
              </span>
              <strong>正在读取状态</strong>
              <p>正在获取目录、曲目数量和最近扫描时间。</p>
            </div>
          )}
        </section>

        <section className="management-card management-card--result">
          <div className="management-card__heading">
            <span>最近结果</span>
            <h2>本次扫描结果</h2>
          </div>
          {scanResult ? (
            <>
              <div className="result-status">
                <span>
                  <Icon name="check" />
                </span>
                <div>
                  <strong>扫描完成</strong>
                  <small>{formatDateTime(scanResult.scanned_at)}</small>
                </div>
              </div>
              <div className="result-grid">
                <div>
                  <strong>{scanResult.total}</strong>
                  <span>曲目总数</span>
                </div>
                <div>
                  <strong>{scanResult.tracks.length}</strong>
                  <span>返回曲目</span>
                </div>
              </div>
              <p className="result-duration">
                扫描响应已接收，音乐库列表和服务端状态均已刷新。
              </p>
            </>
          ) : (
            <div className="result-empty">
              <span className="empty-orbit">
                <Icon name="manage" size={28} />
              </span>
              <strong>等待下一次扫描</strong>
              <p>执行扫描后，这里会显示曲目总数与响应时间。</p>
            </div>
          )}
        </section>
      </div>

      <section className="scrape-workbench">
        <div className="section-heading">
          <div>
            <span className="eyebrow">刮削工作台</span>
            <h2>刮削工作台</h2>
          </div>
          <span className="section-count">
            {scrapeSearch ? `${scrapeTracks.length} 个匹配` : `${tracks.length} 首可选`}
          </span>
        </div>
        <p>在本地曲库中搜索并选择任意曲目，再打开元数据刮削。</p>

        {tracks.length === 0 ? (
          <div className="empty-library empty-library--compact">
            <strong>暂无可刮削曲目</strong>
            <p>先完成曲库扫描。</p>
          </div>
        ) : (
          <>
            <div className="library-toolbar">
              <label className="search-box">
                <Icon name="search" size={19} />
                <span className="sr-only">搜索可刮削曲目</span>
                <input
                  onChange={(event) => {
                    setScrapeSearch(event.target.value);
                    setSelectedScrapeTrackId("");
                  }}
                  placeholder="搜索标题、艺人、专辑或文件名…"
                  type="search"
                  value={scrapeSearch}
                />
                {scrapeSearch && (
                  <button
                    aria-label="清除曲目搜索"
                    onClick={() => {
                      setScrapeSearch("");
                      setSelectedScrapeTrackId("");
                    }}
                    type="button"
                  >
                    <Icon name="close" size={16} />
                  </button>
                )}
              </label>
              <label className="sort-select">
                <span>曲目</span>
                <select
                  aria-label="选择要刮削的曲目"
                  disabled={scrapeTracks.length === 0}
                  onChange={(event) => setSelectedScrapeTrackId(event.target.value)}
                  value={selectedScrapeTrackId}
                >
                  <option value="">
                    {scrapeTracks.length === 0
                      ? "没有匹配曲目"
                      : "选择要刮削的曲目"}
                  </option>
                  {scrapeTracks.map((track) => (
                    <option key={track.id} value={track.id}>
                      {track.title} — {displayArtist(track)} · {track.file_name}
                    </option>
                  ))}
                </select>
              </label>
              <button
                className="button button--secondary"
                disabled={!selectedScrapeTrack}
                onClick={() => {
                  if (selectedScrapeTrack) {
                    onOpenScrape(selectedScrapeTrack);
                  }
                }}
                type="button"
              >
                <Icon name="wand" size={17} />
                打开刮削
              </button>
            </div>
            {scrapeSearch && scrapeTracks.length === 0 && (
              <div className="empty-library empty-library--compact">
                <strong>没有匹配的曲目</strong>
                <p>试试标题、艺人、专辑或文件名。</p>
              </div>
            )}
          </>
        )}
      </section>
    </div>
  );
}
