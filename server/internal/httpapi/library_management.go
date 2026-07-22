package httpapi

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"sync"
	"time"

	"music-player-server/internal/library"
	"music-player-server/internal/store"
)

var (
	ErrLibraryScanInProgress       = errors.New("library scan already in progress")
	ErrLibraryScanFailed           = errors.New("library scan failed")
	ErrLibraryScanPathUnavailable  = errors.New("library scan path is unavailable")
	ErrLibraryScanPathInaccessible = errors.New("library scan path is inaccessible")
)

var errLibraryScannerNotConfigured = errors.New("library scanner is not configured")

var errLibraryRepositoryNotConfigured = errors.New("library repository is not configured")

type LibraryScanner interface {
	Scan(ctx context.Context) ([]library.Track, error)
}

type LibraryManagement interface {
	Scan(ctx context.Context) (LibraryScanResult, error)
	Status(ctx context.Context) (LibraryStatus, error)
}

type LibraryManagementService struct {
	directory  string
	scanner    LibraryScanner
	repository store.TrackRepository
	now        func() time.Time

	mu                 sync.RWMutex
	scanning           bool
	lastScannedAt      time.Time
	hasLastScannedAt   bool
	lastScanErrMessage string
}

type LibraryScanResult struct {
	Tracks    []library.Track `json:"tracks"`
	Total     int             `json:"total"`
	ScannedAt time.Time       `json:"scanned_at"`
}

type LibraryStatus struct {
	Directory     string     `json:"directory"`
	TrackCount    int        `json:"track_count"`
	Scanning      bool       `json:"scanning"`
	LastScannedAt *time.Time `json:"last_scanned_at"`
	LastError     string     `json:"last_error"`
}

func NewLibraryManagementService(
	directory string,
	scanner LibraryScanner,
	repository store.TrackRepository,
) *LibraryManagementService {
	return &LibraryManagementService{
		directory:  directory,
		scanner:    scanner,
		repository: repository,
		now:        time.Now,
	}
}

func (s *LibraryManagementService) Scan(ctx context.Context) (LibraryScanResult, error) {
	if !s.beginScan() {
		return LibraryScanResult{}, ErrLibraryScanInProgress
	}
	defer s.finishScan()

	if s.scanner == nil {
		s.recordScanError(errLibraryScannerNotConfigured)
		return LibraryScanResult{}, errLibraryScannerNotConfigured
	}
	if s.repository == nil {
		s.recordScanError(errLibraryRepositoryNotConfigured)
		return LibraryScanResult{}, errLibraryRepositoryNotConfigured
	}
	tracks, err := s.scanner.Scan(ctx)
	if err != nil {
		s.recordScanError(err)
		return LibraryScanResult{}, classifyLibraryScanError(err)
	}
	if len(tracks) == 0 {
		if err := validateLibraryDirectory(s.directory); err != nil {
			s.recordScanError(err)
			return LibraryScanResult{}, err
		}
	}
	if err := s.repository.ReplaceTracks(ctx, tracks); err != nil {
		s.recordScanError(err)
		return LibraryScanResult{}, err
	}

	scannedAt := s.clock().UTC()
	s.recordScanSuccess(scannedAt)
	return LibraryScanResult{
		Tracks:    tracks,
		Total:     len(tracks),
		ScannedAt: scannedAt,
	}, nil
}

func (s *LibraryManagementService) Status(ctx context.Context) (LibraryStatus, error) {
	if s.repository == nil {
		return LibraryStatus{}, errLibraryRepositoryNotConfigured
	}

	tracks, err := s.repository.ListTracks(ctx)
	if err != nil {
		return LibraryStatus{}, err
	}

	s.mu.RLock()
	defer s.mu.RUnlock()

	status := LibraryStatus{
		Directory:  s.directory,
		TrackCount: len(tracks),
		Scanning:   s.scanning,
		LastError:  s.lastScanErrMessage,
	}
	if s.hasLastScannedAt {
		lastScannedAt := s.lastScannedAt
		status.LastScannedAt = &lastScannedAt
	}
	return status, nil
}

func (s *LibraryManagementService) beginScan() bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.scanning {
		return false
	}
	s.scanning = true
	return true
}

func (s *LibraryManagementService) finishScan() {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.scanning = false
}

func (s *LibraryManagementService) recordScanSuccess(scannedAt time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.lastScannedAt = scannedAt
	s.hasLastScannedAt = true
	s.lastScanErrMessage = ""
}

func (s *LibraryManagementService) recordScanError(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.lastScanErrMessage = err.Error()
}

func (s *LibraryManagementService) clock() time.Time {
	if s.now == nil {
		return time.Now()
	}
	return s.now()
}

func validateLibraryDirectory(directory string) error {
	info, err := os.Stat(directory)
	if err != nil {
		return classifyLibraryDirectoryError(directory, err)
	}
	if !info.IsDir() {
		return fmt.Errorf("%w: %q is not a directory", ErrLibraryScanPathUnavailable, directory)
	}

	handle, err := os.Open(directory)
	if err != nil {
		return classifyLibraryDirectoryError(directory, err)
	}
	defer handle.Close()

	if _, err := handle.Readdirnames(1); err != nil && !errors.Is(err, io.EOF) {
		return classifyLibraryDirectoryError(directory, err)
	}
	return nil
}

func classifyLibraryDirectoryError(directory string, err error) error {
	if errors.Is(err, fs.ErrPermission) {
		return fmt.Errorf("%w: %q: %w", ErrLibraryScanPathInaccessible, directory, err)
	}
	return fmt.Errorf("%w: %q: %w", ErrLibraryScanPathUnavailable, directory, err)
}

func classifyLibraryScanError(err error) error {
	if errors.Is(err, fs.ErrPermission) {
		return fmt.Errorf("%w: %w", ErrLibraryScanPathInaccessible, err)
	}
	return fmt.Errorf("%w: %w", ErrLibraryScanFailed, err)
}

func (h *Handler) scanLibrary(w http.ResponseWriter, r *http.Request) {
	if h.libraryManagement == nil {
		writeError(w, http.StatusServiceUnavailable, "library management is not configured")
		return
	}

	result, err := h.libraryManagement.Scan(r.Context())
	if errors.Is(err, ErrLibraryScanInProgress) {
		writeError(w, http.StatusConflict, "library scan already in progress")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to scan library")
		return
	}

	writeJSON(w, http.StatusOK, result)
}

func (h *Handler) libraryStatus(w http.ResponseWriter, r *http.Request) {
	if h.libraryManagement == nil {
		writeError(w, http.StatusServiceUnavailable, "library management is not configured")
		return
	}

	status, err := h.libraryManagement.Status(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to read library status")
		return
	}

	writeJSON(w, http.StatusOK, status)
}
