package httpapi

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io/fs"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"music-player-server/internal/library"
	"music-player-server/internal/metadata"
	"music-player-server/internal/store"
)

const artworkCacheControl = "no-cache"

var (
	errArtworkNotFound           = errors.New("artwork not found")
	artworkSidecarFileExtensions = []string{".jpg", ".jpeg", ".png", ".webp"}
)

type artworkAsset struct {
	data        []byte
	contentType string
	fileName    string
	modified    time.Time
}

type overrideArtworkReader interface {
	ReadArtwork(ctx context.Context, track library.Track) (metadata.Cover, bool, error)
}

func (h *Handler) getTrackArtwork(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.PathValue("id"))
	if id == "" {
		writeArtworkError(w, r, http.StatusBadRequest, "track id is required")
		return
	}

	track, err := h.repository.GetTrack(r.Context(), id)
	if errors.Is(err, store.ErrTrackNotFound) {
		writeArtworkError(w, r, http.StatusNotFound, "track not found")
		return
	}
	if err != nil {
		writeArtworkError(w, r, http.StatusInternalServerError, "failed to read track")
		return
	}

	artwork, found, err := h.loadOverrideArtwork(r.Context(), track)
	if err != nil {
		writeArtworkError(w, r, http.StatusInternalServerError, "failed to read artwork")
		return
	}
	if !found {
		artwork, err = loadTrackArtwork(r.Context(), track)
	}
	if errors.Is(err, errArtworkNotFound) {
		writeArtworkError(w, r, http.StatusNotFound, "artwork not found")
		return
	}
	if err != nil {
		writeArtworkError(w, r, http.StatusInternalServerError, "failed to read artwork")
		return
	}

	header := w.Header()
	header.Set("Cache-Control", artworkCacheControl)
	header.Set("Content-Type", artwork.contentType)
	header.Set("ETag", artworkETag(artwork.data))
	header.Set("X-Content-Type-Options", "nosniff")
	http.ServeContent(w, r, artwork.fileName, artwork.modified, bytes.NewReader(artwork.data))
}

func (h *Handler) loadOverrideArtwork(ctx context.Context, track library.Track) (artworkAsset, bool, error) {
	reader, ok := h.lyricsReader.(overrideArtworkReader)
	if !ok {
		return artworkAsset{}, false, nil
	}

	cover, found, err := reader.ReadArtwork(ctx, track)
	if err != nil || !found {
		return artworkAsset{}, false, err
	}
	if len(cover.Data) == 0 {
		return artworkAsset{}, false, nil
	}

	contentType := artworkContentType(cover.Data, cover.MIMEType, cover.Extension)
	return artworkAsset{
		data:        cover.Data,
		contentType: contentType,
		fileName:    "artwork" + artworkFileExtension(contentType, cover.Extension),
	}, true, nil
}

func loadTrackArtwork(ctx context.Context, track library.Track) (artworkAsset, error) {
	if err := ctx.Err(); err != nil {
		return artworkAsset{}, err
	}
	if track.Path == "" {
		return artworkAsset{}, errors.New("track path is empty")
	}

	if artwork, found, err := readSidecarArtwork(track.Path); err != nil {
		return artworkAsset{}, err
	} else if found {
		return artwork, nil
	}

	return readEmbeddedArtwork(ctx, track.Path)
}

func readSidecarArtwork(trackPath string) (artworkAsset, bool, error) {
	basePath := strings.TrimSuffix(trackPath, filepath.Ext(trackPath))
	for _, extension := range artworkSidecarFileExtensions {
		path := basePath + extension
		info, err := os.Stat(path)
		if errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err != nil {
			return artworkAsset{}, false, err
		}
		if !info.Mode().IsRegular() {
			continue
		}

		data, err := os.ReadFile(path)
		if errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err != nil {
			return artworkAsset{}, false, err
		}
		if len(data) == 0 {
			continue
		}

		return artworkAsset{
			data:        data,
			contentType: artworkContentType(data, "", extension),
			fileName:    "artwork" + extension,
			modified:    info.ModTime(),
		}, true, nil
	}

	return artworkAsset{}, false, nil
}

func readEmbeddedArtwork(ctx context.Context, trackPath string) (artworkAsset, error) {
	info, err := os.Stat(trackPath)
	if errors.Is(err, fs.ErrNotExist) {
		return artworkAsset{}, errArtworkNotFound
	}
	if err != nil {
		return artworkAsset{}, err
	}
	if !info.Mode().IsRegular() {
		return artworkAsset{}, errArtworkNotFound
	}

	embedded, err := metadata.NewLocalReader().Read(ctx, trackPath)
	if err != nil {
		if contextError := ctx.Err(); contextError != nil {
			return artworkAsset{}, contextError
		}
		return artworkAsset{}, errArtworkNotFound
	}
	if embedded.Cover == nil || len(embedded.Cover.Data) == 0 {
		return artworkAsset{}, errArtworkNotFound
	}

	contentType := artworkContentType(embedded.Cover.Data, embedded.Cover.MIMEType, embedded.Cover.Extension)
	extension := artworkFileExtension(contentType, embedded.Cover.Extension)
	return artworkAsset{
		data:        embedded.Cover.Data,
		contentType: contentType,
		fileName:    "artwork" + extension,
		modified:    info.ModTime(),
	}, nil
}

func artworkContentType(data []byte, declaredType, extension string) string {
	if contentType := canonicalImageContentType(http.DetectContentType(data)); contentType != "" {
		return contentType
	}
	if contentType := canonicalImageContentType(declaredType); contentType != "" {
		return contentType
	}

	switch strings.ToLower(strings.TrimSpace(strings.TrimPrefix(extension, "."))) {
	case "jpg", "jpeg":
		return "image/jpeg"
	case "png":
		return "image/png"
	case "webp":
		return "image/webp"
	}
	return "application/octet-stream"
}

func canonicalImageContentType(value string) string {
	contentType, _, err := mime.ParseMediaType(strings.TrimSpace(value))
	if err != nil {
		return ""
	}

	contentType = strings.ToLower(contentType)
	switch contentType {
	case "image/jpg", "image/pjpeg":
		return "image/jpeg"
	}
	if strings.HasPrefix(contentType, "image/") {
		return contentType
	}
	return ""
}

func artworkFileExtension(contentType, extension string) string {
	switch normalized := strings.ToLower(strings.TrimSpace(strings.TrimPrefix(extension, "."))); normalized {
	case "jpg", "jpeg", "png", "webp":
		return "." + normalized
	}

	switch contentType {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	default:
		return ".bin"
	}
}

func artworkETag(data []byte) string {
	sum := sha256.Sum256(data)
	return `"` + hex.EncodeToString(sum[:]) + `"`
}

func writeArtworkError(w http.ResponseWriter, r *http.Request, status int, message string) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != http.MethodHead {
		writeError(w, status, message)
		return
	}

	payload, _ := json.Marshal(errorResponse{Error: message})
	payload = append(payload, '\n')
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Content-Length", strconv.Itoa(len(payload)))
	w.WriteHeader(status)
}
