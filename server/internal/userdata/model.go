package userdata

import (
	"context"
	"errors"
	"time"
)

var (
	ErrDataDirRequired     = errors.New("user data directory is required")
	ErrCorrupt             = errors.New("user data store file is corrupt")
	ErrUnsupportedVersion  = errors.New("unsupported user data store version")
	ErrInvalidUserID       = errors.New("invalid user id")
	ErrInvalidTrackID      = errors.New("invalid track id")
	ErrInvalidPlaylist     = errors.New("invalid playlist")
	ErrPlaylistConflict    = errors.New("playlist id conflicts with existing playlist")
	ErrPlaylistNotFound    = errors.New("playlist not found")
	ErrInvalidEvent        = errors.New("invalid listening event")
	ErrInvalidPlaybackMode = errors.New("invalid playback mode")
	ErrDataLimit           = errors.New("user data limit exceeded")
)

type PlaybackMode string

const (
	PlaybackModeSequential PlaybackMode = "sequential"
	PlaybackModeShuffle    PlaybackMode = "shuffle"
	PlaybackModeRepeatAll  PlaybackMode = "repeat_all"
	PlaybackModeRepeatOne  PlaybackMode = "repeat_one"
)

type Playlist struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	TrackIDs  []string  `json:"track_ids"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type CollectionsSnapshot struct {
	Revision         int64      `json:"revision"`
	FavoriteTrackIDs []string   `json:"favorite_track_ids"`
	Playlists        []Playlist `json:"playlists"`
}

type CollectionsImport struct {
	FavoriteTrackIDs []string   `json:"favorite_track_ids"`
	Playlists        []Playlist `json:"playlists"`
}

type PlaybackModeSnapshot struct {
	Revision int64        `json:"revision"`
	Mode     PlaybackMode `json:"mode"`
}

type ListeningEvent struct {
	EventID    string    `json:"event_id"`
	TrackID    string    `json:"track_id"`
	ListenedMS int64     `json:"listened_ms"`
	Completed  bool      `json:"completed"`
	PlayedAt   time.Time `json:"played_at"`
}

type EventIngestResult struct {
	Accepted   int `json:"accepted"`
	Duplicates int `json:"duplicates"`
}

type TrackMetric struct {
	TrackID    string `json:"-"`
	PlayCount  int64  `json:"play_count"`
	ListenedMS int64  `json:"listened_ms"`
}

type DailyMetric struct {
	Date       string `json:"date"`
	PlayCount  int64  `json:"play_count"`
	ListenedMS int64  `json:"listened_ms"`
}

type ListeningReport struct {
	Year            int           `json:"year"`
	TotalListenedMS int64         `json:"total_listened_ms"`
	TotalPlays      int64         `json:"total_plays"`
	ListeningDays   int           `json:"listening_days"`
	UniqueTracks    int           `json:"unique_tracks"`
	Heatmap         []DailyMetric `json:"heatmap"`
	TrackMetrics    []TrackMetric `json:"-"`
}

type Repository interface {
	Collections(ctx context.Context, userID string) (CollectionsSnapshot, error)
	AddFavorite(ctx context.Context, userID, trackID string) (CollectionsSnapshot, error)
	RemoveFavorite(ctx context.Context, userID, trackID string) (CollectionsSnapshot, error)
	CreatePlaylist(ctx context.Context, userID, name string) (CollectionsSnapshot, error)
	UpdatePlaylist(ctx context.Context, userID, playlistID, name string) (CollectionsSnapshot, error)
	DeletePlaylist(ctx context.Context, userID, playlistID string) (CollectionsSnapshot, error)
	AddPlaylistTrack(ctx context.Context, userID, playlistID, trackID string) (CollectionsSnapshot, error)
	RemovePlaylistTrack(ctx context.Context, userID, playlistID, trackID string) (CollectionsSnapshot, error)
	ImportCollections(ctx context.Context, userID string, value CollectionsImport) (CollectionsSnapshot, error)
	RecordEvents(ctx context.Context, userID string, events []ListeningEvent) (EventIngestResult, error)
	RecentEvents(ctx context.Context, userID string, since time.Time) ([]ListeningEvent, error)
	ListeningReport(ctx context.Context, userID string, year int) (ListeningReport, error)
	HotTrackMetrics(ctx context.Context) ([]TrackMetric, error)
}

type PlaylistIDCreator interface {
	CreatePlaylistWithID(
		ctx context.Context,
		userID, playlistID, name string,
	) (CollectionsSnapshot, bool, error)
}

type PlaybackModeRepository interface {
	PlaybackMode(ctx context.Context, userID string) (PlaybackModeSnapshot, error)
	SetPlaybackMode(ctx context.Context, userID string, mode PlaybackMode) (PlaybackModeSnapshot, error)
}
