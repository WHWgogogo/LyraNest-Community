package userdata

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	dataFileName          = "user-data-v1.json"
	documentVersion       = 1
	maxDocumentBytes      = 16 << 20
	maxUsers              = 1_000
	maxFavorites          = 5_000
	maxPlaylists          = 250
	maxPlaylistTracks     = 5_000
	maxTrackYearMetrics   = 25_000
	maxRecentEvents       = 5_000
	maxEventReceipts      = 50_000
	maxTrackIDLength      = 256
	maxPlaylistIDLength   = 128
	maxPlaylistNameLength = 120
	maxEventIDLength      = 128
	maxListenedMS         = 24 * 60 * 60 * 1000
	recentEventWindow     = 90 * 24 * time.Hour
	maxFutureEventSkew    = 5 * time.Minute
)

type Option func(*Store)

func WithNow(now func() time.Time) Option {
	return func(store *Store) {
		if now != nil {
			store.now = now
		}
	}
}

type Store struct {
	mu       sync.RWMutex
	dataDir  string
	filePath string
	document persistedDocument
	now      func() time.Time
	syncDir  func(string) error
}

type persistedDocument struct {
	Version int                      `json:"version"`
	Users   map[string]persistedUser `json:"users"`
}

type persistedUser struct {
	Revision         int64         `json:"revision"`
	FavoriteTrackIDs []string      `json:"favorite_track_ids"`
	Playlists        []Playlist    `json:"playlists"`
	PlaybackMode     PlaybackMode  `json:"playback_mode,omitempty"`
	Listening        listeningData `json:"listening"`
}

type listeningData struct {
	Daily         map[string]aggregate            `json:"daily"`
	TrackYears    map[string]map[string]aggregate `json:"track_years"`
	RecentEvents  []ListeningEvent                `json:"recent_events"`
	EventReceipts map[string]time.Time            `json:"event_receipts"`
}

type aggregate struct {
	PlayCount  int64 `json:"play_count"`
	ListenedMS int64 `json:"listened_ms"`
}

var _ Repository = (*Store)(nil)
var _ PlaybackModeRepository = (*Store)(nil)

func NewStore(dataDir string, options ...Option) (*Store, error) {
	if strings.TrimSpace(dataDir) == "" {
		return nil, ErrDataDirRequired
	}
	absoluteDataDir, err := filepath.Abs(dataDir)
	if err != nil {
		return nil, fmt.Errorf("resolve user data directory: %w", err)
	}
	if err := os.MkdirAll(absoluteDataDir, 0o700); err != nil {
		return nil, fmt.Errorf("create user data directory: %w", err)
	}
	info, err := os.Stat(absoluteDataDir)
	if err != nil {
		return nil, fmt.Errorf("stat user data directory: %w", err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("user data path %q is not a directory", absoluteDataDir)
	}
	if err := os.Chmod(absoluteDataDir, 0o700); err != nil {
		return nil, fmt.Errorf("secure user data directory: %w", err)
	}

	store := &Store{
		dataDir:  absoluteDataDir,
		filePath: filepath.Join(absoluteDataDir, dataFileName),
		document: persistedDocument{
			Version: documentVersion,
			Users:   make(map[string]persistedUser),
		},
		now:     time.Now,
		syncDir: syncDirectory,
	}
	for _, option := range options {
		if option != nil {
			option(store)
		}
	}
	if err := store.load(); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *Store) Collections(ctx context.Context, userID string) (CollectionsSnapshot, error) {
	if err := ctx.Err(); err != nil {
		return CollectionsSnapshot{}, err
	}
	userID, err := normalizeUserID(userID)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return snapshotForUser(s.document.Users[userID]), nil
}

func (s *Store) AddFavorite(ctx context.Context, userID, trackID string) (CollectionsSnapshot, error) {
	trackID, err := normalizeTrackID(trackID)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	return s.mutateCollections(ctx, userID, func(user *persistedUser, now time.Time) (bool, error) {
		if contains(user.FavoriteTrackIDs, trackID) {
			return false, nil
		}
		if len(user.FavoriteTrackIDs) >= maxFavorites {
			return false, ErrDataLimit
		}
		user.FavoriteTrackIDs = append(user.FavoriteTrackIDs, trackID)
		return true, nil
	})
}

func (s *Store) RemoveFavorite(ctx context.Context, userID, trackID string) (CollectionsSnapshot, error) {
	trackID, err := normalizeTrackID(trackID)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	return s.mutateCollections(ctx, userID, func(user *persistedUser, now time.Time) (bool, error) {
		index := indexOf(user.FavoriteTrackIDs, trackID)
		if index < 0 {
			return false, nil
		}
		user.FavoriteTrackIDs = removeAt(user.FavoriteTrackIDs, index)
		return true, nil
	})
}

func (s *Store) CreatePlaylist(ctx context.Context, userID, name string) (CollectionsSnapshot, error) {
	playlistID, err := newPlaylistID()
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	snapshot, _, err := s.CreatePlaylistWithID(ctx, userID, playlistID, name)
	return snapshot, err
}

func (s *Store) CreatePlaylistWithID(
	ctx context.Context,
	userID, playlistID, name string,
) (CollectionsSnapshot, bool, error) {
	if err := ctx.Err(); err != nil {
		return CollectionsSnapshot{}, false, err
	}
	userID, err := normalizeUserID(userID)
	if err != nil {
		return CollectionsSnapshot{}, false, err
	}
	name, err = normalizePlaylistName(name)
	if err != nil {
		return CollectionsSnapshot{}, false, err
	}
	playlistID, err = normalizePlaylistID(playlistID)
	if err != nil {
		return CollectionsSnapshot{}, false, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	next := cloneDocument(s.document)
	user := next.Users[userID]
	if index := playlistIndex(user.Playlists, playlistID); index >= 0 {
		if user.Playlists[index].Name != name {
			return CollectionsSnapshot{}, false, ErrPlaylistConflict
		}
		return snapshotForUser(s.document.Users[userID]), false, nil
	}
	if len(user.Playlists) >= maxPlaylists {
		return CollectionsSnapshot{}, false, ErrDataLimit
	}
	now := s.now().UTC()
	user.Playlists = append(user.Playlists, Playlist{
		ID:        playlistID,
		Name:      name,
		TrackIDs:  []string{},
		CreatedAt: now,
		UpdatedAt: now,
	})
	user.Revision++
	next.Users[userID] = user
	if err := validateDocument(next); err != nil {
		return CollectionsSnapshot{}, false, err
	}
	if err := s.write(next); err != nil {
		return CollectionsSnapshot{}, false, err
	}
	s.document = next
	return snapshotForUser(user), true, nil
}

func (s *Store) UpdatePlaylist(ctx context.Context, userID, playlistID, name string) (CollectionsSnapshot, error) {
	playlistID, err := normalizePlaylistID(playlistID)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	name, err = normalizePlaylistName(name)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	return s.mutateCollections(ctx, userID, func(user *persistedUser, now time.Time) (bool, error) {
		index := playlistIndex(user.Playlists, playlistID)
		if index < 0 {
			return false, ErrPlaylistNotFound
		}
		if user.Playlists[index].Name == name {
			return false, nil
		}
		user.Playlists[index].Name = name
		user.Playlists[index].UpdatedAt = now
		return true, nil
	})
}

func (s *Store) DeletePlaylist(ctx context.Context, userID, playlistID string) (CollectionsSnapshot, error) {
	playlistID, err := normalizePlaylistID(playlistID)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	return s.mutateCollections(ctx, userID, func(user *persistedUser, now time.Time) (bool, error) {
		index := playlistIndex(user.Playlists, playlistID)
		if index < 0 {
			return false, ErrPlaylistNotFound
		}
		user.Playlists = removePlaylistAt(user.Playlists, index)
		return true, nil
	})
}

func (s *Store) AddPlaylistTrack(ctx context.Context, userID, playlistID, trackID string) (CollectionsSnapshot, error) {
	playlistID, err := normalizePlaylistID(playlistID)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	trackID, err = normalizeTrackID(trackID)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	return s.mutateCollections(ctx, userID, func(user *persistedUser, now time.Time) (bool, error) {
		index := playlistIndex(user.Playlists, playlistID)
		if index < 0 {
			return false, ErrPlaylistNotFound
		}
		playlist := &user.Playlists[index]
		if contains(playlist.TrackIDs, trackID) {
			return false, nil
		}
		if len(playlist.TrackIDs) >= maxPlaylistTracks {
			return false, ErrDataLimit
		}
		playlist.TrackIDs = append(playlist.TrackIDs, trackID)
		playlist.UpdatedAt = now
		return true, nil
	})
}

func (s *Store) RemovePlaylistTrack(ctx context.Context, userID, playlistID, trackID string) (CollectionsSnapshot, error) {
	playlistID, err := normalizePlaylistID(playlistID)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	trackID, err = normalizeTrackID(trackID)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	return s.mutateCollections(ctx, userID, func(user *persistedUser, now time.Time) (bool, error) {
		index := playlistIndex(user.Playlists, playlistID)
		if index < 0 {
			return false, ErrPlaylistNotFound
		}
		playlist := &user.Playlists[index]
		trackIndex := indexOf(playlist.TrackIDs, trackID)
		if trackIndex < 0 {
			return false, nil
		}
		playlist.TrackIDs = removeAt(playlist.TrackIDs, trackIndex)
		playlist.UpdatedAt = now
		return true, nil
	})
}

func (s *Store) ImportCollections(ctx context.Context, userID string, value CollectionsImport) (CollectionsSnapshot, error) {
	favorites, err := normalizeTrackIDs(value.FavoriteTrackIDs, maxFavorites)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	playlists, err := normalizeImportedPlaylists(value.Playlists)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	return s.mutateCollections(ctx, userID, func(user *persistedUser, now time.Time) (bool, error) {
		changed := false
		for _, trackID := range favorites {
			if contains(user.FavoriteTrackIDs, trackID) {
				continue
			}
			if len(user.FavoriteTrackIDs) >= maxFavorites {
				return false, ErrDataLimit
			}
			user.FavoriteTrackIDs = append(user.FavoriteTrackIDs, trackID)
			changed = true
		}
		for _, imported := range playlists {
			index := playlistIndex(user.Playlists, imported.ID)
			if index < 0 {
				if len(user.Playlists) >= maxPlaylists {
					return false, ErrDataLimit
				}
				imported.TrackIDs = append([]string{}, imported.TrackIDs...)
				imported.CreatedAt = now
				imported.UpdatedAt = now
				user.Playlists = append(user.Playlists, imported)
				changed = true
				continue
			}
			playlist := &user.Playlists[index]
			for _, trackID := range imported.TrackIDs {
				if contains(playlist.TrackIDs, trackID) {
					continue
				}
				if len(playlist.TrackIDs) >= maxPlaylistTracks {
					return false, ErrDataLimit
				}
				playlist.TrackIDs = append(playlist.TrackIDs, trackID)
				playlist.UpdatedAt = now
				changed = true
			}
		}
		return changed, nil
	})
}

func (s *Store) PlaybackMode(ctx context.Context, userID string) (PlaybackModeSnapshot, error) {
	if err := ctx.Err(); err != nil {
		return PlaybackModeSnapshot{}, err
	}
	userID, err := normalizeUserID(userID)
	if err != nil {
		return PlaybackModeSnapshot{}, err
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return playbackModeSnapshotForUser(s.document.Users[userID]), nil
}

func (s *Store) SetPlaybackMode(ctx context.Context, userID string, mode PlaybackMode) (PlaybackModeSnapshot, error) {
	if err := ctx.Err(); err != nil {
		return PlaybackModeSnapshot{}, err
	}
	userID, err := normalizeUserID(userID)
	if err != nil {
		return PlaybackModeSnapshot{}, err
	}
	mode, err = normalizePlaybackMode(mode)
	if err != nil {
		return PlaybackModeSnapshot{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	next := cloneDocument(s.document)
	user := next.Users[userID]
	currentMode, err := normalizePlaybackMode(user.PlaybackMode)
	if err != nil {
		return PlaybackModeSnapshot{}, err
	}
	if currentMode == mode {
		return playbackModeSnapshotForUser(s.document.Users[userID]), nil
	}

	user.PlaybackMode = mode
	user.Revision++
	next.Users[userID] = user
	if err := validateDocument(next); err != nil {
		return PlaybackModeSnapshot{}, err
	}
	if err := s.write(next); err != nil {
		return PlaybackModeSnapshot{}, err
	}
	s.document = next
	return playbackModeSnapshotForUser(user), nil
}

func (s *Store) RecordEvents(ctx context.Context, userID string, events []ListeningEvent) (EventIngestResult, error) {
	if err := ctx.Err(); err != nil {
		return EventIngestResult{}, err
	}
	userID, err := normalizeUserID(userID)
	if err != nil {
		return EventIngestResult{}, err
	}
	if len(events) == 0 || len(events) > 50 {
		return EventIngestResult{}, ErrInvalidEvent
	}
	now := s.now().UTC()
	normalized := make([]ListeningEvent, len(events))
	for index, event := range events {
		normalized[index], err = normalizeListeningEvent(event, now)
		if err != nil {
			return EventIngestResult{}, err
		}
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	next := cloneDocument(s.document)
	user := next.Users[userID]
	initializeListening(&user.Listening)
	result := EventIngestResult{}
	changed := false
	for _, event := range normalized {
		if _, ok := user.Listening.EventReceipts[event.EventID]; ok {
			result.Duplicates++
			continue
		}
		if _, exists := user.Listening.TrackYears[event.TrackID][event.PlayedAt.Format("2006")]; !exists &&
			trackYearMetricCount(user.Listening.TrackYears) >= maxTrackYearMetrics {
			return EventIngestResult{}, ErrDataLimit
		}
		if len(user.Listening.EventReceipts) >= maxEventReceipts {
			removeOldestReceipt(user.Listening.EventReceipts)
		}
		user.Listening.EventReceipts[event.EventID] = now
		day := event.PlayedAt.Format("2006-01-02")
		daily := user.Listening.Daily[day]
		daily.PlayCount++
		daily.ListenedMS += event.ListenedMS
		user.Listening.Daily[day] = daily

		year := event.PlayedAt.Format("2006")
		if user.Listening.TrackYears[event.TrackID] == nil {
			user.Listening.TrackYears[event.TrackID] = make(map[string]aggregate)
		}
		trackYear := user.Listening.TrackYears[event.TrackID][year]
		trackYear.PlayCount++
		trackYear.ListenedMS += event.ListenedMS
		user.Listening.TrackYears[event.TrackID][year] = trackYear

		user.Listening.RecentEvents = append(user.Listening.RecentEvents, event)
		result.Accepted++
		changed = true
	}
	if !changed {
		return result, nil
	}
	user.Listening.RecentEvents = trimRecentEvents(user.Listening.RecentEvents, now)
	next.Users[userID] = user
	if err := validateDocument(next); err != nil {
		return EventIngestResult{}, err
	}
	if err := s.write(next); err != nil {
		return EventIngestResult{}, err
	}
	s.document = next
	return result, nil
}

func (s *Store) RecentEvents(ctx context.Context, userID string, since time.Time) ([]ListeningEvent, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	userID, err := normalizeUserID(userID)
	if err != nil {
		return nil, err
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	events := s.document.Users[userID].Listening.RecentEvents
	result := make([]ListeningEvent, 0, len(events))
	for _, event := range events {
		if !event.PlayedAt.Before(since) {
			result = append(result, event)
		}
	}
	sort.Slice(result, func(left, right int) bool {
		if result[left].PlayedAt.Equal(result[right].PlayedAt) {
			return result[left].EventID < result[right].EventID
		}
		return result[left].PlayedAt.After(result[right].PlayedAt)
	})
	return result, nil
}

func (s *Store) ListeningReport(ctx context.Context, userID string, year int) (ListeningReport, error) {
	if err := ctx.Err(); err != nil {
		return ListeningReport{}, err
	}
	userID, err := normalizeUserID(userID)
	if err != nil {
		return ListeningReport{}, err
	}
	yearText := strconv.Itoa(year)
	s.mu.RLock()
	defer s.mu.RUnlock()
	user := s.document.Users[userID]
	report := ListeningReport{
		Year:         year,
		Heatmap:      []DailyMetric{},
		TrackMetrics: []TrackMetric{},
	}
	for date, metric := range user.Listening.Daily {
		if !strings.HasPrefix(date, yearText+"-") || metric.PlayCount == 0 {
			continue
		}
		report.TotalPlays += metric.PlayCount
		report.TotalListenedMS += metric.ListenedMS
		report.ListeningDays++
		report.Heatmap = append(report.Heatmap, DailyMetric{
			Date:       date,
			PlayCount:  metric.PlayCount,
			ListenedMS: metric.ListenedMS,
		})
	}
	for trackID, years := range user.Listening.TrackYears {
		metric := years[yearText]
		if metric.PlayCount == 0 {
			continue
		}
		report.UniqueTracks++
		report.TrackMetrics = append(report.TrackMetrics, TrackMetric{
			TrackID:    trackID,
			PlayCount:  metric.PlayCount,
			ListenedMS: metric.ListenedMS,
		})
	}
	sort.Slice(report.Heatmap, func(left, right int) bool {
		return report.Heatmap[left].Date < report.Heatmap[right].Date
	})
	sortTrackMetrics(report.TrackMetrics)
	return report, nil
}

func (s *Store) HotTrackMetrics(ctx context.Context) ([]TrackMetric, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	values := make(map[string]TrackMetric)
	for _, user := range s.document.Users {
		for trackID, years := range user.Listening.TrackYears {
			metric := values[trackID]
			metric.TrackID = trackID
			for _, yearMetric := range years {
				metric.PlayCount += yearMetric.PlayCount
				metric.ListenedMS += yearMetric.ListenedMS
			}
			values[trackID] = metric
		}
	}
	result := make([]TrackMetric, 0, len(values))
	for _, metric := range values {
		result = append(result, metric)
	}
	sortTrackMetrics(result)
	return result, nil
}

func (s *Store) mutateCollections(
	ctx context.Context,
	userID string,
	mutate func(*persistedUser, time.Time) (bool, error),
) (CollectionsSnapshot, error) {
	if err := ctx.Err(); err != nil {
		return CollectionsSnapshot{}, err
	}
	userID, err := normalizeUserID(userID)
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	next := cloneDocument(s.document)
	user := next.Users[userID]
	changed, err := mutate(&user, s.now().UTC())
	if err != nil {
		return CollectionsSnapshot{}, err
	}
	if !changed {
		return snapshotForUser(s.document.Users[userID]), nil
	}
	user.Revision++
	next.Users[userID] = user
	if err := validateDocument(next); err != nil {
		return CollectionsSnapshot{}, err
	}
	if err := s.write(next); err != nil {
		return CollectionsSnapshot{}, err
	}
	s.document = next
	return snapshotForUser(user), nil
}

func (s *Store) load() error {
	file, err := os.Open(s.filePath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("open user data store: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return fmt.Errorf("stat user data store: %w", err)
	}
	if info.IsDir() {
		return fmt.Errorf("%w: %s is a directory", ErrCorrupt, s.filePath)
	}
	if info.Size() > maxDocumentBytes {
		return fmt.Errorf("%w: user data file exceeds %d bytes", ErrDataLimit, maxDocumentBytes)
	}
	var document persistedDocument
	decoder := json.NewDecoder(io.LimitReader(file, maxDocumentBytes+1))
	if err := decoder.Decode(&document); err != nil {
		return fmt.Errorf("%w: %s: %v", ErrCorrupt, s.filePath, err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return fmt.Errorf("%w: %s contains multiple JSON values", ErrCorrupt, s.filePath)
		}
		return fmt.Errorf("%w: %s: %v", ErrCorrupt, s.filePath, err)
	}
	if document.Version != documentVersion {
		return fmt.Errorf("%w: %d", ErrUnsupportedVersion, document.Version)
	}
	if document.Users == nil {
		document.Users = make(map[string]persistedUser)
	}
	if err := validateDocument(document); err != nil {
		return err
	}
	if err := os.Chmod(s.filePath, 0o600); err != nil {
		return fmt.Errorf("secure user data store: %w", err)
	}
	s.document = document
	return nil
}

func (s *Store) write(document persistedDocument) error {
	temp, err := os.CreateTemp(s.dataDir, ".user-data-*.tmp")
	if err != nil {
		return fmt.Errorf("create temporary user data store: %w", err)
	}
	tempPath := temp.Name()
	remove := true
	defer func() {
		_ = temp.Close()
		if remove {
			_ = os.Remove(tempPath)
		}
	}()
	if err := os.Chmod(tempPath, 0o600); err != nil {
		return fmt.Errorf("secure temporary user data store: %w", err)
	}
	encoder := json.NewEncoder(temp)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(document); err != nil {
		return fmt.Errorf("encode user data store: %w", err)
	}
	info, err := temp.Stat()
	if err != nil {
		return fmt.Errorf("stat temporary user data store: %w", err)
	}
	if info.Size() > maxDocumentBytes {
		return ErrDataLimit
	}
	if err := temp.Sync(); err != nil {
		return fmt.Errorf("sync temporary user data store: %w", err)
	}
	if err := temp.Close(); err != nil {
		return fmt.Errorf("close temporary user data store: %w", err)
	}
	if err := os.Rename(tempPath, s.filePath); err != nil {
		return fmt.Errorf("commit user data store: %w", err)
	}
	remove = false
	if err := s.syncDir(s.dataDir); err != nil {
		return fmt.Errorf("sync user data directory: %w", err)
	}
	return nil
}

func validateDocument(document persistedDocument) error {
	if document.Version != documentVersion {
		return fmt.Errorf("%w: %d", ErrUnsupportedVersion, document.Version)
	}
	if len(document.Users) > maxUsers {
		return ErrDataLimit
	}
	for userID, user := range document.Users {
		if _, err := normalizeUserID(userID); err != nil {
			return fmt.Errorf("%w: %v", ErrCorrupt, err)
		}
		if len(user.FavoriteTrackIDs) > maxFavorites || len(user.Playlists) > maxPlaylists {
			return ErrDataLimit
		}
		if _, err := normalizeTrackIDs(user.FavoriteTrackIDs, maxFavorites); err != nil {
			return fmt.Errorf("%w: %v", ErrCorrupt, err)
		}
		seenPlaylists := make(map[string]struct{}, len(user.Playlists))
		for _, playlist := range user.Playlists {
			if _, err := normalizePlaylistID(playlist.ID); err != nil {
				return fmt.Errorf("%w: %v", ErrCorrupt, err)
			}
			if _, exists := seenPlaylists[playlist.ID]; exists {
				return fmt.Errorf("%w: duplicate playlist id", ErrCorrupt)
			}
			seenPlaylists[playlist.ID] = struct{}{}
			if _, err := normalizePlaylistName(playlist.Name); err != nil {
				return fmt.Errorf("%w: %v", ErrCorrupt, err)
			}
			if _, err := normalizeTrackIDs(playlist.TrackIDs, maxPlaylistTracks); err != nil {
				return fmt.Errorf("%w: %v", ErrCorrupt, err)
			}
		}
		if _, err := normalizePlaybackMode(user.PlaybackMode); err != nil {
			return fmt.Errorf("%w: %v", ErrCorrupt, err)
		}
		if len(user.Listening.EventReceipts) > maxEventReceipts ||
			len(user.Listening.RecentEvents) > maxRecentEvents ||
			trackYearMetricCount(user.Listening.TrackYears) > maxTrackYearMetrics {
			return ErrDataLimit
		}
	}
	return nil
}

func snapshotForUser(user persistedUser) CollectionsSnapshot {
	favorites := append([]string{}, user.FavoriteTrackIDs...)
	playlists := clonePlaylists(user.Playlists)
	if favorites == nil {
		favorites = []string{}
	}
	if playlists == nil {
		playlists = []Playlist{}
	}
	return CollectionsSnapshot{
		Revision:         user.Revision,
		FavoriteTrackIDs: favorites,
		Playlists:        playlists,
	}
}

func playbackModeSnapshotForUser(user persistedUser) PlaybackModeSnapshot {
	mode, err := normalizePlaybackMode(user.PlaybackMode)
	if err != nil {
		mode = PlaybackModeSequential
	}
	return PlaybackModeSnapshot{
		Revision: user.Revision,
		Mode:     mode,
	}
}

func normalizeImportedPlaylists(playlists []Playlist) ([]Playlist, error) {
	if len(playlists) > maxPlaylists {
		return nil, ErrDataLimit
	}
	result := make([]Playlist, 0, len(playlists))
	seen := make(map[string]struct{}, len(playlists))
	for _, playlist := range playlists {
		name, err := normalizePlaylistName(playlist.Name)
		if err != nil {
			return nil, err
		}
		trackIDs, err := normalizeTrackIDs(playlist.TrackIDs, maxPlaylistTracks)
		if err != nil {
			return nil, err
		}
		playlistID := strings.TrimSpace(playlist.ID)
		if playlistID == "" {
			playlistID = importPlaylistID(name, trackIDs)
		}
		playlistID, err = normalizePlaylistID(playlistID)
		if err != nil {
			return nil, err
		}
		if _, exists := seen[playlistID]; exists {
			return nil, ErrInvalidPlaylist
		}
		seen[playlistID] = struct{}{}
		result = append(result, Playlist{ID: playlistID, Name: name, TrackIDs: trackIDs})
	}
	return result, nil
}

func normalizeListeningEvent(event ListeningEvent, now time.Time) (ListeningEvent, error) {
	event.EventID = strings.TrimSpace(event.EventID)
	if event.EventID == "" || len(event.EventID) > maxEventIDLength {
		return ListeningEvent{}, ErrInvalidEvent
	}
	trackID, err := normalizeTrackID(event.TrackID)
	if err != nil {
		return ListeningEvent{}, ErrInvalidEvent
	}
	if event.ListenedMS < 0 || event.ListenedMS > maxListenedMS || event.PlayedAt.IsZero() {
		return ListeningEvent{}, ErrInvalidEvent
	}
	event.TrackID = trackID
	event.PlayedAt = event.PlayedAt.UTC()
	now = now.UTC()
	if event.PlayedAt.After(now) {
		if event.PlayedAt.After(now.Add(maxFutureEventSkew)) {
			return ListeningEvent{}, ErrInvalidEvent
		}
		event.PlayedAt = now
	}
	return event, nil
}

func normalizeUserID(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" || len(value) > 256 {
		return "", ErrInvalidUserID
	}
	return value, nil
}

func normalizeTrackID(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" || len(value) > maxTrackIDLength {
		return "", ErrInvalidTrackID
	}
	return value, nil
}

func normalizePlaylistID(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" || len(value) > maxPlaylistIDLength {
		return "", ErrInvalidPlaylist
	}
	return value, nil
}

func normalizePlaylistName(value string) (string, error) {
	value = strings.Join(strings.Fields(value), " ")
	if value == "" || len([]rune(value)) > maxPlaylistNameLength {
		return "", ErrInvalidPlaylist
	}
	return value, nil
}

func normalizePlaybackMode(value PlaybackMode) (PlaybackMode, error) {
	switch PlaybackMode(strings.TrimSpace(string(value))) {
	case "":
		return PlaybackModeSequential, nil
	case PlaybackModeSequential:
		return PlaybackModeSequential, nil
	case PlaybackModeShuffle:
		return PlaybackModeShuffle, nil
	case PlaybackModeRepeatAll:
		return PlaybackModeRepeatAll, nil
	case PlaybackModeRepeatOne:
		return PlaybackModeRepeatOne, nil
	default:
		return "", ErrInvalidPlaybackMode
	}
}

func normalizeTrackIDs(values []string, limit int) ([]string, error) {
	if len(values) > limit {
		return nil, ErrDataLimit
	}
	result := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		trackID, err := normalizeTrackID(value)
		if err != nil {
			return nil, err
		}
		if _, exists := seen[trackID]; exists {
			continue
		}
		seen[trackID] = struct{}{}
		result = append(result, trackID)
	}
	return result, nil
}

func initializeListening(value *listeningData) {
	if value.Daily == nil {
		value.Daily = make(map[string]aggregate)
	}
	if value.TrackYears == nil {
		value.TrackYears = make(map[string]map[string]aggregate)
	}
	if value.EventReceipts == nil {
		value.EventReceipts = make(map[string]time.Time)
	}
	if value.RecentEvents == nil {
		value.RecentEvents = []ListeningEvent{}
	}
}

func trimRecentEvents(events []ListeningEvent, now time.Time) []ListeningEvent {
	cutoff := now.Add(-recentEventWindow)
	result := make([]ListeningEvent, 0, len(events))
	for _, event := range events {
		if !event.PlayedAt.Before(cutoff) {
			result = append(result, event)
		}
	}
	sort.Slice(result, func(left, right int) bool {
		if result[left].PlayedAt.Equal(result[right].PlayedAt) {
			return result[left].EventID < result[right].EventID
		}
		return result[left].PlayedAt.After(result[right].PlayedAt)
	})
	if len(result) > maxRecentEvents {
		result = result[:maxRecentEvents]
	}
	return result
}

func trackYearMetricCount(values map[string]map[string]aggregate) int {
	count := 0
	for _, years := range values {
		count += len(years)
	}
	return count
}

func removeOldestReceipt(receipts map[string]time.Time) {
	var oldestID string
	var oldestAt time.Time
	for eventID, receivedAt := range receipts {
		if oldestID == "" || receivedAt.Before(oldestAt) || (receivedAt.Equal(oldestAt) && eventID < oldestID) {
			oldestID = eventID
			oldestAt = receivedAt
		}
	}
	delete(receipts, oldestID)
}

func sortTrackMetrics(values []TrackMetric) {
	sort.Slice(values, func(left, right int) bool {
		if values[left].PlayCount != values[right].PlayCount {
			return values[left].PlayCount > values[right].PlayCount
		}
		if values[left].ListenedMS != values[right].ListenedMS {
			return values[left].ListenedMS > values[right].ListenedMS
		}
		return values[left].TrackID < values[right].TrackID
	})
}

func cloneDocument(value persistedDocument) persistedDocument {
	result := persistedDocument{
		Version: value.Version,
		Users:   make(map[string]persistedUser, len(value.Users)),
	}
	for userID, user := range value.Users {
		result.Users[userID] = persistedUser{
			Revision:         user.Revision,
			FavoriteTrackIDs: append([]string{}, user.FavoriteTrackIDs...),
			Playlists:        clonePlaylists(user.Playlists),
			PlaybackMode:     user.PlaybackMode,
			Listening: listeningData{
				Daily:         cloneAggregateMap(user.Listening.Daily),
				TrackYears:    cloneTrackYears(user.Listening.TrackYears),
				RecentEvents:  append([]ListeningEvent{}, user.Listening.RecentEvents...),
				EventReceipts: cloneReceiptMap(user.Listening.EventReceipts),
			},
		}
	}
	return result
}

func clonePlaylists(values []Playlist) []Playlist {
	result := make([]Playlist, len(values))
	for index, playlist := range values {
		result[index] = playlist
		result[index].TrackIDs = append([]string{}, playlist.TrackIDs...)
	}
	return result
}

func cloneAggregateMap(values map[string]aggregate) map[string]aggregate {
	result := make(map[string]aggregate, len(values))
	for key, value := range values {
		result[key] = value
	}
	return result
}

func cloneTrackYears(values map[string]map[string]aggregate) map[string]map[string]aggregate {
	result := make(map[string]map[string]aggregate, len(values))
	for trackID, years := range values {
		result[trackID] = cloneAggregateMap(years)
	}
	return result
}

func cloneReceiptMap(values map[string]time.Time) map[string]time.Time {
	result := make(map[string]time.Time, len(values))
	for eventID, receivedAt := range values {
		result[eventID] = receivedAt
	}
	return result
}

func contains(values []string, target string) bool {
	return indexOf(values, target) >= 0
}

func indexOf(values []string, target string) int {
	for index, value := range values {
		if value == target {
			return index
		}
	}
	return -1
}

func playlistIndex(values []Playlist, playlistID string) int {
	for index, playlist := range values {
		if playlist.ID == playlistID {
			return index
		}
	}
	return -1
}

func removeAt(values []string, index int) []string {
	result := append([]string{}, values[:index]...)
	return append(result, values[index+1:]...)
}

func removePlaylistAt(values []Playlist, index int) []Playlist {
	result := append([]Playlist{}, values[:index]...)
	return append(result, values[index+1:]...)
}

func newPlaylistID() (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", fmt.Errorf("generate playlist id: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(value), nil
}

func importPlaylistID(name string, trackIDs []string) string {
	value := strings.ToLower(name) + "\x00" + strings.Join(trackIDs, "\x00")
	sum := sha256.Sum256([]byte(value))
	return "import-" + hex.EncodeToString(sum[:12])
}

func syncDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open directory: %w", err)
	}
	defer directory.Close()
	if err := directory.Sync(); err != nil {
		if runtime.GOOS == "windows" {
			return syncFile(filepath.Join(path, dataFileName))
		}
		return fmt.Errorf("sync directory: %w", err)
	}
	return nil
}

func syncFile(path string) error {
	file, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("open committed user data store: %w", err)
	}
	defer file.Close()
	if err := file.Sync(); err != nil {
		return fmt.Errorf("sync committed user data store: %w", err)
	}
	return nil
}
