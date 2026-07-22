import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { Sidebar } from "./Sidebar";

describe("Sidebar", () => {
  it("shows the support notice only for first-time visitors", () => {
    const withNotice = renderToStaticMarkup(
      <Sidebar
        activeView="discovery"
        connected
        onLogout={vi.fn()}
        onNavigate={vi.fn()}
        showSupportNotice
        trackCount={12}
        username="管理员"
      />,
    );
    const withoutNotice = renderToStaticMarkup(
      <Sidebar
        activeView="discovery"
        connected
        onLogout={vi.fn()}
        onNavigate={vi.fn()}
        showSupportNotice={false}
        trackCount={12}
        username="管理员"
      />,
    );

    expect(withNotice).toContain("关于 / 支持作者");
    expect(withNotice).toContain("sidebar__notification-dot");
    expect(withNotice).toContain('src="/brand/lyranest-logo-512.png"');
    expect(withNotice).not.toContain("brand__mark\"><span");
    expect(withoutNotice).not.toContain("sidebar__notification-dot");
  });
});
