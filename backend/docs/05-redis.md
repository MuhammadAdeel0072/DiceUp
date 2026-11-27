# Redis setup guide

Redis 7 via `ioredis`, behind `RedisService` (`src/redis/`) — the
only Redis API the app uses. No business truth is ever stored only
in Redis (CI-05): Redis holds counters and locks that PostgreSQL can
rebuild, plus the Socket.IO adapter's pub/sub channels.

## Local setup

```bash
redis-server --daemonize yes --port 6379 --save '' --appendonly no \
  --protected-mode yes --bind 127.0.0.1
redis-cli ping         # expect: PONG
```

Localhost only, no persistence, no password. `REDIS_URL` for dev:
`redis://127.0.0.1:6379`.

## RedisService API

- `ping()` / `get()` / `set()` / `del()` — basic operations.
- `incrWithExpiry(key, ttlSeconds)` — atomic Lua `INCR` + `EXPIRE`
  (first increment sets the TTL); the primitive behind every
  rate-limit counter.
- `acquireLock(key, token, ttlSeconds)` / `releaseLock(key, token)` —
  `SET NX EX` with a token-checked release (Lua). The lock helper
  exists; no Phase 4 caller uses it yet (match locks are Phase 5).

## Key registry (`src/redis/redis-keys.ts`)

Every key pattern is named here so later phases do not invent
conflicting names. Only the rate-limit keys are written in Phase 4;
the rest are named only.

| Key | Written in Phase 4? | Purpose |
|---|---|---|
| `ratelimit:{userId\|ip}:{window}` | Yes | REST rate-limit counters. |
| `ratelimit:login:{accountOrIp}:15m` | Yes | Login throttle (NFR-16). |
| `ratelimit:socket:{socketId}:1s` | Yes | Socket event rate limit (20/s). |
| `presence:user:{userId}` | No — Phase 6 (FR-61) | Presence. |
| `matchmaking:queue` | No — Phase 5 (FR-45) | Matchmaking queue. |
| `match:lock:{matchId}` | No — Phase 5 (FR-50/53) | Match lock. |
| `match:state:{matchId}` | No — Phase 5 (FR-57) | Match snapshot cache (PostgreSQL is the truth). |
| `room:code:{code}` | No — Phase 5 (FR-43/44) | Room lookup by code. |

## Socket.IO adapter clients

The Socket.IO Redis adapter uses its own dedicated ioredis pub/sub
pair (`SocketRedisClients`, `src/socket/`): one publisher and one
subscriber (`sub = pub.duplicate()`), separate from the
`RedisService` client. They disconnect in `onApplicationShutdown`,
after the Socket.IO server has closed — see `08-socket-io.md` for
why that ordering is load-bearing. Unlike the `RedisService` client
(`maxRetriesPerRequest: 3`), the adapter pair uses
`maxRetriesPerRequest: null` — Stage 4, H-01: the adapter issues
SUBSCRIBE internally without a rejection handler, so a numeric limit
made a dead Redis kill the process with an unhandled
MaxRetriesPerRequestError in <1 s. With `null` the commands queue
until Redis answers, the app boots degraded, and the adapter recovers
when Redis returns. Shutdown awaits on these clients are bounded by a
2 s timeout each, so a dead Redis cannot hang `app.close()` either.

## Failure policy (SDD §9.4)

- Redis down → auth writes fail closed; the socket rate-limit guard
  fails closed (`SERVICE_UNAVAILABLE`); the login throttle fails
  closed (503).
- PostgreSQL-backed reads keep working (fail-open for reads).
- Readiness (`GET /v1/health/ready`) reports `redis: down` and
  returns 503.

There is no Redis persistence, replication, or Sentinel configured
in this environment — that is a deployment decision for later.
