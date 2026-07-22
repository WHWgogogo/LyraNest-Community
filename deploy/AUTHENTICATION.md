# Server authentication deployment

The server stores authentication state inside `MUSIC_DATA_DIR` alongside the existing music index. The Docker Compose default bind mount is `${DATA_DIR:-./data}:/data`, so these files survive container replacement:

- `tracks.json` and `metadata-overrides.json`: existing music data, unchanged by authentication setup.
- `auth-users.json`: versioned user database containing salted password hashes only.
- `auth-sessions.json`: active server-side sessions containing HMAC token digests, never raw bearer tokens.
- `auth.key`: a generated 32-byte HMAC key used to protect session token lookups.

## Upgrade an existing deployment

1. Keep the existing host `DATA_DIR` mounted at `/data`.
2. Deploy the new server image. Existing music index and metadata override files remain in place and keep their current format.
3. Call `GET /api/v1/auth/setup`. A deployment with no users returns `register_allowed: true`.
4. Call `POST /api/v1/auth/register` once to create the administrator. The server atomically closes registration after the first successful user creation.
5. Log in and send `Authorization: Bearer <token>` to protected API routes.

Do not delete or regenerate `auth.key` while sessions are active. Losing the key invalidates all persisted sessions; losing `auth-users.json` reopens first-administrator registration.

`AUTH_SESSION_TTL` controls session lifetime and defaults to `24h`. Back up the entire host `DATA_DIR` together so music data, users, sessions, and the key remain consistent.
