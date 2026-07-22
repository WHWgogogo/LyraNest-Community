package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"music-player-server/internal/auth"
	"music-player-server/internal/library"
	"music-player-server/internal/store"
	"music-player-server/internal/userdata"
	"music-player-server/internal/webui"
)

type Handler struct {
	auth              *auth.Service
	repository        store.TrackRepository
	userData          userdata.Repository
	lyrics            *library.LyricsService
	lyricsReader      LyricsReader
	libraryManagement LibraryManagement
}

type HandlerOption func(*Handler)

type LyricsReader interface {
	ReadLyrics(ctx context.Context, track library.Track) (library.Lyrics, error)
}

func NewHandler(repository store.TrackRepository, lyrics *library.LyricsService, options ...HandlerOption) *Handler {
	handler := &Handler{
		repository: repository,
		lyrics:     lyrics,
	}
	for _, option := range options {
		if option != nil {
			option(handler)
		}
	}
	return handler
}

func WithLibraryManagement(service LibraryManagement) HandlerOption {
	return func(h *Handler) {
		h.libraryManagement = service
	}
}

func WithLibraryManagementService(service LibraryManagement) HandlerOption {
	return WithLibraryManagement(service)
}

func WithLyricsReader(reader LyricsReader) HandlerOption {
	return func(h *Handler) {
		h.lyricsReader = reader
	}
}

func WithUserDataRepository(repository userdata.Repository) HandlerOption {
	return func(h *Handler) {
		h.userData = repository
	}
}

func (h *Handler) Routes() http.Handler {
	mux := http.NewServeMux()
	if h.auth != nil {
		mux.HandleFunc("GET /api/v1/auth/setup", h.authSetup)
		mux.HandleFunc("POST /api/v1/auth/register", h.register)
		mux.HandleFunc("POST /api/v1/auth/login", h.login)
		mux.HandleFunc("GET /api/v1/auth/me", h.currentUser)
		mux.HandleFunc("POST /api/v1/auth/logout", h.logout)
	}
	mux.HandleFunc("GET /api/v1", h.index)
	mux.HandleFunc("GET /api/v1/{$}", h.index)
	mux.HandleFunc("GET /healthz", h.healthz)
	mux.HandleFunc("POST /api/v1/library/scan", h.scanLibrary)
	mux.HandleFunc("GET /api/v1/library/status", h.libraryStatus)
	mux.HandleFunc("GET /api/v1/tracks", h.listTracks)
	mux.HandleFunc("GET /api/v1/albums", h.listAlbums)
	mux.HandleFunc("GET /api/v1/albums/{albumId}/tracks", h.listAlbumTracks)
	mux.HandleFunc("GET /api/v1/artists", h.listArtists)
	mux.HandleFunc("GET /api/v1/artists/{artistId}/tracks", h.listArtistTracks)
	mux.HandleFunc("GET /api/v1/search", h.searchLibrary)
	mux.HandleFunc("GET /api/v1/tracks/{id}/lyrics", h.getLyrics)
	mux.HandleFunc("GET /api/v1/tracks/{id}/artwork", h.getTrackArtwork)
	mux.HandleFunc("HEAD /api/v1/tracks/{id}/artwork", h.getTrackArtwork)
	mux.HandleFunc("GET /api/v1/tracks/{id}/stream", h.streamTrack)
	mux.HandleFunc("HEAD /api/v1/tracks/{id}/stream", h.streamTrack)
	mux.HandleFunc("GET /api/v1/me/collections", h.getCollections)
	mux.HandleFunc("GET /api/v1/me/favorites/tracks", h.getFavoriteTracks)
	mux.HandleFunc("GET /api/v1/me/playback-mode", h.getPlaybackMode)
	mux.HandleFunc("PUT /api/v1/me/playback-mode", h.setPlaybackMode)
	mux.HandleFunc("PUT /api/v1/me/favorites/{trackId}", h.addFavorite)
	mux.HandleFunc("DELETE /api/v1/me/favorites/{trackId}", h.removeFavorite)
	mux.HandleFunc("POST /api/v1/me/playlists", h.createPlaylist)
	mux.HandleFunc("PATCH /api/v1/me/playlists/{playlistId}", h.updatePlaylist)
	mux.HandleFunc("DELETE /api/v1/me/playlists/{playlistId}", h.deletePlaylist)
	mux.HandleFunc("PUT /api/v1/me/playlists/{playlistId}/tracks/{trackId}", h.addPlaylistTrack)
	mux.HandleFunc("DELETE /api/v1/me/playlists/{playlistId}/tracks/{trackId}", h.removePlaylistTrack)
	mux.HandleFunc("POST /api/v1/me/collections/import", h.importCollections)
	mux.Handle("/", webui.NewHandler())
	return requestLogger(corsMiddleware(h.authMiddleware(mux)))
}

func (h *Handler) index(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"name":   "LyraNest Community Server",
		"status": "ok",
		"health": "/healthz",
		"tracks": "/api/v1/tracks",
	})
}

func (h *Handler) healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) listTracks(w http.ResponseWriter, r *http.Request) {
	tracks, err := h.repository.ListTracks(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list tracks")
		return
	}

	writeJSON(w, http.StatusOK, tracksResponse{
		Tracks: tracks,
		Total:  len(tracks),
	})
}

func (h *Handler) getLyrics(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.PathValue("id"))
	if id == "" {
		writeError(w, http.StatusBadRequest, "track id is required")
		return
	}

	track, err := h.repository.GetTrack(r.Context(), id)
	if errors.Is(err, store.ErrTrackNotFound) {
		writeError(w, http.StatusNotFound, "track not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to read track")
		return
	}

	var lyrics library.Lyrics
	if h.lyricsReader != nil {
		lyrics, err = h.lyricsReader.ReadLyrics(r.Context(), track)
	} else {
		lyricsService := h.lyrics
		if lyricsService == nil {
			lyricsService = library.NewLyricsService()
		}
		lyrics, err = lyricsService.ReadForTrack(track)
	}
	if errors.Is(err, library.ErrLyricsNotFound) {
		writeError(w, http.StatusNotFound, "lyrics not found")
		return
	}
	if errors.Is(err, library.ErrUnsupportedLyricsEncoding) {
		writeError(w, http.StatusUnsupportedMediaType, "lyrics encoding must be UTF-8, GB18030, or GBK")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to read lyrics")
		return
	}

	writeJSON(w, http.StatusOK, lyrics)
}

type tracksResponse struct {
	Tracks []library.Track `json:"tracks"`
	Total  int             `json:"total"`
}

type errorResponse struct {
	Error string `json:"error"`
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		slog.Error("failed to write json response", "error", err)
	}
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, errorResponse{Error: message})
}

func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(recorder, r)
		slog.InfoContext(r.Context(), "request completed",
			"method", r.Method,
			"path", r.URL.Path,
			"status", recorder.status,
			"remote_addr", r.RemoteAddr,
		)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := w.Header()
		header.Set("Access-Control-Allow-Origin", "*")
		header.Set("Access-Control-Allow-Methods", "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS")
		header.Set("Access-Control-Allow-Headers", "Authorization, Range, Content-Type")
		header.Set("Access-Control-Expose-Headers", "Accept-Ranges, Content-Length, Content-Range, Content-Type, Last-Modified, Content-Disposition")
		header.Set("Vary", "Origin")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}
