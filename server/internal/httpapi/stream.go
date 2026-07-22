package httpapi

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"io"
	"io/fs"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"music-player-server/internal/library"
	"music-player-server/internal/store"
)

type streamDigestCacheEntry struct {
	size    int64
	modTime int64
	digest  [sha256.Size]byte
	lastUse uint64
}

const maxStreamDigestCacheEntries = 4096

type streamDigestCacheStore struct {
	sync.RWMutex
	entries    map[string]streamDigestCacheEntry
	maxEntries int
	sequence   uint64
}

func newStreamDigestCache(maxEntries int) *streamDigestCacheStore {
	if maxEntries <= 0 {
		maxEntries = maxStreamDigestCacheEntries
	}
	return &streamDigestCacheStore{
		entries:    make(map[string]streamDigestCacheEntry),
		maxEntries: maxEntries,
	}
}

var streamDigestCache = newStreamDigestCache(maxStreamDigestCacheEntries)

func (h *Handler) streamTrack(w http.ResponseWriter, r *http.Request) {
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

	file, err := os.Open(track.Path)
	if errors.Is(err, fs.ErrNotExist) {
		writeError(w, http.StatusNotFound, "audio file not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to read audio file")
		return
	}
	defer file.Close()

	info, err := file.Stat()
	if errors.Is(err, fs.ErrNotExist) {
		writeError(w, http.StatusNotFound, "audio file not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to read audio file")
		return
	}
	if !info.Mode().IsRegular() {
		writeError(w, http.StatusNotFound, "audio file not found")
		return
	}

	digest, err := streamFileDigest(file, info)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to read audio file")
		return
	}

	fileName := safeFileName(track)
	header := w.Header()
	header.Set("Content-Type", audioContentType(track))
	header.Set("Content-Disposition", contentDisposition(fileName))
	header.Set("ETag", streamETag(digest))
	header.Set("Digest", streamDigestHeader(digest))
	header.Set("X-Media-Version", streamMediaVersion(digest))
	http.ServeContent(w, r, fileName, info.ModTime(), file)
}

func streamFileDigest(file *os.File, info fs.FileInfo) ([sha256.Size]byte, error) {
	if digest, ok := cachedStreamDigest(file.Name(), info); ok {
		return digest, nil
	}

	for attempt := 0; attempt < 2; attempt++ {
		if _, err := file.Seek(0, io.SeekStart); err != nil {
			return [sha256.Size]byte{}, err
		}

		hash := sha256.New()
		if _, err := io.Copy(hash, file); err != nil {
			return [sha256.Size]byte{}, err
		}

		currentInfo, err := file.Stat()
		if err != nil {
			return [sha256.Size]byte{}, err
		}
		if currentInfo.Size() != info.Size() || currentInfo.ModTime().UnixNano() != info.ModTime().UnixNano() {
			info = currentInfo
			continue
		}

		var digest [sha256.Size]byte
		copy(digest[:], hash.Sum(nil))
		cacheStreamDigest(file.Name(), info, digest)
		return digest, nil
	}

	return [sha256.Size]byte{}, errors.New("audio file changed while hashing")
}

func cachedStreamDigest(path string, info fs.FileInfo) ([sha256.Size]byte, bool) {
	return streamDigestCache.get(path, info)
}

func (c *streamDigestCacheStore) get(path string, info fs.FileInfo) ([sha256.Size]byte, bool) {
	c.Lock()
	defer c.Unlock()

	entry, ok := c.entries[path]
	if !ok || entry.size != info.Size() || entry.modTime != info.ModTime().UnixNano() {
		if ok {
			delete(c.entries, path)
		}
		return [sha256.Size]byte{}, false
	}
	entry.lastUse = c.nextUseLocked()
	c.entries[path] = entry
	return entry.digest, true
}

func cacheStreamDigest(path string, info fs.FileInfo, digest [sha256.Size]byte) {
	streamDigestCache.put(path, info, digest)
}

func (c *streamDigestCacheStore) put(path string, info fs.FileInfo, digest [sha256.Size]byte) {
	c.Lock()
	defer c.Unlock()

	if _, exists := c.entries[path]; !exists {
		for len(c.entries) >= c.maxEntries {
			c.evictLeastRecentlyUsedLocked()
		}
	}
	c.entries[path] = streamDigestCacheEntry{
		size:    info.Size(),
		modTime: info.ModTime().UnixNano(),
		digest:  digest,
		lastUse: c.nextUseLocked(),
	}
}

func (c *streamDigestCacheStore) nextUseLocked() uint64 {
	c.sequence++
	if c.sequence == 0 {
		c.sequence++
	}
	return c.sequence
}

func (c *streamDigestCacheStore) evictLeastRecentlyUsedLocked() {
	var oldestPath string
	var oldestUse uint64
	for path, entry := range c.entries {
		if oldestPath == "" || entry.lastUse < oldestUse {
			oldestPath = path
			oldestUse = entry.lastUse
		}
	}
	if oldestPath != "" {
		delete(c.entries, oldestPath)
	}
}

func streamETag(digest [sha256.Size]byte) string {
	return `"` + hex.EncodeToString(digest[:]) + `"`
}

func streamDigestHeader(digest [sha256.Size]byte) string {
	return "sha-256=" + base64.StdEncoding.EncodeToString(digest[:])
}

func streamMediaVersion(digest [sha256.Size]byte) string {
	return hex.EncodeToString(digest[:])
}

func audioContentType(track library.Track) string {
	extension := strings.ToLower(strings.TrimPrefix(strings.TrimSpace(track.Extension), "."))
	if extension == "" {
		extension = strings.ToLower(strings.TrimPrefix(filepath.Ext(track.FileName), "."))
	}

	switch extension {
	case "mp3":
		return "audio/mpeg"
	case "flac":
		return "audio/flac"
	case "m4a":
		return "audio/mp4"
	case "ogg", "opus":
		return "audio/ogg"
	case "wav":
		return "audio/wav"
	}

	if extension != "" {
		if contentType := mime.TypeByExtension("." + extension); contentType != "" {
			return contentType
		}
	}
	return "application/octet-stream"
}

func safeFileName(track library.Track) string {
	fileName := filepath.Base(strings.TrimSpace(track.FileName))
	if fileName == "" || fileName == "." {
		fileName = filepath.Base(track.Path)
	}
	if fileName == "" || fileName == "." {
		return "audio"
	}
	return fileName
}

func contentDisposition(fileName string) string {
	disposition := mime.FormatMediaType("inline", map[string]string{"filename": fileName})
	if disposition == "" {
		return "inline"
	}
	return disposition
}
