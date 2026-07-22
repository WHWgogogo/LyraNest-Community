package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"music-player-server/internal/auth"
	"music-player-server/internal/library"
	"music-player-server/internal/store"
	"music-player-server/internal/userdata"
)

func TestCollectionsAPILifecycle(t *testing.T) {
	handler, token := newPersonalTestHandler(t, testPersonalTracks())

	unauthorized := performAuthRequest(t, handler, http.MethodGet, "/api/v1/me/collections", "", "")
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized collections status = %d, want %d", unauthorized.Code, http.StatusUnauthorized)
	}

	addedFavorite := performAuthRequest(t, handler, http.MethodPut, "/api/v1/me/favorites/track-1", "", token)
	favoriteSnapshot := decodeCollectionsSnapshot(t, addedFavorite, http.StatusOK)
	if favoriteSnapshot.Revision != 1 || !reflect.DeepEqual(favoriteSnapshot.FavoriteTrackIDs, []string{"track-1"}) {
		t.Fatalf("favorite snapshot = %#v", favoriteSnapshot)
	}
	if addedFavorite.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("cache-control = %q, want no-store", addedFavorite.Header().Get("Cache-Control"))
	}
	favoriteTracks := performAuthRequest(t, handler, http.MethodGet, "/api/v1/me/favorites/tracks", "", token)
	var favoriteTrackList tracksResponse
	if favoriteTracks.Code != http.StatusOK {
		t.Fatalf("favorite tracks status = %d, want %d: %s", favoriteTracks.Code, http.StatusOK, favoriteTracks.Body.String())
	}
	if err := json.NewDecoder(favoriteTracks.Body).Decode(&favoriteTrackList); err != nil {
		t.Fatalf("decode favorite tracks: %v", err)
	}
	if favoriteTrackList.Total != 1 || favoriteTrackList.Tracks[0].ID != "track-1" {
		t.Fatalf("favorite tracks = %#v, want track-1", favoriteTrackList)
	}

	created := performAuthRequest(t, handler, http.MethodPost, "/api/v1/me/playlists", `{"name":"Morning Mix"}`, token)
	playlistSnapshot := decodeCollectionsSnapshot(t, created, http.StatusCreated)
	if len(playlistSnapshot.Playlists) != 1 {
		t.Fatalf("playlist count = %d, want 1", len(playlistSnapshot.Playlists))
	}
	playlistID := playlistSnapshot.Playlists[0].ID

	renamed := performAuthRequest(t, handler, http.MethodPatch, "/api/v1/me/playlists/"+playlistID, `{"name":"Morning Focus"}`, token)
	renamedSnapshot := decodeCollectionsSnapshot(t, renamed, http.StatusOK)
	if renamedSnapshot.Playlists[0].Name != "Morning Focus" {
		t.Fatalf("renamed playlist = %#v", renamedSnapshot.Playlists[0])
	}

	addedTrack := performAuthRequest(t, handler, http.MethodPut, "/api/v1/me/playlists/"+playlistID+"/tracks/track-2", "", token)
	addedTrackSnapshot := decodeCollectionsSnapshot(t, addedTrack, http.StatusOK)
	if !reflect.DeepEqual(addedTrackSnapshot.Playlists[0].TrackIDs, []string{"track-2"}) {
		t.Fatalf("playlist tracks = %#v", addedTrackSnapshot.Playlists[0].TrackIDs)
	}
	removedTrack := performAuthRequest(t, handler, http.MethodDelete, "/api/v1/me/playlists/"+playlistID+"/tracks/track-2", "", token)
	removedTrackSnapshot := decodeCollectionsSnapshot(t, removedTrack, http.StatusOK)
	if len(removedTrackSnapshot.Playlists[0].TrackIDs) != 0 {
		t.Fatalf("playlist tracks after delete = %#v", removedTrackSnapshot.Playlists[0].TrackIDs)
	}

	imported := performAuthRequest(t, handler, http.MethodPost, "/api/v1/me/collections/import", `{
		"revision": 99,
		"favorite_track_ids": ["track-1", "track-3"],
		"playlists": [
			{"id":"`+playlistID+`","name":"stale name","track_ids":["track-1"]},
			{"name":"Imported","track_ids":["track-2","track-3"]}
		]
	}`, token)
	importedSnapshot := decodeCollectionsSnapshot(t, imported, http.StatusOK)
	if !reflect.DeepEqual(importedSnapshot.FavoriteTrackIDs, []string{"track-1", "track-3"}) {
		t.Fatalf("imported favorites = %#v", importedSnapshot.FavoriteTrackIDs)
	}
	if len(importedSnapshot.Playlists) != 2 || importedSnapshot.Playlists[0].Name != "Morning Focus" ||
		!reflect.DeepEqual(importedSnapshot.Playlists[0].TrackIDs, []string{"track-1"}) {
		t.Fatalf("imported playlists = %#v", importedSnapshot.Playlists)
	}

	deleted := performAuthRequest(t, handler, http.MethodDelete, "/api/v1/me/playlists/"+playlistID, "", token)
	deletedSnapshot := decodeCollectionsSnapshot(t, deleted, http.StatusOK)
	if len(deletedSnapshot.Playlists) != 1 || deletedSnapshot.Playlists[0].Name != "Imported" {
		t.Fatalf("deleted snapshot = %#v", deletedSnapshot)
	}

	current := performAuthRequest(t, handler, http.MethodGet, "/api/v1/me/collections", "", token)
	currentSnapshot := decodeCollectionsSnapshot(t, current, http.StatusOK)
	if !reflect.DeepEqual(currentSnapshot, deletedSnapshot) {
		t.Fatalf("current snapshot = %#v, want %#v", currentSnapshot, deletedSnapshot)
	}
}

func TestCreatePlaylistWithClientIDIsIdempotent(t *testing.T) {
	handler, token := newPersonalTestHandler(t, testPersonalTracks())
	requestBody := `{"id":"client-playlist-1","name":"Morning Mix"}`

	created := performAuthRequest(t, handler, http.MethodPost, "/api/v1/me/playlists", requestBody, token)
	createdSnapshot := decodeCollectionsSnapshot(t, created, http.StatusCreated)
	if len(createdSnapshot.Playlists) != 1 || createdSnapshot.Playlists[0].ID != "client-playlist-1" {
		t.Fatalf("created playlists = %#v", createdSnapshot.Playlists)
	}

	retried := performAuthRequest(t, handler, http.MethodPost, "/api/v1/me/playlists", `{"id":"client-playlist-1","name":"  Morning   Mix "}`, token)
	retriedSnapshot := decodeCollectionsSnapshot(t, retried, http.StatusOK)
	if !reflect.DeepEqual(retriedSnapshot, createdSnapshot) {
		t.Fatalf("retried snapshot = %#v, want %#v", retriedSnapshot, createdSnapshot)
	}

	conflict := performAuthRequest(t, handler, http.MethodPost, "/api/v1/me/playlists", `{"id":"client-playlist-1","name":"Evening Mix"}`, token)
	assertErrorResponse(t, conflict, http.StatusConflict, "playlist id conflicts with existing playlist name")

	invalid := performAuthRequest(t, handler, http.MethodPost, "/api/v1/me/playlists", `{"id":" ","name":"Invalid"}`, token)
	assertErrorResponse(t, invalid, http.StatusBadRequest, "playlist id must not be empty")
}

func TestPlaybackModeAPI(t *testing.T) {
	handler, token := newPersonalTestHandler(t, testPersonalTracks())

	unauthorized := performAuthRequest(t, handler, http.MethodGet, "/api/v1/me/playback-mode", "", "")
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized playback mode status = %d, want %d", unauthorized.Code, http.StatusUnauthorized)
	}

	current := performAuthRequest(t, handler, http.MethodGet, "/api/v1/me/playback-mode", "", token)
	currentMode := decodePlaybackModeSnapshot(t, current, http.StatusOK)
	if currentMode.Revision != 0 || currentMode.Mode != userdata.PlaybackModeSequential {
		t.Fatalf("current playback mode = %#v, want default sequential", currentMode)
	}

	updated := performAuthRequest(t, handler, http.MethodPut, "/api/v1/me/playback-mode", `{"mode":"shuffle"}`, token)
	updatedMode := decodePlaybackModeSnapshot(t, updated, http.StatusOK)
	if updatedMode.Revision != 1 || updatedMode.Mode != userdata.PlaybackModeShuffle {
		t.Fatalf("updated playback mode = %#v, want shuffle revision 1", updatedMode)
	}

	repeated := performAuthRequest(t, handler, http.MethodPut, "/api/v1/me/playback-mode", `{"mode":"shuffle"}`, token)
	repeatedMode := decodePlaybackModeSnapshot(t, repeated, http.StatusOK)
	if !reflect.DeepEqual(repeatedMode, updatedMode) {
		t.Fatalf("repeated playback mode = %#v, want %#v", repeatedMode, updatedMode)
	}

	invalid := performAuthRequest(t, handler, http.MethodPut, "/api/v1/me/playback-mode", `{"mode":"smart"}`, token)
	assertErrorResponse(t, invalid, http.StatusBadRequest, "invalid request")
}

func TestCommunityCommercialRoutesDisabledAndCORS(t *testing.T) {
	handler, token := newPersonalTestHandler(t, testPersonalTracks())

	for _, request := range []struct {
		method string
		path   string
		body   string
	}{
		{method: http.MethodPost, path: "/api/v1/listening/events", body: `{"events":[]}`},
		{method: http.MethodGet, path: "/api/v1/discovery"},
		{method: http.MethodGet, path: "/api/v1/listening/report?year=2026"},
	} {
		response := performAuthRequest(t, handler, request.method, request.path, request.body, token)
		if response.Code != http.StatusNotFound {
			t.Fatalf("%s %s status = %d, want %d", request.method, request.path, response.Code, http.StatusNotFound)
		}
	}

	preflight := performAuthRequest(t, handler, http.MethodOptions, "/api/v1/me/playlists/playlist/tracks/track", "", "")
	if preflight.Code != http.StatusNoContent {
		t.Fatalf("preflight status = %d, want %d", preflight.Code, http.StatusNoContent)
	}
	allowedMethods := preflight.Header().Get("Access-Control-Allow-Methods")
	for _, method := range []string{"PUT", "PATCH", "DELETE"} {
		if !strings.Contains(allowedMethods, method) {
			t.Fatalf("allowed methods = %q, missing %s", allowedMethods, method)
		}
	}
}

func newPersonalTestHandler(t *testing.T, tracks []library.Track) (http.Handler, string) {
	t.Helper()
	dataDir := t.TempDir()
	authService, err := auth.NewService(dataDir, time.Hour, auth.WithPasswordIterations(10))
	if err != nil {
		t.Fatalf("NewService returned error: %v", err)
	}
	userStore, err := userdata.NewStore(dataDir)
	if err != nil {
		t.Fatalf("NewStore returned error: %v", err)
	}
	repository := store.NewMemoryRepository()
	if err := repository.ReplaceTracks(context.Background(), tracks); err != nil {
		t.Fatalf("ReplaceTracks returned error: %v", err)
	}
	handler := NewHandler(
		repository,
		library.NewLyricsService(),
		WithAuthService(authService),
		WithUserDataRepository(userStore),
	).Routes()
	credentials := `{"username":"admin","password":"correct horse battery staple"}`
	registered := performAuthRequest(t, handler, http.MethodPost, "/api/v1/auth/register", credentials, "")
	if registered.Code != http.StatusCreated {
		t.Fatalf("register response = %d %s", registered.Code, registered.Body.String())
	}
	login := performAuthRequest(t, handler, http.MethodPost, "/api/v1/auth/login", credentials, "")
	if login.Code != http.StatusOK {
		t.Fatalf("login response = %d %s", login.Code, login.Body.String())
	}
	var session struct {
		Token string `json:"token"`
	}
	if err := json.NewDecoder(login.Body).Decode(&session); err != nil {
		t.Fatalf("decode login: %v", err)
	}
	if session.Token == "" {
		t.Fatal("login response did not include token")
	}
	return handler, session.Token
}

func decodeCollectionsSnapshot(t *testing.T, response *httptest.ResponseRecorder, wantStatus int) userdata.CollectionsSnapshot {
	t.Helper()
	if response.Code != wantStatus {
		t.Fatalf("status = %d, want %d: %s", response.Code, wantStatus, response.Body.String())
	}
	var snapshot userdata.CollectionsSnapshot
	if err := json.NewDecoder(response.Body).Decode(&snapshot); err != nil {
		t.Fatalf("decode collection snapshot: %v", err)
	}
	return snapshot
}

func decodePlaybackModeSnapshot(t *testing.T, response *httptest.ResponseRecorder, wantStatus int) userdata.PlaybackModeSnapshot {
	t.Helper()
	if response.Code != wantStatus {
		t.Fatalf("status = %d, want %d: %s", response.Code, wantStatus, response.Body.String())
	}
	var snapshot userdata.PlaybackModeSnapshot
	if err := json.NewDecoder(response.Body).Decode(&snapshot); err != nil {
		t.Fatalf("decode playback mode snapshot: %v", err)
	}
	return snapshot
}

func testPersonalTracks() []library.Track {
	modified := time.Date(2026, 7, 20, 8, 0, 0, 0, time.UTC)
	return []library.Track{
		{
			ID:         "track-1",
			Title:      "First",
			Artist:     "Artist One",
			Album:      "Album One",
			Genres:     []string{"Rock"},
			DurationMS: 3_000,
			FileName:   "first.mp3",
			Extension:  "mp3",
			Modified:   modified,
		},
		{
			ID:         "track-2",
			Title:      "Second",
			Artist:     "Artist Two",
			Album:      "Album Two",
			Genres:     []string{"Jazz"},
			DurationMS: 3_000,
			FileName:   "second.mp3",
			Extension:  "mp3",
			Modified:   modified,
		},
		{
			ID:         "track-3",
			Title:      "Third",
			Artist:     "Artist Three",
			Album:      "Album Three",
			Genres:     []string{"Rock"},
			DurationMS: 3_000,
			FileName:   "third.mp3",
			Extension:  "mp3",
			Modified:   modified,
		},
	}
}
