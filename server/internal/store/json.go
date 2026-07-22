package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"music-player-server/internal/library"
)

const trackStoreFileName = "tracks.json"

type JSONRepository struct {
	mu       sync.RWMutex
	dataDir  string
	filePath string
	tracks   map[string]library.Track
}

var _ TrackRepository = (*JSONRepository)(nil)

func NewJSONRepository(dataDir string) (*JSONRepository, error) {
	if dataDir == "" {
		return nil, ErrTrackStoreDataPath
	}

	absoluteDataDir, err := filepath.Abs(dataDir)
	if err != nil {
		return nil, fmt.Errorf("resolve track store data directory: %w", err)
	}
	if err := os.MkdirAll(absoluteDataDir, 0o700); err != nil {
		return nil, fmt.Errorf("create track store data directory: %w", err)
	}
	info, err := os.Stat(absoluteDataDir)
	if err != nil {
		return nil, fmt.Errorf("stat track store data directory: %w", err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("track store data path %q is not a directory", absoluteDataDir)
	}
	if err := os.Chmod(absoluteDataDir, 0o700); err != nil {
		return nil, fmt.Errorf("secure track store data directory: %w", err)
	}

	repository := &JSONRepository{
		dataDir:  absoluteDataDir,
		filePath: filepath.Join(absoluteDataDir, trackStoreFileName),
		tracks:   make(map[string]library.Track),
	}
	if err := repository.load(); err != nil {
		return nil, err
	}
	return repository, nil
}

func (r *JSONRepository) ReplaceTracks(ctx context.Context, tracks []library.Track) error {
	if err := ctx.Err(); err != nil {
		return err
	}

	next := make(map[string]library.Track, len(tracks))
	for _, track := range tracks {
		next[track.ID] = track
	}

	r.mu.Lock()
	defer r.mu.Unlock()

	if err := ctx.Err(); err != nil {
		return err
	}
	if err := r.writeTracks(sortedTrackValues(next)); err != nil {
		return err
	}
	r.tracks = next
	return nil
}

func (r *JSONRepository) ListTracks(ctx context.Context) ([]library.Track, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}

	r.mu.RLock()
	defer r.mu.RUnlock()

	return sortedTrackValues(r.tracks), nil
}

func (r *JSONRepository) GetTrack(ctx context.Context, id string) (library.Track, error) {
	if err := ctx.Err(); err != nil {
		return library.Track{}, err
	}

	r.mu.RLock()
	defer r.mu.RUnlock()

	track, ok := r.tracks[id]
	if !ok {
		return library.Track{}, ErrTrackNotFound
	}
	return track, nil
}

func (r *JSONRepository) load() error {
	file, err := os.Open(r.filePath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("open track store file: %w", err)
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return fmt.Errorf("stat track store file: %w", err)
	}
	if info.IsDir() {
		return fmt.Errorf("track store file %q is a directory", r.filePath)
	}

	decoder := json.NewDecoder(file)
	var persistedTracks []persistedTrack
	if err := decoder.Decode(&persistedTracks); err != nil {
		return corruptTrackStoreError(r.filePath, err)
	}

	var trailingValue struct{}
	if err := decoder.Decode(&trailingValue); err != io.EOF {
		if err == nil {
			return fmt.Errorf("%w: %s contains multiple JSON values", ErrTrackStoreCorrupt, r.filePath)
		}
		return corruptTrackStoreError(r.filePath, err)
	}

	next := make(map[string]library.Track, len(persistedTracks))
	for _, persistedTrack := range persistedTracks {
		track := persistedTrack.toTrack()
		next[track.ID] = track
	}
	r.tracks = next
	return nil
}

func (r *JSONRepository) writeTracks(tracks []library.Track) error {
	tempFile, err := os.CreateTemp(r.dataDir, "."+trackStoreFileName+"-*.tmp")
	if err != nil {
		return fmt.Errorf("create temporary track store file: %w", err)
	}

	tempPath := tempFile.Name()
	removeTemp := true
	defer func() {
		_ = tempFile.Close()
		if removeTemp {
			_ = os.Remove(tempPath)
		}
	}()

	if err := os.Chmod(tempPath, 0o600); err != nil {
		return fmt.Errorf("secure temporary track store file: %w", err)
	}

	encoder := json.NewEncoder(tempFile)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(persistTracks(tracks)); err != nil {
		return fmt.Errorf("encode track store file: %w", err)
	}
	if err := tempFile.Sync(); err != nil {
		return fmt.Errorf("sync temporary track store file: %w", err)
	}
	if err := tempFile.Close(); err != nil {
		return fmt.Errorf("close temporary track store file: %w", err)
	}

	if err := os.Rename(tempPath, r.filePath); err != nil {
		return fmt.Errorf("commit track store file: %w", err)
	}
	removeTemp = false
	syncDirectory(r.dataDir)
	return nil
}

type persistedTrack struct {
	library.Track
	Path string `json:"path"`
}

func persistTracks(tracks []library.Track) []persistedTrack {
	persistedTracks := make([]persistedTrack, 0, len(tracks))
	for _, track := range tracks {
		persistedTracks = append(persistedTracks, persistedTrack{
			Track: track,
			Path:  track.Path,
		})
	}
	return persistedTracks
}

func (t persistedTrack) toTrack() library.Track {
	track := t.Track
	track.Path = t.Path
	return track
}

func sortedTrackValues(trackMap map[string]library.Track) []library.Track {
	tracks := make([]library.Track, 0, len(trackMap))
	for _, track := range trackMap {
		tracks = append(tracks, track)
	}
	sort.Slice(tracks, func(left, right int) bool {
		return strings.ToLower(tracks[left].Path) < strings.ToLower(tracks[right].Path)
	})
	return tracks
}

func corruptTrackStoreError(path string, err error) error {
	return fmt.Errorf("%w: %s: %v", ErrTrackStoreCorrupt, path, err)
}

func syncDirectory(path string) {
	directory, err := os.Open(path)
	if err != nil {
		return
	}
	defer directory.Close()
	_ = directory.Sync()
}
