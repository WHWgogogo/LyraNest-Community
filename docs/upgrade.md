# Upgrade Guide

1. Back up `DATA_DIR` before upgrading.
2. Pull or copy the new community edition source.
3. Rebuild and restart:

```bash
docker compose down
docker compose up -d --build
```

4. Open the Web UI and confirm login, library scan status, favorites and playlists.

Do not overwrite your music directory or data directory during upgrade.
