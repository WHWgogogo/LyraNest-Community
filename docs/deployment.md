# Deployment

## Docker Compose

1. Put music files in a host directory, for example `/srv/music`.
2. Create persistent data directory, for example `/srv/lyranest/data`.
3. Start the service:

```bash
cd deploy
MUSIC_LIBRARY_HOST_DIR=/srv/music DATA_DIR=/srv/lyranest/data SERVER_PORT=8080 docker compose up -d --build
```

The Go server serves both API and embedded Web UI on the same port.

## Directory Configuration

- `MUSIC_LIBRARY_HOST_DIR`: mounted read-only to `/music`.
- `DATA_DIR`: mounted read-write to `/data` and stores accounts, sessions, favorites, playlists and scan index.

## First Run

Open `http://SERVER_IP:SERVER_PORT`, create the administrator account and run a library scan from the management page.
