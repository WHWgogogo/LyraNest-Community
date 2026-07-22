# Roadmap

## Phase 0: Foundation

- Define the OpenAPI contract for health, tracks, lyrics, and unified errors.
- Build the Go server skeleton around `/healthz`, versioned `/api/v1` routes, and request IDs.
- Add Docker Compose for local deployment with read-only music, persistent data, cache, and health checks.
- Create Flutter shell screens for library list, track detail, playback queue, and lyrics display.

## Phase 1: Local Library MVP

- Implement filesystem scanning for common audio formats such as MP3, FLAC, M4A, OGG, and WAV.
- Extract embedded metadata, artwork, technical audio fields, and embedded lyrics.
- Match sidecar `.lrc` and `.txt` lyrics with deterministic precedence rules.
- Add incremental rescans based on file modified time, size, and content fingerprints.
- Provide fast local search and pagination for tracks, artists, albums, and albums artists.

## Phase 2: Metadata Quality

- Integrate MusicTag-style scraping workflows for album, artist, artwork, release year, genre, and track number enrichment.
- Keep scraped metadata staged so users can review before overwriting local tags or normalized database fields.
- Cache provider responses with source attribution, confidence, and refresh timestamps.
- Add duplicate detection and manual merge tools for albums and artists.

## Phase 3: Protocol Compatibility

- Add Navidrome-compatible behavior where it improves ecosystem interoperability.
- Implement OpenSubsonic-compatible endpoints for clients that expect Subsonic-style browsing, search, cover art, lyrics, and streaming.
- Map internal track, album, artist, and playlist models to protocol-specific response shapes without leaking internal storage IDs.
- Maintain OpenAPI-first endpoints as the primary native client contract.

## Phase 4: Multi-User Library

- Add user accounts, sessions, API tokens, and role-based access controls.
- Separate global library metadata from per-user favorites, playlists, ratings, recently played, and playback progress.
- Add admin controls for scan roots, provider credentials, user management, and background jobs.
- Define privacy boundaries for listening history and shared playlists.

## Phase 5: Streaming and Transcoding

- Add byte-range streaming for direct playback of supported source files.
- Introduce on-demand transcoding for unsupported formats, bandwidth limits, and mobile-friendly bitrates.
- Cache transcoded segments with eviction policies tied to disk limits and source fingerprints.
- Expose client capability negotiation so Flutter, OpenSubsonic, and browser clients can request appropriate formats.

## Phase 6: Cross-Platform Polish

- Add Android media session integration, notification controls, lock-screen metadata, and audio focus handling.
- Add Windows desktop lyrics, global shortcuts, media keys, and system media transport controls.
- Improve offline client cache behavior for metadata, artwork, lyrics, and recently played items.
- Add observability for scan jobs, scrape jobs, transcoding queues, API latency, and health dependencies.

## Phase 7: Automation and Extensibility

- Add scheduled rescans, scheduled metadata refresh, and cache cleanup jobs.
- Add plugin-style provider interfaces for lyrics, metadata, artwork, and future recommendation sources.
- Add export and import for playlists, ratings, user preferences, and normalized metadata snapshots.
- Publish deployment examples for single-user desktop, homelab server, and LAN sharing setups.
