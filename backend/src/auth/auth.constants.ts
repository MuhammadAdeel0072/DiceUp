/**
 * Auth constants (plan §7.1 / §6.5).
 *
 * SDD-prescribed values are marked as such; values the SDD leaves
 * silent are flagged [P4 choice] and are one-line changes.
 */
export const ACCESS_TOKEN_TTL_SECONDS = 900; // 15 min, NFR-15 (SDD §12.4)

/** Refresh-token lifetime. [P4 choice] — the SDD names no refresh TTL. */
export const REFRESH_TOKEN_TTL_DAYS = 30;

/** Email-verification token lifetime, 24 h [Proposed] (SDD §13.1). */
export const EMAIL_VERIFY_TOKEN_TTL_HOURS = 24;

/** Password-reset token lifetime, 1 h [Proposed] (SDD §13.1). */
export const PASSWORD_RESET_TOKEN_TTL_HOURS = 1;

/** Argon2id parameters (SDD §13.1, OWASP baseline [Proposed]). */
export const ARGON2_MEMORY_KIB = 64 * 1024; // 64 MiB
export const ARGON2_TIME_COST = 3;
export const ARGON2_PARALLELISM = 1;

/** NFR-16: 5 consecutive failed logins in 15 min, same account or IP. */
export const LOGIN_MAX_FAILURES = 5;
export const LOGIN_THROTTLE_WINDOW_SECONDS = 15 * 60;

/** Rate limits (plan §6.5). NFR-16 is failure-based (LoginThrottleService);
 * the rest are per-attempt limits enforced by RateLimitGuard. */
export const RATE_LIMITS = {
  /** POST /auth/register — 10/hour per IP [P4 choice]. */
  register: { limit: 10, windowSeconds: 3600, windowLabel: '1h' },
  /** POST /auth/forgot-password — 5/hour per email [P4 choice]. */
  forgotPassword: { limit: 5, windowSeconds: 3600, windowLabel: '1h' },
  /** POST /auth/reset-password, verify-email, resend — 10/hour per IP. */
  tokenEndpoint: { limit: 10, windowSeconds: 3600, windowLabel: '1h' },
  /** POST /auth/refresh — 60/hour per IP [P4 choice]. */
  refresh: { limit: 60, windowSeconds: 3600, windowLabel: '1h' },
  /** All authenticated REST — 100/min per user (SDD §13.4). */
  authenticated: { limit: 100, windowSeconds: 60, windowLabel: '1m' },
} as const;

/** Avatar keys — the bundled set (SDD §5.1.9 "from a bundled set
 * [Proposed]", no keys enumerated). [P4 choice] set; no uploads. */
export const AVATAR_KEYS = [
  'default',
  'red',
  'blue',
  'green',
  'gold',
  'violet',
] as const;

/** Username allow-list pattern (SDD §13.4). 3–30 chars, letters/digits/._- */
export const USERNAME_PATTERN = /^[a-zA-Z0-9_.-]{3,30}$/;
