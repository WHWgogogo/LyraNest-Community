# Backup and Restore

## What to Back Up

Back up the directory mapped to `DATA_DIR`. It contains:

- user accounts and sessions
- favorites
- playlists
- scan index

Music files are not copied into `DATA_DIR`; back up your music library separately.

## Backup

```bash
docker compose down
tar -czf lyranest-community-data-backup.tar.gz ./data
docker compose up -d
```

## Restore

```bash
docker compose down
rm -rf ./data
tar -xzf lyranest-community-data-backup.tar.gz
docker compose up -d
```
