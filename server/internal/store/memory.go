package store

import (
	"context"
	"sort"
	"strings"
	"sync"

	"music-player-server/internal/library"
)

type MemoryRepository struct {
	mu     sync.RWMutex
	tracks map[string]library.Track
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{
		tracks: make(map[string]library.Track),
	}
}

func (r *MemoryRepository) ReplaceTracks(_ context.Context, tracks []library.Track) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	next := make(map[string]library.Track, len(tracks))
	for _, track := range tracks {
		next[track.ID] = track
	}
	r.tracks = next
	return nil
}

func (r *MemoryRepository) ListTracks(_ context.Context) ([]library.Track, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	tracks := make([]library.Track, 0, len(r.tracks))
	for _, track := range r.tracks {
		tracks = append(tracks, track)
	}
	sort.Slice(tracks, func(left, right int) bool {
		return strings.ToLower(tracks[left].Path) < strings.ToLower(tracks[right].Path)
	})
	return tracks, nil
}

func (r *MemoryRepository) GetTrack(_ context.Context, id string) (library.Track, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	track, ok := r.tracks[id]
	if !ok {
		return library.Track{}, ErrTrackNotFound
	}
	return track, nil
}
