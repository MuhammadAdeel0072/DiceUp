/**
 * Redis key registry (plan §5.3, SDD §9.4). The only Phase 4 writes are
 * rate-limit / login-throttle counters. Every other pattern is named
 * here so later phases do not invent conflicting names — no Phase 4
 * code reads or writes the preparation-only keys.
 */
export const REDIS_KEYS = {
  /** REST + socket rate-limit counters: ratelimit:{userId|ip}:{window} */
  rateLimit: (subject: string, window: string) =>
    `ratelimit:${subject}:${window}`,
  /** Login throttle (NFR-16): ratelimit:login:{accountOrIp}:15m */
  loginThrottle: (subject: string) => `ratelimit:login:${subject}:15m`,
  /** Socket event rate limit (NFR-20): ratelimit:socket:{socketId}:1s */
  socketRateLimit: (socketId: string) => `ratelimit:socket:${socketId}:1s`,
  /** Phase 6 (FR-61) — defined only, no writes in Phase 4. */
  presenceUser: (userId: string) => `presence:user:${userId}`,
  /** Phase 5 (FR-45) — defined only. */
  matchmakingQueue: 'matchmaking:queue',
  /** Phase 5 (FR-50/53) — lock helper exists; no caller yet. */
  matchLock: (matchId: string) => `match:lock:${matchId}`,
  /** Phase 5 (FR-57) — snapshot cache only; PostgreSQL is the truth. */
  matchState: (matchId: string) => `match:state:${matchId}`,
  /** Phase 5 (FR-43/44) — defined only. */
  roomCode: (code: string) => `room:code:${code}`,
} as const;
