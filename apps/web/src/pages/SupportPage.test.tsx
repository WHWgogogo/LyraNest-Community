import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { SupportPage } from "./SupportPage";

describe("SupportPage", () => {
  it("renders the appreciation code on a dedicated page", () => {
    const markup = renderToStaticMarkup(<SupportPage />);

    expect(markup).toContain("关于");
    expect(markup).toContain("LyraNest");
    expect(markup).toContain("支持作者");
    expect(markup).toContain('class="support-hero__logo"');
    expect(markup).toContain('src="/brand/lyranest-logo-512.png"');
    expect(markup).toContain("/support/lyranest-appreciation-code.jpg");
    expect(markup).not.toContain('role="dialog"');
  });

  it("contains the brand image without clipping it", () => {
    const styles = readFileSync(new URL("../styles.css", import.meta.url), "utf8");

    expect(styles).toMatch(
      /\.brand__mark img,\s*\.support-hero__logo img\s*\{[\s\S]*?object-fit: contain;/,
    );
    expect(styles).toMatch(
      /\.support-hero__logo\s*\{[\s\S]*?padding: 6px;/,
    );
  });
});
