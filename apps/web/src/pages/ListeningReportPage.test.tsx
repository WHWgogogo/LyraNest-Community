import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import type { ListeningReport } from "../api/types";
import { ListeningReportPage } from "./ListeningReportPage";

const report: ListeningReport = {
  year: 2026,
  total_plays: 12,
  total_listened_ms: 3_600_000,
  listening_days: 4,
  unique_tracks: 3,
  unique_albums: 2,
  heatmap: [{ date: "2026-07-20", play_count: 3, listened_ms: 600_000 }],
  top_tracks: [
    {
      play_count: 5,
      listened_ms: 900_000,
      track: {
        id: "track-1",
        title: "热门曲目",
        artist: "测试艺术家",
        file_name: "track-1.flac",
        extension: "flac",
        size_bytes: 1024,
        modified: "2026-07-20T00:00:00Z",
      },
    },
  ],
};

describe("ListeningReportPage", () => {
  it("renders report statistics, heatmap and ranking", () => {
    const markup = renderToStaticMarkup(
      <ListeningReportPage
        error={null}
        loading={false}
        onPlay={vi.fn()}
        onRefresh={vi.fn()}
        report={report}
      />,
    );

    expect(markup).toContain("2026 听歌报告");
    expect(markup).toContain("年度热力图");
    expect(markup).toContain("热门榜");
    expect(markup).toContain("热门曲目");
  });
});
