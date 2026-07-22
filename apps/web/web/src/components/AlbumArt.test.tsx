import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { Track } from "../api/types";
import { AlbumArt, handleAlbumArtError } from "./AlbumArt";

const track: Track = {
  id: "track-1",
  title: "测试歌曲",
  file_name: "test.flac",
  extension: "flac",
  size_bytes: 1024,
  modified: "2026-07-18T12:00:00Z",
  artwork_url: "http://localhost:8080/api/v1/tracks/track-1/artwork",
};

describe("AlbumArt", () => {
  it("renders the artwork URL with a hidden icon fallback", () => {
    const markup = renderToStaticMarkup(<AlbumArt track={track} />);

    expect(markup).toContain(`src="${track.artwork_url}"`);
    expect(markup).toContain('aria-label="封面加载失败"');
    expect(markup).toContain("hidden");
  });

  it("hides a failed image and reveals the fallback icon", () => {
    const fallback = { hidden: true };
    const image = {
      hidden: false,
      nextElementSibling: fallback,
    };

    handleAlbumArtError({
      currentTarget: image,
    } as unknown as Parameters<typeof handleAlbumArtError>[0]);

    expect(image.hidden).toBe(true);
    expect(fallback.hidden).toBe(false);
  });
});
