import { afterEach, describe, expect, it, vi } from "vitest";
import { buildApiUrl, createMusicApi, normalizeServerUrl } from "./client";
import personalResponses from "./fixtures/personal-responses.json";

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json" },
    status: 200,
  });
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("normalizeServerUrl", () => {
  it("adds an HTTP protocol and removes trailing slashes", () => {
    expect(normalizeServerUrl("localhost:8080///")).toBe(
      "http://localhost:8080",
    );
  });

  it("keeps HTTPS URLs", () => {
    expect(normalizeServerUrl("https://music.example.com/")).toBe(
      "https://music.example.com",
    );
  });
});

describe("buildApiUrl", () => {
  it("joins an API path safely", () => {
    expect(buildApiUrl("http://localhost:8080", "/healthz")).toBe(
      "http://localhost:8080/healthz",
    );
  });
});

describe("authentication API contracts", () => {
  it("checks initialization and normalizes a registration session", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({ setup_required: true }))
      .mockResolvedValueOnce(
        jsonResponse({ id: "admin-1", username: "admin" }),
      );
    vi.stubGlobal("fetch", fetchMock);
    const api = createMusicApi("http://localhost:8080");

    await expect(api.authStatus()).resolves.toEqual({ initialized: false });
    await expect(
      api.register({ username: "admin", password: "long-enough-secret" }),
    ).resolves.toEqual({ id: "admin-1", username: "admin" });
    expect(fetchMock).toHaveBeenLastCalledWith(
      "http://localhost:8080/api/v1/auth/register",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({
          username: "admin",
          password: "long-enough-secret",
        }),
      }),
    );
  });

  it("adds the bearer token and reports unauthorized sessions", async () => {
    const onUnauthorized = vi.fn();
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: "unauthorized" }), {
        headers: { "Content-Type": "application/json" },
        status: 401,
      }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const api = createMusicApi("http://localhost:8080", {
      getToken: () => "saved-token",
      onUnauthorized,
    });

    await expect(api.listTracks()).rejects.toMatchObject({ status: 401 });
    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/tracks",
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: "Bearer saved-token",
        }),
      }),
    );
    expect(onUnauthorized).toHaveBeenCalledTimes(1);
  });
});

describe("library API contracts", () => {
  it("normalizes current backend track metadata fields", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        tracks: [
          {
            id: "track-rich",
            title: "完整标签",
            artist: "主艺术家",
            album: "测试专辑",
            album_artist: "专辑艺术家",
            year: 2026,
            track_number: 3,
            disc_number: 2,
            genres: [" Pop ", "Mandopop", "Pop", ""],
            duration_ms: 185432,
            file_name: "rich.flac",
            extension: "flac",
            size_bytes: 4096,
            modified: "2026-07-18T12:00:00Z",
            metadata_source: "embedded",
            metadata_error: " ",
          },
        ],
        total: 1,
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await createMusicApi(
      "http://localhost:8080",
    ).listTracks();

    expect(result.tracks[0]).toEqual({
      id: "track-rich",
      title: "完整标签",
      artist: "主艺术家",
      album: "测试专辑",
      album_artist: "专辑艺术家",
      file_name: "rich.flac",
      extension: "flac",
      size_bytes: 4096,
      modified: "2026-07-18T12:00:00Z",
      duration_seconds: 185.432,
      artwork_url:
        "http://localhost:8080/api/v1/tracks/track-rich/artwork",
      genre: "Pop, Mandopop",
      genres: ["Pop", "Mandopop"],
      year: 2026,
      track_number: 3,
      disc_number: 2,
      metadata_source: "embedded",
    });
  });

  it("keeps legacy duration and genre fields compatible", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        tracks: [
          {
            id: "track-legacy",
            title: "旧接口曲目",
            duration_seconds: 90,
            duration_ms: 999999,
            genre: "Rock",
            file_name: "legacy.mp3",
            extension: "mp3",
            size_bytes: 2048,
            modified: "2026-07-18T12:00:00Z",
          },
        ],
        total: 1,
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await createMusicApi(
      "http://localhost:8080",
    ).listTracks();

    expect(result.tracks[0]).toMatchObject({
      duration_seconds: 90,
      genre: "Rock",
      genres: ["Rock"],
    });
  });

  it("normalizes the real library scan response", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        tracks: [
          {
            id: "track-1",
            title: "测试歌曲",
            file_name: "test.flac",
            extension: ".FLAC",
            size_bytes: 1024,
            modified: "2026-07-18T12:00:00Z",
          },
        ],
        total: 1,
        scanned_at: "2026-07-18T12:01:00Z",
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await createMusicApi(
      "http://localhost:8080",
    ).scanLibrary();

    expect(result).toEqual({
      tracks: [
        {
          id: "track-1",
          title: "测试歌曲",
          file_name: "test.flac",
          extension: "flac",
          size_bytes: 1024,
          modified: "2026-07-18T12:00:00Z",
          artwork_url:
            "http://localhost:8080/api/v1/tracks/track-1/artwork",
        },
      ],
      total: 1,
      scanned_at: "2026-07-18T12:01:00Z",
    });
    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/library/scan",
      expect.objectContaining({ method: "POST" }),
    );
    const request = fetchMock.mock.calls[0]?.[1] as RequestInit | undefined;
    expect(request?.body).toBeUndefined();
  });

  it("normalizes the real library status response", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        directory: "D:\\Music",
        track_count: 42,
        scanning: false,
        last_scanned_at: "2026-07-18T12:01:00Z",
        last_error: null,
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await createMusicApi(
      "http://localhost:8080",
    ).libraryStatus();

    expect(result).toEqual({
      directory: "D:\\Music",
      track_count: 42,
      scanning: false,
      last_scanned_at: "2026-07-18T12:01:00Z",
      last_error: null,
    });
    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/library/status",
      expect.objectContaining({
        headers: expect.objectContaining({ Accept: "application/json" }),
      }),
    );
  });

  it("preserves explicit backend artwork URLs", async () => {
    const artworkUrl = "https://images.example.com/covers/track.jpg";
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        tracks: [
          {
            id: "track-artwork",
            title: "已有封面",
            artwork_url: artworkUrl,
          },
        ],
        total: 1,
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await createMusicApi(
      "http://localhost:8080",
    ).listTracks();

    expect(result.tracks[0]?.artwork_url).toBe(artworkUrl);
  });

  it("preserves scrape candidate artwork URLs", async () => {
    const artworkUrl = "https://covers.example.com/candidate.png";
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        track_id: "track-1",
        candidates: [
          {
            id: "candidate-1",
            provider: "cover-art",
            confidence: 0.9,
            metadata: {
              artwork_url: artworkUrl,
            },
          },
        ],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await createMusicApi(
      "http://localhost:8080",
    ).searchScrape({
      id: "track-1",
      title: "测试歌曲",
      file_name: "test.flac",
      extension: "flac",
      size_bytes: 1024,
      modified: "2026-07-18T12:00:00Z",
    });

    expect(result.candidates[0]?.metadata.artwork_url).toBe(artworkUrl);
  });

  it("sends manual scrape search fields and a candidate limit", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({
        track_id: "track-1",
        candidates: [],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await createMusicApi("http://localhost:8080").searchScrape(
      {
        id: "track-1",
        title: "原始标题",
        file_name: "test.flac",
        extension: "flac",
        size_bytes: 1024,
        modified: "2026-07-18T12:00:00Z",
      },
      {
        title: "手动标题",
        artist: "手动艺人",
        album: "手动专辑",
        limit: 20,
      },
    );

    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/tracks/track-1/scrape/search",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({
          title: "手动标题",
          artist: "手动艺人",
          album: "手动专辑",
          limit: 20,
        }),
      }),
    );
  });
});

describe("third-stage API contracts", () => {
  it("uses real personal-data paths and snapshot responses", async () => {
    const fetchMock = vi
      .fn()
      .mockImplementation(() => Promise.resolve(jsonResponse(personalResponses.collections)));
    vi.stubGlobal("fetch", fetchMock);
    const api = createMusicApi("http://localhost:8080");

    await expect(api.listCollections()).resolves.toMatchObject({
      revision: 7,
      favorite_track_ids: ["track-1"],
      playlists: [{ id: "playlist-1", track_ids: ["track-2"] }],
    });
    await api.addFavorite("track-2");
    await api.removeFavorite("track-2");
    await api.createPlaylist({ id: "client-playlist-1", name: "通勤" });
    await api.updatePlaylist("playlist-1", "专注");
    await api.addPlaylistTrack("playlist-1", "track-3");
    await api.removePlaylistTrack("playlist-1", "track-3");
    await api.deletePlaylist("playlist-1");
    await api.importCollections({
      revision: 7,
      favorite_track_ids: ["track-1"],
      playlists: [{ name: "通勤", track_ids: ["track-2"] }],
    });

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      "http://localhost:8080/api/v1/me/collections",
      expect.objectContaining({
        headers: expect.objectContaining({ Accept: "application/json" }),
      }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      "http://localhost:8080/api/v1/me/favorites/track-2",
      expect.objectContaining({
        method: "PUT",
      }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      3,
      "http://localhost:8080/api/v1/me/favorites/track-2",
      expect.objectContaining({
        method: "DELETE",
      }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      4,
      "http://localhost:8080/api/v1/me/playlists",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ id: "client-playlist-1", name: "通勤" }),
      }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      5,
      "http://localhost:8080/api/v1/me/playlists/playlist-1",
      expect.objectContaining({
        method: "PATCH",
        body: JSON.stringify({ name: "专注" }),
      }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      6,
      "http://localhost:8080/api/v1/me/playlists/playlist-1/tracks/track-3",
      expect.objectContaining({ method: "PUT" }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      7,
      "http://localhost:8080/api/v1/me/playlists/playlist-1/tracks/track-3",
      expect.objectContaining({ method: "DELETE" }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      8,
      "http://localhost:8080/api/v1/me/playlists/playlist-1",
      expect.objectContaining({ method: "DELETE" }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      9,
      "http://localhost:8080/api/v1/me/collections/import",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({
          revision: 7,
          favorite_track_ids: ["track-1"],
          playlists: [{ name: "通勤", track_ids: ["track-2"] }],
        }),
      }),
    );
  });

  it("normalizes real discovery and listening-report fixtures", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(personalResponses.discovery))
      .mockResolvedValueOnce(jsonResponse(personalResponses.report));
    vi.stubGlobal("fetch", fetchMock);
    const api = createMusicApi("http://localhost:8080");

    await expect(api.discovery()).resolves.toMatchObject({
      for_you: [{ id: "track-1" }],
      daily: [{ id: "track-2" }],
      hot_tracks: [{ track: { id: "track-1" }, listened_ms: 3000 }],
      categories: [{ name: "Pop", track_count: 2 }],
    });
    await expect(api.listeningReport(2026)).resolves.toMatchObject({
      year: 2026,
      total_listened_ms: 3500,
      total_plays: 3,
      heatmap: [{ date: "2026-07-20", listened_ms: 3500 }],
      top_tracks: [{ track: { id: "track-1" }, play_count: 2 }],
    });
    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      "http://localhost:8080/api/v1/discovery",
      expect.any(Object),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      "http://localhost:8080/api/v1/listening/report?year=2026",
      expect.any(Object),
    );
  });

  it("posts bounded listening-event batches with server field names", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(personalResponses.event_ingest),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(
      createMusicApi("http://localhost:8080").recordListeningEvents([
        {
          event_id: "event-1",
          track_id: "track-1",
          listened_ms: 32_000,
          completed: false,
          played_at: "2026-07-20T00:00:00Z",
        },
      ]),
    ).resolves.toEqual({ accepted: 3, duplicates: 0 });

    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:8080/api/v1/listening/events",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({
          events: [
            {
              event_id: "event-1",
              track_id: "track-1",
              listened_ms: 32_000,
              completed: false,
              played_at: "2026-07-20T00:00:00Z",
            },
          ],
        }),
      }),
    );
  });
});
