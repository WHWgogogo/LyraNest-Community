package httpapi

import (
	"errors"
	"net/http"
	"strings"

	"music-player-server/internal/auth"
	"music-player-server/internal/userdata"
)

type playlistRequest struct {
	Name string `json:"name"`
}

type playlistCreateRequest struct {
	ID   *string `json:"id"`
	Name string  `json:"name"`
}

type listeningEventsRequest struct {
	Events []userdata.ListeningEvent `json:"events"`
}

type collectionsImportRequest struct {
	Revision         int64               `json:"revision"`
	FavoriteTrackIDs []string            `json:"favorite_track_ids"`
	Playlists        []userdata.Playlist `json:"playlists"`
}

type playbackModeRequest struct {
	Mode userdata.PlaybackMode `json:"mode"`
}

func (h *Handler) getCollections(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	snapshot, err := h.userDataRepository(w)
	if err != nil {
		return
	}
	value, err := snapshot.Collections(r.Context(), userID)
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	writeNoStoreJSON(w, http.StatusOK, value)
}

func (h *Handler) addFavorite(w http.ResponseWriter, r *http.Request) {
	h.changeFavorite(w, r, true)
}

func (h *Handler) removeFavorite(w http.ResponseWriter, r *http.Request) {
	h.changeFavorite(w, r, false)
}

func (h *Handler) changeFavorite(w http.ResponseWriter, r *http.Request, add bool) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	repository, err := h.userDataRepository(w)
	if err != nil {
		return
	}
	trackID := strings.TrimSpace(r.PathValue("trackId"))
	var value userdata.CollectionsSnapshot
	if add {
		value, err = repository.AddFavorite(r.Context(), userID, trackID)
	} else {
		value, err = repository.RemoveFavorite(r.Context(), userID, trackID)
	}
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	writeNoStoreJSON(w, http.StatusOK, value)
}

func (h *Handler) createPlaylist(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	repository, err := h.userDataRepository(w)
	if err != nil {
		return
	}
	var request playlistCreateRequest
	if err := decodeJSONBody(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	status := http.StatusCreated
	var value userdata.CollectionsSnapshot
	if request.ID == nil {
		value, err = repository.CreatePlaylist(r.Context(), userID, request.Name)
	} else {
		playlistID := strings.TrimSpace(*request.ID)
		if playlistID == "" {
			writeError(w, http.StatusBadRequest, "playlist id must not be empty")
			return
		}
		creator, ok := repository.(userdata.PlaylistIDCreator)
		if !ok {
			writeError(w, http.StatusServiceUnavailable, "playlist idempotency is not configured")
			return
		}
		var created bool
		value, created, err = creator.CreatePlaylistWithID(r.Context(), userID, playlistID, request.Name)
		if !created {
			status = http.StatusOK
		}
	}
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	writeNoStoreJSON(w, status, value)
}

func (h *Handler) updatePlaylist(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	repository, err := h.userDataRepository(w)
	if err != nil {
		return
	}
	var request playlistRequest
	if err := decodeJSONBody(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	value, err := repository.UpdatePlaylist(r.Context(), userID, r.PathValue("playlistId"), request.Name)
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	writeNoStoreJSON(w, http.StatusOK, value)
}

func (h *Handler) deletePlaylist(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	repository, err := h.userDataRepository(w)
	if err != nil {
		return
	}
	value, err := repository.DeletePlaylist(r.Context(), userID, r.PathValue("playlistId"))
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	writeNoStoreJSON(w, http.StatusOK, value)
}

func (h *Handler) addPlaylistTrack(w http.ResponseWriter, r *http.Request) {
	h.changePlaylistTrack(w, r, true)
}

func (h *Handler) removePlaylistTrack(w http.ResponseWriter, r *http.Request) {
	h.changePlaylistTrack(w, r, false)
}

func (h *Handler) changePlaylistTrack(w http.ResponseWriter, r *http.Request, add bool) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	repository, err := h.userDataRepository(w)
	if err != nil {
		return
	}
	playlistID := r.PathValue("playlistId")
	trackID := r.PathValue("trackId")
	var value userdata.CollectionsSnapshot
	if add {
		value, err = repository.AddPlaylistTrack(r.Context(), userID, playlistID, trackID)
	} else {
		value, err = repository.RemovePlaylistTrack(r.Context(), userID, playlistID, trackID)
	}
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	writeNoStoreJSON(w, http.StatusOK, value)
}

func (h *Handler) importCollections(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	repository, err := h.userDataRepository(w)
	if err != nil {
		return
	}
	var request collectionsImportRequest
	if err := decodeJSONBody(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	value, err := repository.ImportCollections(r.Context(), userID, userdata.CollectionsImport{
		FavoriteTrackIDs: request.FavoriteTrackIDs,
		Playlists:        request.Playlists,
	})
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	writeNoStoreJSON(w, http.StatusOK, value)
}

func (h *Handler) getPlaybackMode(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	repository, err := h.playbackModeRepository(w)
	if err != nil {
		return
	}
	value, err := repository.PlaybackMode(r.Context(), userID)
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	writeNoStoreJSON(w, http.StatusOK, value)
}

func (h *Handler) setPlaybackMode(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	repository, err := h.playbackModeRepository(w)
	if err != nil {
		return
	}
	var request playbackModeRequest
	if err := decodeJSONBody(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	value, err := repository.SetPlaybackMode(r.Context(), userID, request.Mode)
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	writeNoStoreJSON(w, http.StatusOK, value)
}

func (h *Handler) recordListeningEvents(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	repository, err := h.userDataRepository(w)
	if err != nil {
		return
	}
	var request listeningEventsRequest
	if err := decodeJSONBody(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	value, err := repository.RecordEvents(r.Context(), userID, request.Events)
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	writeNoStoreJSON(w, http.StatusOK, value)
}

func (h *Handler) authenticatedUserID(w http.ResponseWriter, r *http.Request) (string, bool) {
	user, ok := r.Context().Value(authenticatedUserContextKey{}).(auth.User)
	if !ok || strings.TrimSpace(user.ID) == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return "", false
	}
	return user.ID, true
}

func (h *Handler) userDataRepository(w http.ResponseWriter) (userdata.Repository, error) {
	if h.userData == nil {
		writeError(w, http.StatusServiceUnavailable, "user data service is not configured")
		return nil, errors.New("user data service is not configured")
	}
	return h.userData, nil
}

func (h *Handler) playbackModeRepository(w http.ResponseWriter) (userdata.PlaybackModeRepository, error) {
	repository, err := h.userDataRepository(w)
	if err != nil {
		return nil, err
	}
	playbackRepository, ok := repository.(userdata.PlaybackModeRepository)
	if !ok {
		writeError(w, http.StatusServiceUnavailable, "playback mode service is not configured")
		return nil, errors.New("playback mode service is not configured")
	}
	return playbackRepository, nil
}

func (h *Handler) writeUserDataError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, userdata.ErrPlaylistConflict):
		writeError(w, http.StatusConflict, "playlist id conflicts with existing playlist name")
	case errors.Is(err, userdata.ErrPlaylistNotFound):
		writeError(w, http.StatusNotFound, "playlist not found")
	case errors.Is(err, userdata.ErrDataLimit):
		writeError(w, http.StatusRequestEntityTooLarge, "user data limit exceeded")
	case errors.Is(err, userdata.ErrInvalidUserID),
		errors.Is(err, userdata.ErrInvalidTrackID),
		errors.Is(err, userdata.ErrInvalidPlaylist),
		errors.Is(err, userdata.ErrInvalidEvent),
		errors.Is(err, userdata.ErrInvalidPlaybackMode):
		writeError(w, http.StatusBadRequest, "invalid request")
	default:
		writeError(w, http.StatusInternalServerError, "failed to persist user data")
	}
}

func writeNoStoreJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, status, value)
}
