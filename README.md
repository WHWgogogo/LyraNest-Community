# LyraNest Community（律巢社区版社区版）

LyraNest Community is the open-source baseline of LyraNest Community. It focuses on self-hosted music library scanning, authenticated access, browsing, playback, favorites and playlists across Web, Android and Windows clients.

## Included Features

- User registration, login and basic server-side session authentication
- Server URL configuration in the Flutter client
- Music library scanning and track list API
- Browse by all tracks, favorites, albums, artists and playlists
- Basic search by title, artist, album and filename
- Playback controls: play, pause, previous and next
- Queue and playlist playback
- Playback modes: sequential, list loop, single loop and shuffle
- Basic lyric reading and display inside the player
- Favorite synchronization and playlist management
- Embedded Web player served by the Go backend
- Docker Compose deployment with configurable music and data directories
- Health check, backup and upgrade documentation

## Not Included

The community edition intentionally does not include Discovery, listening reports, heatmaps, recommendation algorithms, metadata scraping, desktop lyrics overlays or offline downloads.

## Repository Layout

```text
api/           API notes and OpenAPI draft
apps/player/   Flutter client for Android and Windows
apps/web/      React Web player embedded into the server
server/        Go music server
deploy/        Docker Compose deployment files
docs/          Deployment, backup, health check and upgrade docs
scripts/       Build and verification helpers
```

## Quick Start with Docker Compose

```bash
cd deploy
cp .env.example .env  # optional; create it if you want to override defaults
docker compose up -d --build
```

Open the Web UI:

```text
http://localhost:8080
```

On first launch, create the administrator account, then scan the mounted music folder.

## Docker Compose Example

```yaml
services:
  lyranest-community-server:
    build:
      context: "${SERVER_BUILD_CONTEXT:-../server}"
      dockerfile: "${SERVER_DOCKERFILE:-Dockerfile}"
    image: lyranest-community-server:${SERVER_IMAGE_TAG:-1.0.0}
    container_name: lyranest-community-server
    restart: unless-stopped
    mem_limit: "${SERVER_MEMORY_LIMIT:-256m}"
    mem_reservation: "${SERVER_MEMORY_RESERVATION:-128m}"
    environment:
      SERVER_ADDR: ":8080"
      MUSIC_LIBRARY_DIR: /music
      MUSIC_DATA_DIR: /data
      GOMEMLIMIT: "${GOMEMLIMIT:-192MiB}"
      GOGC: "${GOGC:-100}"
      LOG_LEVEL: "${LOG_LEVEL:-info}"
      SHUTDOWN_TIMEOUT: "${SHUTDOWN_TIMEOUT:-10s}"
      AUTH_SESSION_TTL: "${AUTH_SESSION_TTL:-24h}"
    ports:
      - "${SERVER_PORT:-8080}:8080"
    volumes:
      - "${MUSIC_LIBRARY_HOST_DIR:-./music}:/music:ro"
      - "${DATA_DIR:-./data}:/data:rw"
    healthcheck:
      test: ["CMD", "/usr/local/bin/music-player-server", "healthcheck"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 60s
```

### Configurable Values

- `SERVER_PORT`: host port, default `8080`.
- `MUSIC_LIBRARY_HOST_DIR`: host music directory, default `./music`.
- `DATA_DIR`: host data directory, default `./data`.
- `SERVER_MEMORY_LIMIT`: Docker memory limit, default `256m`.
- `AUTH_SESSION_TTL`: login session lifetime, default `24h`.

## Development Verification

```bash
cd server
go test ./...

cd ../apps/web
npm install
npm run build

cd ../player
flutter analyze
```

## Documentation

- `docs/deployment.md`: deployment guide
- `docs/backup.md`: data backup and restore
- `docs/health-check.md`: health check and troubleshooting
- `docs/upgrade.md`: safe upgrade process
