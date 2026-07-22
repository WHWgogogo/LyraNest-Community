package userdata

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestStoreCollectionsPersistAndImportIdempotently(t *testing.T) {
	now := time.Date(2026, 7, 20, 10, 0, 0, 0, time.UTC)
	store, err := NewStore(t.TempDir(), WithNow(func() time.Time { return now }))
	if err != nil {
		t.Fatalf("NewStore returned error: %v", err)
	}

	first, err := store.AddFavorite(context.Background(), "user-a", "track-1")
	if err != nil {
		t.Fatalf("AddFavorite returned error: %v", err)
	}
	if first.Revision != 1 || !reflect.DeepEqual(first.FavoriteTrackIDs, []string{"track-1"}) {
		t.Fatalf("first snapshot = %#v", first)
	}
	idempotent, err := store.AddFavorite(context.Background(), "user-a", "track-1")
	if err != nil {
		t.Fatalf("idempotent AddFavorite returned error: %v", err)
	}
	if idempotent.Revision != first.Revision {
		t.Fatalf("idempotent revision = %d, want %d", idempotent.Revision, first.Revision)
	}

	created, err := store.CreatePlaylist(context.Background(), "user-a", "  Road   Trip ")
	if err != nil {
		t.Fatalf("CreatePlaylist returned error: %v", err)
	}
	if len(created.Playlists) != 1 || created.Playlists[0].Name != "Road Trip" {
		t.Fatalf("created playlists = %#v", created.Playlists)
	}
	playlistID := created.Playlists[0].ID
	withTrack, err := store.AddPlaylistTrack(context.Background(), "user-a", playlistID, "track-2")
	if err != nil {
		t.Fatalf("AddPlaylistTrack returned error: %v", err)
	}
	if withTrack.Revision != 3 {
		t.Fatalf("revision after playlist track = %d, want 3", withTrack.Revision)
	}

	imported, err := store.ImportCollections(context.Background(), "user-a", CollectionsImport{
		FavoriteTrackIDs: []string{"track-1", "track-3"},
		Playlists: []Playlist{
			{ID: playlistID, Name: "ignored old name", TrackIDs: []string{"track-2", "track-4"}},
			{Name: "Archive", TrackIDs: []string{"track-5"}},
		},
	})
	if err != nil {
		t.Fatalf("ImportCollections returned error: %v", err)
	}
	if imported.Revision != 4 {
		t.Fatalf("import revision = %d, want 4", imported.Revision)
	}
	if !reflect.DeepEqual(imported.FavoriteTrackIDs, []string{"track-1", "track-3"}) {
		t.Fatalf("favorites = %#v", imported.FavoriteTrackIDs)
	}
	if len(imported.Playlists) != 2 {
		t.Fatalf("playlist count = %d, want 2", len(imported.Playlists))
	}
	if !reflect.DeepEqual(imported.Playlists[0].TrackIDs, []string{"track-2", "track-4"}) {
		t.Fatalf("merged playlist tracks = %#v", imported.Playlists[0].TrackIDs)
	}
	if imported.Playlists[1].ID == "" || imported.Playlists[1].CreatedAt.IsZero() {
		t.Fatalf("imported playlist = %#v, want generated ID and timestamps", imported.Playlists[1])
	}

	replayed, err := store.ImportCollections(context.Background(), "user-a", CollectionsImport{
		FavoriteTrackIDs: []string{"track-1", "track-3"},
		Playlists: []Playlist{
			{ID: playlistID, Name: "ignored old name", TrackIDs: []string{"track-2", "track-4"}},
			{Name: "Archive", TrackIDs: []string{"track-5"}},
		},
	})
	if err != nil {
		t.Fatalf("replayed ImportCollections returned error: %v", err)
	}
	if replayed.Revision != imported.Revision {
		t.Fatalf("replayed revision = %d, want %d", replayed.Revision, imported.Revision)
	}

	restarted, err := NewStore(store.dataDir, WithNow(func() time.Time { return now }))
	if err != nil {
		t.Fatalf("restart NewStore returned error: %v", err)
	}
	persisted, err := restarted.Collections(context.Background(), "user-a")
	if err != nil {
		t.Fatalf("persisted Collections returned error: %v", err)
	}
	if !reflect.DeepEqual(persisted, imported) {
		t.Fatalf("persisted snapshot = %#v, want %#v", persisted, imported)
	}
	otherUser, err := restarted.Collections(context.Background(), "user-b")
	if err != nil {
		t.Fatalf("other user Collections returned error: %v", err)
	}
	if otherUser.Revision != 0 || len(otherUser.FavoriteTrackIDs) != 0 || len(otherUser.Playlists) != 0 {
		t.Fatalf("other user snapshot = %#v, want empty", otherUser)
	}
}

func TestStorePlaybackModePersists(t *testing.T) {
	dataDir := t.TempDir()
	store, err := NewStore(dataDir)
	if err != nil {
		t.Fatalf("NewStore returned error: %v", err)
	}

	initial, err := store.PlaybackMode(context.Background(), "user-a")
	if err != nil {
		t.Fatalf("PlaybackMode returned error: %v", err)
	}
	if initial.Revision != 0 || initial.Mode != PlaybackModeSequential {
		t.Fatalf("initial playback mode = %#v, want sequential revision 0", initial)
	}

	updated, err := store.SetPlaybackMode(context.Background(), "user-a", PlaybackModeRepeatOne)
	if err != nil {
		t.Fatalf("SetPlaybackMode returned error: %v", err)
	}
	if updated.Revision != 1 || updated.Mode != PlaybackModeRepeatOne {
		t.Fatalf("updated playback mode = %#v, want repeat_one revision 1", updated)
	}
	repeated, err := store.SetPlaybackMode(context.Background(), "user-a", PlaybackModeRepeatOne)
	if err != nil {
		t.Fatalf("repeated SetPlaybackMode returned error: %v", err)
	}
	if !reflect.DeepEqual(repeated, updated) {
		t.Fatalf("repeated playback mode = %#v, want %#v", repeated, updated)
	}
	if _, err := store.SetPlaybackMode(context.Background(), "user-a", PlaybackMode("smart")); !errors.Is(err, ErrInvalidPlaybackMode) {
		t.Fatalf("invalid SetPlaybackMode error = %v, want ErrInvalidPlaybackMode", err)
	}

	restarted, err := NewStore(dataDir)
	if err != nil {
		t.Fatalf("restart NewStore returned error: %v", err)
	}
	persisted, err := restarted.PlaybackMode(context.Background(), "user-a")
	if err != nil {
		t.Fatalf("persisted PlaybackMode returned error: %v", err)
	}
	if !reflect.DeepEqual(persisted, updated) {
		t.Fatalf("persisted playback mode = %#v, want %#v", persisted, updated)
	}
}

func TestStoreListeningEventsArePersistentAndIdempotent(t *testing.T) {
	now := time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC)
	dataDir := t.TempDir()
	store, err := NewStore(dataDir, WithNow(func() time.Time { return now }))
	if err != nil {
		t.Fatalf("NewStore returned error: %v", err)
	}
	events := []ListeningEvent{
		{
			EventID:    "event-1",
			TrackID:    "track-a",
			ListenedMS: 100,
			Completed:  true,
			PlayedAt:   time.Date(2026, 1, 2, 8, 0, 0, 0, time.UTC),
		},
		{
			EventID:    "event-2",
			TrackID:    "track-a",
			ListenedMS: 50,
			PlayedAt:   time.Date(2026, 1, 2, 9, 0, 0, 0, time.UTC),
		},
		{
			EventID:    "event-3",
			TrackID:    "track-b",
			ListenedMS: 70,
			Completed:  true,
			PlayedAt:   time.Date(2025, 12, 31, 23, 0, 0, 0, time.UTC),
		},
		{
			EventID:    "event-4",
			TrackID:    "track-c",
			ListenedMS: 80,
			PlayedAt:   now.Add(-time.Hour),
		},
	}
	result, err := store.RecordEvents(context.Background(), "user-a", events)
	if err != nil {
		t.Fatalf("RecordEvents returned error: %v", err)
	}
	if result.Accepted != 4 || result.Duplicates != 0 {
		t.Fatalf("result = %#v, want four accepted events", result)
	}
	duplicate, err := store.RecordEvents(context.Background(), "user-a", []ListeningEvent{events[0]})
	if err != nil {
		t.Fatalf("duplicate RecordEvents returned error: %v", err)
	}
	if duplicate.Accepted != 0 || duplicate.Duplicates != 1 {
		t.Fatalf("duplicate result = %#v", duplicate)
	}

	report, err := store.ListeningReport(context.Background(), "user-a", 2026)
	if err != nil {
		t.Fatalf("ListeningReport returned error: %v", err)
	}
	if report.TotalPlays != 3 || report.TotalListenedMS != 230 || report.ListeningDays != 2 || report.UniqueTracks != 2 {
		t.Fatalf("report = %#v", report)
	}
	if len(report.Heatmap) != 2 || report.Heatmap[0].Date != "2026-01-02" {
		t.Fatalf("heatmap = %#v", report.Heatmap)
	}
	if len(report.TrackMetrics) != 2 || report.TrackMetrics[0].TrackID != "track-a" || report.TrackMetrics[0].PlayCount != 2 {
		t.Fatalf("track metrics = %#v", report.TrackMetrics)
	}
	recent, err := store.RecentEvents(context.Background(), "user-a", now.Add(-90*24*time.Hour))
	if err != nil {
		t.Fatalf("RecentEvents returned error: %v", err)
	}
	if len(recent) != 1 || recent[0].EventID != "event-4" {
		t.Fatalf("recent events = %#v", recent)
	}

	restarted, err := NewStore(dataDir, WithNow(func() time.Time { return now }))
	if err != nil {
		t.Fatalf("restart NewStore returned error: %v", err)
	}
	afterRestart, err := restarted.RecordEvents(context.Background(), "user-a", []ListeningEvent{events[0]})
	if err != nil {
		t.Fatalf("post-restart duplicate RecordEvents returned error: %v", err)
	}
	if afterRestart.Accepted != 0 || afterRestart.Duplicates != 1 {
		t.Fatalf("post-restart duplicate result = %#v", afterRestart)
	}
	hot, err := restarted.HotTrackMetrics(context.Background())
	if err != nil {
		t.Fatalf("HotTrackMetrics returned error: %v", err)
	}
	if len(hot) != 3 || hot[0].TrackID != "track-a" || hot[0].PlayCount != 2 {
		t.Fatalf("hot metrics = %#v", hot)
	}
}

func TestStoreNormalizesNearFutureEventsAndRejectsDistantFutureEvents(t *testing.T) {
	now := time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC)
	store, err := NewStore(t.TempDir(), WithNow(func() time.Time { return now }))
	if err != nil {
		t.Fatalf("NewStore returned error: %v", err)
	}

	result, err := store.RecordEvents(context.Background(), "user-a", []ListeningEvent{{
		EventID:    "near-future",
		TrackID:    "track-a",
		ListenedMS: 100,
		PlayedAt:   now.Add(time.Minute),
	}})
	if err != nil {
		t.Fatalf("RecordEvents near-future event returned error: %v", err)
	}
	if result.Accepted != 1 {
		t.Fatalf("near-future result = %#v, want one accepted event", result)
	}
	recent, err := store.RecentEvents(context.Background(), "user-a", now.Add(-time.Hour))
	if err != nil {
		t.Fatalf("RecentEvents returned error: %v", err)
	}
	if len(recent) != 1 || !recent[0].PlayedAt.Equal(now) {
		t.Fatalf("recent events = %#v, want played_at normalized to %s", recent, now)
	}

	_, err = store.RecordEvents(context.Background(), "user-a", []ListeningEvent{{
		EventID:    "distant-future",
		TrackID:    "track-a",
		ListenedMS: 100,
		PlayedAt:   now.Add(maxFutureEventSkew + time.Nanosecond),
	}})
	if !errors.Is(err, ErrInvalidEvent) {
		t.Fatalf("RecordEvents distant-future error = %v, want %v", err, ErrInvalidEvent)
	}
	recent, err = store.RecentEvents(context.Background(), "user-a", now.Add(-time.Hour))
	if err != nil {
		t.Fatalf("RecentEvents after rejection returned error: %v", err)
	}
	if len(recent) != 1 {
		t.Fatalf("recent event count after rejected event = %d, want 1", len(recent))
	}
}

func TestStorePlaylistIDCreationIsIdempotent(t *testing.T) {
	store, err := NewStore(t.TempDir())
	if err != nil {
		t.Fatalf("NewStore returned error: %v", err)
	}

	created, wasCreated, err := store.CreatePlaylistWithID(context.Background(), "user-a", "client-playlist-1", "Road Trip")
	if err != nil {
		t.Fatalf("CreatePlaylistWithID returned error: %v", err)
	}
	if !wasCreated || len(created.Playlists) != 1 || created.Playlists[0].ID != "client-playlist-1" {
		t.Fatalf("created snapshot = %#v, wasCreated = %t", created, wasCreated)
	}
	retried, wasCreated, err := store.CreatePlaylistWithID(context.Background(), "user-a", "client-playlist-1", "  Road   Trip ")
	if err != nil {
		t.Fatalf("idempotent CreatePlaylistWithID returned error: %v", err)
	}
	if wasCreated || !reflect.DeepEqual(retried, created) {
		t.Fatalf("retry snapshot = %#v, wasCreated = %t, want %#v and false", retried, wasCreated, created)
	}
	_, _, err = store.CreatePlaylistWithID(context.Background(), "user-a", "client-playlist-1", "Different Name")
	if !errors.Is(err, ErrPlaylistConflict) {
		t.Fatalf("conflicting CreatePlaylistWithID error = %v, want %v", err, ErrPlaylistConflict)
	}
}

func TestStoreReturnsDirectorySyncFailure(t *testing.T) {
	store, err := NewStore(t.TempDir())
	if err != nil {
		t.Fatalf("NewStore returned error: %v", err)
	}
	store.syncDir = func(string) error {
		return errors.New("directory sync failed")
	}

	_, err = store.AddFavorite(context.Background(), "user-a", "track-a")
	if err == nil || !strings.Contains(err.Error(), "directory sync failed") {
		t.Fatalf("AddFavorite error = %v, want directory sync failure", err)
	}
	snapshot, err := store.Collections(context.Background(), "user-a")
	if err != nil {
		t.Fatalf("Collections returned error: %v", err)
	}
	if snapshot.Revision != 0 || len(snapshot.FavoriteTrackIDs) != 0 {
		t.Fatalf("snapshot after failed persistence = %#v, want unchanged", snapshot)
	}
}

func TestStoreRejectsOversizedEventBatch(t *testing.T) {
	store, err := NewStore(t.TempDir())
	if err != nil {
		t.Fatalf("NewStore returned error: %v", err)
	}
	events := make([]ListeningEvent, 51)
	for index := range events {
		events[index] = ListeningEvent{
			EventID:    "event-" + string(rune('a'+index)),
			TrackID:    "track",
			ListenedMS: 1,
			PlayedAt:   time.Now(),
		}
	}
	if _, err := store.RecordEvents(context.Background(), "user-a", events); err != ErrInvalidEvent {
		t.Fatalf("RecordEvents error = %v, want %v", err, ErrInvalidEvent)
	}
}
