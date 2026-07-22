# Health Check

## Docker Health

```bash
docker compose ps
```

The container health check runs:

```bash
/usr/local/bin/music-player-server healthcheck
```

## HTTP Health

```bash
curl http://localhost:8080/healthz
```

Expected response:

```json
{"status":"ok"}
```

## Common Checks

- Verify `SERVER_PORT` is not occupied.
- Verify `MUSIC_LIBRARY_HOST_DIR` exists and is readable by Docker.
- Verify `DATA_DIR` is writable.
- Check logs with `docker compose logs -f lyranest-community-server`.
