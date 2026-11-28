# DiceUp load / concurrency harness (Stage 8, NFR-05/06/24)

Drives real clients against a running dev server: seeded verified users
log in over HTTP, connect to `/game` with `socket.io-client`, create/join
rooms, start matches and play rolls/moves, while the harness records
connected clients, `match:started` rate, intent round-trip latency
(p50/p95) and error/rejected/429 rates at each ramp step. It also runs
the three known concurrency cases once, at small scale:

- duplicate `requestId` replay (FR-53): roll + move return the original
  result, no second `move_events` row;
- simultaneous intents: two rolls at once, exactly one wins
  (one `dice:rolled`, one `action:rejected` `INVALID_STATE`, one row);
- 10 concurrent joins on the last seat: exactly 1 wins, 9 get
  `ROOM_FULL`, room ends with 2 members.

## Run

From `backend/` (uses `backend/node_modules`: `socket.io-client`, `pg`,
`argon2`, `ioredis`, `dotenv` — no new dependencies):

```sh
node test/load/load-test.js [--steps 50,100,250,500] [--rolls 2] \
  [--base-url http://127.0.0.1:3000]
```

`--checks-only` runs the seed + concurrency checks + live `startedAt`
probe and skips the ramp (fast iteration on the checks). `--run-id`
pins the seeded-user namespace; the default is fresh per invocation.
Re-running a ramp with the SAME `--run-id` reuses users that already
own rooms, and room creation then 409s (`ALREADY_IN_ROOM`) by design —
use a fresh `--run-id` (or none) for repeat ramp runs. Check/probe
users are always seeded under a timestamped namespace, so the checks
stay fresh even on a reused `--run-id`.

Known wart: the seed lookup uses `LIKE 'load_<run-id>_%'`, so a
`--run-id` that is a prefix of an earlier run's id (e.g. `stage8`
after `stage8smoke`) also matches that run's users. Prefer a
run-id that is not a prefix of any earlier one; the ramp itself is
unaffected (fresh users sort first), but the counts will include the
older rows.

The dev server must be running (`node dist/main.js`, port 3000) against
the live scratch DB. Exit code 0 = every concurrency check passed;
1 = a check failed; 2 = harness fatal error. Ramp steps never fail the
run on latency alone — they report.

## What it measures (per step)

`players`, `connected`, `matchesStarted`, `matchStartedRate` (matches/s),
intent latency `p50`/`p95`/`max` (roll/move emit → broadcast receipt),
`errors`, `action:rejected` count, server CPU/RSS before/after
(`ps` on the `node dist/main.js` pid), load average, step duration.
A full JSON report is printed at the end.

## Deliberate limits (read before quoting numbers)

- **Users are seeded, not registered.** Verification tokens are never
  logged and never leave the server, so an external harness cannot
  complete verify-email. Users are inserted directly in the live
  scratch DB (verified, one shared Argon2id hash of `LoadPass!1`,
  same params as `PasswordHasherService`). Register itself is
  smoke-tested (5 POSTs, latency + status); register → verify → login
  is covered by the e2e suite.
- **The 120/min/IP socket-connection limit (L-02) is a product
  control.** All load clients come from 127.0.0.1, so the harness
  clears `ratelimit:socket-conn-ip:127.0.0.1:1m` between connect waves
  (and all `ratelimit:*` keys between phases). Without the clears,
  connects past 120/min would be refused by design — that refusal is
  the product working, not a load failure.
- **Rows are left in the live scratch DB** (users, rooms, matches,
  `move_events`). The Flutter gate truncates the live tables before
  its run.
- **Turns are server-paced, not bot-paced.** Each match plays
  `--rolls` rounds (default 2); a roll is followed by a
  `state:request` to learn the phase, then a move if one is pending.
  Intent latency is emit → broadcast receipt on the actor's socket.
- **Settle waits.** After each step the harness waits (up to 180 s)
  for `in_progress` matches to resolve via turn-timer forfeits, so
  the next step measures a quiet server. Settle times are reported.
- **The VM is 1.5 shared CPUs.** Where the ramp degrades, the report
  says whether the limit looks like the VM or the server; 500 was
  the target, not a promise — the highest clean step is the result.
