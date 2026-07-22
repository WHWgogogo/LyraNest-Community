package library

import (
	"bytes"
	"context"
	"encoding/binary"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

func TestScannerFiltersSupportedAudioExtensions(t *testing.T) {
	root := t.TempDir()
	writeTestFile(t, filepath.Join(root, "alpha.mp3"))
	writeTestFile(t, filepath.Join(root, "bravo.FLAC"))
	writeTestFile(t, filepath.Join(root, "charlie.wav"))
	writeTestFile(t, filepath.Join(root, "cover.jpg"))
	writeTestFile(t, filepath.Join(root, "notes.txt"))

	tracks, err := NewScanner(root).Scan(context.Background())
	if err != nil {
		t.Fatalf("Scan returned error: %v", err)
	}

	extensions := make([]string, 0, len(tracks))
	for _, track := range tracks {
		extensions = append(extensions, track.Extension)
	}
	want := []string{"mp3", "flac", "wav"}
	if !reflect.DeepEqual(extensions, want) {
		t.Fatalf("extensions = %#v, want %#v", extensions, want)
	}
}

func TestScannerStableID(t *testing.T) {
	root := t.TempDir()
	writeTestFile(t, filepath.Join(root, "stable.mp3"))

	firstScan, err := NewScanner(root).Scan(context.Background())
	if err != nil {
		t.Fatalf("first Scan returned error: %v", err)
	}
	secondScan, err := NewScanner(root).Scan(context.Background())
	if err != nil {
		t.Fatalf("second Scan returned error: %v", err)
	}
	if len(firstScan) != 1 || len(secondScan) != 1 {
		t.Fatalf("track counts = %d and %d, want 1 and 1", len(firstScan), len(secondScan))
	}
	if firstScan[0].ID == "" {
		t.Fatal("track id is empty")
	}
	if firstScan[0].ID != secondScan[0].ID {
		t.Fatalf("ids = %q and %q, want equal", firstScan[0].ID, secondScan[0].ID)
	}
}

func TestScannerMissingDirectory(t *testing.T) {
	root := filepath.Join(t.TempDir(), "missing")

	tracks, err := NewScanner(root).Scan(context.Background())
	if err != nil {
		t.Fatalf("Scan returned error: %v", err)
	}
	if len(tracks) != 0 {
		t.Fatalf("tracks = %#v, want empty", tracks)
	}
}

func TestScannerReadsEmbeddedFLACMetadata(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "fallback-title.flac")
	writeTestFLACFile(t, path, 3*time.Second, map[string]string{
		"TITLE":       "Real Title",
		"ARTIST":      "Real Artist",
		"ALBUM":       "Real Album",
		"DATE":        "2026",
		"TRACKNUMBER": "7",
		"DISCNUMBER":  "2",
		"GENRE":       "Pop; Mandopop",
	})

	tracks, err := NewScanner(root).Scan(context.Background())
	if err != nil {
		t.Fatalf("Scan returned error: %v", err)
	}
	if len(tracks) != 1 {
		t.Fatalf("tracks = %d, want 1", len(tracks))
	}

	track := tracks[0]
	if track.Title != "Real Title" || track.Artist != "Real Artist" || track.Album != "Real Album" {
		t.Fatalf("track metadata = %#v, want embedded tags", track)
	}
	if track.Year != 2026 || track.TrackNumber != 7 || track.DiscNumber != 2 {
		t.Fatalf("track numbers = %#v, want embedded numeric tags", track)
	}
	if track.DurationMS != 3000 {
		t.Fatalf("duration_ms = %d, want 3000", track.DurationMS)
	}
	if !reflect.DeepEqual(track.Genres, []string{"Pop", "Mandopop"}) {
		t.Fatalf("genres = %#v, want split genres", track.Genres)
	}
	if track.MetadataSource != "embedded" {
		t.Fatalf("metadata source = %q, want embedded", track.MetadataSource)
	}
}

func TestScannerFallsBackToFileNameWhenFLACHasNoTags(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "追光者 - 岑宁儿.flac")
	writeTestFLACFile(t, path, 2*time.Second, nil)

	tracks, err := NewScanner(root).Scan(context.Background())
	if err != nil {
		t.Fatalf("Scan returned error: %v", err)
	}
	if len(tracks) != 1 {
		t.Fatalf("tracks = %d, want 1", len(tracks))
	}

	track := tracks[0]
	if track.Title != "追光者 - 岑宁儿" {
		t.Fatalf("title = %q, want filename fallback", track.Title)
	}
	if track.Artist != "" || track.Album != "" {
		t.Fatalf("artist/album = %q/%q, want empty fallback fields", track.Artist, track.Album)
	}
	if track.MetadataSource != "filename" {
		t.Fatalf("metadata source = %q, want filename", track.MetadataSource)
	}
}

func TestScannerContinuesWhenOneAudioFileIsCorrupt(t *testing.T) {
	root := t.TempDir()
	writeTestFile(t, filepath.Join(root, "broken.flac"))
	writeTestFLACFile(t, filepath.Join(root, "valid.flac"), time.Second, map[string]string{
		"TITLE": "Valid",
	})

	tracks, err := NewScanner(root).Scan(context.Background())
	if err != nil {
		t.Fatalf("Scan returned error: %v", err)
	}
	if len(tracks) != 2 {
		t.Fatalf("tracks = %d, want 2", len(tracks))
	}

	var broken Track
	for _, track := range tracks {
		if track.FileName == "broken.flac" {
			broken = track
		}
	}
	if broken.Title != "broken" {
		t.Fatalf("broken title = %q, want filename fallback", broken.Title)
	}
	if broken.MetadataError == "" {
		t.Fatal("broken metadata error is empty")
	}
}

func writeTestFile(t *testing.T, path string) {
	t.Helper()
	if err := os.WriteFile(path, []byte("test data"), 0o600); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func writeTestFLACFile(t *testing.T, path string, duration time.Duration, comments map[string]string) {
	t.Helper()

	var data bytes.Buffer
	data.WriteString("fLaC")

	streamInfo := make([]byte, 34)
	binary.BigEndian.PutUint16(streamInfo[0:2], 4096)
	binary.BigEndian.PutUint16(streamInfo[2:4], 4096)
	sampleRate := uint64(44100)
	totalSamples := uint64(duration) * sampleRate / uint64(time.Second)
	audioBits := sampleRate<<44 | uint64(1)<<41 | uint64(15)<<36 | totalSamples
	binary.BigEndian.PutUint64(streamInfo[10:18], audioBits)

	lastStreamInfo := len(comments) == 0
	writeFLACMetadataBlock(&data, 0, lastStreamInfo, streamInfo)

	if len(comments) > 0 {
		var commentBlock bytes.Buffer
		vendor := []byte("harmony-test")
		binary.Write(&commentBlock, binary.LittleEndian, uint32(len(vendor)))
		commentBlock.Write(vendor)
		binary.Write(&commentBlock, binary.LittleEndian, uint32(len(comments)))
		for key, value := range comments {
			comment := []byte(key + "=" + value)
			binary.Write(&commentBlock, binary.LittleEndian, uint32(len(comment)))
			commentBlock.Write(comment)
		}
		writeFLACMetadataBlock(&data, 4, true, commentBlock.Bytes())
	}

	if err := os.WriteFile(path, data.Bytes(), 0o600); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func writeFLACMetadataBlock(w *bytes.Buffer, blockType byte, last bool, payload []byte) {
	headerType := blockType
	if last {
		headerType |= 0x80
	}
	w.WriteByte(headerType)
	w.Write([]byte{byte(len(payload) >> 16), byte(len(payload) >> 8), byte(len(payload))})
	w.Write(payload)
}
