import type { CSSProperties, SyntheticEvent } from "react";
import type { Track } from "../api/types";
import { trackGradient, trackInitials } from "../utils/format";
import { Icon } from "./Icon";

interface AlbumArtProps {
  track?: Track | null;
  size?: "small" | "medium" | "large";
  className?: string;
}

export function handleAlbumArtError(
  event: SyntheticEvent<HTMLImageElement>,
) {
  const image = event.currentTarget;
  image.hidden = true;

  const fallback = image.nextElementSibling as HTMLElement | null;
  if (fallback) {
    fallback.hidden = false;
  }
}

export function AlbumArt({
  track,
  size = "medium",
  className = "",
}: AlbumArtProps) {
  if (!track) {
    return (
      <div className={`album-art album-art--${size} ${className}`}>
        <Icon name="music" size={size === "large" ? 38 : 20} />
      </div>
    );
  }

  const style = {
    "--cover-background": trackGradient(track),
  } as CSSProperties;

  return (
    <div
      className={`album-art album-art--${size} ${className}`}
      style={style}
    >
      {track.artwork_url ? (
        <>
          <img
            alt={`${track.title} 封面`}
            onError={handleAlbumArtError}
            src={track.artwork_url}
          />
          <span aria-label="封面加载失败" hidden role="img">
            <Icon name="music" size={size === "large" ? 38 : 20} />
          </span>
        </>
      ) : (
        <>
          <span>{trackInitials(track)}</span>
          <i aria-hidden="true" />
        </>
      )}
    </div>
  );
}
