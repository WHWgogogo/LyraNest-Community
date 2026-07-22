import { useEffect, useState, type FormEvent } from "react";
import { ApiError, friendlyError, type MusicApi } from "../api/client";
import type {
  ScrapeCandidate,
  ScrapeFieldName,
  ScrapeSearchRequest,
  ScrapeSearchResponse,
  Track,
} from "../api/types";
import {
  displayAlbum,
  displayArtist,
  displayScrapeValue,
  scrapeFieldLabels,
} from "../utils/format";
import { AlbumArt } from "./AlbumArt";
import { Icon } from "./Icon";

interface ScrapeDrawerProps {
  track: Track | null;
  api: MusicApi;
  onClose(): void;
  onApplied(message: string): void;
}

type SearchState =
  | { status: "loading" }
  | { status: "ready"; data: ScrapeSearchResponse }
  | { status: "error"; message: string; missingEndpoint: boolean };

interface ScrapeSearchFields {
  title: string;
  artist: string;
  album: string;
}

const MORE_CANDIDATES_STEP = 10;

function candidateFields(candidate: ScrapeCandidate): ScrapeFieldName[] {
  const changed = candidate.differences
    .filter((difference) => difference.changed)
    .map((difference) => difference.field);
  if (changed.length > 0) {
    return changed;
  }
  return Object.keys(candidate.metadata) as ScrapeFieldName[];
}

function searchRequest(
  fields: ScrapeSearchFields,
  limit?: number,
): ScrapeSearchRequest {
  const title = fields.title.trim();
  const artist = fields.artist.trim();
  const album = fields.album.trim();

  return {
    ...(title ? { title } : {}),
    ...(artist ? { artist } : {}),
    ...(album ? { album } : {}),
    ...(limit ? { limit } : {}),
  };
}

export function ScrapeDrawer({
  track,
  api,
  onClose,
  onApplied,
}: ScrapeDrawerProps) {
  const [state, setState] = useState<SearchState>({ status: "loading" });
  const [applyingId, setApplyingId] = useState<string | null>(null);
  const [fields, setFields] = useState<ScrapeSearchFields>({
    title: "",
    artist: "",
    album: "",
  });
  const [requestedLimit, setRequestedLimit] = useState<number | null>(null);

  function search(
    currentTrack: Track,
    searchFields = fields,
    limit?: number,
  ) {
    setState({ status: "loading" });
    api
      .searchScrape(currentTrack, searchRequest(searchFields, limit))
      .then((data) => setState({ status: "ready", data }))
      .catch((error: unknown) => {
        setState({
          status: "error",
          message: friendlyError(error),
          missingEndpoint:
            error instanceof ApiError &&
            (error.status === 404 || error.status === 405),
        });
      });
  }

  useEffect(() => {
    if (track) {
      const initialFields = {
        title: track.title,
        artist: track.artist ?? "",
        album: track.album ?? "",
      };
      setFields(initialFields);
      setRequestedLimit(null);
      search(track, initialFields);
    }
  }, [api, track]);

  if (!track) {
    return null;
  }
  const currentTrack = track;

  function submitSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setRequestedLimit(null);
    search(currentTrack);
  }

  function requestMoreCandidates() {
    const currentCount =
      state.status === "ready" ? state.data.candidates.length : 0;
    const nextLimit =
      Math.max(requestedLimit ?? 0, currentCount) + MORE_CANDIDATES_STEP;
    setRequestedLimit(nextLimit);
    search(currentTrack, fields, nextLimit);
  }

  async function apply(candidate: ScrapeCandidate) {
    const fields = candidateFields(candidate);
    if (fields.length === 0) {
      return;
    }
    setApplyingId(candidate.id);
    try {
      const result = await api.applyScrape(currentTrack.id, {
        candidate_id: candidate.id,
        provider: candidate.provider,
        fields,
      });
      onApplied(
        result.message ||
          `已从 ${candidate.provider} 应用 ${result.applied_fields.length} 个字段`,
      );
      onClose();
    } catch (error) {
      setState({
        status: "error",
        message: friendlyError(error),
        missingEndpoint:
          error instanceof ApiError &&
          (error.status === 404 || error.status === 405),
      });
    } finally {
      setApplyingId(null);
    }
  }

  return (
    <div className="drawer-backdrop" onMouseDown={onClose}>
      <aside
        aria-labelledby="scrape-title"
        className="drawer scrape-drawer"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="drawer__header">
          <div>
            <small>元数据刮削</small>
            <h2 id="scrape-title">匹配元数据</h2>
          </div>
          <button
            aria-label="关闭刮削面板"
            className="icon-button"
            onClick={onClose}
            type="button"
          >
            <Icon name="close" />
          </button>
        </div>

        <div className="scrape-track">
          <AlbumArt size="medium" track={track} />
          <div>
            <strong>{track.title}</strong>
            <span>{displayArtist(track)}</span>
            <small>{displayAlbum(track)}</small>
          </div>
          <span className="file-badge">
            {track.extension.toUpperCase() || "音频"}
          </span>
        </div>

        <div className="scrape-body">
          <form
            aria-label="刮削搜索条件"
            onSubmit={submitSearch}
            style={{ display: "grid", gap: 10, marginBottom: 18 }}
          >
            <label>
              <span className="sr-only">标题</span>
              <span className="field__input">
                <Icon name="search" size={16} />
                <input
                  aria-label="标题"
                  onChange={(event) =>
                    setFields((current) => ({
                      ...current,
                      title: event.target.value,
                    }))
                  }
                  placeholder="标题"
                  value={fields.title}
                />
              </span>
            </label>
            <label>
              <span className="sr-only">艺人</span>
              <span className="field__input">
                <Icon name="music" size={16} />
                <input
                  aria-label="艺人"
                  onChange={(event) =>
                    setFields((current) => ({
                      ...current,
                      artist: event.target.value,
                    }))
                  }
                  placeholder="艺人"
                  value={fields.artist}
                />
              </span>
            </label>
            <label>
              <span className="sr-only">专辑</span>
              <span className="field__input">
                <Icon name="manage" size={16} />
                <input
                  aria-label="专辑"
                  onChange={(event) =>
                    setFields((current) => ({
                      ...current,
                      album: event.target.value,
                    }))
                  }
                  placeholder="专辑"
                  value={fields.album}
                />
              </span>
            </label>
            <button className="button button--secondary" type="submit">
              <Icon name="search" size={17} />
              搜索候选
            </button>
          </form>

          {state.status === "loading" && (
            <div className="drawer-state">
              <span className="spinner" />
              <strong>正在搜索候选</strong>
              <p>正在请求已配置的元数据提供方，请稍候。</p>
            </div>
          )}

          {state.status === "error" && (
            <div className="drawer-state drawer-state--error">
              <span className="empty-orbit">
                <Icon name="alert" size={28} />
              </span>
              <strong>无法获取刮削候选</strong>
              <p>{state.message}</p>
              {state.missingEndpoint && (
                <div className="contract-hint">
                  后端尚未提供此管理接口。Web 已按
                  <code>
                    POST /api/v1/tracks/{"{id}"}/scrape/search
                  </code>
                  发起请求。
                </div>
              )}
              <button
                className="button button--secondary"
                onClick={() => search(track)}
                type="button"
              >
                <Icon name="refresh" size={17} />
                重试搜索
              </button>
            </div>
          )}

          {state.status === "ready" && state.data.candidates.length === 0 && (
            <div className="drawer-state drawer-state--empty">
              <span className="empty-orbit">
                <Icon name="wand" size={28} />
              </span>
              <strong>没有找到合适候选</strong>
              <p>可以完善文件名或标签后再次搜索。</p>
              <button
                className="button button--secondary"
                onClick={() => search(track)}
                type="button"
              >
                <Icon name="refresh" size={17} />
                重新搜索
              </button>
            </div>
          )}

          {state.status === "ready" && state.data.candidates.length > 0 && (
            <>
              <div className="candidate-heading">
                <div>
                  <strong>{state.data.candidates.length} 个候选结果</strong>
                  <span>应用前请检查字段差异</span>
                </div>
                <button
                  className="button button--ghost button--compact"
                  onClick={() => search(track)}
                  type="button"
                >
                  <Icon name="refresh" size={16} />
                  重新搜索
                </button>
              </div>
              <div className="candidate-list">
                {state.data.candidates.map((candidate, index) => {
                  const percentage = Math.round(candidate.confidence * 100);
                  const changedCount = candidate.differences.filter(
                    (difference) => difference.changed,
                  ).length;
                  return (
                    <article className="candidate-card" key={candidate.id}>
                      <div className="candidate-card__top">
                        <span className="candidate-rank">
                          {(index + 1).toString().padStart(2, "0")}
                        </span>
                        <div>
                          <strong>
                            {candidate.metadata.title || track.title}
                          </strong>
                          <span>
                            {candidate.metadata.artist || "未知艺术家"} ·{" "}
                            {candidate.metadata.album || "未知专辑"}
                          </span>
                        </div>
                        <span className="provider-badge">
                          {candidate.provider}
                        </span>
                      </div>

                      <div className="confidence">
                        <div>
                          <span>匹配置信度</span>
                          <strong>{percentage}%</strong>
                        </div>
                        <div className="confidence__bar">
                          <span style={{ width: `${percentage}%` }} />
                        </div>
                      </div>

                      <div className="diff-list">
                        <div className="diff-list__head">
                          <span>字段</span>
                          <span>当前值</span>
                          <span>候选值</span>
                        </div>
                        {candidate.differences.map((difference) => (
                          <div
                            className={`diff-row ${
                              difference.changed ? "is-changed" : ""
                            }`}
                            key={difference.field}
                          >
                            <span>{scrapeFieldLabels[difference.field]}</span>
                            <span title={String(difference.current ?? "")}>
                              {displayScrapeValue(difference.current)}
                            </span>
                            <span title={String(difference.candidate ?? "")}>
                              {displayScrapeValue(difference.candidate)}
                            </span>
                          </div>
                        ))}
                      </div>

                      <div className="candidate-card__footer">
                        <span>
                          {changedCount > 0
                            ? `${changedCount} 个字段将被更新`
                            : "候选与当前元数据一致"}
                        </span>
                        <button
                          className="button button--primary button--compact"
                          disabled={
                            applyingId !== null ||
                            candidateFields(candidate).length === 0
                          }
                          onClick={() => void apply(candidate)}
                          type="button"
                        >
                          {applyingId === candidate.id ? (
                            <span className="spinner spinner--light" />
                          ) : (
                            <Icon name="check" size={17} />
                          )}
                          应用候选
                        </button>
                      </div>
                    </article>
                  );
                })}
              </div>
              <button
                className="button button--secondary"
                onClick={requestMoreCandidates}
                type="button"
              >
                <Icon name="refresh" size={17} />
                请求更多候选
              </button>
            </>
          )}
        </div>
      </aside>
    </div>
  );
}
