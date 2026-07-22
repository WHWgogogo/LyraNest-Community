package httpapi

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
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

func TestStreamTrackGET(t *testing.T) {
	content := []byte("fLaC\x00\x00\x00\x22test audio data")
	modified := time.Date(2026, 7, 18, 12, 30, 0, 0, time.UTC)
	track := testStreamTrack(t, "track-flac", "sample.flac", content, modified)
	handler := NewHandler(&fakeTrackRepository{tracks: []library.Track{track}}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-flac/stream", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	if body := response.Body.Bytes(); string(body) != string(content) {
		t.Fatalf("body = %q, want %q", body, content)
	}
	assertStreamHeaders(t, response, track.FileName, "audio/flac", len(content), modified, content)
	if response.Header().Get("Accept-Ranges") != "bytes" {
		t.Fatalf("Accept-Ranges = %q, want bytes", response.Header().Get("Accept-Ranges"))
	}
}

func TestStreamDigestCacheEvictsLeastRecentlyUsedEntry(t *testing.T) {
	root := t.TempDir()
	paths := []string{
		filepath.Join(root, "one.mp3"),
		filepath.Join(root, "two.mp3"),
		filepath.Join(root, "three.mp3"),
	}
	infos := make([]os.FileInfo, len(paths))
	for index, path := range paths {
		if err := os.WriteFile(path, []byte{byte(index)}, 0o600); err != nil {
			t.Fatalf("write fixture: %v", err)
		}
		info, err := os.Stat(path)
		if err != nil {
			t.Fatalf("stat fixture: %v", err)
		}
		infos[index] = info
	}

	cache := newStreamDigestCache(2)
	cache.put(paths[0], infos[0], sha256.Sum256([]byte("one")))
	cache.put(paths[1], infos[1], sha256.Sum256([]byte("two")))
	if _, ok := cache.get(paths[0], infos[0]); !ok {
		t.Fatal("first digest cache lookup = miss, want hit")
	}
	cache.put(paths[2], infos[2], sha256.Sum256([]byte("three")))

	if _, ok := cache.get(paths[1], infos[1]); ok {
		t.Fatal("least recently used digest remained cached")
	}
	if _, ok := cache.get(paths[0], infos[0]); !ok {
		t.Fatal("recent digest cache lookup = miss, want hit")
	}
	if _, ok := cache.get(paths[2], infos[2]); !ok {
		t.Fatal("new digest cache lookup = miss, want hit")
	}
}

func TestStreamTrackHEAD(t *testing.T) {
	content := []byte("ID3 head request")
	modified := time.Date(2026, 7, 18, 12, 31, 0, 0, time.UTC)
	track := testStreamTrack(t, "track-mp3", "sample.mp3", content, modified)
	handler := NewHandler(&fakeTrackRepository{tracks: []library.Track{track}}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodHead, "/api/v1/tracks/track-mp3/stream", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	if response.Body.Len() != 0 {
		t.Fatalf("body length = %d, want 0", response.Body.Len())
	}
	assertStreamHeaders(t, response, track.FileName, "audio/mpeg", len(content), modified, content)
}

func TestStreamTrackRange(t *testing.T) {
	content := []byte("0123456789")
	modified := time.Date(2026, 7, 18, 12, 32, 0, 0, time.UTC)
	track := testStreamTrack(t, "track-range", "sample.ogg", content, modified)
	handler := NewHandler(&fakeTrackRepository{tracks: []library.Track{track}}, library.NewLyricsService()).Routes()

	request := httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-range/stream", nil)
	request.Header.Set("Range", "bytes=2-5")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusPartialContent {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusPartialContent)
	}
	if body := response.Body.String(); body != "2345" {
		t.Fatalf("body = %q, want %q", body, "2345")
	}
	if contentRange := response.Header().Get("Content-Range"); contentRange != "bytes 2-5/10" {
		t.Fatalf("Content-Range = %q, want %q", contentRange, "bytes 2-5/10")
	}
	if contentLength := response.Header().Get("Content-Length"); contentLength != "4" {
		t.Fatalf("Content-Length = %q, want 4", contentLength)
	}
	assertStreamHeaders(t, response, track.FileName, "audio/ogg", 4, modified, content)
}

func TestStreamTrackIfRange(t *testing.T) {
	content := []byte("0123456789")
	modified := time.Date(2026, 7, 18, 12, 33, 0, 0, time.UTC)
	track := testStreamTrack(t, "track-if-range", "sample.mp3", content, modified)
	handler := NewHandler(&fakeTrackRepository{tracks: []library.Track{track}}, library.NewLyricsService()).Routes()

	initialResponse := httptest.NewRecorder()
	handler.ServeHTTP(initialResponse, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-if-range/stream", nil))
	etag := initialResponse.Header().Get("ETag")
	if etag == "" {
		t.Fatal("initial response did not include ETag")
	}

	tests := []struct {
		name       string
		ifRange    string
		wantStatus int
		wantBody   string
		wantRange  string
		wantLength string
	}{
		{
			name:       "matching etag",
			ifRange:    etag,
			wantStatus: http.StatusPartialContent,
			wantBody:   "2345",
			wantRange:  "bytes 2-5/10",
			wantLength: "4",
		},
		{
			name:       "stale etag",
			ifRange:    `"stale"`,
			wantStatus: http.StatusOK,
			wantBody:   string(content),
			wantLength: "10",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-if-range/stream", nil)
			request.Header.Set("Range", "bytes=2-5")
			request.Header.Set("If-Range", test.ifRange)
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, request)

			if response.Code != test.wantStatus {
				t.Fatalf("status = %d, want %d", response.Code, test.wantStatus)
			}
			if body := response.Body.String(); body != test.wantBody {
				t.Fatalf("body = %q, want %q", body, test.wantBody)
			}
			if got := response.Header().Get("Content-Range"); got != test.wantRange {
				t.Fatalf("Content-Range = %q, want %q", got, test.wantRange)
			}
			if got := response.Header().Get("Content-Length"); got != test.wantLength {
				t.Fatalf("Content-Length = %q, want %q", got, test.wantLength)
			}
			assertStreamHeaders(t, response, track.FileName, "audio/mpeg", len([]byte(test.wantBody)), modified, content)
		})
	}
}

func TestStreamTrackUnknownTrack(t *testing.T) {
	handler := NewHandler(&fakeTrackRepository{}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/missing/stream", nil))

	assertErrorResponse(t, response, http.StatusNotFound, "track not found")
}

func TestStreamTrackMissingFile(t *testing.T) {
	track := testTrack(t, "track-missing-file", "missing.flac")
	handler := NewHandler(&fakeTrackRepository{tracks: []library.Track{track}}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-missing-file/stream", nil))

	assertErrorResponse(t, response, http.StatusNotFound, "audio file not found")
	if strings.Contains(response.Body.String(), track.Path) {
		t.Fatalf("error response exposed absolute path %q", track.Path)
	}
}

func TestStreamTrackFileReadError(t *testing.T) {
	track := testTrack(t, "track-read-error", "unreadable.flac")
	track.Path += "\x00"
	handler := NewHandler(&fakeTrackRepository{tracks: []library.Track{track}}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-read-error/stream", nil))

	assertErrorResponse(t, response, http.StatusInternalServerError, "failed to read audio file")
	if strings.Contains(response.Body.String(), track.Path) {
		t.Fatalf("error response exposed source path")
	}
}

func TestAudioContentType(t *testing.T) {
	tests := map[string]string{
		"mp3":  "audio/mpeg",
		"flac": "audio/flac",
		"m4a":  "audio/mp4",
		"ogg":  "audio/ogg",
		"opus": "audio/ogg",
		"wav":  "audio/wav",
	}

	for extension, want := range tests {
		t.Run(extension, func(t *testing.T) {
			track := library.Track{Extension: extension}
			if got := audioContentType(track); got != want {
				t.Fatalf("audioContentType(%q) = %q, want %q", extension, got, want)
			}
		})
	}
}

func testStreamTrack(t *testing.T, id, fileName string, content []byte, modified time.Time) library.Track {
	t.Helper()

	path := filepath.Join(t.TempDir(), fileName)
	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatalf("write stream fixture: %v", err)
	}
	if err := os.Chtimes(path, modified, modified); err != nil {
		t.Fatalf("set stream fixture time: %v", err)
	}

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

func assertStreamHeaders(
	t *testing.T,
	response *httptest.ResponseRecorder,
	fileName string,
	contentType string,
	contentLength int,
	modified time.Time,
	mediaContent []byte,
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
	digest := sha256.Sum256(mediaContent)
	if got := response.Header().Get("ETag"); got != fmt.Sprintf(`"%x"`, digest) {
		t.Fatalf("ETag = %q, want %q", got, fmt.Sprintf(`"%x"`, digest))
	}
	if got := response.Header().Get("Digest"); got != "sha-256="+base64.StdEncoding.EncodeToString(digest[:]) {
		t.Fatalf("Digest = %q, want sha-256 digest", got)
	}
	if got := response.Header().Get("X-Media-Version"); got != hex.EncodeToString(digest[:]) {
		t.Fatalf("X-Media-Version = %q, want %q", got, hex.EncodeToString(digest[:]))
	}
	wantDisposition := fmt.Sprintf(`inline; filename=%s`, fileName)
	if got := response.Header().Get("Content-Disposition"); got != wantDisposition {
		t.Fatalf("Content-Disposition = %q, want %q", got, wantDisposition)
	}
}
