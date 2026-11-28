# DiceUp Phase 5 — Plan (as built)

**Phase:** 5 — Online Multiplayer Gameplay
**Branch (staged, unpushed):** `feature/online-phase-5-gameplay`
**Base:** `implementation/foundation-phase-2-3` tip `ba0d37c`
**Base commit in this repo:** `367f573` ("chore(phase5): base tree from
implementation/foundation-phase-2-3 at ba0d37c") — the staging repo was
built by file copy, not by clone, so `ba0d37c` is **not** a local object;
`367f573` is the local commit standing in for it (see §5).
**Assessment:** `docs/PHASE-5-ASSESSMENT.md` (Stage 1, commit `1ba404b`)
**Traceability:** `docs/PHASE-5-TRACEABILITY.md` (Stage 9)
**API / socket supplement:** `backend/docs/11-phase5-online-api.md` (Stage 9)

## 1. What Phase 5 built

Online multiplayer on the Phase 4 foundation, with **no rework of the
foundation** and **no change to the Dart offline engine**:

- Flutter auth (login / register / verify / forgot / reset / account),
  API client, secure token storage, session restore, silent refresh.
- Rooms (create / join by code / ready / host start / leave / host
  transfer / 10-min sweeper) + matchmaking queue (group of 4, arrival
  order) + lobby / matchmaking screens.
- Server-authoritative TypeScript Ludo engine mirroring the Dart engine
  (D-20: the engine wins on every conflict), with the shared rule vectors
  extended 23 → 39 cases and a Dart/TS parity run on the same file.
- Real-time gameplay over Socket.IO `/game`: `seq` ordering,
  `requestId` idempotency, server-generated dice, `action:rejected`.
- Turn timers (30 s), grace (60 s), missed-turn limit (3), presence,
  disconnect/reconnect, forfeit (BR-15), restart recovery from
  `move_events` replay.
- Flutter online game screen + `OnlineGameController` + connection /
  reconnection UI + ordered event buffer.
- Rate limits L-01 (per-IP flood limit on unauthenticated requests to
  protected routes) and L-02 (socket connection limits 120/min/IP,
  20/min/user); Redis-down gameplay behaviour.
- Load / concurrency harness (`backend/test/load/`): 500 concurrent
  players reached in Stage 8.

Explicitly **not** built (Stage 3 scope): friends / friend-graph
invitations, online history / statistics / leaderboard / ranking,
notifications, admin game config, deep links (`go_router` not adopted).

## 2. Stages

Verification counts below are the coordinator-measured numbers where
stated. Where a stage's counts are not in front of Stage 9, the table says
so rather than inventing a number — the Stage 9 final pass (§4) is the
authoritative re-measurement.

| Stage | Work | Commits (HEAD) | Verification (as measured) |
|---|---|---|---|
| 1 — Assessment | Implementation assessment: buildable on Phase 4, all gameplay unbuilt; six scope decisions recorded | `1ba404b` | Read-only audit; no suites run. Counts in the assessment are as documented in the tree, labelled as such |
| 2 — Auth integration | Flutter auth screens, API client, secure storage, session restore, logout, error states | `7008d8c`, `19c7dff`, `5793d5d` (HEAD `5793d5d`) | Not re-measured in Stage 9 |
| 3 — Rooms + matchmaking | Rooms module + tables + codes + readiness + host transfer + sweeper; matchmaking queue + endpoints; lobby UI | `27c9f72`, `3318e45`, `fd61fa8` (HEAD `fd61fa8`) | Not re-measured in Stage 9 |
| 4 — Authoritative TS engine | Engine module, validation, transitions, shared vectors extended (23 → 39), Dart/TS parity harness; server-authoritative match aggregate with checkpointing + replay | `f5eaf32`, `3733a64`, `1b61022`, `d4d137f` (HEAD `d4d137f`) | Not re-measured in Stage 9 |
| 5 — Real-time multiplayer | Socket event contracts, server-authoritative broadcasts, `seq`/`requestId` discipline, simultaneous-request handling; L-01/L-02 rate limits; Redis-down gameplay behaviour | `5995500`, `397d3a1`, `ec00cc0` (HEAD `ec00cc0`) | Not re-measured in Stage 9 |
| 6 — Recovery + timers | Disconnect/grace/forfeit, `match:state`, restart recovery, turn timers + auto-play; Flutter socket auto-reconnect with back-off | `fb427d3`, `b135041`, `d2bd67a`, `ade6e2f`, `d78ccda` (HEAD `d78ccda`) | Not re-measured in Stage 9 |
| 7 — Flutter integration | Online game screen, controller, connection UI, mode-selection wiring | `39dd035`, `b776f88` (HEAD `b776f88`) | Not re-measured in Stage 9 |
| 8 — Verification + hardening | All backend + Flutter + parity + scenario tests; load/concurrency harness; format/lint/analyze | `26a5cff`, `ec62183`, `5d47cf7` (HEAD `5d47cf7`) | **Coordinator-measured on HEAD `5d47cf7`:** backend unit 324/324 (33 suites); backend e2e 162/162 (15 suites); TS parity spec 42 (39 cases + 3 meta); Dart vector suite 41 (39 + 2); Flutter gate 845/0/0, live tests executed; format/lint/typecheck/build exit 0. Load: 500 concurrent players reached (worker-measured full ramp, log `/tmp/load-full.log`; coordinator independently re-ran the harness at 50 players, exit 0, checks ALL PASS; live `startedAt` Z-suffixed) |
| 9 — Documentation + PR preparation | Traceability + this plan + API/socket supplement; full diff review; final verification pass; tap-gated push plan (§6) | (this stage — HEAD below) | See §4 |

## 3. Environment incidents

- **Two VM rebuilds** during Phase 5 (2026-11-28 ~03:08 and ~05:10 UTC).
  Each rebuild wipes the rootfs: system apt packages do **not** survive
  (postgresql-16, redis-server installed via dpkg are gone afterwards, and
  apt has no usable sources). Only `/home/hatch` persists.
- **Services are user-local under `~/workspace/scratch/` and survive:**
  PostgreSQL 16.4 (user-local build, port 5432), Redis 7.0.15 (source
  build, port 6379), dev server (port 3000). Full restart/reset commands
  are in `~/workspace/scratch/diceup-phase5-service-recovery.md` (not in
  this repo — it describes this VM, not the product).
- There is **no `psql`** on the box; DB inspection uses `/tmp/pgq.js`.
  There is **no Docker and no Android SDK** — never claim an APK build.
- The Khareedo cluster (`~/workspace/scratch/pgdata`) is **STOPPED** —
  leave it stopped; DiceUp owns port 5432 in this VM.
- Live DB for Stage 5 verification:
  `diceup_test_stage5_live_f8dcc36b443c`, 4 migrations. Live-test users
  `live3-{host,guest,mm1..mm4}@example.com` exist and are verified
  out-of-band. Before every full Flutter gate: truncate the live game
  tables + clear `ratelimit:*` keys + delete `matchmaking:queue` (see the
  service-recovery note — the shared `ratelimit:ip:127.0.0.1:1h` key makes
  a full gate run exceed the 10/hr register limit otherwise; a 429 on a
  register assertion after a run is a harness flake, cleared by re-run).

## 4. Stage 9 final verification (measured in Stage 9)

Re-run sequentially on the staged HEAD (see §6 for the HEAD):

- Backend unit (`npm test`): **324 passed, 324 total, 33 suites** —
  matches Stage 8 exactly, no regression.
- Backend e2e (`npm run test:e2e`, the npm script): **162 passed, 162
  total, 15 suites** — matches Stage 8 exactly, no regression.
- TS parity spec (`test/vectors/rules-vectors.parity.spec.ts`): **42
  passed, 42 total** (39 cases + 3 meta) — matches Stage 8.
- Dart vector suite (`flutter test test/vectors/rules_vectors_test.dart`):
  **41 passed, 41 total** (39 + 2) — matches Stage 8.
- Flutter gate (`sh tool/check.sh`, live reset first): **845 passed, 0
  failed, 0 skipped; format / analyze / boundaries / strings all passed;
  "check: all gates passed", exit 0** — matches Stage 8; live tests
  executed against the live DB after the documented reset.
- Backend `format:check` / `lint` / `typecheck` / `build`: **all exit 0**.

No regressions vs Stage 8 on any suite. The load harness was **not**
re-run in Stage 9 (Stage 8 result stands: 500 concurrent players reached,
log `/tmp/load-full.log`).

## 5. Diff review (base `ba0d37c` → HEAD)

Reviewed in Stage 9 as `367f573..HEAD` (the local base commit standing in
for `ba0d37c`, which is not a local object — the staging repo was built by
file copy, so the remote base SHA cannot be diffed locally; the push plan
in §6 verifies the remote base before pushing).

- **138 files changed, +32,248 / −249.**
- **M4.1 overlaps: none.** None of `diceup_app/lib/domain/engine/ludo_game.dart`,
  `settings_screen.dart`, `docs/IMPLEMENTATION-PLAN.md`,
  `docs/TRACEABILITY.md`, `docs/ruleset.md` appears in the diff. The only
  `ruleset` match is the new Phase 5 TypeScript file
  `backend/src/game/ruleset-config.ts` (not an M4.1 file).
- **Secrets: none found** (beyond test-only credentials, see below).
  `backend/.env` and `backend/.keys/` are untracked and git-ignored and
  appear in no manifest, commit, or doc. `.env.example` holds placeholders
  only. Grep over the full diff for tokens/keys/passwords/private-key
  material found only: `LoadPass!1` (load-harness seed password for
  throwaway local accounts), `LivePass!1` (live-test accounts on the local
  scratch DB), and the fake `CorrectHorse!9` (mocked API-client tests).
  These are test-only credentials for throwaway local accounts, documented
  in `docs/PHASE-5-TRACEABILITY.md` §7 — no production secret is committed.
- **Stray files: none.** Every changed file is Phase 5 work: backend
  modules/tests/docs, Flutter online code/tests, `pubspec.yaml` +
  `pubspec.lock` (new deps: `http`, `flutter_secure_storage`,
  `socket_io_client`, `uuid`, `share_plus`), regenerated Linux/macOS
  plugin registrants (expected from the new plugins), the extended
  `rules.json` (23 → 39 cases), and the assessment/plan/traceability docs.
- **Dead code introduced in Phase 5:** one item — the `onlineMatchStarted`
  l10n key exists in `app_en.arb` (+ generated localizations) but is
  referenced by no screen. Documented as a known limitation; removal is a
  follow-up, not a Stage 9 code change. `invitation:received` is **not**
  dead code — it was never built (Stage 3, FR-62).
- **Code problems found: none.** No production-code fix was made in Stage 9
  (docs + diff review + verification only, per the brief).

## 6. Tap-gated push + draft PR plan (DO NOT EXECUTE — awaiting Anti's tap)

**Status: NOT EXECUTED. Push + draft PR await Anti's explicit tap, given
while present. No CI runs exist for unpushed branches.**

1. **Confirm the tap.** Anti must approve this exact push while present.
   The approval expires after roughly 30 minutes; if it lapses, re-present
   and get a fresh tap — an old tap does not carry over.
2. **Branch / base.** Push local branch `feature/online-phase-5-gameplay`
   → base branch `implementation/foundation-phase-2-3`, whose tip is
   `ba0d37c`. Never branch from `main`, never modify `main`, no
   force-push, no history rewrite, no branch deletion.
3. **Create the remote branch from the base NAME, not a SHA.**
   The Phase 4 trap: branch creation takes a branch **name** as its base —
   a SHA argument is silently ignored and the branch lands on the repo
   default (`main`). Create the branch from
   `implementation/foundation-phase-2-3` by name.
4. **Verify the created branch's head is `ba0d37c` BEFORE pushing any
   files.** If the head is anything else, STOP and report — do not push.
5. **Snapshot push-files procedure.** Build a NUL-delimited manifest from
   `git ls-files` (tracked files), excluding
   `*.muse-github-snapshot-sync.json` at every depth, and **NEVER**
   `.github/workflows/` (the GitHub App lacks Workflows read/write; the
   push fails 403). `backend/.env` and `backend/.keys/` are untracked and
   git-ignored and must never appear in any manifest, commit, or doc.
6. **Verify after pushing** with `list_commits` using the `sha` param,
   and confirm the remote head and tree match the staged HEAD.
7. **Draft PR.** Title: **"feat: complete online phase 5 gameplay"**.
   Base: `implementation/foundation-phase-2-3`. Draft, **do NOT merge**.
   Body: link the assessment (`docs/PHASE-5-ASSESSMENT.md`), traceability
   (`docs/PHASE-5-TRACEABILITY.md`), this plan, and the API supplement
   (`backend/docs/11-phase5-online-api.md`); state the Stage 9 measured
   verification counts and the known limitations (§7 of the traceability
   doc); note plainly that no CI runs exist for unpushed branches.
8. **If anything fails verification** at steps 4 or 6, STOP and report to
   the coordinator — do not push through, do not retry with a different
   base, do not delete and recreate the branch without a fresh tap
   (branch deletion needs its own approval).

## 7. Known limitations (summary)

Full list with detail: `docs/PHASE-5-TRACEABILITY.md` §7. In short:
login-burst Argon2id cost under concurrency (VM-capacity observation, not
a defect, not in scope to fix); presence caveat (connected-but-idle client
marked disconnected after ~30 s idle, grace protects); load-harness
run-id prefix wart; `onlineMatchStarted` unused l10n key; NFR-12 blocked
on M4.1; L-01 fail-open on Redis error (deliberate, logged); deep links
not built; no CI; test-only credentials in the tree; matchmaking has no
criteria (arrival order, group of 4); no flagged-match state (C-12).
