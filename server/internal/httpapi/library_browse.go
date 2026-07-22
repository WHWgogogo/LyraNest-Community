package httpapi

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"sort"
	"strconv"
	"strings"

	"music-player-server/internal/library"
)

const (
	defaultSearchLimit = 50
	maxSearchLimit     = 100
	unknownAlbumTitle  = "Unknown Album"
	unknownArtistName  = "Unknown Artist"
)

type albumsResponse struct {
	Albums []albumSummary `json:"albums"`
	Total  int            `json:"total"`
}

type albumSummary struct {
	ID             string `json:"id"`
	Title          string `json:"title"`
	Artist         string `json:"artist"`
	AlbumArtist    string `json:"album_artist,omitempty"`
	Year           int    `json:"year,omitempty"`
	TrackCount     int    `json:"track_count"`
	DurationMS     int64  `json:"duration_ms,omitempty"`
	ArtworkTrackID string `json:"artwork_track_id,omitempty"`
}

type artistsResponse struct {
	Artists []artistSummary `json:"artists"`
	Total   int             `json:"total"`
}

type artistSummary struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	TrackCount int    `json:"track_count"`
	AlbumCount int    `json:"album_count"`
	DurationMS int64  `json:"duration_ms,omitempty"`
}

type searchResponse struct {
	Query   string          `json:"query"`
	Tracks  []library.Track `json:"tracks"`
	Albums  []albumSummary  `json:"albums"`
	Artists []artistSummary `json:"artists"`
	Total   int             `json:"total"`
}

type albumAggregate struct {
	summary albumSummary
	tracks  []library.Track
}

type artistAggregate struct {
	summary  artistSummary
	tracks   []library.Track
	albumIDs map[string]struct{}
}

func (h *Handler) listAlbums(w http.ResponseWriter, r *http.Request) {
	tracks, err := h.repository.ListTracks(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list albums")
		return
	}

	albums := buildAlbumSummaries(tracks)
	writeJSON(w, http.StatusOK, albumsResponse{
		Albums: albums,
		Total:  len(albums),
	})
}

func (h *Handler) listAlbumTracks(w http.ResponseWriter, r *http.Request) {
	albumID := strings.TrimSpace(r.PathValue("albumId"))
	if albumID == "" {
		writeError(w, http.StatusBadRequest, "album id is required")
		return
	}

	tracks, err := h.repository.ListTracks(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list album tracks")
		return
	}

	result := make([]library.Track, 0)
	for _, track := range tracks {
		if albumIDForTrack(track) == albumID {
			result = append(result, track)
		}
	}
	if len(result) == 0 {
		writeError(w, http.StatusNotFound, "album not found")
		return
	}

	sortTracksForPlayback(result)
	writeJSON(w, http.StatusOK, tracksResponse{
		Tracks: result,
		Total:  len(result),
	})
}

func (h *Handler) listArtists(w http.ResponseWriter, r *http.Request) {
	tracks, err := h.repository.ListTracks(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list artists")
		return
	}

	artists := buildArtistSummaries(tracks)
	writeJSON(w, http.StatusOK, artistsResponse{
		Artists: artists,
		Total:   len(artists),
	})
}

func (h *Handler) listArtistTracks(w http.ResponseWriter, r *http.Request) {
	artistID := strings.TrimSpace(r.PathValue("artistId"))
	if artistID == "" {
		writeError(w, http.StatusBadRequest, "artist id is required")
		return
	}

	tracks, err := h.repository.ListTracks(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list artist tracks")
		return
	}

	result := make([]library.Track, 0)
	for _, track := range tracks {
		if artistIDForTrack(track) == artistID {
			result = append(result, track)
		}
	}
	if len(result) == 0 {
		writeError(w, http.StatusNotFound, "artist not found")
		return
	}

	sortTracksForPlayback(result)
	writeJSON(w, http.StatusOK, tracksResponse{
		Tracks: result,
		Total:  len(result),
	})
}

func (h *Handler) searchLibrary(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	if query == "" {
		writeError(w, http.StatusBadRequest, "search query is required")
		return
	}
	limit, ok := searchLimit(r.URL.Query().Get("limit"))
	if !ok {
		writeError(w, http.StatusBadRequest, "search limit must be between 1 and 100")
		return
	}

	tracks, err := h.repository.ListTracks(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to search library")
		return
	}

	normalizedQuery := normalizeSearchText(query)
	trackMatches := make([]library.Track, 0)
	for _, track := range tracks {
		if trackMatchesQuery(track, normalizedQuery) {
			trackMatches = append(trackMatches, track)
		}
	}
	sortTracksForPlayback(trackMatches)

	albumMatches := filterAlbums(buildAlbumSummaries(tracks), normalizedQuery)
	artistMatches := filterArtists(buildArtistSummaries(tracks), normalizedQuery)

	response := searchResponse{
		Query:   query,
		Tracks:  limitTracks(trackMatches, limit),
		Albums:  limitAlbums(albumMatches, limit),
		Artists: limitArtists(artistMatches, limit),
	}
	response.Total = len(response.Tracks) + len(response.Albums) + len(response.Artists)
	writeJSON(w, http.StatusOK, response)
}

func (h *Handler) getFavoriteTracks(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.authenticatedUserID(w, r)
	if !ok {
		return
	}
	userDataStore, err := h.userDataRepository(w)
	if err != nil {
		return
	}
	collections, err := userDataStore.Collections(r.Context(), userID)
	if err != nil {
		h.writeUserDataError(w, err)
		return
	}
	tracks, err := h.repository.ListTracks(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list favorite tracks")
		return
	}

	trackByID := make(map[string]library.Track, len(tracks))
	for _, track := range tracks {
		trackByID[track.ID] = track
	}
	favorites := make([]library.Track, 0, len(collections.FavoriteTrackIDs))
	for _, trackID := range collections.FavoriteTrackIDs {
		track, exists := trackByID[trackID]
		if exists {
			favorites = append(favorites, track)
		}
	}
	writeNoStoreJSON(w, http.StatusOK, tracksResponse{
		Tracks: favorites,
		Total:  len(favorites),
	})
}

func buildAlbumSummaries(tracks []library.Track) []albumSummary {
	albums := make(map[string]*albumAggregate)
	for _, track := range tracks {
		albumID := albumIDForTrack(track)
		aggregate := albums[albumID]
		if aggregate == nil {
			aggregate = &albumAggregate{
				summary: albumSummary{
					ID:             albumID,
					Title:          displayAlbumTitle(track),
					Artist:         displayAlbumArtist(track),
					AlbumArtist:    displayAlbumArtist(track),
					ArtworkTrackID: track.ID,
				},
			}
			albums[albumID] = aggregate
		}
		aggregate.summary.TrackCount++
		aggregate.summary.DurationMS += track.DurationMS
		if aggregate.summary.Year == 0 && track.Year != 0 {
			aggregate.summary.Year = track.Year
		}
		aggregate.tracks = append(aggregate.tracks, track)
	}

	result := make([]albumSummary, 0, len(albums))
	for _, aggregate := range albums {
		result = append(result, aggregate.summary)
	}
	sort.Slice(result, func(left, right int) bool {
		leftKey := strings.ToLower(result[left].Artist + "\x00" + result[left].Title)
		rightKey := strings.ToLower(result[right].Artist + "\x00" + result[right].Title)
		if leftKey != rightKey {
			return leftKey < rightKey
		}
		return result[left].ID < result[right].ID
	})
	return result
}

func buildArtistSummaries(tracks []library.Track) []artistSummary {
	artists := make(map[string]*artistAggregate)
	for _, track := range tracks {
		artistID := artistIDForTrack(track)
		aggregate := artists[artistID]
		if aggregate == nil {
			aggregate = &artistAggregate{
				summary: artistSummary{
					ID:   artistID,
					Name: displayArtistName(track),
				},
				albumIDs: make(map[string]struct{}),
			}
			artists[artistID] = aggregate
		}
		aggregate.summary.TrackCount++
		aggregate.summary.DurationMS += track.DurationMS
		aggregate.albumIDs[albumIDForTrack(track)] = struct{}{}
		aggregate.tracks = append(aggregate.tracks, track)
	}

	result := make([]artistSummary, 0, len(artists))
	for _, aggregate := range artists {
		aggregate.summary.AlbumCount = len(aggregate.albumIDs)
		result = append(result, aggregate.summary)
	}
	sort.Slice(result, func(left, right int) bool {
		leftName := strings.ToLower(result[left].Name)
		rightName := strings.ToLower(result[right].Name)
		if leftName != rightName {
			return leftName < rightName
		}
		return result[left].ID < result[right].ID
	})
	return result
}

func filterAlbums(albums []albumSummary, normalizedQuery string) []albumSummary {
	result := make([]albumSummary, 0)
	for _, album := range albums {
		if containsNormalized(album.Title, normalizedQuery) ||
			containsNormalized(album.Artist, normalizedQuery) ||
			containsNormalized(album.AlbumArtist, normalizedQuery) {
			result = append(result, album)
		}
	}
	return result
}

func filterArtists(artists []artistSummary, normalizedQuery string) []artistSummary {
	result := make([]artistSummary, 0)
	for _, artist := range artists {
		if containsNormalized(artist.Name, normalizedQuery) {
			result = append(result, artist)
		}
	}
	return result
}

func trackMatchesQuery(track library.Track, normalizedQuery string) bool {
	if containsNormalized(track.Title, normalizedQuery) ||
		containsNormalized(track.Artist, normalizedQuery) ||
		containsNormalized(track.Album, normalizedQuery) ||
		containsNormalized(track.AlbumArtist, normalizedQuery) ||
		containsNormalized(track.FileName, normalizedQuery) {
		return true
	}
	for _, genre := range track.Genres {
		if containsNormalized(genre, normalizedQuery) {
			return true
		}
	}
	return false
}

func searchLimit(value string) (int, bool) {
	if strings.TrimSpace(value) == "" {
		return defaultSearchLimit, true
	}
	limit, err := strconv.Atoi(value)
	if err != nil || limit < 1 || limit > maxSearchLimit {
		return 0, false
	}
	return limit, true
}

func albumIDForTrack(track library.Track) string {
	return browseID("album", normalizeBrowseFacet(displayAlbumArtist(track))+"\x00"+normalizeBrowseFacet(displayAlbumTitle(track)))
}

func artistIDForTrack(track library.Track) string {
	return browseID("artist", normalizeBrowseFacet(displayArtistName(track)))
}

func browseID(prefix, key string) string {
	sum := sha256.Sum256([]byte(prefix + "\x00" + key))
	return hex.EncodeToString(sum[:16])
}

func displayAlbumTitle(track library.Track) string {
	if title := strings.TrimSpace(track.Album); title != "" {
		return title
	}
	return unknownAlbumTitle
}

func displayAlbumArtist(track library.Track) string {
	if artist := strings.TrimSpace(track.AlbumArtist); artist != "" {
		return artist
	}
	if artist := strings.TrimSpace(track.Artist); artist != "" {
		return artist
	}
	return unknownArtistName
}

func displayArtistName(track library.Track) string {
	if artist := strings.TrimSpace(track.Artist); artist != "" {
		return artist
	}
	if artist := strings.TrimSpace(track.AlbumArtist); artist != "" {
		return artist
	}
	return unknownArtistName
}

func normalizeBrowseFacet(value string) string {
	return strings.ToLower(strings.Join(strings.Fields(value), " "))
}

func normalizeSearchText(value string) string {
	return normalizeBrowseFacet(value)
}

func containsNormalized(value, normalizedQuery string) bool {
	return strings.Contains(normalizeSearchText(value), normalizedQuery)
}

func sortTracksForPlayback(tracks []library.Track) {
	sort.SliceStable(tracks, func(left, right int) bool {
		if tracks[left].Album != tracks[right].Album {
			return strings.ToLower(tracks[left].Album) < strings.ToLower(tracks[right].Album)
		}
		if tracks[left].DiscNumber != tracks[right].DiscNumber {
			return tracks[left].DiscNumber < tracks[right].DiscNumber
		}
		if tracks[left].TrackNumber != tracks[right].TrackNumber {
			return tracks[left].TrackNumber < tracks[right].TrackNumber
		}
		if strings.ToLower(tracks[left].Title) != strings.ToLower(tracks[right].Title) {
			return strings.ToLower(tracks[left].Title) < strings.ToLower(tracks[right].Title)
		}
		if strings.ToLower(tracks[left].FileName) != strings.ToLower(tracks[right].FileName) {
			return strings.ToLower(tracks[left].FileName) < strings.ToLower(tracks[right].FileName)
		}
		return tracks[left].ID < tracks[right].ID
	})
}

func limitTracks(tracks []library.Track, limit int) []library.Track {
	if len(tracks) <= limit {
		return tracks
	}
	return tracks[:limit]
}

func limitAlbums(albums []albumSummary, limit int) []albumSummary {
	if len(albums) <= limit {
		return albums
	}
	return albums[:limit]
}

func limitArtists(artists []artistSummary, limit int) []artistSummary {
	if len(artists) <= limit {
		return artists
	}
	return artists[:limit]
}
