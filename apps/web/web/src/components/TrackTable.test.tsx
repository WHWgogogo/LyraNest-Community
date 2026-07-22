import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import type { Track } from "../api/types";
import { TrackTable } from "./TrackTable";

function track(overrides: Partial<Track>): Track {
  return {
    id: "track-1",
    title: "测试曲目",
    file_name: "test.flac",
    extension: "flac",
    size_bytes: 1024,
    modified: "2026-07-18T12:00:00Z",
    ...overrides,
  };
}

describe("TrackTable metadata compatibility", () => {
  it("renders genre arrays and friendly metadata sources", () => {
    const markup = renderToStaticMarkup(
      <TrackTable
        isPlaying={false}
        onLyrics={vi.fn()}
        onPlay={vi.fn()}
        onScrape={vi.fn()}
        tracks={[
          track({
            genres: ["Pop", "Mandopop"],
            metadata_source: "embedded",
          }),
        ]}
      />,
    );

    expect(markup).toContain("Pop · Mandopop");
    expect(markup).toContain("内嵌标签");
    expect(markup).toContain("来自音频文件");
  });

  it("shows a friendly fallback when metadata reading fails", () => {
    const markup = renderToStaticMarkup(
      <TrackTable
        isPlaying={false}
        onLyrics={vi.fn()}
        onPlay={vi.fn()}
        onScrape={vi.fn()}
        tracks={[
          track({
            metadata_source: "filename",
            metadata_error: "unsupported tag payload",
          }),
        ]}
      />,
    );

    expect(markup).toContain("读取异常");
    expect(markup).toContain("已回退到文件名");
    expect(markup).toContain("unsupported tag payload");
  });
});
