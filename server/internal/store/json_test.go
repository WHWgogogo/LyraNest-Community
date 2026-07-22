package store

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"sync"
	"testing"
	"time"

	"music-player-server/internal/library"
)

func TestJSONRepositoryFirstStart(t *testing.T) {
	dataDir := filepath.Join(t.TempDir(), "store")

	repository, err := NewJSONRepository(dataDir)
	if err != nil {
		t.Fatalf("NewJSONRepository returned error: %v", err)
	}

	tracks, err := repository.ListTracks(context.Background())
	if err != nil {
		t.Fatalf("ListTracks returned error: %v", err)
	}
	if len(tracks) != 0 {
		t.Fatalf("tracks = %#v, want empty", tracks)
	}
	if _, err := os.Stat(dataDir); err != nil {
		t.Fatalf("data directory was not created: %v", err)
	}
}

func TestJSONRepositoryReplaceListGet(t *testing.T) {
	repository := newTestJSONRepository(t)
	ctx := context.Background()
	alpha := testTrack("alpha", "/music/Alpha.mp3")
	bravo := testTrack("bravo", "/music/bravo.mp3")
	obsolete := testTrack("obsolete", "/music/obsolete.mp3")

	if err := repository.ReplaceTracks(ctx, []library.Track{obsolete}); err != nil {
		t.Fatalf("first ReplaceTracks returned error: %v", err)
	}
	if err := repository.ReplaceTracks(ctx, []library.Track{bravo, alpha}); err != nil {
		t.Fatalf("second ReplaceTracks returned error: %v", err)
	}

	tracks, err := repository.ListTracks(ctx)
	if err != nil {
		t.Fatalf("ListTracks returned error: %v", err)
	}
	assertTracksEqual(t, tracks, []library.Track{alpha, bravo})

	track, err := repository.GetTrack(ctx, bravo.ID)
	if err != nil {
		t.Fatalf("GetTrack returned error: %v", err)
	}
	assertTrackEqual(t, track, bravo)

	_, err = repository.GetTrack(ctx, obsolete.ID)
	if !errors.Is(err, ErrTrackNotFound) {
		t.Fatalf("GetTrack missing err = %v, want ErrTrackNotFound", err)
	}
}

func TestJSONRepositoryRestoresTracksOnRestart(t *testing.T) {
	dataDir := filepath.Join(t.TempDir(), "store")
	ctx := context.Background()
	alpha := testTrack("alpha", "/music/Alpha.mp3")
	bravo := testTrack("bravo", "/music/bravo.mp3")

	firstRepository, err := NewJSONRepository(dataDir)
	if err != nil {
		t.Fatalf("first NewJSONRepository returned error: %v", err)
	}
	if err := firstRepository.ReplaceTracks(ctx, []library.Track{bravo, alpha}); err != nil {
		t.Fatalf("ReplaceTracks returned error: %v", err)
	}

	secondRepository, err := NewJSONRepository(dataDir)
	if err != nil {
		t.Fatalf("second NewJSONRepository returned error: %v", err)
	}

	tracks, err := secondRepository.ListTracks(ctx)
	if err != nil {
		t.Fatalf("ListTracks returned error: %v", err)
	}
	assertTracksEqual(t, tracks, []library.Track{alpha, bravo})

	track, err := secondRepository.GetTrack(ctx, alpha.ID)
	if err != nil {
		t.Fatalf("GetTrack returned error: %v", err)
	}
	assertTrackEqual(t, track, alpha)
	if track.Path == "" {
		t.Fatal("Path was not restored from the repository JSON")
	}
}

func TestJSONRepositoryRejectsCorruptFile(t *testing.T) {
	dataDir := filepath.Join(t.TempDir(), "store")
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dataDir, trackStoreFileName), []byte("{not-json"), 0o600); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}

	_, err := NewJSONRepository(dataDir)
	if !errors.Is(err, ErrTrackStoreCorrupt) {
		t.Fatalf("NewJSONRepository err = %v, want ErrTrackStoreCorrupt", err)
	}
}

func TestJSONRepositoryConcurrentReadWrite(t *testing.T) {
	repository := newTestJSONRepository(t)
	ctx := context.Background()
	stable := testTrack("stable", "/music/stable.mp3")

	if err := repository.ReplaceTracks(ctx, []library.Track{stable}); err != nil {
		t.Fatalf("ReplaceTracks returned error: %v", err)
	}

	var waitGroup sync.WaitGroup
	errs := make(chan error, 16)
	for writer := 0; writer < 4; writer++ {
		waitGroup.Add(1)
		go func(writer int) {
			defer waitGroup.Done()
			for iteration := 0; iteration < 25; iteration++ {
				track := testTrack(
					fmt.Sprintf("writer-%d-%d", writer, iteration),
					fmt.Sprintf("/music/writer-%d-%d.mp3", writer, iteration),
				)
				if err := repository.ReplaceTracks(ctx, []library.Track{stable, track}); err != nil {
					errs <- err
					return
				}
			}
		}(writer)
	}
	for reader := 0; reader < 8; reader++ {
		waitGroup.Add(1)
		go func() {
			defer waitGroup.Done()
			for iteration := 0; iteration < 100; iteration++ {
				if _, err := repository.ListTracks(ctx); err != nil {
					errs <- err
					return
				}
				if _, err := repository.GetTrack(ctx, stable.ID); err != nil {
					errs <- err
					return
				}
			}
		}()
	}

	waitGroup.Wait()
	close(errs)
	for err := range errs {
		t.Errorf("concurrent repository operation returned error: %v", err)
	}
}

func TestJSONRepositoryUsesPrivatePermissions(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows file mode bits do not represent ACL privacy")
	}

	dataDir := filepath.Join(t.TempDir(), "store")
	repository, err := NewJSONRepository(dataDir)
	if err != nil {
		t.Fatalf("NewJSONRepository returned error: %v", err)
	}

	dataDirInfo, err := os.Stat(dataDir)
	if err != nil {
		t.Fatalf("Stat data directory returned error: %v", err)
	}
	if mode := dataDirInfo.Mode().Perm(); mode != 0o700 {
		t.Fatalf("data directory mode = %o, want 0700", mode)
	}

	if err := repository.ReplaceTracks(context.Background(), []library.Track{testTrack("alpha", "/music/Alpha.mp3")}); err != nil {
		t.Fatalf("ReplaceTracks returned error: %v", err)
	}

	storeFileInfo, err := os.Stat(filepath.Join(dataDir, trackStoreFileName))
	if err != nil {
		t.Fatalf("Stat store file returned error: %v", err)
	}
	if mode := storeFileInfo.Mode().Perm(); mode != 0o600 {
		t.Fatalf("store file mode = %o, want 0600", mode)
	}
}

func newTestJSONRepository(t *testing.T) *JSONRepository {
	t.Helper()
	repository, err := NewJSONRepository(filepath.Join(t.TempDir(), "store"))
	if err != nil {
		t.Fatalf("NewJSONRepository returned error: %v", err)
	}
	return repository
}

func testTrack(id string, path string) library.Track {
	return library.Track{
		ID:        id,
		Title:     "Title " + id,
		Artist:    "Artist " + id,
		Album:     "Album " + id,
		FileName:  filepath.Base(path),
		Path:      path,
		Extension: "mp3",
		SizeBytes: int64(len(id) * 100),
		Modified:  time.Date(2026, 7, 18, len(id)%24, 30, 0, 0, time.UTC),
	}
}

func assertTracksEqual(t *testing.T, got []library.Track, want []library.Track) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("tracks = %#v, want %#v", got, want)
	}
}

func assertTrackEqual(t *testing.T, got library.Track, want library.Track) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("track = %#v, want %#v", got, want)
	}
}
