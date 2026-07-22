package webui

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"
)

func TestNewHandlerServesEmbeddedIndex(t *testing.T) {
	response := serveRequest(NewHandler(), http.MethodGet, "/", "")

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	if contentType := response.Header().Get("Content-Type"); contentType != "text/html; charset=utf-8" {
		t.Fatalf("content type = %q, want text/html; charset=utf-8", contentType)
	}
	if cacheControl := response.Header().Get("Cache-Control"); cacheControl != noCacheControl {
		t.Fatalf("cache control = %q, want %q", cacheControl, noCacheControl)
	}
	if !strings.Contains(strings.ToLower(response.Body.String()), "<!doctype html>") {
		t.Fatalf("body = %q, want embedded HTML document", response.Body.String())
	}
}

func TestHandlerServesStaticAssetsWithMIMEAndCacheHeaders(t *testing.T) {
	handler := newTestHandler(t)

	tests := []struct {
		name             string
		path             string
		wantContentType  string
		wantCacheControl string
		wantBody         string
	}{
		{
			name:             "hashed javascript",
			path:             "/assets/app-deadbeef.js",
			wantContentType:  "text/javascript; charset=utf-8",
			wantCacheControl: immutableCacheControl,
			wantBody:         "console.log('app');",
		},
		{
			name:             "unhashed stylesheet",
			path:             "/styles.css",
			wantContentType:  "text/css; charset=utf-8",
			wantCacheControl: shortCacheControl,
			wantBody:         "body { color: black; }",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			response := serveRequest(handler, http.MethodGet, test.path, "")

			if response.Code != http.StatusOK {
				t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
			}
			if contentType := response.Header().Get("Content-Type"); contentType != test.wantContentType {
				t.Fatalf("content type = %q, want %q", contentType, test.wantContentType)
			}
			if cacheControl := response.Header().Get("Cache-Control"); cacheControl != test.wantCacheControl {
				t.Fatalf("cache control = %q, want %q", cacheControl, test.wantCacheControl)
			}
			if body := response.Body.String(); body != test.wantBody {
				t.Fatalf("body = %q, want %q", body, test.wantBody)
			}
		})
	}
}

func TestHandlerUsesIndexForSPAHistoryRoutes(t *testing.T) {
	response := serveRequest(newTestHandler(t), http.MethodGet, "/library/albums/favorites", "text/html")

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}
	if body := response.Body.String(); !strings.Contains(body, "app shell") {
		t.Fatalf("body = %q, want SPA index", body)
	}
	if cacheControl := response.Header().Get("Cache-Control"); cacheControl != noCacheControl {
		t.Fatalf("cache control = %q, want %q", cacheControl, noCacheControl)
	}
}

func TestHandlerDoesNotFallbackForBackendOrMissingAssetPaths(t *testing.T) {
	handler := newTestHandler(t)

	for _, requestPath := range []string{"/api/v1/tracks", "/healthz", "/assets/missing.js", "/favicon.ico"} {
		t.Run(requestPath, func(t *testing.T) {
			response := serveRequest(handler, http.MethodGet, requestPath, "*/*")

			if response.Code != http.StatusNotFound {
				t.Fatalf("status = %d, want %d", response.Code, http.StatusNotFound)
			}
			if strings.Contains(response.Body.String(), "app shell") {
				t.Fatalf("body = %q, must not contain SPA index", response.Body.String())
			}
		})
	}
}

func TestHandlerRejectsUnsupportedMethods(t *testing.T) {
	response := serveRequest(newTestHandler(t), http.MethodPost, "/library", "")

	if response.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusMethodNotAllowed)
	}
	if allow := response.Header().Get("Allow"); allow != "GET, HEAD" {
		t.Fatalf("allow = %q, want GET, HEAD", allow)
	}
}

func newTestHandler(t *testing.T) http.Handler {
	t.Helper()

	assets := fstest.MapFS{
		"index.html": {
			Data: []byte("<!doctype html><html><body>app shell</body></html>"),
		},
		"assets/app-deadbeef.js": {
			Data: []byte("console.log('app');"),
		},
		"styles.css": {
			Data: []byte("body { color: black; }"),
		},
	}

	return newHandler(assets)
}

func serveRequest(handler http.Handler, method, target, accept string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(method, target, nil)
	if accept != "" {
		request.Header.Set("Accept", accept)
	}
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}
