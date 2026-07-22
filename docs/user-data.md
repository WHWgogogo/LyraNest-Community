# User Data Persistence

The server persists authenticated users' collections and listening aggregates separately from the music-library index and authentication files. The state lives in `${MUSIC_DATA_DIR}/user-data-v1.json`; its JSON document has an explicit version and is written through a same-directory temporary file, `fsync`, atomic rename, and directory sync.

## Synchronization

`GET /api/v1/me/collections` is the authoritative multi-device snapshot. Every collection mutation returns the complete replacement snapshot:

```json
{
  "revision": 4,
  "favorite_track_ids": ["track-a"],
  "playlists": [
    {
      "id": "playlist-id",
      "name": "Road trip",
      "track_ids": ["track-a", "track-b"],
      "created_at": "2026-07-20T10:00:00Z",
      "updated_at": "2026-07-20T10:05:00Z"
    }
  ]
}
```

The import endpoint unions favorites and playlist tracks. It uses playlist IDs to recognize an existing playlist; an imported playlist with no ID receives a deterministic ID, so retries of unchanged legacy data do not create duplicates.

## Listening Aggregates

Listening events are accepted in batches of up to 50 and deduplicated by `event_id` per authenticated user before aggregates are updated. The store retains:

- daily totals and per-track yearly totals for reports and popular tracks;
- the latest 90 days of events for personalized ranking;
- a bounded receipt ledger for idempotent retry handling.

Discovery uses the same per-track aggregate counters as reports for `hot_tracks`. Personalized ranks weight the last 90 days of artist and genre affinity, completion, and exponential recency decay. The daily list is deterministic for the same user and UTC date.

## Container Limits

The data document is capped at 16 MiB, with limits of 5,000 favorites, 250 playlists, 5,000 tracks per playlist, 25,000 per-track/year aggregate entries, 5,000 retained recent events, and 50,000 receipt IDs per user. The user store uses an in-process read/write lock and keeps bounded state, which fits the deployment's 256 MiB container limit when `GOMEMLIMIT=192MiB` is retained.
