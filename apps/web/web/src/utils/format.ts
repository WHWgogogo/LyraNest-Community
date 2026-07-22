import type { ScrapeFieldName, ScrapeValue, Track } from "../api/types";

export function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) {
    return "0:00";
  }
  const wholeSeconds = Math.floor(seconds);
  const minutes = Math.floor(wholeSeconds / 60);
  const remainder = wholeSeconds % 60;
  return `${minutes}:${remainder.toString().padStart(2, "0")}`;
}

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return "0 B";
  }
  const units = ["B", "KB", "MB", "GB", "TB"];
  const index = Math.min(
    Math.floor(Math.log(bytes) / Math.log(1024)),
    units.length - 1,
  );
  const value = bytes / 1024 ** index;
  const unit = units[index] ?? "B";
  return `${value.toFixed(index === 0 || value >= 10 ? 0 : 1)} ${unit}`;
}

export function formatDate(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "未知";
  }
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

export function formatDateTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "未知时间";
  }
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

export function displayArtist(track: Track): string {
  return (
    track.artist?.trim() ||
    track.album_artist?.trim() ||
    "未知艺术家"
  );
}

export function displayAlbum(track: Track): string {
  return track.album?.trim() || "未分类专辑";
}

export function displayGenres(track: Track): string {
  const genres = track.genres
    ?.map((genre) => genre.trim())
    .filter(Boolean);
  if (genres && genres.length > 0) {
    return genres.join(" · ");
  }
  return track.genre?.trim() || "—";
}

export type TrackMetadataTone = "success" | "warning" | "error" | "neutral";

export interface TrackMetadataStatus {
  label: string;
  detail: string;
  tone: TrackMetadataTone;
  title?: string;
}

export function trackMetadataStatus(track: Track): TrackMetadataStatus {
  const error = track.metadata_error?.trim();
  if (error) {
    return {
      label: "读取异常",
      detail:
        track.metadata_source === "filename"
          ? "已回退到文件名"
          : "元数据解析失败",
      tone: "error",
      title: error,
    };
  }

  switch (track.metadata_source?.trim().toLowerCase()) {
    case "embedded":
      return {
        label: "内嵌标签",
        detail: "来自音频文件",
        tone: "success",
      };
    case "override":
      return {
        label: "手动覆盖",
        detail: "已应用管理元数据",
        tone: "success",
      };
    case "filename":
      return {
        label: "文件名",
        detail: "未找到可读标签",
        tone: "warning",
      };
    default:
      return {
        label: track.metadata_source?.trim() || "未标记",
        detail: "元数据来源未知",
        tone: "neutral",
      };
  }
}

export function trackInitials(track: Track): string {
  const source = track.title.trim() || track.file_name.trim() || "M";
  return Array.from(source).slice(0, 2).join("").toUpperCase();
}

export function trackGradient(track: Track): string {
  let hash = 0;
  for (const character of track.id || track.title) {
    hash = (hash * 31 + character.charCodeAt(0)) >>> 0;
  }
  const hueA = hash % 360;
  const hueB = (hueA + 42 + (hash % 70)) % 360;
  return `linear-gradient(145deg, hsl(${hueA} 72% 68%), hsl(${hueB} 74% 48%))`;
}

export const scrapeFieldLabels: Record<ScrapeFieldName, string> = {
  title: "标题",
  artist: "艺术家",
  album: "专辑",
  album_artist: "专辑艺术家",
  year: "年份",
  track_number: "音轨号",
  disc_number: "碟片号",
  genre: "流派",
  artwork_url: "封面",
  lyrics: "歌词",
};

export function displayScrapeValue(value: ScrapeValue): string {
  if (value === null || value === "") {
    return "—";
  }
  const text = String(value);
  return text.length > 90 ? `${text.slice(0, 90)}…` : text;
}
