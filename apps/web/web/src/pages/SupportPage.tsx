export function SupportPage() {
  return (
    <div className="support-page">
      <section className="support-hero">
        <div>
          <span className="eyebrow">LYRANEST · 律巢</span>
          <h1>
            关于 <em>LyraNest</em>
          </h1>
          <p>
            律巢是一处安静、由你掌控的私人音乐空间，让每一首珍藏的音乐自在归位。
          </p>
        </div>
        <div aria-hidden="true" className="support-hero__logo">
          <img alt="" src="/brand/lyranest-logo-512.png" />
        </div>
      </section>

      <section className="support-card" aria-labelledby="support-author-title">
        <div className="support-card__copy">
          <span className="eyebrow">SUPPORT THE CREATOR</span>
          <h2 id="support-author-title">支持作者</h2>
          <p>
            如果 LyraNest 让你的听歌体验更自在，欢迎通过下方二维码表达支持。每一份心意都会帮助它持续成长。
          </p>
          <small>感谢你让律巢有继续完善的动力。</small>
        </div>
        <figure className="support-code">
          <img
            alt="LyraNest 律巢赞赏码"
            loading="lazy"
            src="/support/lyranest-appreciation-code.jpg"
          />
          <figcaption>扫码支持 LyraNest</figcaption>
        </figure>
      </section>
    </div>
  );
}
