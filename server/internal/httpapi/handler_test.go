package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"music-player-server/internal/library"
	"music-player-server/internal/store"
)

type fakeTrackRepository struct {
	tracks  []library.Track
	listErr error
}

func (r *fakeTrackRepository) ReplaceTracks(_ context.Context, tracks []library.Track) error {
	r.tracks = tracks
	return nil
}

func (r *fakeTrackRepository) ListTracks(_ context.Context) ([]library.Track, error) {
	if r.listErr != nil {
		return nil, r.listErr
	}
	return r.tracks, nil
}

func (r *fakeTrackRepository) GetTrack(_ context.Context, id string) (library.Track, error) {
	for _, track := range r.tracks {
		if track.ID == id {
			return track, nil
		}
	}
	return library.Track{}, store.ErrTrackNotFound
}

func TestHealthz(t *testing.T) {
	handler := NewHandler(&fakeTrackRepository{}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}

	var body map[string]string
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body["status"] != "ok" {
		t.Fatalf("status body = %q, want ok", body["status"])
	}
}

func TestIndex(t *testing.T) {
	handler := NewHandler(&fakeTrackRepository{}, library.NewLyricsService()).Routes()
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	if contentType := response.Header().Get("Content-Type"); contentType != "text/html; charset=utf-8" {
		t.Fatalf("content type = %q, want text/html; charset=utf-8", contentType)
	}
	if !strings.Contains(strings.ToLower(response.Body.String()), "<!doctype html>") {
		t.Fatalf("body = %q, want embedded web UI", response.Body.String())
	}
}

func TestAPIIndex(t *testing.T) {
	handler := NewHandler(&fakeTrackRepository{}, library.NewLyricsService()).Routes()
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	var body map[string]string
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body["name"] != "LyraNest Community Server" || body["tracks"] != "/api/v1/tracks" {
		t.Fatalf("body = %#v, want API index", body)
	}
}

func TestListTracks(t *testing.T) {
	modified := time.Date(2026, 7, 18, 10, 0, 0, 0, time.UTC)
	tracks := []library.Track{
		{
			ID:        "track-1",
			Title:     "Song One",
			FileName:  "song-one.mp3",
			Path:      filepath.Join(t.TempDir(), "song-one.mp3"),
			Extension: "mp3",
			SizeBytes: 123,
			Modified:  modified,
		},
	}
	handler := NewHandler(&fakeTrackRepository{tracks: tracks}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks", nil))

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}

	var body tracksResponse
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Total != 1 {
		t.Fatalf("total = %d, want 1", body.Total)
	}
	if len(body.Tracks) != 1 || body.Tracks[0].ID != "track-1" {
		t.Fatalf("tracks = %#v, want track-1", body.Tracks)
	}
}

func TestLibraryBrowseAndSearch(t *testing.T) {
	modified := time.Date(2026, 7, 18, 10, 0, 0, 0, time.UTC)
	tracks := []library.Track{
		{
			ID:          "track-1",
			Title:       "Opening",
			Artist:      "Artist One",
			Album:       "First Album",
			AlbumArtist: "Artist One",
			TrackNumber: 1,
			DurationMS:  1000,
			FileName:    "opening.mp3",
			Extension:   "mp3",
			Modified:    modified,
		},
		{
			ID:          "track-2",
			Title:       "Finale",
			Artist:      "Artist One",
			Album:       "First Album",
			AlbumArtist: "Artist One",
			TrackNumber: 2,
			DurationMS:  2000,
			FileName:    "finale.mp3",
			Extension:   "mp3",
			Modified:    modified,
		},
		{
			ID:         "track-3",
			Title:      "Side Song",
			Artist:     "Artist Two",
			Album:      "Second Album",
			DurationMS: 3000,
			FileName:   "side.mp3",
			Extension:  "mp3",
			Modified:   modified,
		},
	}
	handler := NewHandler(&fakeTrackRepository{tracks: tracks}, library.NewLyricsService()).Routes()

	albumsResponseRecorder := httptest.NewRecorder()
	handler.ServeHTTP(albumsResponseRecorder, httptest.NewRequest(http.MethodGet, "/api/v1/albums", nil))
	if albumsResponseRecorder.Code != http.StatusOK {
		t.Fatalf("albums status = %d, want %d", albumsResponseRecorder.Code, http.StatusOK)
	}
	var albums albumsResponse
	if err := json.NewDecoder(albumsResponseRecorder.Body).Decode(&albums); err != nil {
		t.Fatalf("decode albums response: %v", err)
	}
	if albums.Total != 2 || albums.Albums[0].Title != "First Album" || albums.Albums[0].TrackCount != 2 {
		t.Fatalf("albums = %#v, want first album summary", albums)
	}

	albumTracksResponse := httptest.NewRecorder()
	handler.ServeHTTP(albumTracksResponse, httptest.NewRequest(http.MethodGet, "/api/v1/albums/"+albums.Albums[0].ID+"/tracks", nil))
	if albumTracksResponse.Code != http.StatusOK {
		t.Fatalf("album tracks status = %d, want %d", albumTracksResponse.Code, http.StatusOK)
	}
	var albumTracks tracksResponse
	if err := json.NewDecoder(albumTracksResponse.Body).Decode(&albumTracks); err != nil {
		t.Fatalf("decode album tracks response: %v", err)
	}
	if albumTracks.Total != 2 || albumTracks.Tracks[0].ID != "track-1" || albumTracks.Tracks[1].ID != "track-2" {
		t.Fatalf("album tracks = %#v, want album tracks in playback order", albumTracks)
	}

	artistsResponseRecorder := httptest.NewRecorder()
	handler.ServeHTTP(artistsResponseRecorder, httptest.NewRequest(http.MethodGet, "/api/v1/artists", nil))
	if artistsResponseRecorder.Code != http.StatusOK {
		t.Fatalf("artists status = %d, want %d", artistsResponseRecorder.Code, http.StatusOK)
	}
	var artists artistsResponse
	if err := json.NewDecoder(artistsResponseRecorder.Body).Decode(&artists); err != nil {
		t.Fatalf("decode artists response: %v", err)
	}
	if artists.Total != 2 || artists.Artists[0].Name != "Artist One" || artists.Artists[0].AlbumCount != 1 {
		t.Fatalf("artists = %#v, want artist summary", artists)
	}

	searchResponseRecorder := httptest.NewRecorder()
	handler.ServeHTTP(searchResponseRecorder, httptest.NewRequest(http.MethodGet, "/api/v1/search?q=first&limit=5", nil))
	if searchResponseRecorder.Code != http.StatusOK {
		t.Fatalf("search status = %d, want %d", searchResponseRecorder.Code, http.StatusOK)
	}
	var search searchResponse
	if err := json.NewDecoder(searchResponseRecorder.Body).Decode(&search); err != nil {
		t.Fatalf("decode search response: %v", err)
	}
	if search.Query != "first" || len(search.Tracks) != 2 || len(search.Albums) != 1 || len(search.Artists) != 0 {
		t.Fatalf("search = %#v, want first album matches", search)
	}
}

func TestRoutesTrackArtwork(t *testing.T) {
	handler := NewHandler(&fakeTrackRepository{}, library.NewLyricsService()).Routes()

	for _, method := range []string{http.MethodGet, http.MethodHead} {
		t.Run(method, func(t *testing.T) {
			response := httptest.NewRecorder()
			handler.ServeHTTP(
				response,
				httptest.NewRequest(method, "/api/v1/tracks/missing/artwork", nil),
			)

			if response.Code != http.StatusNotFound {
				t.Fatalf("status = %d, want %d", response.Code, http.StatusNotFound)
			}
			if method == http.MethodHead && response.Body.Len() != 0 {
				t.Fatalf("HEAD body length = %d, want 0", response.Body.Len())
			}
		})
	}
}

func TestGetLyricsUnknownTrack(t *testing.T) {
	handler := NewHandler(&fakeTrackRepository{}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/missing/lyrics", nil))

	assertErrorResponse(t, response, http.StatusNotFound, "track not found")
}

func TestGetLyricsMissingLyrics(t *testing.T) {
	track := testTrack(t, "track-1", "song.mp3")
	handler := NewHandler(&fakeTrackRepository{tracks: []library.Track{track}}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-1/lyrics", nil))

	assertErrorResponse(t, response, http.StatusNotFound, "lyrics not found")
}

func TestGetLyricsUTF8(t *testing.T) {
	track := testTrack(t, "track-utf8", "utf8-song.mp3")
	writeFile(t, trimExtension(track.Path)+".lrc", []byte("[00:01.00]\u4f60\u597d\nHello"))
	handler := NewHandler(&fakeTrackRepository{tracks: []library.Track{track}}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-utf8/lyrics", nil))

	assertLyricsResponse(t, response, http.StatusOK, "track-utf8", "UTF-8", "[00:01.00]\u4f60\u597d\nHello")
}

func TestGetLyricsGBK(t *testing.T) {
	track := testTrack(t, "track-gbk", "gbk-song.mp3")
	writeFile(t, trimExtension(track.Path)+".lrc", []byte{0xC4, 0xE3, 0xBA, 0xC3, '\n', 'H', 'i'})
	handler := NewHandler(&fakeTrackRepository{tracks: []library.Track{track}}, library.NewLyricsService()).Routes()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/tracks/track-gbk/lyrics", nil))

	assertLyricsResponse(t, response, http.StatusOK, "track-gbk", "", "\u4f60\u597d\nHi")
}

func assertErrorResponse(t *testing.T, response *httptest.ResponseRecorder, wantStatus int, wantError string) {
	t.Helper()
	if response.Code != wantStatus {
		t.Fatalf("status = %d, want %d", response.Code, wantStatus)
	}

	var body errorResponse
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Error != wantError {
		t.Fatalf("error = %q, want %q", body.Error, wantError)
	}
}

func assertLyricsResponse(t *testing.T, response *httptest.ResponseRecorder, wantStatus int, wantTrackID, wantEncoding, wantContent string) {
	t.Helper()
	if response.Code != wantStatus {
		t.Fatalf("status = %d, want %d", response.Code, wantStatus)
	}

	var body library.Lyrics
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.TrackID != wantTrackID {
		t.Fatalf("track id = %q, want %q", body.TrackID, wantTrackID)
	}
	if wantEncoding != "" && body.Encoding != wantEncoding {
		t.Fatalf("encoding = %q, want %q", body.Encoding, wantEncoding)
	}
	if wantEncoding == "" && body.Encoding != "GB18030" && body.Encoding != "GBK" {
		t.Fatalf("encoding = %q, want GB18030 or GBK", body.Encoding)
	}
	if body.Content != wantContent {
		t.Fatalf("content = %q, want %q", body.Content, wantContent)
	}
}

func testTrack(t *testing.T, id, fileName string) library.Track {
	t.Helper()
	path := filepath.Join(t.TempDir(), fileName)
	return library.Track{
		ID:        id,
		Title:     trimExtension(fileName),
		FileName:  fileName,
		Path:      path,
		Extension: filepath.Ext(fileName)[1:],
		Modified:  time.Date(2026, 7, 18, 10, 0, 0, 0, time.UTC),
	}
}

func trimExtension(path string) string {
	return strings.TrimSuffix(path, filepath.Ext(path))
}

func writeFile(t *testing.T, path string, data []byte) {
	t.Helper()
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}
