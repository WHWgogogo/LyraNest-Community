import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import type { LyricLine as ParsedLyricLine } from "../utils/lyrics";
import { LyricLine } from "./LyricsDrawer";

function renderLine(
  line: ParsedLyricLine,
  active = false,
  onSeek = vi.fn(),
) {
  return {
    element: LyricLine({ active, line, onSeek }),
    onSeek,
  };
}

describe("LyricLine", () => {
  it("uses keyboard-accessible buttons for active and inactive timed lines", () => {
    const activeLine = renderLine(
      { id: "active", time: 12.5, text: "当前行" },
      true,
    );
    const inactiveLine = renderLine({
      id: "inactive",
      time: 38,
      text: "非当前行",
    });

    const activeProps = activeLine.element.props as {
      onClick(): void;
      type: string;
    };
    const inactiveProps = inactiveLine.element.props as {
      onClick(): void;
      type: string;
    };

    expect(activeLine.element.type).toBe("button");
    expect(activeProps.type).toBe("button");
    expect(inactiveLine.element.type).toBe("button");
    expect(inactiveProps.type).toBe("button");

    activeProps.onClick();
    inactiveProps.onClick();

    expect(activeLine.onSeek).toHaveBeenCalledWith(12.5);
    expect(inactiveLine.onSeek).toHaveBeenCalledWith(38);
  });

  it("keeps untimed lyrics non-interactive", () => {
    const { element } = renderLine({
      id: "plain",
      time: null,
      text: "纯文本行",
    });
    const markup = renderToStaticMarkup(element);

    expect(element.type).toBe("p");
    expect(element.props).not.toHaveProperty("onClick");
    expect(markup).not.toContain("<button");
  });
});
