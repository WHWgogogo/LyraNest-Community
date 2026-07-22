package webui

import (
	"bytes"
	"embed"
	"fmt"
	"io/fs"
	"mime"
	"net/http"
	"path"
	"regexp"
	"strings"
	"time"
)

const (
	noCacheControl        = "no-cache"
	shortCacheControl     = "public, max-age=3600"
	immutableCacheControl = "public, max-age=31536000, immutable"
)

var hashedAssetPattern = regexp.MustCompile(`-[A-Za-z0-9_-]{8,}\.[^./]+$`)

//go:embed dist
var embeddedFiles embed.FS

type handler struct {
	assets     fs.FS
	fileServer http.Handler
	index      []byte
}

func NewHandler() http.Handler {
	assets, err := fs.Sub(embeddedFiles, "dist")
	if err != nil {
		panic(fmt.Sprintf("open embedded web assets: %v", err))
	}

	return newHandler(assets)
}

func newHandler(assets fs.FS) http.Handler {
	index, err := fs.ReadFile(assets, "index.html")
	if err != nil {
		panic(fmt.Sprintf("read embedded web index: %v", err))
	}

	return &handler{
		assets:     assets,
		fileServer: http.FileServer(http.FS(assets)),
		index:      index,
	}
}

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	requestPath := path.Clean("/" + r.URL.Path)
	if isBackendPath(requestPath) {
		http.NotFound(w, r)
		return
	}

	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, http.StatusText(http.StatusMethodNotAllowed), http.StatusMethodNotAllowed)
		return
	}

	if requestPath == "/" || requestPath == "/index.html" {
		h.serveIndex(w, r)
		return
	}

	assetName := strings.TrimPrefix(requestPath, "/")
	if fs.ValidPath(assetName) {
		info, err := fs.Stat(h.assets, assetName)
		if err == nil && info.Mode().IsRegular() {
			setAssetHeaders(w.Header(), assetName)
			request := r.Clone(r.Context())
			urlCopy := *r.URL
			urlCopy.Path = "/" + assetName
			urlCopy.RawPath = ""
			request.URL = &urlCopy
			h.fileServer.ServeHTTP(w, request)
			return
		}
	}

	if isAssetRequest(requestPath) {
		http.NotFound(w, r)
		return
	}

	h.serveIndex(w, r)
}

func (h *handler) serveIndex(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", noCacheControl)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	http.ServeContent(w, r, "index.html", time.Time{}, bytes.NewReader(h.index))
}

func isBackendPath(requestPath string) bool {
	return requestPath == "/api" ||
		strings.HasPrefix(requestPath, "/api/") ||
		requestPath == "/healthz" ||
		strings.HasPrefix(requestPath, "/healthz/")
}

func isAssetRequest(requestPath string) bool {
	if requestPath == "/assets" || strings.HasPrefix(requestPath, "/assets/") {
		return true
	}

	return path.Ext(requestPath) != ""
}

func setAssetHeaders(header http.Header, assetName string) {
	if contentType := assetContentType(assetName); contentType != "" {
		header.Set("Content-Type", contentType)
	}

	if hashedAssetPattern.MatchString(path.Base(assetName)) {
		header.Set("Cache-Control", immutableCacheControl)
		return
	}

	header.Set("Cache-Control", shortCacheControl)
}

func assetContentType(assetName string) string {
	switch strings.ToLower(path.Ext(assetName)) {
	case ".css":
		return "text/css; charset=utf-8"
	case ".html":
		return "text/html; charset=utf-8"
	case ".js", ".mjs":
		return "text/javascript; charset=utf-8"
	case ".json", ".map":
		return "application/json; charset=utf-8"
	case ".svg":
		return "image/svg+xml"
	case ".wasm":
		return "application/wasm"
	default:
		return mime.TypeByExtension(path.Ext(assetName))
	}
}
