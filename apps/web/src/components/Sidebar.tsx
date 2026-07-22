import { Icon, type IconName } from "./Icon";

export type AppView =
  | "discovery"
  | "library"
  | "report"
  | "management"
  | "support";

interface SidebarProps {
  activeView: AppView;
  onNavigate(view: AppView): void;
  onLogout(): void;
  connected: boolean;
  showSupportNotice: boolean;
  trackCount: number;
  username: string;
}

const navigation: Array<{
  view: AppView;
  icon: IconName;
  title: string;
  description: string;
}> = [
  { view: "library", icon: "library", title: "Library", description: "Favorites and playlists" },
  { view: "management", icon: "manage", title: "Music Admin", description: "Scan and status" },
  { view: "support", icon: "heart", title: "About", description: "Community edition" },
];

export function Sidebar({
  activeView,
  onNavigate,
  onLogout,
  connected,
  showSupportNotice,
  trackCount,
  username,
}: SidebarProps) {
  return (
    <aside className="sidebar">
      <div className="brand">
        <div aria-hidden="true" className="brand__mark">
          <img alt="" src="/brand/lyranest-logo-512.png" />
        </div>
        <div>
          <strong>LyraNest Community</strong>
          <small>律巢社区版</small>
        </div>
      </div>

      <nav className="sidebar__nav" aria-label="主导航">
        {navigation.map((item) => (
          <button
            className={activeView === item.view ? "is-active" : ""}
            key={item.view}
            onClick={() => onNavigate(item.view)}
            type="button"
          >
            <Icon name={item.icon} />
            <span>
              <b>{item.title}</b>
              <small>{item.description}</small>
            </span>
            {item.view === "library" && <em>{trackCount}</em>}
            {item.view === "support" && showSupportNotice && (
              <i
                aria-label="有新的支持入口"
                className="sidebar__notification-dot"
              />
            )}
          </button>
        ))}
      </nav>

      <div className="sidebar__footer">
        <div className="server-chip server-chip--account">
          <span
            className={`status-dot ${connected ? "is-online" : "is-offline"}`}
          />
          <span>
            <b>{username}</b>
            <small>{connected ? "服务在线" : "服务连接待确认"}</small>
          </span>
        </div>
        <button className="sidebar__logout" onClick={onLogout} type="button">
          <Icon name="chevron" size={16} />
          退出登录
        </button>
        <p>你的音乐，安静地待在自己的服务器里。</p>
      </div>
    </aside>
  );
}
