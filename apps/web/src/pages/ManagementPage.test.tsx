import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import type { MusicApi } from "../api/client";
import type { Track } from "../api/types";
import { ManagementPage } from "./ManagementPage";

function track(index: number): Track {
  return {
    id: `track-${index}`,
    title: `曲目 ${index}`,
    artist: `艺人 ${index}`,
    file_name: `track-${index}.flac`,
    extension: "flac",
    size_bytes: 1024,
    modified: "2026-07-18T12:00:00Z",
  };
}

const api = {} as MusicApi;

describe("ManagementPage scrape workbench", () => {
  it("offers every local track for selection instead of a fixed recent subset", () => {
    const markup = renderToStaticMarkup(
      <ManagementPage
        api={api}
        connected
        onNotify={vi.fn()}
        onOpenScrape={vi.fn()}
        onRefreshTracks={async () => {}}
        tracks={Array.from({ length: 7 }, (_, index) => track(index + 1))}
      />,
    );

    expect(markup).toContain("搜索标题、艺人、专辑或文件名");
    expect(markup).toContain("曲目 7");
    expect(markup).toContain("打开刮削");
  });
});
