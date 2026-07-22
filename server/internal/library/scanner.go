package library

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"music-player-server/internal/metadata"
)

type Track struct {
	ID             string    `json:"id"`
	Title          string    `json:"title"`
	Artist         string    `json:"artist,omitempty"`
	Album          string    `json:"album,omitempty"`
	AlbumArtist    string    `json:"album_artist,omitempty"`
	Year           int       `json:"year,omitempty"`
	TrackNumber    int       `json:"track_number,omitempty"`
	TrackTotal     int       `json:"track_total,omitempty"`
	DiscNumber     int       `json:"disc_number,omitempty"`
	DiscTotal      int       `json:"disc_total,omitempty"`
	Genres         []string  `json:"genres,omitempty"`
	RecordingMBID  string    `json:"recording_mbid,omitempty"`
	ReleaseMBID    string    `json:"release_mbid,omitempty"`
	DurationMS     int64     `json:"duration_ms,omitempty"`
	FileName       string    `json:"file_name"`
	Path           string    `json:"-"`
	Extension      string    `json:"extension"`
	SizeBytes      int64     `json:"size_bytes"`
	Modified       time.Time `json:"modified"`
	MetadataSource string    `json:"metadata_source,omitempty"`
	MetadataError  string    `json:"metadata_error,omitempty"`
}

type Scanner struct {
	root           string
	metadataReader metadata.Reader
}

func NewScanner(root string) *Scanner {
	return NewScannerWithMetadataReader(root, metadata.NewLocalReader())
}

func NewScannerWithMetadataReader(root string, metadataReader metadata.Reader) *Scanner {
	return &Scanner{
		root:           root,
		metadataReader: metadataReader,
	}
}

func (s *Scanner) Scan(ctx context.Context) ([]Track, error) {
	tracks := make([]Track, 0)
	err := filepath.WalkDir(s.root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if contextDone(ctx) {
			return ctx.Err()
		}
		if entry.IsDir() {
			return nil
		}
		if !isSupportedAudioFile(path) {
			return nil
		}

		info, err := entry.Info()
		if err != nil {
			return err
		}

		absolutePath, err := filepath.Abs(path)
		if err != nil {
			return err
		}
		track := NewTrack(absolutePath, info.Size(), info.ModTime())
		if s.metadataReader != nil {
			embedded, err := s.metadataReader.Read(ctx, absolutePath)
			if err != nil {
				track.MetadataError = err.Error()
			} else {
				track.ApplyEmbeddedMetadata(embedded)
			}
		}
		tracks = append(tracks, track)
		return nil
	})
	if os.IsNotExist(err) {
		return tracks, nil
	}
	if err != nil {
		return nil, err
	}

	sort.Slice(tracks, func(left, right int) bool {
		return strings.ToLower(tracks[left].Path) < strings.ToLower(tracks[right].Path)
	})
	return tracks, nil
}

func NewTrack(path string, sizeBytes int64, modified time.Time) Track {
	fileName := filepath.Base(path)
	extension := strings.ToLower(filepath.Ext(fileName))
	title := strings.TrimSuffix(fileName, filepath.Ext(fileName))
	return Track{
		ID:             stableTrackID(path),
		Title:          title,
		FileName:       fileName,
		Path:           path,
		Extension:      strings.TrimPrefix(extension, "."),
		SizeBytes:      sizeBytes,
		Modified:       modified.UTC(),
		MetadataSource: "filename",
	}
}

func (t *Track) ApplyEmbeddedMetadata(embedded metadata.Embedded) {
	if embedded.Fields.Title != "" {
		t.Title = embedded.Fields.Title
	}
	if embedded.Fields.Artist != "" {
		t.Artist = embedded.Fields.Artist
	}
	if embedded.Fields.Album != "" {
		t.Album = embedded.Fields.Album
	}
	if embedded.Fields.AlbumArtist != "" {
		t.AlbumArtist = embedded.Fields.AlbumArtist
	}
	if embedded.Fields.Year != 0 {
		t.Year = embedded.Fields.Year
	}
	if embedded.Fields.TrackNumber != 0 {
		t.TrackNumber = embedded.Fields.TrackNumber
	}
	if embedded.Fields.TrackTotal != 0 {
		t.TrackTotal = embedded.Fields.TrackTotal
	}
	if embedded.Fields.DiscNumber != 0 {
		t.DiscNumber = embedded.Fields.DiscNumber
	}
	if embedded.Fields.DiscTotal != 0 {
		t.DiscTotal = embedded.Fields.DiscTotal
	}
	if len(embedded.Fields.Genres) > 0 {
		t.Genres = append([]string(nil), embedded.Fields.Genres...)
	}
	if embedded.Fields.RecordingMBID != "" {
		t.RecordingMBID = embedded.Fields.RecordingMBID
	}
	if embedded.Fields.ReleaseMBID != "" {
		t.ReleaseMBID = embedded.Fields.ReleaseMBID
	}
	if embedded.Duration > 0 {
		t.DurationMS = embedded.Duration.Milliseconds()
	}
	if !embedded.Fields.IsZero() {
		t.MetadataSource = "embedded"
	}
}

func isSupportedAudioFile(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav":
		return true
	default:
		return false
	}
}

func stableTrackID(path string) string {
	normalized := filepath.Clean(path)
	hash := sha1.Sum([]byte(strings.ToLower(normalized)))
	return hex.EncodeToString(hash[:])
}

func contextDone(ctx context.Context) bool {
	select {
	case <-ctx.Done():
		return true
	default:
		return false
	}
}
