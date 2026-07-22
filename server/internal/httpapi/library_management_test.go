package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"music-player-server/internal/library"
	"music-player-server/internal/store"
)

type fakeLibraryScanner struct {
	tracks []library.Track
	err    error
	calls  int
}

func (s *fakeLibraryScanner) Scan(_ context.Context) ([]library.Track, error) {
	s.calls++
	if s.err != nil {
		return nil, s.err
	}
	return s.tracks, nil
}

type blockingLibraryScanner struct {
	started chan struct{}
	release chan struct{}
	once    sync.Once
	tracks  []library.Track
}

func (s *blockingLibraryScanner) Scan(ctx context.Context) ([]library.Track, error) {
	s.once.Do(func() {
		close(s.started)
	})

	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-s.release:
		return s.tracks, nil
	}
}

func TestScanLibrarySuccessUpdatesRepositoryAndStatus(t *testing.T) {
	scannedAt := time.Date(2026, 7, 18, 14, 30, 0, 0, time.UTC)
	track := library.Track{
		ID:        "track-1",
		Title:     "Song One",
		FileName:  "song-one.mp3",
		Path:      filepath.Join(t.TempDir(), "song-one.mp3"),
		Extension: "mp3",
		SizeBytes: 123,
		Modified:  scannedAt.Add(-time.Hour),
	}
	repository := &fakeTrackRepository{}
	scanner := &fakeLibraryScanner{tracks: []library.Track{track}}
	manager := NewLibraryManagementService("C:\\Music", scanner, repository)
	manager.now = func() time.Time { return scannedAt }
	handler := NewHandler(
		repository,
		library.NewLyricsService(),
		WithLibraryManagementService(manager),
	).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/api/v1/library/scan", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	var body LibraryScanResult
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatalf("decode scan response: %v", err)
	}
	if scanner.calls != 1 {
		t.Fatalf("scanner calls = %d, want 1", scanner.calls)
	}
	if body.Total != 1 || len(body.Tracks) != 1 || body.Tracks[0].ID != "track-1" {
		t.Fatalf("scan response = %#v, want track-1 total 1", body)
	}
	if !body.ScannedAt.Equal(scannedAt) {
		t.Fatalf("scanned_at = %s, want %s", body.ScannedAt, scannedAt)
	}

	statusResponse := httptest.NewRecorder()
	handler.ServeHTTP(statusResponse, httptest.NewRequest(http.MethodGet, "/api/v1/library/status", nil))

	if statusResponse.Code != http.StatusOK {
		t.Fatalf("status code = %d, want %d", statusResponse.Code, http.StatusOK)
	}
	var status LibraryStatus
	if err := json.NewDecoder(statusResponse.Body).Decode(&status); err != nil {
		t.Fatalf("decode status response: %v", err)
	}
	if status.Directory != "C:\\Music" {
		t.Fatalf("directory = %q, want C:\\Music", status.Directory)
	}
	if status.TrackCount != 1 {
		t.Fatalf("track_count = %d, want 1", status.TrackCount)
	}
	if status.Scanning {
		t.Fatal("scanning = true, want false")
	}
	if status.LastScannedAt == nil || !status.LastScannedAt.Equal(scannedAt) {
		t.Fatalf("last_scanned_at = %v, want %s", status.LastScannedAt, scannedAt)
	}
	if status.LastError != "" {
		t.Fatalf("last_error = %q, want empty", status.LastError)
	}
}

func TestScanLibraryErrorRecordsStatus(t *testing.T) {
	scanErr := errors.New("decode music file")
	existing := library.Track{ID: "existing", Title: "Existing", FileName: "existing.mp3", Extension: "mp3"}
	repository := &fakeTrackRepository{tracks: []library.Track{existing}}
	manager := NewLibraryManagementService(
		"C:\\Music",
		&fakeLibraryScanner{err: scanErr},
		repository,
	)
	handler := NewHandler(
		repository,
		library.NewLyricsService(),
		WithLibraryManagementService(manager),
	).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/api/v1/library/scan", nil))

	assertErrorResponse(t, response, http.StatusInternalServerError, "failed to scan library")

	statusResponse := httptest.NewRecorder()
	handler.ServeHTTP(statusResponse, httptest.NewRequest(http.MethodGet, "/api/v1/library/status", nil))

	if statusResponse.Code != http.StatusOK {
		t.Fatalf("status code = %d, want %d", statusResponse.Code, http.StatusOK)
	}
	var status LibraryStatus
	if err := json.NewDecoder(statusResponse.Body).Decode(&status); err != nil {
		t.Fatalf("decode status response: %v", err)
	}
	if status.LastError != scanErr.Error() {
		t.Fatalf("last_error = %q, want %q", status.LastError, scanErr.Error())
	}
	if status.LastScannedAt != nil {
		t.Fatalf("last_scanned_at = %v, want nil", status.LastScannedAt)
	}
	tracks, err := repository.ListTracks(context.Background())
	if err != nil {
		t.Fatalf("ListTracks returned error: %v", err)
	}
	if len(tracks) != 1 || tracks[0].ID != existing.ID {
		t.Fatalf("tracks = %#v, want existing index unchanged", tracks)
	}
}

func TestScanLibraryMissingDirectoryPreservesPersistedIndex(t *testing.T) {
	dataDir := filepath.Join(t.TempDir(), "data")
	repository, err := store.NewJSONRepository(dataDir)
	if err != nil {
		t.Fatalf("NewJSONRepository returned error: %v", err)
	}
	existing := library.Track{
		ID:        "existing",
		Title:     "Existing",
		FileName:  "existing.mp3",
		Path:      filepath.Join(t.TempDir(), "existing.mp3"),
		Extension: "mp3",
	}
	if err := repository.ReplaceTracks(context.Background(), []library.Track{existing}); err != nil {
		t.Fatalf("seed persisted tracks: %v", err)
	}

	missingDirectory := filepath.Join(t.TempDir(), "missing")
	manager := NewLibraryManagementService(
		missingDirectory,
		library.NewScanner(missingDirectory),
		repository,
	)

	_, err = manager.Scan(context.Background())
	if !errors.Is(err, ErrLibraryScanPathUnavailable) {
		t.Fatalf("Scan error = %v, want ErrLibraryScanPathUnavailable", err)
	}

	restarted, err := store.NewJSONRepository(dataDir)
	if err != nil {
		t.Fatalf("reopen JSON repository: %v", err)
	}
	tracks, err := restarted.ListTracks(context.Background())
	if err != nil {
		t.Fatalf("ListTracks returned error: %v", err)
	}
	if len(tracks) != 1 || tracks[0].ID != existing.ID {
		t.Fatalf("persisted tracks = %#v, want existing index unchanged", tracks)
	}
}

func TestScanLibraryAccessibleEmptyDirectoryClearsPersistedIndex(t *testing.T) {
	dataDir := filepath.Join(t.TempDir(), "data")
	repository, err := store.NewJSONRepository(dataDir)
	if err != nil {
		t.Fatalf("NewJSONRepository returned error: %v", err)
	}
	existing := library.Track{
		ID:        "existing",
		Title:     "Existing",
		FileName:  "existing.mp3",
		Path:      filepath.Join(t.TempDir(), "existing.mp3"),
		Extension: "mp3",
	}
	if err := repository.ReplaceTracks(context.Background(), []library.Track{existing}); err != nil {
		t.Fatalf("seed persisted tracks: %v", err)
	}

	emptyDirectory := t.TempDir()
	manager := NewLibraryManagementService(
		emptyDirectory,
		library.NewScanner(emptyDirectory),
		repository,
	)

	result, err := manager.Scan(context.Background())
	if err != nil {
		t.Fatalf("Scan returned error: %v", err)
	}
	if result.Total != 0 || len(result.Tracks) != 0 {
		t.Fatalf("scan result = %#v, want an empty library", result)
	}

	restarted, err := store.NewJSONRepository(dataDir)
	if err != nil {
		t.Fatalf("reopen JSON repository: %v", err)
	}
	tracks, err := restarted.ListTracks(context.Background())
	if err != nil {
		t.Fatalf("ListTracks returned error: %v", err)
	}
	if len(tracks) != 0 {
		t.Fatalf("persisted tracks = %#v, want empty", tracks)
	}
}

func TestScanLibraryConcurrentRequestReturnsConflict(t *testing.T) {
	track := library.Track{ID: "track-1", Title: "Song One", FileName: "song-one.mp3", Extension: "mp3"}
	repository := &fakeTrackRepository{}
	scanner := &blockingLibraryScanner{
		started: make(chan struct{}),
		release: make(chan struct{}),
		tracks:  []library.Track{track},
	}
	manager := NewLibraryManagementService("C:\\Music", scanner, repository)
	handler := NewHandler(
		repository,
		library.NewLyricsService(),
		WithLibraryManagementService(manager),
	).Routes()

	firstDone := make(chan *httptest.ResponseRecorder, 1)
	go func() {
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/api/v1/library/scan", nil))
		firstDone <- response
	}()

	select {
	case <-scanner.started:
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for first scan to start")
	}

	conflictResponse := httptest.NewRecorder()
	handler.ServeHTTP(conflictResponse, httptest.NewRequest(http.MethodPost, "/api/v1/library/scan", nil))

	assertErrorResponse(t, conflictResponse, http.StatusConflict, "library scan already in progress")

	close(scanner.release)
	select {
	case response := <-firstDone:
		if response.Code != http.StatusOK {
			t.Fatalf("first scan status = %d, want %d", response.Code, http.StatusOK)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for first scan to finish")
	}
}

func TestLibraryCORSPreflightAllowsWebHeaders(t *testing.T) {
	handler := NewHandler(&fakeTrackRepository{}, library.NewLyricsService()).Routes()
	request := httptest.NewRequest(http.MethodOptions, "/api/v1/library/scan", nil)
	request.Header.Set("Origin", "http://192.168.1.20:5173")
	request.Header.Set("Access-Control-Request-Method", http.MethodPost)
	request.Header.Set("Access-Control-Request-Headers", "Range, Content-Type")

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusNoContent)
	}
	if got := response.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("Access-Control-Allow-Origin = %q, want *", got)
	}
	if got := response.Header().Get("Access-Control-Allow-Methods"); !strings.Contains(got, "GET") || !strings.Contains(got, "HEAD") || !strings.Contains(got, "POST") || !strings.Contains(got, "OPTIONS") {
		t.Fatalf("Access-Control-Allow-Methods = %q, want GET/HEAD/POST/OPTIONS", got)
	}
	if got := response.Header().Get("Access-Control-Allow-Headers"); !strings.Contains(got, "Range") || !strings.Contains(got, "Content-Type") {
		t.Fatalf("Access-Control-Allow-Headers = %q, want Range and Content-Type", got)
	}
}
