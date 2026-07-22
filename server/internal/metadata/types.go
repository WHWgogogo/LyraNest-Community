package metadata

import (
	"context"
	"time"
)

type FieldSet struct {
	Title         string   `json:"title,omitempty"`
	Artist        string   `json:"artist,omitempty"`
	Album         string   `json:"album,omitempty"`
	AlbumArtist   string   `json:"album_artist,omitempty"`
	Year          int      `json:"year,omitempty"`
	TrackNumber   int      `json:"track_number,omitempty"`
	TrackTotal    int      `json:"track_total,omitempty"`
	DiscNumber    int      `json:"disc_number,omitempty"`
	DiscTotal     int      `json:"disc_total,omitempty"`
	Genres        []string `json:"genres,omitempty"`
	RecordingMBID string   `json:"recording_mbid,omitempty"`
	ReleaseMBID   string   `json:"release_mbid,omitempty"`
}

func (f FieldSet) IsZero() bool {
	return f.Title == "" &&
		f.Artist == "" &&
		f.Album == "" &&
		f.AlbumArtist == "" &&
		f.Year == 0 &&
		f.TrackNumber == 0 &&
		f.TrackTotal == 0 &&
		f.DiscNumber == 0 &&
		f.DiscTotal == 0 &&
		len(f.Genres) == 0 &&
		f.RecordingMBID == "" &&
		f.ReleaseMBID == ""
}

func (f FieldSet) HasDisplayTags() bool {
	return f.Title != "" || f.Artist != "" || f.Album != "" || f.AlbumArtist != ""
}

type Embedded struct {
	Fields   FieldSet
	Duration time.Duration
	Lyrics   LyricsText
	Comment  string
	Cover    *Cover
	Format   string
	FileType string
	Raw      map[string]any
}

type Reader interface {
	Read(ctx context.Context, path string) (Embedded, error)
}

type LyricsText struct {
	Content  string `json:"content,omitempty"`
	Encoding string `json:"encoding,omitempty"`
	Source   string `json:"source,omitempty"`
}

type Cover struct {
	Data      []byte `json:"data,omitempty"`
	MIMEType  string `json:"mime_type,omitempty"`
	Extension string `json:"extension,omitempty"`
	Source    string `json:"source,omitempty"`
	SourceURL string `json:"source_url,omitempty"`
}

type LyricsOverride struct {
	Content     string `json:"content,omitempty"`
	Encoding    string `json:"encoding,omitempty"`
	Source      string `json:"source,omitempty"`
	SidecarPath string `json:"sidecar_path,omitempty"`
}

type CoverOverride struct {
	Data        []byte `json:"data,omitempty"`
	MIMEType    string `json:"mime_type,omitempty"`
	Extension   string `json:"extension,omitempty"`
	Source      string `json:"source,omitempty"`
	SourceURL   string `json:"source_url,omitempty"`
	SidecarPath string `json:"sidecar_path,omitempty"`
}

type TrackOverride struct {
	TrackID    string          `json:"track_id"`
	Path       string          `json:"path,omitempty"`
	Fields     FieldSet        `json:"fields"`
	Lyrics     *LyricsOverride `json:"lyrics,omitempty"`
	Cover      *CoverOverride  `json:"cover,omitempty"`
	Source     string          `json:"source,omitempty"`
	Confidence float64         `json:"confidence,omitempty"`
	AppliedAt  time.Time       `json:"applied_at"`
}
