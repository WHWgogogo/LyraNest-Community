import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import type { DiscoveryResponse, Track } from "../api/types";
import { DiscoveryPage } from "./DiscoveryPage";

const track: Track = {
  id: "track-1",
  title: "测试曲目",
  artist: "测试艺术家",
  album: "测试专辑",
  file_name: "track-1.flac",
  extension: "flac",
  size_bytes: 1024,
  modified: "2026-07-20T00:00:00Z",
};

const dailyTracks = Array.from({ length: 31 }, (_, index) => ({
  ...track,
  id: `daily-${index + 1}`,
  title: `每日曲目 ${index + 1}`,
}));

const response: DiscoveryResponse = {
  for_you: [track],
  daily: dailyTracks,
  hot_tracks: [{ track, play_count: 3, listened_ms: 600_000 }],
  categories: [{ id: "pop", name: "流行", track_count: 1, tracks: [track] }],
  recent_recommendations: [track],
};

describe("DiscoveryPage", () => {
  it("renders visible discovery sections without category playlists", () => {
    const markup = renderToStaticMarkup(
      <DiscoveryPage
        data={response}
        error={null}
        isPlaying={false}
        loading={false}
        onPlay={vi.fn()}
        onRefresh={vi.fn()}
        onSearch={vi.fn()}
        onSubmitSearch={vi.fn()}
        search="测试"
        searchResults={[track]}
      />,
    );

    expect(markup).toContain("猜你喜欢");
    expect(markup).toContain("每日 30 首");
    expect(markup).toContain("每日曲目 30");
    expect(markup).not.toContain("每日曲目 31");
    expect(markup).toContain("排行榜");
    expect(markup).toContain("最近听歌推荐");
    expect(markup).not.toContain("分类");
    expect(markup).not.toContain("流行");
  });
});
