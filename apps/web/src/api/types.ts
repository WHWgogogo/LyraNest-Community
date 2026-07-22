export interface HealthResponse {
  status: "ok" | string;
}

export interface AuthStatusResponse {
  initialized: boolean;
}

export interface AuthUser {
  id?: string;
  username: string;
  display_name?: string;
}

export interface AuthSessionResponse {
  token: string;
  user?: AuthUser;
}

export interface AuthCredentials {
  username: string;
  password: string;
}

export interface Track {
  id: string;
  title: string;
  artist?: string;
  album?: string;
  album_artist?: string;
  file_name: string;
  extension: string;
  size_bytes: number;
  modified: string;
  duration_seconds?: number;
  artwork_url?: string;
  genre?: string;
  genres?: string[];
  year?: number;
  track_number?: number;
  disc_number?: number;
  metadata_source?: string;
  metadata_error?: string;
}

export interface TrackListResponse {
  tracks: Track[];
  total: number;
}

export type CollectionKind = "favorites" | "playlist";

export interface MusicCollection {
  id: string;
  kind: CollectionKind;
  name: string;
  track_ids: string[];
  created_at: string;
  updated_at?: string;
}

export interface Playlist {
  id: string;
  name: string;
  track_ids: string[];
  created_at: string;
  updated_at: string;
}

export interface CreatePlaylistRequest {
  id?: string;
  name: string;
}

export interface CollectionsSnapshot {
  revision: number;
  favorite_track_ids: string[];
  playlists: Playlist[];
}

export interface CollectionsImportRequest {
  revision: number;
  favorite_track_ids: string[];
  playlists: Array<{
    id?: string;
    name: string;
    track_ids: string[];
    created_at?: string;
    updated_at?: string;
  }>;
}

export type PlaybackEventType = "pause" | "skip" | "completed";

export interface ListeningEventRequest {
  event_id: string;
  track_id: string;
  listened_ms: number;
  completed: boolean;
  played_at: string;
}

export interface ListeningEventIngestResult {
  accepted: number;
  duplicates: number;
}

export interface DiscoveryCategory {
  id: string;
  name: string;
  track_count: number;
  tracks: Track[];
}

export interface RankedTrack {
  track: Track;
  play_count: number;
  listened_ms: number;
}

export interface DiscoveryResponse {
  for_you: Track[];
  daily: Track[];
  recent_recommendations: Track[];
  hot_tracks: RankedTrack[];
  categories: DiscoveryCategory[];
}

export interface ListeningHeatmapCell {
  date: string;
  play_count: number;
  listened_ms: number;
}

export interface ListeningReport {
  year: number;
  total_listened_ms: number;
  total_plays: number;
  listening_days: number;
  unique_tracks: number;
  unique_albums: number;
  heatmap: ListeningHeatmapCell[];
  top_tracks: RankedTrack[];
}

export interface LyricsResponse {
  track_id: string;
  encoding: "UTF-8" | "GB18030" | "GBK" | string;
  content: string;
}

export interface ErrorResponse {
  error: string;
  message?: string;
  code?: string;
}

export interface LibraryScanResponse {
  tracks: Track[];
  total: number;
  scanned_at: string;
}

export interface LibraryStatusResponse {
  directory: string;
  track_count: number;
  scanning: boolean;
  last_scanned_at: string | null;
  last_error: string | null;
}

export type ScrapeFieldName =
  | "title"
  | "artist"
  | "album"
  | "album_artist"
  | "year"
  | "track_number"
  | "disc_number"
  | "genre"
  | "artwork_url"
  | "lyrics";

export type ScrapeValue = string | number | null;

export interface ScrapeMetadata {
  title?: string;
  artist?: string;
  album?: string;
  album_artist?: string;
  year?: number;
  track_number?: number;
  disc_number?: number;
  genre?: string;
  artwork_url?: string;
  lyrics?: string;
}

export interface ScrapeFieldDifference {
  field: ScrapeFieldName;
  current: ScrapeValue;
  candidate: ScrapeValue;
  changed: boolean;
}

export interface ScrapeCandidate {
  id: string;
  provider: string;
  confidence: number;
  metadata: ScrapeMetadata;
  differences: ScrapeFieldDifference[];
  source_url?: string;
}

export interface ScrapeSearchResponse {
  track_id: string;
  candidates: ScrapeCandidate[];
  searched_at?: string;
}

export interface ScrapeSearchRequest {
  title?: string;
  artist?: string;
  album?: string;
  limit?: number;
}

export interface ScrapeApplyRequest {
  candidate_id: string;
  provider: string;
  fields: ScrapeFieldName[];
}

export interface ScrapeApplyResponse {
  track: Track;
  provider: string;
  applied_fields: ScrapeFieldName[];
  applied_at: string;
  message?: string;
}
