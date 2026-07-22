import { describe, expect, it } from "vitest";
import {
  getRelativeQueueIndex,
  nextPlayMode,
  playModeLabels,
} from "./playback";

describe("播放队列策略", () => {
  it("在顺序播放末尾停止，而列表循环会回到开头", () => {
    expect(
      getRelativeQueueIndex({
        queueLength: 3,
        currentIndex: 2,
        mode: "order",
      }),
    ).toBeNull();
    expect(
      getRelativeQueueIndex({
        queueLength: 3,
        currentIndex: 2,
        mode: "list-loop",
      }),
    ).toBe(0);
  });

  it("单曲循环保持当前位置，随机播放避开当前曲目", () => {
    expect(
      getRelativeQueueIndex({
        queueLength: 3,
        currentIndex: 1,
        mode: "single-loop",
      }),
    ).toBe(1);
    expect(
      getRelativeQueueIndex({
        queueLength: 3,
        currentIndex: 1,
        mode: "shuffle",
        random: () => 0,
      }),
    ).toBe(2);
  });

  it("循环切换四种播放模式", () => {
    expect(nextPlayMode("order")).toBe("list-loop");
    expect(nextPlayMode("shuffle")).toBe("order");
    expect(playModeLabels["single-loop"]).toBe("单曲循环");
  });
});
