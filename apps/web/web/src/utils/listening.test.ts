import { describe, expect, it } from "vitest";
import { createListeningEvent, playbackDelta } from "./listening";

describe("listening event accumulation", () => {
  it("counts contiguous audio progress but ignores seeks and long gaps", () => {
    expect(playbackDelta(10, 12.5)).toBe(2.5);
    expect(playbackDelta(10, 42)).toBe(0);
    expect(playbackDelta(42, 18)).toBe(0);
  });

  it("emits only real listening segments", () => {
    expect(createListeningEvent("track-1", "pause", 0.8, 4)).toBeNull();
    expect(
      createListeningEvent("track-1", "completed", 64.9, 65.2, 180),
    ).toMatchObject({
      track_id: "track-1",
      listened_ms: 64_900,
      completed: true,
      played_at: expect.any(String),
    });
  });
});
