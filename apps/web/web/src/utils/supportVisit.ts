export const SUPPORT_VISIT_STORAGE_KEY = "lyranest.support.visited";

export interface SupportVisitStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

export function hasVisitedSupport(storage: SupportVisitStorage): boolean {
  return storage.getItem(SUPPORT_VISIT_STORAGE_KEY) === "true";
}

export function recordSupportVisit(storage: SupportVisitStorage): void {
  storage.setItem(SUPPORT_VISIT_STORAGE_KEY, "true");
}
