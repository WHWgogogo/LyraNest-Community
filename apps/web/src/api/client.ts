import type {
  AuthCredentials,
  AuthSessionResponse,
  AuthStatusResponse,
  AuthUser,
  CreatePlaylistRequest,
  CollectionsImportRequest,
  CollectionsSnapshot,
  DiscoveryCategory,
  DiscoveryResponse,
  ErrorResponse,
  HealthResponse,
  LibraryScanResponse,
  LibraryStatusResponse,
  ListeningEventIngestResult,
  ListeningEventRequest,
  ListeningHeatmapCell,
  ListeningReport,
  LyricsResponse,
  Playlist,
  RankedTrack,
  ScrapeApplyRequest,
  ScrapeApplyResponse,
  ScrapeCandidate,
  ScrapeFieldDifference,
  ScrapeFieldName,
  ScrapeMetadata,
  ScrapeSearchRequest,
  ScrapeSearchResponse,
  ScrapeValue,
  Track,
  TrackListResponse,
} from "./types";

const DEFAULT_TIMEOUT = 15_000;
const LONG_JOB_TIMEOUT = 120_000;

const AUTH_PATHS = {
  status: "/api/v1/auth/setup",
  register: "/api/v1/auth/register",
  login: "/api/v1/auth/login",
  me: "/api/v1/auth/me",
  logout: "/api/v1/auth/logout",
} as const;

export interface MusicApiOptions {
  getToken?(): string | null;
  onUnauthorized?(): void;
}

export class ApiError extends Error {
  readonly status?: number;
  readonly code?: string;
  readonly details?: unknown;

  constructor(
    message: string,
    options?: { status?: number; code?: string; details?: unknown },
  ) {
    super(message);
    this.name = "ApiError";
    this.status = options?.status;
    this.code = options?.code;
    this.details = options?.details;
  }
}

export function normalizeServerUrl(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) {
    throw new ApiError("请输入服务器 URL");
  }

  const candidate = /^[a-z][a-z\d+.-]*:\/\//i.test(trimmed)
    ? trimmed
    : `http://${trimmed}`;

  let parsed: URL;
  try {
    parsed = new URL(candidate);
  } catch {
    throw new ApiError("服务器 URL 格式不正确");
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new ApiError("服务器 URL 仅支持 HTTP 或 HTTPS");
  }

  parsed.hash = "";
  parsed.search = "";
  return parsed.toString().replace(/\/+$/, "");
}

export function buildApiUrl(baseUrl: string, path: string): string {
  const normalizedBase = normalizeServerUrl(baseUrl);
  return `${normalizedBase}${path.startsWith("/") ? path : `/${path}`}`;
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)
    : {};
}

function stringValue(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value : undefined;
}

function numberValue(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallback;
}

function optionalNumber(value: unknown): number | undefined {
  const parsed = numberValue(value, Number.NaN);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return Array.from(
    new Set(
      value
        .filter((item): item is string => typeof item === "string")
        .map((item) => item.trim())
        .filter(Boolean),
    ),
  );
}

function booleanValue(value: unknown, fallback = false): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function normalizeAuthUser(value: unknown): AuthUser {
  const record = asRecord(value);
  return {
    id: optionalString(record.id ?? record.user_id ?? record.userId),
    username: stringValue(
      record.username ?? record.name ?? record.account,
      "管理员",
    ),
    display_name: optionalString(
      record.display_name ?? record.displayName ?? record.nickname,
    ),
  };
}

function normalizeAuthSession(value: unknown): AuthSessionResponse {
  const record = asRecord(value);
  const token = stringValue(
    record.token ?? record.access_token ?? record.accessToken,
  );
  if (!token) {
    throw new ApiError("服务器未返回登录令牌，请检查认证接口响应");
  }
  const userValue = record.user ?? record.account ?? record.profile;
  return {
    token,
    user: userValue ? normalizeAuthUser(userValue) : undefined,
  };
}

function normalizeTrack(value: unknown, baseUrl: string): Track {
  const record = asRecord(value);
  const id = stringValue(record.id);
  const legacyGenre = optionalString(record.genre);
  const genres = stringArray(record.genres);
  const durationSeconds = optionalNumber(
    record.duration_seconds ?? record.durationSeconds ?? record.duration,
  );
  const durationMilliseconds = optionalNumber(
    record.duration_ms ?? record.durationMs,
  );

  return {
    id,
    title: stringValue(record.title, "未命名曲目"),
    artist: optionalString(record.artist),
    album: optionalString(record.album),
    album_artist: optionalString(
      record.album_artist ?? record.albumArtist,
    ),
    file_name: stringValue(
      record.file_name ?? record.fileName,
      stringValue(record.title, "unknown"),
    ),
    extension: stringValue(record.extension).replace(/^\./, "").toLowerCase(),
    size_bytes: numberValue(record.size_bytes ?? record.sizeBytes),
    modified: stringValue(record.modified, new Date(0).toISOString()),
    duration_seconds:
      durationSeconds ??
      (durationMilliseconds === undefined
        ? undefined
        : durationMilliseconds / 1000),
    artwork_url:
      optionalString(record.artwork_url ?? record.artworkUrl) ??
      (id
        ? buildApiUrl(
            baseUrl,
            `/api/v1/tracks/${encodeURIComponent(id)}/artwork`,
          )
        : undefined),
    genre: legacyGenre ?? (genres.length > 0 ? genres.join(", ") : undefined),
    genres:
      genres.length > 0 ? genres : legacyGenre ? [legacyGenre] : undefined,
    year: optionalNumber(record.year),
    track_number: optionalNumber(record.track_number ?? record.trackNumber),
    disc_number: optionalNumber(record.disc_number ?? record.discNumber),
    metadata_source: optionalString(
      record.metadata_source ?? record.metadataSource,
    ),
    metadata_error: optionalString(
      record.metadata_error ?? record.metadataError,
    ),
  };
}

function normalizePlaylist(value: unknown): Playlist | null {
  const record = asRecord(value);
  const id = stringValue(record.id);
  const name = stringValue(record.name).trim();
  if (!id || !name) {
    return null;
  }
  return {
    id,
    name,
    track_ids: stringArray(record.track_ids),
    created_at: stringValue(record.created_at, new Date(0).toISOString()),
    updated_at: stringValue(record.updated_at, new Date(0).toISOString()),
  };
}

function normalizeCollectionsSnapshot(value: unknown): CollectionsSnapshot {
  const record = asRecord(value);
  return {
    revision: numberValue(record.revision),
    favorite_track_ids: stringArray(record.favorite_track_ids),
    playlists: Array.isArray(record.playlists)
      ? record.playlists
          .map(normalizePlaylist)
          .filter((playlist): playlist is Playlist => playlist !== null)
      : [],
  };
}

function normalizeDiscoveryCategory(
  value: unknown,
  baseUrl: string,
  index: number,
): DiscoveryCategory {
  const record = asRecord(value);
  const trackValues = Array.isArray(record.tracks)
    ? record.tracks
    : Array.isArray(record.items)
      ? record.items
      : [];
  return {
    id: stringValue(record.id, `category-${index}`),
    name: stringValue(record.name, "未分类"),
    track_count: numberValue(record.track_count, trackValues.length),
    tracks: trackValues
      .map((track) => normalizeTrack(track, baseUrl))
      .filter((track) => track.id),
  };
}

function discoveryTrackValues(record: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const value = record[key];
    if (Array.isArray(value)) {
      return value;
    }
  }
  return [];
}

function normalizeDiscovery(value: unknown, baseUrl: string): DiscoveryResponse {
  const record = asRecord(value);
  const tracks = (keys: string[]) =>
    discoveryTrackValues(record, keys)
      .map((track) => normalizeTrack(track, baseUrl))
      .filter((track) => track.id);
  const rankedTracks = discoveryTrackValues(record, ["hot_tracks"])
    .map((track) => normalizeRankedTrack(track, baseUrl))
    .filter((track): track is RankedTrack => track !== null);
  const categoryValues = discoveryTrackValues(record, ["categories"]);

  return {
    for_you: tracks(["for_you"]),
    daily: tracks(["daily"]),
    recent_recommendations: tracks(["recent_recommendations"]),
    hot_tracks: rankedTracks,
    categories: categoryValues.map((category, index) =>
      normalizeDiscoveryCategory(category, baseUrl, index),
    ),
  };
}

function normalizeHeatmapCell(value: unknown): ListeningHeatmapCell | null {
  const record = asRecord(value);
  const date = stringValue(record.date);
  if (!date) {
    return null;
  }
  return {
    date,
    play_count: numberValue(record.play_count),
    listened_ms: numberValue(record.listened_ms),
  };
}

function normalizeRankedTrack(value: unknown, baseUrl: string): RankedTrack | null {
  const record = asRecord(value);
  const track = normalizeTrack(record.track, baseUrl);
  if (!track.id) {
    return null;
  }
  return {
    track,
    play_count: numberValue(record.play_count),
    listened_ms: numberValue(record.listened_ms),
  };
}

function normalizeListeningReport(
  value: unknown,
  baseUrl: string,
  year: number,
): ListeningReport {
  const record = asRecord(value);
  const heatmapValues = Array.isArray(record.heatmap)
    ? record.heatmap
    : [];
  const rankedValues = discoveryTrackValues(record, ["top_tracks"]);
  return {
    year: numberValue(record.year, year),
    total_listened_ms: numberValue(record.total_listened_ms),
    total_plays: numberValue(record.total_plays),
    listening_days: numberValue(record.listening_days),
    unique_tracks: numberValue(record.unique_tracks),
    unique_albums: numberValue(record.unique_albums),
    heatmap: heatmapValues
      .map(normalizeHeatmapCell)
      .filter((cell): cell is ListeningHeatmapCell => cell !== null),
    top_tracks: rankedValues
      .map((track) => normalizeRankedTrack(track, baseUrl))
      .filter((track): track is RankedTrack => track !== null),
  };
}

function normalizeMetadata(value: unknown): ScrapeMetadata {
  const record = asRecord(value);
  return {
    title: optionalString(record.title),
    artist: optionalString(record.artist),
    album: optionalString(record.album),
    album_artist: optionalString(record.album_artist ?? record.albumArtist),
    year: optionalNumber(record.year),
    track_number: optionalNumber(record.track_number ?? record.trackNumber),
    disc_number: optionalNumber(record.disc_number ?? record.discNumber),
    genre: optionalString(record.genre),
    artwork_url: optionalString(record.artwork_url ?? record.artworkUrl),
    lyrics: optionalString(record.lyrics),
  };
}

function normalizeScrapeValue(value: unknown): ScrapeValue {
  if (typeof value === "string" || typeof value === "number") {
    return value;
  }
  return null;
}

const scrapeFields: ScrapeFieldName[] = [
  "title",
  "artist",
  "album",
  "album_artist",
  "year",
  "track_number",
  "disc_number",
  "genre",
  "artwork_url",
  "lyrics",
];

function deriveDifferences(
  track: Track,
  metadata: ScrapeMetadata,
): ScrapeFieldDifference[] {
  const current: Partial<Record<ScrapeFieldName, ScrapeValue>> = {
    title: track.title,
    artist: track.artist ?? null,
    album: track.album ?? null,
    album_artist: track.album_artist ?? null,
    year: track.year ?? null,
    track_number: track.track_number ?? null,
    disc_number: track.disc_number ?? null,
    genre: track.genre ?? null,
    artwork_url: track.artwork_url ?? null,
  };

  return scrapeFields.flatMap((field) => {
    const candidate = metadata[field];
    if (candidate === undefined) {
      return [];
    }
    const currentValue = current[field] ?? null;
    return [
      {
        field,
        current: currentValue,
        candidate,
        changed: String(currentValue ?? "") !== String(candidate ?? ""),
      },
    ];
  });
}

function normalizeDifference(value: unknown): ScrapeFieldDifference | null {
  const record = asRecord(value);
  const field = stringValue(record.field) as ScrapeFieldName;
  if (!scrapeFields.includes(field)) {
    return null;
  }
  const current = normalizeScrapeValue(record.current);
  const candidate = normalizeScrapeValue(record.candidate);
  return {
    field,
    current,
    candidate,
    changed:
      typeof record.changed === "boolean"
        ? record.changed
        : String(current ?? "") !== String(candidate ?? ""),
  };
}

function normalizeCandidate(value: unknown, track: Track): ScrapeCandidate {
  const record = asRecord(value);
  const metadata = normalizeMetadata(record.metadata ?? record.fields);
  const rawConfidence = numberValue(record.confidence);
  const suppliedDifferences = Array.isArray(record.differences)
    ? record.differences
        .map(normalizeDifference)
        .filter((item): item is ScrapeFieldDifference => item !== null)
    : [];

  return {
    id: stringValue(record.id ?? record.candidate_id ?? record.candidateId),
    provider: stringValue(record.provider, "unknown"),
    confidence:
      rawConfidence > 1
        ? Math.min(rawConfidence / 100, 1)
        : Math.max(0, Math.min(rawConfidence, 1)),
    metadata,
    differences:
      suppliedDifferences.length > 0
        ? suppliedDifferences
        : deriveDifferences(track, metadata),
    source_url: optionalString(record.source_url ?? record.sourceUrl),
  };
}

async function parseResponseBody(response: Response): Promise<unknown> {
  if (response.status === 204) {
    return undefined;
  }
  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    return response.json();
  }
  const text = await response.text();
  return text ? { error: text } : undefined;
}

async function requestJson(
  baseUrl: string,
  path: string,
  init?: RequestInit,
  timeout = DEFAULT_TIMEOUT,
  options: MusicApiOptions = {},
): Promise<unknown> {
  const controller = new AbortController();
  const timer = globalThis.setTimeout(() => controller.abort(), timeout);

  try {
    const token = options.getToken?.();
    const response = await fetch(buildApiUrl(baseUrl, path), {
      ...init,
      headers: {
        Accept: "application/json",
        ...(init?.body ? { "Content-Type": "application/json" } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...init?.headers,
      },
      signal: controller.signal,
    });
    const body = await parseResponseBody(response);

    if (!response.ok) {
      if (response.status === 401) {
        options.onUnauthorized?.();
      }
      const errorBody = asRecord(body);
      throw new ApiError(
        stringValue(errorBody.error ?? errorBody.message, response.statusText) ||
          `请求失败（HTTP ${response.status}）`,
        {
          status: response.status,
          code: optionalString(errorBody.code),
          details: body,
        },
      );
    }
    return body;
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new ApiError("请求超时，请检查服务器状态");
    }
    throw new ApiError("无法连接服务器，请检查服务是否正在运行", {
      details: error,
    });
  } finally {
    globalThis.clearTimeout(timer);
  }
}

export function friendlyError(error: unknown): string {
  if (!(error instanceof ApiError)) {
    return "发生未知错误，请稍后重试";
  }
  if (error.status === 404) {
    return "接口或资源不存在，请确认后端版本是否支持此功能";
  }
  if (error.status === 401 || error.status === 403) {
    if (error.message === "invalid username or password") {
      return "账号或密码错误";
    }
    if (error.message === "registration is closed") {
      return "管理员账号已创建，请直接登录";
    }
    return "服务器拒绝了请求，请重新登录";
  }
  const translatedMessages: Record<string, string> = {
    "invalid username": "管理员账号格式不正确",
    "invalid password": "密码至少需要 12 个字符",
    "invalid request body": "提交内容格式不正确",
    "failed to create administrator": "创建管理员账号失败",
    "failed to create session": "登录会话创建失败",
  };
  const translatedMessage = translatedMessages[error.message];
  if (translatedMessage) {
    return translatedMessage;
  }
  if (error.status && error.status >= 500) {
    return `服务器处理失败：${error.message}`;
  }
  return error.message;
}

export interface MusicApi {
  authStatus(): Promise<AuthStatusResponse>;
  register(credentials: AuthCredentials): Promise<AuthUser>;
  login(credentials: AuthCredentials): Promise<AuthSessionResponse>;
  me(): Promise<AuthUser>;
  logout(): Promise<void>;
  health(): Promise<HealthResponse>;
  listTracks(): Promise<TrackListResponse>;
  listCollections(): Promise<CollectionsSnapshot>;
  addFavorite(trackId: string): Promise<CollectionsSnapshot>;
  removeFavorite(trackId: string): Promise<CollectionsSnapshot>;
  createPlaylist(
    request: CreatePlaylistRequest,
  ): Promise<CollectionsSnapshot>;
  updatePlaylist(
    playlistId: string,
    name: string,
  ): Promise<CollectionsSnapshot>;
  deletePlaylist(playlistId: string): Promise<CollectionsSnapshot>;
  addPlaylistTrack(
    playlistId: string,
    trackId: string,
  ): Promise<CollectionsSnapshot>;
  removePlaylistTrack(
    playlistId: string,
    trackId: string,
  ): Promise<CollectionsSnapshot>;
  importCollections(
    request: CollectionsImportRequest,
  ): Promise<CollectionsSnapshot>;
  recordListeningEvents(
    events: ListeningEventRequest[],
  ): Promise<ListeningEventIngestResult>;
  discovery(): Promise<DiscoveryResponse>;
  listeningReport(year: number): Promise<ListeningReport>;
  lyrics(trackId: string): Promise<LyricsResponse>;
  scanLibrary(): Promise<LibraryScanResponse>;
  libraryStatus(): Promise<LibraryStatusResponse>;
  searchScrape(
    track: Track,
    request?: ScrapeSearchRequest,
  ): Promise<ScrapeSearchResponse>;
  applyScrape(
    trackId: string,
    request: ScrapeApplyRequest,
  ): Promise<ScrapeApplyResponse>;
  streamBlob(trackId: string): Promise<Blob>;
}

async function requestBlob(
  baseUrl: string,
  path: string,
  options: MusicApiOptions,
): Promise<Blob> {
  const controller = new AbortController();
  const timer = globalThis.setTimeout(
    () => controller.abort(),
    LONG_JOB_TIMEOUT,
  );
  try {
    const token = options.getToken?.();
    const response = await fetch(buildApiUrl(baseUrl, path), {
      headers: token ? { Authorization: `Bearer ${token}` } : undefined,
      signal: controller.signal,
    });
    if (!response.ok) {
      if (response.status === 401) {
        options.onUnauthorized?.();
      }
      const body = await parseResponseBody(response);
      const errorBody = asRecord(body);
      throw new ApiError(
        stringValue(errorBody.error ?? errorBody.message, response.statusText) ||
          `请求失败（HTTP ${response.status}）`,
        { status: response.status, details: body },
      );
    }
    return response.blob();
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new ApiError("音频加载超时，请稍后重试");
    }
    throw new ApiError("无法加载音频，请检查服务是否正在运行", {
      details: error,
    });
  } finally {
    globalThis.clearTimeout(timer);
  }
}

export function createMusicApi(
  baseUrl: string,
  options: MusicApiOptions = {},
): MusicApi {
  const normalizedBase = normalizeServerUrl(baseUrl);
  const requestApi = (
    path: string,
    init?: RequestInit,
    timeout?: number,
  ) => requestJson(normalizedBase, path, init, timeout, options);

  return {
    async authStatus() {
      const body = asRecord(await requestApi(AUTH_PATHS.status));
      const initializedValue =
        body.initialized ?? body.is_initialized ?? body.isInitialized;
      const setupRequired =
        body.setup_required ?? body.setupRequired ?? body.needs_initialization;
      return {
        initialized:
          typeof initializedValue === "boolean"
            ? initializedValue
            : typeof setupRequired === "boolean"
              ? !setupRequired
              : false,
      };
    },

    async register(credentials) {
      return normalizeAuthUser(
        await requestApi(AUTH_PATHS.register, {
          method: "POST",
          body: JSON.stringify(credentials),
        }),
      );
    },

    async login(credentials) {
      return normalizeAuthSession(
        await requestApi(AUTH_PATHS.login, {
          method: "POST",
          body: JSON.stringify(credentials),
        }),
      );
    },

    async me() {
      const body = asRecord(await requestApi(AUTH_PATHS.me));
      return normalizeAuthUser(body.user ?? body.account ?? body);
    },

    async logout() {
      await requestApi(AUTH_PATHS.logout, { method: "POST" });
    },

    async health() {
      const body = asRecord(await requestApi("/healthz"));
      return { status: stringValue(body.status, "unknown") };
    },

    async listTracks() {
      const body = asRecord(
        await requestApi("/api/v1/tracks"),
      );
      const tracks = Array.isArray(body.tracks)
        ? body.tracks
            .map((track) => normalizeTrack(track, normalizedBase))
            .filter((track) => track.id)
        : [];
      return {
        tracks,
        total: numberValue(body.total, tracks.length),
      };
    },

    async listCollections() {
      return normalizeCollectionsSnapshot(
        await requestApi("/api/v1/me/collections"),
      );
    },

    async addFavorite(trackId) {
      return normalizeCollectionsSnapshot(
        await requestApi(
          `/api/v1/me/favorites/${encodeURIComponent(trackId)}`,
          { method: "PUT" },
        ),
      );
    },

    async removeFavorite(trackId) {
      return normalizeCollectionsSnapshot(
        await requestApi(
          `/api/v1/me/favorites/${encodeURIComponent(trackId)}`,
          { method: "DELETE" },
        ),
      );
    },

    async createPlaylist(request) {
      return normalizeCollectionsSnapshot(await requestApi("/api/v1/me/playlists", {
        method: "POST",
        body: JSON.stringify(request),
      }));
    },

    async updatePlaylist(playlistId, name) {
      return normalizeCollectionsSnapshot(await requestApi(
        `/api/v1/me/playlists/${encodeURIComponent(playlistId)}`,
        {
          method: "PATCH",
          body: JSON.stringify({ name }),
        },
      ));
    },

    async deletePlaylist(playlistId) {
      return normalizeCollectionsSnapshot(await requestApi(
        `/api/v1/me/playlists/${encodeURIComponent(playlistId)}`,
        { method: "DELETE" },
      ));
    },

    async addPlaylistTrack(playlistId, trackId) {
      return normalizeCollectionsSnapshot(await requestApi(
        `/api/v1/me/playlists/${encodeURIComponent(playlistId)}/tracks/${encodeURIComponent(trackId)}`,
        { method: "PUT" },
      ));
    },

    async removePlaylistTrack(playlistId, trackId) {
      return normalizeCollectionsSnapshot(await requestApi(
        `/api/v1/me/playlists/${encodeURIComponent(playlistId)}/tracks/${encodeURIComponent(trackId)}`,
        { method: "DELETE" },
      ));
    },

    async importCollections(request) {
      return normalizeCollectionsSnapshot(
        await requestApi("/api/v1/me/collections/import", {
          method: "POST",
          body: JSON.stringify(request),
        }),
      );
    },

    async recordListeningEvents(events) {
      const body = asRecord(await requestApi("/api/v1/listening/events", {
        method: "POST",
        body: JSON.stringify({ events }),
      }));
      return {
        accepted: numberValue(body.accepted),
        duplicates: numberValue(body.duplicates),
      };
    },

    async discovery() {
      return normalizeDiscovery(
        await requestApi("/api/v1/discovery"),
        normalizedBase,
      );
    },

    async listeningReport(year) {
      const params = new URLSearchParams({ year: String(year) });
      return normalizeListeningReport(
        await requestApi(`/api/v1/listening/report?${params.toString()}`),
        normalizedBase,
        year,
      );
    },

    async lyrics(trackId) {
      const body = asRecord(
        await requestApi(
          `/api/v1/tracks/${encodeURIComponent(trackId)}/lyrics`,
        ),
      );
      return {
        track_id: stringValue(body.track_id ?? body.trackId, trackId),
        encoding: stringValue(body.encoding, "UTF-8"),
        content: stringValue(body.content),
      };
    },

    async scanLibrary() {
      const body = asRecord(
        await requestApi(
          "/api/v1/library/scan",
          {
            method: "POST",
          },
          LONG_JOB_TIMEOUT,
        ),
      );
      const tracks = Array.isArray(body.tracks)
        ? body.tracks
            .map((track) => normalizeTrack(track, normalizedBase))
            .filter((track) => track.id)
        : [];
      return {
        tracks,
        total: numberValue(body.total, tracks.length),
        scanned_at: stringValue(body.scanned_at ?? body.scannedAt),
      };
    },

    async libraryStatus() {
      const body = asRecord(
        await requestApi("/api/v1/library/status"),
      );
      return {
        directory: stringValue(body.directory),
        track_count: numberValue(body.track_count ?? body.trackCount),
        scanning: booleanValue(body.scanning),
        last_scanned_at:
          optionalString(body.last_scanned_at ?? body.lastScannedAt) ?? null,
        last_error: optionalString(body.last_error ?? body.lastError) ?? null,
      };
    },

    async searchScrape(track, request = {}) {
      const body = asRecord(
        await requestApi(
          `/api/v1/tracks/${encodeURIComponent(track.id)}/scrape/search`,
          {
            method: "POST",
            body: JSON.stringify(request),
          },
          LONG_JOB_TIMEOUT,
        ),
      );
      const values = Array.isArray(body.candidates)
        ? body.candidates
        : Array.isArray(body.results)
          ? body.results
          : [];
      return {
        track_id: stringValue(body.track_id ?? body.trackId, track.id),
        candidates: values.map((value) => normalizeCandidate(value, track)),
        searched_at: optionalString(body.searched_at ?? body.searchedAt),
      };
    },

    async applyScrape(trackId, request) {
      const body = asRecord(
        await requestApi(
          `/api/v1/tracks/${encodeURIComponent(trackId)}/scrape/apply`,
          {
            method: "POST",
            body: JSON.stringify(request),
          },
          LONG_JOB_TIMEOUT,
        ),
      );
      return {
        track: normalizeTrack(body.track, normalizedBase),
        provider: stringValue(body.provider, request.provider),
        applied_fields: Array.isArray(body.applied_fields)
          ? (body.applied_fields.filter((field) =>
              scrapeFields.includes(field as ScrapeFieldName),
            ) as ScrapeFieldName[])
          : request.fields,
        applied_at: stringValue(
          body.applied_at ?? body.appliedAt,
          new Date().toISOString(),
        ),
        message: optionalString(body.message),
      };
    },

    streamBlob(trackId) {
      return requestBlob(
        normalizedBase,
        `/api/v1/tracks/${encodeURIComponent(trackId)}/stream`,
        options,
      );
    },
  };
}
