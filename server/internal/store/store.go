package store

import (
	"context"
	"errors"

	"music-player-server/internal/library"
)

var (
	ErrTrackNotFound      = errors.New("track not found")
	ErrTrackStoreCorrupt  = errors.New("track store file is corrupt")
	ErrTrackStoreDataPath = errors.New("track store data directory is required")
)

type TrackRepository interface {
	ReplaceTracks(ctx context.Context, tracks []library.Track) error
	ListTracks(ctx context.Context) ([]library.Track, error)
	GetTrack(ctx context.Context, id string) (library.Track, error)
}
