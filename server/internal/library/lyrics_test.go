package library

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestDecodeLyricsUTF8(t *testing.T) {
	content, encodingName, err := DecodeLyrics([]byte("\u4f60\u597d\nHello"))
	if err != nil {
		t.Fatalf("DecodeLyrics returned error: %v", err)
	}
	if encodingName != "UTF-8" {
		t.Fatalf("encoding = %q, want UTF-8", encodingName)
	}
	if content != "\u4f60\u597d\nHello" {
		t.Fatalf("content = %q", content)
	}
}

func TestLyricsServiceRejectsOversizedSidecar(t *testing.T) {
	root := t.TempDir()
	trackPath := filepath.Join(root, "song.mp3")
	if err := os.WriteFile(trackPath, []byte("audio"), 0o600); err != nil {
		t.Fatalf("write track: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "song.lrc"), make([]byte, maxLyricsFileBytes+1), 0o600); err != nil {
		t.Fatalf("write lyrics: %v", err)
	}

	_, err := NewLyricsService().ReadForTrack(Track{ID: "track-1", Path: trackPath})
	if !errors.Is(err, ErrLyricsTooLarge) {
		t.Fatalf("ReadForTrack error = %v, want ErrLyricsTooLarge", err)
	}
}

func TestDecodeLyricsGBKCompatible(t *testing.T) {
	gbkData := []byte{0xC4, 0xE3, 0xBA, 0xC3, '\n', 'H', 'i'}

	content, encodingName, err := DecodeLyrics(gbkData)
	if err != nil {
		t.Fatalf("DecodeLyrics returned error: %v", err)
	}
	if encodingName != "GB18030" && encodingName != "GBK" {
		t.Fatalf("encoding = %q, want GB18030 or GBK", encodingName)
	}
	if content != "\u4f60\u597d\nHi" {
		t.Fatalf("content = %q", content)
	}
}

func TestDecodeLyricsInvalidEncoding(t *testing.T) {
	invalidData := []byte{0x81, 0x30, 0x81}

	_, _, err := DecodeLyrics(invalidData)
	if !errors.Is(err, ErrUnsupportedLyricsEncoding) {
		t.Fatalf("err = %v, want ErrUnsupportedLyricsEncoding", err)
	}
}

func TestReadForTrackUsesSidecarBeforeEmbeddedLyrics(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "song.flac")
	writeTestFLACFile(t, path, time.Second, map[string]string{
		"TITLE":  "Song",
		"LYRICS": "[00:01.00]embedded",
	})
	if err := os.WriteFile(filepath.Join(root, "song.lrc"), []byte("[00:01.00]sidecar"), 0o600); err != nil {
		t.Fatalf("write sidecar lyrics: %v", err)
	}

	lyrics, err := NewLyricsService().ReadForTrack(NewTrack(path, 1, time.Now()))
	if err != nil {
		t.Fatalf("ReadForTrack returned error: %v", err)
	}
	if lyrics.Content != "[00:01.00]sidecar" {
		t.Fatalf("content = %q, want sidecar lyrics", lyrics.Content)
	}
	if lyrics.Source != "sidecar" {
		t.Fatalf("source = %q, want sidecar", lyrics.Source)
	}
	if lyrics.Encoding != "UTF-8" {
		t.Fatalf("encoding = %q, want UTF-8", lyrics.Encoding)
	}
}

func TestReadForTrackFallsBackToEmbeddedFLACLyrics(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "lyrics.flac")
	writeTestFLACFile(t, path, time.Second, map[string]string{
		"TITLE":  "Lyrics",
		"LYRICS": "[00:01.00]真实歌词",
	})

	lyrics, err := NewLyricsService().ReadForTrack(NewTrack(path, 1, time.Now()))
	if err != nil {
		t.Fatalf("ReadForTrack returned error: %v", err)
	}
	if lyrics.Content != "[00:01.00]真实歌词" {
		t.Fatalf("content = %q, want embedded lyrics", lyrics.Content)
	}
	if lyrics.Source != "embedded:lyrics" {
		t.Fatalf("source = %q, want embedded:lyrics", lyrics.Source)
	}
	if lyrics.Encoding != "UTF-8" {
		t.Fatalf("encoding = %q, want UTF-8", lyrics.Encoding)
	}
}

func TestReadForTrackFallsBackToEmbeddedCommentLyrics(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "comment.flac")
	writeTestFLACFile(t, path, time.Second, map[string]string{
		"TITLE":   "Comment Lyrics",
		"COMMENT": "[00:01.00]comment lyrics",
	})

	lyrics, err := NewLyricsService().ReadForTrack(NewTrack(path, 1, time.Now()))
	if err != nil {
		t.Fatalf("ReadForTrack returned error: %v", err)
	}
	if lyrics.Content != "[00:01.00]comment lyrics" {
		t.Fatalf("content = %q, want comment lyrics", lyrics.Content)
	}
	if lyrics.Source != "embedded:comment" {
		t.Fatalf("source = %q, want embedded:comment", lyrics.Source)
	}
}

func TestReadForTrackMissingWhenNoSidecarOrEmbeddedLyrics(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "睡公主 - G.E.M. 鄧紫棋.flac")
	writeTestFLACFile(t, path, time.Second, map[string]string{
		"TITLE":  "睡公主",
		"ARTIST": "G.E.M. 鄧紫棋",
		"ALBUM":  "18...",
	})

	_, err := NewLyricsService().ReadForTrack(NewTrack(path, 1, time.Now()))
	if !errors.Is(err, ErrLyricsNotFound) {
		t.Fatalf("err = %v, want ErrLyricsNotFound", err)
	}
}
