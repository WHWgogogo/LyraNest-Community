package httpapi

import (
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"music-player-server/internal/library"
)

func TestGetTrackArtworkPrefersSidecarAndRevalidates(t *testing.T) {
	audioModified := time.Date(2026, 7, 18, 9, 0, 0, 0, time.UTC)
	sidecarModified := time.Date(2026, 7, 18, 10, 30, 0, 0, time.UTC)
	track := testArtworkTrack(t, "track-sidecar", "song.mp3", []byte("audio"), audioModified)
	jpeg := []byte{0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 'J', 'F', 'I', 'F', 0x00, 0x01}
	png := []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n', 'p', 'n', 'g'}
	writeArtworkFixture(t, trimExtension(track.Path)+".png", png, sidecarModified.Add(time.Hour))
	writeArtworkFixture(t, trimExtension(track.Path)+".jpg", jpeg, sidecarModified)

	handler := newArtworkTestHandler(&fakeTrackRepository{tracks: []library.Track{track}})
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-sidecar/artwork", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	if got := response.Body.Bytes(); string(got) != string(jpeg) {
		t.Fatalf("body = %v, want preferred jpg sidecar %v", got, jpeg)
	}
	assertArtworkHeaders(t, response, "image/jpeg", len(jpeg), sidecarModified, jpeg)

	conditionalRequest := httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-sidecar/artwork", nil)
	conditionalRequest.Header.Set("If-None-Match", response.Header().Get("ETag"))
	conditionalResponse := httptest.NewRecorder()
	handler.ServeHTTP(conditionalResponse, conditionalRequest)

	if conditionalResponse.Code != http.StatusNotModified {
		t.Fatalf("conditional status = %d, want %d", conditionalResponse.Code, http.StatusNotModified)
	}
	if conditionalResponse.Body.Len() != 0 {
		t.Fatalf("conditional body length = %d, want 0", conditionalResponse.Body.Len())
	}
	if got := conditionalResponse.Header().Get("Cache-Control"); got != artworkCacheControl {
		t.Fatalf("conditional Cache-Control = %q, want %q", got, artworkCacheControl)
	}
}

func TestGetTrackArtworkHEAD(t *testing.T) {
	modified := time.Date(2026, 7, 18, 11, 0, 0, 0, time.UTC)
	track := testArtworkTrack(t, "track-head", "head.flac", []byte("audio"), modified.Add(-time.Hour))
	png := []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n', 'h', 'e', 'a', 'd'}
	writeArtworkFixture(t, trimExtension(track.Path)+".png", png, modified)
	handler := newArtworkTestHandler(&fakeTrackRepository{tracks: []library.Track{track}})

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodHead, "/api/v1/tracks/track-head/artwork", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	if response.Body.Len() != 0 {
		t.Fatalf("body length = %d, want 0", response.Body.Len())
	}
	assertArtworkHeaders(t, response, "image/png", len(png), modified, png)
}

func TestGetTrackArtworkFallsBackToEmbeddedCover(t *testing.T) {
	modified := time.Date(2026, 7, 18, 12, 0, 0, 0, time.UTC)
	png := []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n', 'c', 'o', 'v', 'e', 'r'}
	audio := id3v23ArtworkFixture("image/png", png)
	track := testArtworkTrack(t, "track-embedded", "embedded.mp3", audio, modified)
	handler := newArtworkTestHandler(&fakeTrackRepository{tracks: []library.Track{track}})

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-embedded/artwork", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d; body = %s", response.Code, http.StatusOK, response.Body.String())
	}
	if got := response.Body.Bytes(); string(got) != string(png) {
		t.Fatalf("body = %v, want embedded cover %v", got, png)
	}
	assertArtworkHeaders(t, response, "image/png", len(png), modified, png)
}

func TestGetTrackArtworkUnknownTrack(t *testing.T) {
	handler := newArtworkTestHandler(&fakeTrackRepository{})
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/missing/artwork", nil))

	assertErrorResponse(t, response, http.StatusNotFound, "track not found")
	if got := response.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", got)
	}
}

func TestGetTrackArtworkMissingArtwork(t *testing.T) {
	modified := time.Date(2026, 7, 18, 13, 0, 0, 0, time.UTC)
	track := testArtworkTrack(t, "track-no-artwork", "plain.mp3", []byte("audio without metadata"), modified)
	handler := newArtworkTestHandler(&fakeTrackRepository{tracks: []library.Track{track}})
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-no-artwork/artwork", nil))

	assertErrorResponse(t, response, http.StatusNotFound, "artwork not found")
}

func TestGetTrackArtworkReadErrorDoesNotExposePath(t *testing.T) {
	privatePath := filepath.Join(t.TempDir(), "private-song.mp3") + "\x00"
	track := library.Track{
		ID:       "track-read-error",
		FileName: "private-song.mp3",
		Path:     privatePath,
	}
	handler := newArtworkTestHandler(&fakeTrackRepository{tracks: []library.Track{track}})
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-read-error/artwork", nil))

	assertErrorResponse(t, response, http.StatusInternalServerError, "failed to read artwork")
	if strings.Contains(response.Body.String(), filepath.Dir(privatePath)) || strings.Contains(response.Body.String(), "private-song.mp3") {
		t.Fatalf("error response exposed source path: %q", response.Body.String())
	}
}

func newArtworkTestHandler(repository *fakeTrackRepository) http.Handler {
	handler := NewHandler(repository, library.NewLyricsService())
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/tracks/{id}/artwork", handler.getTrackArtwork)
	mux.HandleFunc("HEAD /api/v1/tracks/{id}/artwork", handler.getTrackArtwork)
	return mux
}

func testArtworkTrack(t *testing.T, id, fileName string, content []byte, modified time.Time) library.Track {
	t.Helper()

	path := filepath.Join(t.TempDir(), fileName)
	writeArtworkFixture(t, path, content, modified)
	return library.Track{
		ID:        id,
		Title:     strings.TrimSuffix(fileName, filepath.Ext(fileName)),
		FileName:  fileName,
		Path:      path,
		Extension: strings.TrimPrefix(filepath.Ext(fileName), "."),
		SizeBytes: int64(len(content)),
		Modified:  modified,
	}
}

func writeArtworkFixture(t *testing.T, path string, content []byte, modified time.Time) {
	t.Helper()

	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatalf("write artwork fixture: %v", err)
	}
	if err := os.Chtimes(path, modified, modified); err != nil {
		t.Fatalf("set artwork fixture time: %v", err)
	}
}

func assertArtworkHeaders(
	t *testing.T,
	response *httptest.ResponseRecorder,
	contentType string,
	contentLength int,
	modified time.Time,
	content []byte,
) {
	t.Helper()

	if got := response.Header().Get("Content-Type"); got != contentType {
		t.Fatalf("Content-Type = %q, want %q", got, contentType)
	}
	if got := response.Header().Get("Content-Length"); got != strconv.Itoa(contentLength) {
		t.Fatalf("Content-Length = %q, want %d", got, contentLength)
	}
	if got := response.Header().Get("Last-Modified"); got != modified.Format(http.TimeFormat) {
		t.Fatalf("Last-Modified = %q, want %q", got, modified.Format(http.TimeFormat))
	}
	wantETag := fmt.Sprintf(`"%x"`, sha256.Sum256(content))
	if got := response.Header().Get("ETag"); got != wantETag {
		t.Fatalf("ETag = %q, want %q", got, wantETag)
	}
	if got := response.Header().Get("Cache-Control"); got != artworkCacheControl {
		t.Fatalf("Cache-Control = %q, want %q", got, artworkCacheControl)
	}
	if got := response.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options = %q, want nosniff", got)
	}
}

func id3v23ArtworkFixture(mimeType string, artwork []byte) []byte {
	frameData := make([]byte, 0, len(mimeType)+len(artwork)+4)
	frameData = append(frameData, 0)
	frameData = append(frameData, mimeType...)
	frameData = append(frameData, 0, 3, 0)
	frameData = append(frameData, artwork...)

	frame := make([]byte, 10, 10+len(frameData))
	copy(frame, "APIC")
	binary.BigEndian.PutUint32(frame[4:8], uint32(len(frameData)))
	frame = append(frame, frameData...)

	header := []byte{'I', 'D', '3', 3, 0, 0, 0, 0, 0, 0}
	size := len(frame)
	header[6] = byte(size >> 21)
	header[7] = byte(size >> 14)
	header[8] = byte(size >> 7)
	header[9] = byte(size)
	return append(header, frame...)
}
