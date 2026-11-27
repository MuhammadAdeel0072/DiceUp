# Authentication

## Token model

- **Access token:** RS256 JWT, 15 min (NFR-15), claims `sub` /
  `role: 'player'` / `email_verified` / `sid`. `sid` is the
  `auth_sessions` row id — the session-revocation check runs on
  **every** authenticated request (`JwtStrategy.validate`) and on
  **every** socket message (`WsJwtGuard`). It is load-bearing and
  must not be optimised away: logout (or any revocation) takes
  effect immediately, within the 15-minute access-token window.
- **Refresh token:** opaque 256-bit token, SHA-256 hashed at rest in
  `auth_sessions`, 30 days (`[P4 choice]` — the SDD names no refresh
  TTL). Rotated on every use; reuse of a presented refresh token
  revokes the whole token family (`auth_sessions.family_id`).
- **Email tokens:** 256-bit, hashed at rest, single-use. Verification
  24 h, password reset 1 h. Partial unique index
  `(user_id, purpose) WHERE used_at IS NULL` guarantees at most one
  live token per purpose.
- **Passwords:** Argon2id, 64 MiB / 3 iterations / parallelism 1
  (SDD §13.1, OWASP baseline `[Proposed]`), per-password salt.
  `password_hash` is never selected by any read query except the
  dedicated auth path, never serialised (DTO allow-list), never
  logged (covered by a log test). bcrypt is the documented fallback
  if Argon2 cannot run in a deployment — **not** implemented in
  parallel.

## Flows

- **Register** → `POST /auth/register` (201 + user + tokens) →
  verification code by email → `POST /auth/verify-email` (24 h
  window; `POST /auth/verify-email/resend` for a new code).
- **Login** → `POST /auth/login` with email-or-username + password.
  Unverified users *can* log in and resend, but get 403
  `EMAIL_NOT_VERIFIED` on users routes.
- **Refresh** → `POST /auth/refresh` rotates the refresh token and
  returns a new pair.
- **Logout** → `POST /auth/logout` revokes the current session; the
  `sid` check then fails the access token immediately (verified by
  both REST and socket tests).
- **Forgot / reset** → `POST /auth/forgot-password` (neutral 200 even
  for unknown emails) → `POST /auth/reset-password` with the code
  (1 h window); a successful reset revokes **all** sessions.
- **Change password** → `PATCH /users/me/password` (current password
  required); revokes **all** sessions.
- **Deletion request** → `DELETE /users/me` sets the marker and
  revokes sessions. Partial: **no anonymisation** (awaits OD-08).

A daily 03:00 purge job deletes expired sessions and used/expired
email tokens. Revoked-but-unexpired sessions are kept — reuse
detection needs them until they expire.

## Guard chain (REST)

Global `APP_GUARD`s, in order (registered in `AuthModule`):

1. `JwtAuthGuard` — valid access token, unless the route is
   `@Public()`. Public routes are an explicit allow-list (health,
   register, login, refresh, verify-email, resend, forgot/reset).
2. `AccountStatusGuard` — suspended / blocked → 403
   `ACCOUNT_SUSPENDED`; pending deletion request → 403 `FORBIDDEN`.
3. `RolesGuard` — `@Roles('player')` (the only role in Phase 4).
4. `RateLimitGuard` — 100/min per authenticated user.

`UsersController` additionally applies `EmailVerifiedGuard`
(unverified → 403 `EMAIL_NOT_VERIFIED`).

On login, the account-status checks run **after** a correct
password, so a suspended account is indistinguishable from a wrong
password to an unauthenticated prober (no enumeration). Login
failures are throttled at 5 / 15 min per account **and** per IP
(NFR-16), the account counter resets on success while the IP counter
expires naturally after its 15-min TTL (Stage 4, M-03), Redis down fails closed (503).

## Socket authentication

Sockets use the **same** auth path, not a copy: the handshake
middleware in the Socket.IO adapter calls
`WsJwtGuard.authenticate()`, which runs `TokenService.verifyAccessToken`
+ `JwtStrategy.validate` (including the `sid` revocation check) and
then the same account-status / deletion-request / email-verified
rules with the same codes and messages as REST. The guard then
re-validates the stored handshake token on **every** message, so a
session revoked mid-connection fails the next event. Full details
in `08-socket-io.md`.

## Keys

RS256 keys: inline PEM (`JWT_PRIVATE_KEY` / `JWT_PUBLIC_KEY`) or
file paths (`JWT_PRIVATE_KEY_FILE` / `JWT_PUBLIC_KEY_FILE`,
resolved relative to `backend/`). Inline wins when both are set.
Dev: a keypair in `backend/.keys/` (git-ignored, RSA 2048 — see
`02-setup.md`). Dev/test with no keys: the app generates an
ephemeral in-memory keypair at boot (warning logged; tokens die on
restart). Production: boot fails fast without real keys. **Never
commit a key; never use dev keys in production.**

## Mailer

`Mailer` interface (`src/mailer/`), transport selected by
`MAILER_PROVIDER`: unset/`log` (default, dev/test) stores messages
in memory and logs recipient + kind only — never sends real email,
never logs a token; `smtp` sends via nodemailer from
`MAILER_SMTP_HOST` / `MAILER_SMTP_PORT` / `MAILER_SMTP_USER` /
`MAILER_SMTP_PASS` (+ `MAILER_FROM`). Production with anything but
`smtp` fails fast. Verification/reset arrive as a code (no player
web frontend exists in Phase 4 for a link form). Provider selection
is still OPEN (OD-09).
