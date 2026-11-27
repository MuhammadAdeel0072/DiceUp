# REST API documentation

All endpoints live under `/v1` and use the §6.3 envelope
(`01-architecture.md`): success `{ success: true, data }`, error
`{ success: false, error: { code, message, details? } }`. Error
`code` is the machine-readable contract — switch on `code`, never
on message text. `X-Request-Id` is returned on every response.
Swagger (non-production only): `/v1/docs`.

Authenticated requests send the access token as
`Authorization: Bearer <accessToken>`. JSON bodies are limited to
100 KB; unknown fields are stripped (whitelist); malformed JSON →
400 `VALIDATION_FAILED`; oversized body → 413 `PAYLOAD_TOO_LARGE`.

## Health

| Method + endpoint | Auth | Purpose |
|---|---|---|
| `GET /v1/health` | Public | Liveness only. `200 { success: true, data: { status: "ok" } }`. No dependency checks, no version strings, no secrets. |
| `GET /v1/health/ready` | Public | Readiness. `200` only if **both** PostgreSQL (`SELECT 1`) and Redis (`PING`) are up; otherwise `503` with the error envelope and `error.data` naming each dependency (`up`/`down`) plus per-check latency in ms. |

## Auth (`/v1/auth`)

| Method + endpoint | Auth | Rate limit | Purpose |
|---|---|---|---|
| `POST /auth/register` | Public | 10/hr per IP | Register (FR-02). 201 + user + tokens. 409 `EMAIL_TAKEN` / `USERNAME_TAKEN`. |
| `POST /auth/login` | Public | 5 failures / 15 min per account **and** per IP (NFR-16, failure-based; counters reset on success) | Email-or-username + password (FR-04). Wrong credentials → generic 401 `INVALID_CREDENTIALS` (no account enumeration). |
| `POST /auth/refresh` | Public (refresh token in body) | 60/hr per IP | Rotate refresh token (NFR-15); reuse revokes the whole token family. 401 on invalid / reused token. |
| `POST /auth/logout` | Bearer | — | Revoke the current session (FR-05). Returns `{ loggedOut: true }`. |
| `POST /auth/verify-email` | Public | 10/hr per IP | Verify with a single-use code (FR-03). Reuse → 409 `TOKEN_ALREADY_USED`; expired → 410 `TOKEN_EXPIRED`. |
| `POST /auth/verify-email/resend` | Public | 10/hr per IP | Resend verification. Neutral 200 (no leak whether the account exists). |
| `POST /auth/forgot-password` | Public | 5/hr per email (hashed key) | Request reset (FR-06). Neutral 200 even for unknown emails. |
| `POST /auth/reset-password` | Public | 10/hr per IP | Reset with a single-use code (FR-06); revokes all sessions. Reuse → 409; expired → 410. |

All 429s carry a `Retry-After` header. See `07-authentication.md`
for the token model, the guard chain, and the account-state rules.

## Users (`/v1/users`)

All routes require an authenticated, email-verified player
(global `JwtAuthGuard` + `AccountStatusGuard` + controller
`EmailVerifiedGuard` + `@Roles('player')`). All authenticated REST
is additionally rate-limited at 100/min per user.

| Method + endpoint | Purpose |
|---|---|
| `GET /users/me` | Own profile (FR-07). |
| `PATCH /users/me` | Update own display name / avatar (FR-07). Avatar is a key from the bundled set (`default`, `red`, `blue`, `green`, `gold`, `violet`); no uploads. Username: 3–30 chars, `[a-zA-Z0-9_.-]`. |
| `PATCH /users/me/password` | Change password (FR-08). Requires the current password (wrong → 401); revokes all sessions. |
| `PATCH /users/me/preferences` | Update notification preferences (FR-08; JSONB on `profiles`). |
| `GET /users/{id}/profile` | Public profile of another player (FR-63); public fields only. `{id}` must be a UUID (else 400); unknown id → 404. |
| `DELETE /users/me` | Request account deletion (FR-10, **partial**: marker + session revoke; **no anonymisation** — awaits OD-08). |

## Common error codes

| Code | HTTP | Meaning |
|---|---|---|
| `VALIDATION_FAILED` | 400 | DTO validation failed (`details` maps field → messages); also malformed JSON. |
| `UNAUTHORIZED` | 401 | Missing / invalid / expired access token, or revoked session (`sid` check). |
| `FORBIDDEN` | 403 | Authenticated but not allowed (e.g. account has a pending deletion request). |
| `EMAIL_NOT_VERIFIED` | 403 | Unverified user on a route that requires verification. |
| `ACCOUNT_SUSPENDED` | 403 | Suspended / blocked account. On login this is returned only after a correct password, so it cannot enumerate accounts. |
| `NOT_FOUND` | 404 | Resource not found (e.g. public profile). |
| `EMAIL_TAKEN` / `USERNAME_TAKEN` | 409 | Registration conflict. |
| `TOKEN_ALREADY_USED` | 409 | Email token already used. |
| `TOKEN_EXPIRED` | 410 | Email token expired. |
| `PAYLOAD_TOO_LARGE` | 413 | Body over the 100 KB limit (REST) — or socket event over 10 KB (see `08-socket-io.md`). |
| `RATE_LIMITED` | 429 | Rate limit hit; `Retry-After` header present. |
| `SERVICE_UNAVAILABLE` | 503 | A required dependency (Redis) is down, or readiness failed. |
| `INTERNAL_ERROR` | 500 | Unexpected failure (no stack trace or internals in the response). |
