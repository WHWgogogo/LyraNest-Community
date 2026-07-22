import { describe, expect, it } from "vitest";
import { activeLyricIndex, parseLyrics } from "./lyrics";

describe("parseLyrics", () => {
  it("parses and sorts synchronized LRC lines", () => {
    const lines = parseLyrics("[00:10.50]第二句\n[00:02.00]第一句");

    expect(lines.map((line) => line.text)).toEqual(["第一句", "第二句"]);
    expect(lines[0]?.time).toBe(2);
    expect(lines[1]?.time).toBe(10.5);
  });

  it("keeps plain text lyrics", () => {
    expect(parseLyrics("第一行\n第二行").map((line) => line.text)).toEqual([
      "第一行",
      "第二行",
    ]);
  });
});

describe("activeLyricIndex", () => {
  it("returns the latest line before playback time", () => {
    const lines = parseLyrics("[00:01]一\n[00:05]二\n[00:09]三");
    expect(activeLyricIndex(lines, 6)).toBe(1);
  });
});
