import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import type { MusicApi } from "../api/client";
import type {
  CollectionsSnapshot,
  CreatePlaylistRequest,
  Track,
} from "../api/types";
import {
  isRetryableCollectionOutboxError,
  useCollections,
} from "./useCollections";

const emptySnapshot: CollectionsSnapshot = {
  revision: 1,
  favorite_track_ids: [],
  playlists: [],
};

const favoriteTrack: Track = {
  id: "track-1",
  title: "Test track",
  file_name: "test.mp3",
  extension: "mp3",
  size_bytes: 1,
  modified: "2026-07-20T00:00:00.000Z",
};

function renderCollectionsHook(api: MusicApi) {
  let result: ReturnType<typeof useCollections> | undefined;

  function Harness() {
    result = useCollections({ api, userKey: "user-a" });
    return null;
  }

  renderToStaticMarkup(createElement(Harness));
  if (!result) {
    throw new Error("Collections hook did not render");
  }
  return result;
}

describe("collection outbox failures", () => {
  it("discards permanent 4xx failures but retries transient errors", () => {
    for (const status of [400, 401, 403, 404, 413, 422]) {
      expect(isRetryableCollectionOutboxError({ status })).toBe(false);
    }
    for (const status of [408, 409, 429, 500, 503]) {
      expect(isRetryableCollectionOutboxError({ status })).toBe(true);
    }
    expect(isRetryableCollectionOutboxError(new Error("offline"))).toBe(true);
  });

  it("refreshes after a permanent failure and flushes the next operation", async () => {
    const api = {
      addFavorite: vi.fn().mockResolvedValue({
        ...emptySnapshot,
        revision: 2,
        favorite_track_ids: [favoriteTrack.id],
      }),
      createPlaylist: vi.fn().mockRejectedValue({ status: 400 }),
      listCollections: vi.fn().mockResolvedValue(emptySnapshot),
    } as unknown as MusicApi;
    const collections = renderCollectionsHook(api);

    collections.createPlaylist("Invalid playlist");
    collections.toggleFavorite(favoriteTrack);

    await vi.waitFor(() => {
      expect(api.listCollections).toHaveBeenCalledTimes(1);
      expect(api.addFavorite).toHaveBeenCalledWith(favoriteTrack.id);
    });
  });

  it("reuses the client playlist id after a retryable create failure", async () => {
    let rejectFirstAttempt: (reason?: unknown) => void = () => undefined;
    const firstAttempt = new Promise<CollectionsSnapshot>((_resolve, reject) => {
      rejectFirstAttempt = reject;
    });
    let attempts = 0;
    const createPlaylist = vi.fn((request: CreatePlaylistRequest) => {
      attempts += 1;
      if (attempts === 1) {
        return firstAttempt;
      }
      return Promise.resolve({
        ...emptySnapshot,
        playlists: [
          {
            id: request.id ?? "",
            name: request.name,
            track_ids: [],
            created_at: "2026-07-20T00:00:00.000Z",
            updated_at: "2026-07-20T00:00:00.000Z",
          },
        ],
      });
    });
    const api = {
      createPlaylist,
      listCollections: vi.fn().mockResolvedValue(emptySnapshot),
    } as unknown as MusicApi;
    const collections = renderCollectionsHook(api);

    collections.createPlaylist("Commute");
    await vi.waitFor(() => {
      expect(createPlaylist).toHaveBeenCalledTimes(1);
    });
    rejectFirstAttempt(new Error("offline"));
    await new Promise((resolve) => setTimeout(resolve, 0));

    await collections.refresh();

    expect(createPlaylist).toHaveBeenCalledTimes(2);
    expect(createPlaylist.mock.calls[1]?.[0]).toEqual(
      createPlaylist.mock.calls[0]?.[0],
    );
  });
});
