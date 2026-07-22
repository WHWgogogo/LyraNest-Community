import type { SVGProps } from "react";

export type IconName =
  | "library"
  | "discover"
  | "report"
  | "manage"
  | "settings"
  | "play"
  | "pause"
  | "previous"
  | "next"
  | "search"
  | "refresh"
  | "lyrics"
  | "wand"
  | "volume"
  | "volumeOff"
  | "close"
  | "server"
  | "check"
  | "alert"
  | "music"
  | "chevron"
  | "heart"
  | "heartFilled"
  | "more"
  | "queue"
  | "order"
  | "listLoop"
  | "singleLoop"
  | "shuffle"
  | "playlist"
  | "album"
  | "artist"
  | "plus"
  | "trash";

interface IconProps extends SVGProps<SVGSVGElement> {
  name: IconName;
  size?: number;
}

export function Icon({ name, size = 20, ...props }: IconProps) {
  const paths: Record<IconName, JSX.Element> = {
    library: (
      <>
        <path d="M4 5.5h16M4 12h16M4 18.5h10" />
        <circle cx="18" cy="18.5" r="2" />
      </>
    ),
    discover: (
      <>
        <circle cx="12" cy="12" r="8" />
        <path d="m15.5 8.5-2.1 4.8-4.8 2.1 2.1-4.8 4.8-2.1Z" />
      </>
    ),
    report: (
      <>
        <path d="M5 19V10M12 19V5M19 19v-7" />
        <path d="M3 19h18" />
      </>
    ),
    manage: (
      <>
        <path d="M4 7h16M7 4v6M4 17h16M17 14v6" />
        <path d="M4 12h16M13 9v6" />
      </>
    ),
    settings: (
      <>
        <circle cx="12" cy="12" r="3" />
        <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06-2.83 2.83-.06-.06a1.7 1.7 0 0 0-1.88-.34 1.7 1.7 0 0 0-1.03 1.56V21h-4v-.08A1.7 1.7 0 0 0 8.97 19.4a1.7 1.7 0 0 0-1.88.34l-.06.06-2.83-2.83.06-.06A1.7 1.7 0 0 0 4.6 15 1.7 1.7 0 0 0 3.08 14H3v-4h.08A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.34-1.88L4.2 7.06l2.83-2.83.06.06A1.7 1.7 0 0 0 8.97 4.6 1.7 1.7 0 0 0 10 3.08V3h4v.08A1.7 1.7 0 0 0 15.03 4.6a1.7 1.7 0 0 0 1.88-.34l.06-.06 2.83 2.83-.06.06A1.7 1.7 0 0 0 19.4 9 1.7 1.7 0 0 0 20.92 10H21v4h-.08A1.7 1.7 0 0 0 19.4 15Z" />
      </>
    ),
    play: <path d="m9 7 8 5-8 5V7Z" />,
    pause: (
      <>
        <path d="M9 7v10M15 7v10" />
      </>
    ),
    previous: (
      <>
        <path d="M7 6v12M18 7l-8 5 8 5V7Z" />
      </>
    ),
    next: (
      <>
        <path d="M17 6v12M6 7l8 5-8 5V7Z" />
      </>
    ),
    search: (
      <>
        <circle cx="11" cy="11" r="6.5" />
        <path d="m16 16 4 4" />
      </>
    ),
    refresh: (
      <>
        <path d="M20 7v5h-5" />
        <path d="M19 12a7 7 0 1 0-1.6 4.45" />
      </>
    ),
    lyrics: (
      <>
        <path d="M5 5h14v11H9l-4 3V5Z" />
        <path d="M8 9h8M8 12h5" />
      </>
    ),
    wand: (
      <>
        <path d="m4 20 10-10M12 4l1-2 1 2 2 1-2 1-1 2-1-2-2-1 2-1ZM18 11l.8-1.6.8 1.6 1.6.8-1.6.8-.8 1.6-.8-1.6-1.6-.8 1.6-.8Z" />
        <path d="m12 12 3 3" />
      </>
    ),
    volume: (
      <>
        <path d="M5 10v4h3l4 3V7l-4 3H5Z" />
        <path d="M16 9a4 4 0 0 1 0 6M18.5 6.5a7.5 7.5 0 0 1 0 11" />
      </>
    ),
    volumeOff: (
      <>
        <path d="M5 10v4h3l4 3V7l-4 3H5Z" />
        <path d="m17 10 4 4M21 10l-4 4" />
      </>
    ),
    close: <path d="m6 6 12 12M18 6 6 18" />,
    server: (
      <>
        <rect x="4" y="4" width="16" height="6" rx="2" />
        <rect x="4" y="14" width="16" height="6" rx="2" />
        <path d="M8 7h.01M8 17h.01M12 7h5M12 17h5" />
      </>
    ),
    check: <path d="m5 12 4 4L19 6" />,
    alert: (
      <>
        <path d="M12 4 3.5 19h17L12 4Z" />
        <path d="M12 9v4M12 16h.01" />
      </>
    ),
    music: (
      <>
        <path d="M9 18V6l10-2v12" />
        <circle cx="6.5" cy="18" r="2.5" />
        <circle cx="16.5" cy="16" r="2.5" />
      </>
    ),
    chevron: <path d="m9 6 6 6-6 6" />,
    heart: <path d="M20.8 8.4c0 5-8.8 10.6-8.8 10.6S3.2 13.4 3.2 8.4A4.4 4.4 0 0 1 11 5.6L12 7l1-1.4a4.4 4.4 0 0 1 7.8 2.8Z" />,
    heartFilled: (
      <path
        d="M20.8 8.4c0 5-8.8 10.6-8.8 10.6S3.2 13.4 3.2 8.4A4.4 4.4 0 0 1 11 5.6L12 7l1-1.4a4.4 4.4 0 0 1 7.8 2.8Z"
        fill="currentColor"
      />
    ),
    more: (
      <>
        <circle cx="5" cy="12" r="1" fill="currentColor" />
        <circle cx="12" cy="12" r="1" fill="currentColor" />
        <circle cx="19" cy="12" r="1" fill="currentColor" />
      </>
    ),
    queue: (
      <>
        <path d="M4 6h10M4 12h10M4 18h10" />
        <path d="m17 15 3 3-3 3" />
      </>
    ),
    order: (
      <>
        <path d="M5 6h14M5 12h10M5 18h6" />
        <path d="m16 16 3 2-3 2" />
      </>
    ),
    listLoop: (
      <>
        <path d="M17 5h2v5M19 10l-2-2" />
        <path d="M7 19H5v-5M5 14l2 2" />
        <path d="M5 9V7a2 2 0 0 1 2-2h10M19 15v2a2 2 0 0 1-2 2H7" />
      </>
    ),
    singleLoop: (
      <>
        <path d="M17 5h2v5M19 10l-2-2" />
        <path d="M7 19H5v-5M5 14l2 2" />
        <path d="M5 9V7a2 2 0 0 1 2-2h10M19 15v2a2 2 0 0 1-2 2H7" />
        <path d="M12 9v6M10.5 10.5 12 9l1.5 1.5" />
      </>
    ),
    shuffle: (
      <>
        <path d="M4 7h3c3 0 4 10 7 10h2" />
        <path d="m17 14 3 3-3 3M4 17h3c1.2 0 2-1.6 3-3" />
        <path d="M14 7h3M17 4l3 3-3 3" />
      </>
    ),
    playlist: (
      <>
        <path d="M4 6h11M4 11h11M4 16h8" />
        <path d="M18 14v6M15 17h6" />
      </>
    ),
    album: (
      <>
        <rect x="4" y="4" width="16" height="16" rx="3" />
        <circle cx="12" cy="12" r="3.5" />
      </>
    ),
    artist: (
      <>
        <circle cx="12" cy="8" r="3" />
        <path d="M5 20c.7-3.3 3-5 7-5s6.3 1.7 7 5" />
      </>
    ),
    plus: <path d="M12 5v14M5 12h14" />,
    trash: (
      <>
        <path d="M5 7h14M9 7V5h6v2M8 10v7M12 10v7M16 10v7" />
        <path d="M6 7l1 13h10l1-13" />
      </>
    ),
  };

  return (
    <svg
      aria-hidden="true"
      fill="none"
      height={size}
      viewBox="0 0 24 24"
      width={size}
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="1.8"
      {...props}
    >
      {paths[name]}
    </svg>
  );
}
