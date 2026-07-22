package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"music-player-server/internal/auth"
	"music-player-server/internal/library"
	"music-player-server/internal/store"
)

func TestAuthAPIAndMiddlewareLifecycle(t *testing.T) {
	service, err := auth.NewService(t.TempDir(), time.Hour, auth.WithPasswordIterations(10))
	if err != nil {
		t.Fatalf("NewService returned error: %v", err)
	}
	handler := NewHandler(store.NewMemoryRepository(), library.NewLyricsService(), WithAuthService(service)).Routes()

	setup := performAuthRequest(t, handler, http.MethodGet, "/api/v1/auth/setup", "", "")
	if setup.Code != http.StatusOK || !strings.Contains(setup.Body.String(), `"register_allowed":true`) {
		t.Fatalf("initial setup response = %d %s", setup.Code, setup.Body.String())
	}

	unauthorized := performAuthRequest(t, handler, http.MethodGet, "/api/v1/tracks", "", "")
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized tracks status = %d, want 401", unauthorized.Code)
	}
	if unauthorized.Header().Get("WWW-Authenticate") == "" {
		t.Fatal("unauthorized response missing WWW-Authenticate")
	}

	publicStream := performAuthRequest(t, handler, http.MethodGet, "/api/v1/tracks/missing/stream", "", "")
	if publicStream.Code == http.StatusUnauthorized {
		t.Fatal("media stream endpoint unexpectedly requires authentication")
	}

	credentials := `{"username":"admin","password":"correct horse battery staple"}`
	registered := performAuthRequest(t, handler, http.MethodPost, "/api/v1/auth/register", credentials, "")
	if registered.Code != http.StatusCreated {
		t.Fatalf("register response = %d %s", registered.Code, registered.Body.String())
	}
	second := performAuthRequest(t, handler, http.MethodPost, "/api/v1/auth/register", credentials, "")
	if second.Code != http.StatusForbidden {
		t.Fatalf("second register status = %d, want 403", second.Code)
	}

	login := performAuthRequest(t, handler, http.MethodPost, "/api/v1/auth/login", credentials, "")
	if login.Code != http.StatusOK {
		t.Fatalf("login response = %d %s", login.Code, login.Body.String())
	}
	var session struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(login.Body.Bytes(), &session); err != nil {
		t.Fatalf("Unmarshal login response returned error: %v", err)
	}
	if session.Token == "" {
		t.Fatal("login response missing token")
	}

	me := performAuthRequest(t, handler, http.MethodGet, "/api/v1/auth/me", "", session.Token)
	if me.Code != http.StatusOK || !strings.Contains(me.Body.String(), `"username":"admin"`) {
		t.Fatalf("me response = %d %s", me.Code, me.Body.String())
	}
	tracks := performAuthRequest(t, handler, http.MethodGet, "/api/v1/tracks", "", session.Token)
	if tracks.Code != http.StatusOK {
		t.Fatalf("authenticated tracks response = %d %s", tracks.Code, tracks.Body.String())
	}

	logout := performAuthRequest(t, handler, http.MethodPost, "/api/v1/auth/logout", "", session.Token)
	if logout.Code != http.StatusNoContent {
		t.Fatalf("logout response = %d %s", logout.Code, logout.Body.String())
	}
	revoked := performAuthRequest(t, handler, http.MethodGet, "/api/v1/auth/me", "", session.Token)
	if revoked.Code != http.StatusUnauthorized {
		t.Fatalf("revoked token status = %d, want 401", revoked.Code)
	}
}

func TestAuthCORSAllowsAuthorizationHeader(t *testing.T) {
	service, err := auth.NewService(t.TempDir(), time.Hour, auth.WithPasswordIterations(10))
	if err != nil {
		t.Fatalf("NewService returned error: %v", err)
	}
	handler := NewHandler(store.NewMemoryRepository(), library.NewLyricsService(), WithAuthService(service)).Routes()
	response := performAuthRequest(t, handler, http.MethodOptions, "/api/v1/tracks", "", "")
	if response.Code != http.StatusNoContent {
		t.Fatalf("OPTIONS status = %d, want 204", response.Code)
	}
	if !strings.Contains(response.Header().Get("Access-Control-Allow-Headers"), "Authorization") {
		t.Fatalf("allowed headers = %q, want Authorization", response.Header().Get("Access-Control-Allow-Headers"))
	}
}

func performAuthRequest(t *testing.T, handler http.Handler, method, path, body, token string) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}
