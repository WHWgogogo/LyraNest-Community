import { describe, expect, it } from "vitest";
import {
  hasVisitedSupport,
  recordSupportVisit,
  type SupportVisitStorage,
} from "./supportVisit";

function createStorage(): SupportVisitStorage {
  const values = new Map<string, string>();
  return {
    getItem(key) {
      return values.get(key) ?? null;
    },
    setItem(key, value) {
      values.set(key, value);
    },
  };
}

describe("support visit storage", () => {
  it("hides the notice permanently after the support page is opened", () => {
    const storage = createStorage();

    expect(hasVisitedSupport(storage)).toBe(false);

    recordSupportVisit(storage);

    expect(hasVisitedSupport(storage)).toBe(true);
  });
});
