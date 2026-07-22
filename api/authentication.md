# Authentication API

All `/api/**` routes require `Authorization: Bearer <token>` except:

- `GET /healthz`
- `GET /api/v1/auth/setup`
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET` and `HEAD` track artwork and stream routes

## Bootstrap

`GET /api/v1/auth/setup` returns whether the server already has a user. Registration is available only while the user database is empty.

Create the first administrator with `POST /api/v1/auth/register`:

```json
{"username":"admin","password":"a password with at least 12 characters"}
```

The first successful request creates an `admin` user. Every later registration attempt returns `403 Forbidden`. Passwords are stored with PBKDF2-HMAC-SHA-256, a random 128-bit salt, and 600,000 iterations because the existing offline Go dependency set does not include Argon2id or bcrypt.

## Sessions

`POST /api/v1/auth/login` accepts the same JSON shape and returns an opaque bearer token, its expiry, and the user. Raw tokens are returned once and are never persisted by the server.

`GET /api/v1/auth/me` returns the authenticated user. `POST /api/v1/auth/logout` removes the persisted session and immediately revokes the presented token.

Authentication failures return `401 Unauthorized` with `WWW-Authenticate: Bearer`. Login responses set `Cache-Control: no-store`.
