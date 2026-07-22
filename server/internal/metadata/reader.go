package metadata

import (
	"context"
	"errors"
	"io"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/dhowden/tag"
)

var ErrNoReadableMetadata = errors.New("no readable embedded metadata")

type LocalReader struct{}

func NewLocalReader() *LocalReader {
	return &LocalReader{}
}

func (r *LocalReader) Read(ctx context.Context, path string) (Embedded, error) {
	if err := ctx.Err(); err != nil {
		return Embedded{}, err
	}

	file, err := os.Open(path)
	if err != nil {
		return Embedded{}, err
	}
	defer file.Close()

	embedded := Embedded{}
	var tagErr error
	if tags, err := tag.ReadFrom(file); err == nil {
		embedded = embeddedFromTags(tags)
	} else {
		tagErr = err
	}

	if _, err := file.Seek(0, io.SeekStart); err == nil {
		if duration, format, err := ReadDuration(file); err == nil {
			embedded.Duration = duration
			if embedded.FileType == "" {
				embedded.FileType = format
			}
		}
	}

	if embedded.Fields.IsZero() && embedded.Duration == 0 && embedded.Lyrics.Content == "" && embedded.Comment == "" && embedded.Cover == nil {
		if tagErr != nil {
			return embedded, tagErr
		}
		return embedded, ErrNoReadableMetadata
	}

	return embedded, nil
}

func embeddedFromTags(tags tag.Metadata) Embedded {
	trackNumber, trackTotal := tags.Track()
	discNumber, discTotal := tags.Disc()
	fields := FieldSet{
		Title:         cleanTagString(tags.Title()),
		Artist:        cleanTagString(tags.Artist()),
		Album:         cleanTagString(tags.Album()),
		AlbumArtist:   cleanTagString(tags.AlbumArtist()),
		Year:          tags.Year(),
		TrackNumber:   trackNumber,
		TrackTotal:    trackTotal,
		DiscNumber:    discNumber,
		DiscTotal:     discTotal,
		Genres:        splitGenres(tags.Genre()),
		RecordingMBID: rawString(tags.Raw(), "musicbrainz track id", "musicbrainz_trackid", "musicbrainz recording id", "musicbrainz_recordingid"),
		ReleaseMBID:   rawString(tags.Raw(), "musicbrainz album id", "musicbrainz_albumid", "musicbrainz release id", "musicbrainz_releaseid"),
	}

	lyrics := lyricsFromTags(tags)
	cover := coverFromTags(tags)

	return Embedded{
		Fields:   fields,
		Lyrics:   lyrics,
		Comment:  cleanTagString(tags.Comment()),
		Cover:    cover,
		Format:   string(tags.Format()),
		FileType: string(tags.FileType()),
		Raw:      tags.Raw(),
	}
}

func lyricsFromTags(tags tag.Metadata) LyricsText {
	if content := normalizeEmbeddedLyrics(tags.Lyrics()); content != "" {
		return LyricsText{Content: content, Encoding: "UTF-8", Source: "embedded:lyrics"}
	}

	for _, key := range []string{"lyrics", "unsyncedlyrics", "unsynchronizedlyrics", "syncedlyrics", "synchronizedlyrics"} {
		if content := normalizeEmbeddedLyrics(rawString(tags.Raw(), key)); content != "" {
			return LyricsText{Content: content, Encoding: "UTF-8", Source: "embedded:" + key}
		}
	}

	comment := normalizeEmbeddedLyrics(tags.Comment())
	if looksLikeLyrics(comment) {
		return LyricsText{Content: comment, Encoding: "UTF-8", Source: "embedded:comment"}
	}

	return LyricsText{}
}

func coverFromTags(tags tag.Metadata) *Cover {
	picture := tags.Picture()
	if picture == nil || len(picture.Data) == 0 {
		return nil
	}

	extension := strings.TrimPrefix(strings.ToLower(picture.Ext), ".")
	return &Cover{
		Data:      append([]byte(nil), picture.Data...),
		MIMEType:  picture.MIMEType,
		Extension: extension,
		Source:    "embedded",
	}
}

func rawString(raw map[string]any, names ...string) string {
	for _, name := range names {
		normalizedName := normalizeTagKey(name)
		for key, value := range raw {
			if normalizeTagKey(key) != normalizedName {
				continue
			}
			switch typed := value.(type) {
			case string:
				if cleaned := cleanTagString(typed); cleaned != "" {
					return cleaned
				}
			case []string:
				for _, item := range typed {
					if cleaned := cleanTagString(item); cleaned != "" {
						return cleaned
					}
				}
			case fmtStringer:
				if cleaned := cleanTagString(typed.String()); cleaned != "" {
					return cleaned
				}
			case int:
				if typed != 0 {
					return strconv.Itoa(typed)
				}
			}
		}
	}
	return ""
}

type fmtStringer interface {
	String() string
}

func normalizeTagKey(key string) string {
	key = strings.ToLower(strings.TrimSpace(key))
	replacer := strings.NewReplacer(" ", "", "_", "", "-", "", "/", "", ".", "")
	return replacer.Replace(key)
}

func cleanTagString(value string) string {
	return strings.TrimSpace(strings.ReplaceAll(value, "\x00", ""))
}

func splitGenres(value string) []string {
	value = cleanTagString(value)
	if value == "" {
		return nil
	}

	parts := strings.FieldsFunc(value, func(r rune) bool {
		return r == ';' || r == ',' || r == '/'
	})
	genres := make([]string, 0, len(parts))
	seen := make(map[string]struct{}, len(parts))
	for _, part := range parts {
		genre := cleanTagString(part)
		if genre == "" {
			continue
		}
		key := strings.ToLower(genre)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		genres = append(genres, genre)
	}
	return genres
}

func normalizeEmbeddedLyrics(content string) string {
	content = strings.ReplaceAll(content, "\r\n", "\n")
	content = strings.ReplaceAll(content, "\r", "\n")
	return strings.TrimSpace(content)
}

var lrcTimestampPattern = regexp.MustCompile(`\[[0-9]{1,2}:[0-9]{2}(?:\.[0-9]{1,3})?\]`)

func looksLikeLyrics(content string) bool {
	content = strings.TrimSpace(content)
	if content == "" {
		return false
	}
	if lrcTimestampPattern.MatchString(content) {
		return true
	}
	return strings.Count(content, "\n") >= 2
}
