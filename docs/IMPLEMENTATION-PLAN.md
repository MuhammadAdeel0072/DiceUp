# DiceUp — Implementation Plan (Phase 1 Audit)

> Status: Phase 1 audit complete. Phases 2–3 in progress on branch
> `implementation/foundation-phase-2-3`. Source of truth: SRS v0.1
> (16 Nov 2026, draft) and SDD v1.0 (21 Nov 2026). If SRS and SDD ever
> conflict, stop and ask — do not silently pick an interpretation.
>
> Phase 3 REOPENED 2026-11-21 (M0): the compliance audit found Phase 3
> NOT COMPLIANT as "complete" — SQLite persistence, AnimationController,
> the NFR-12 1,000-match simulation and the airplane-mode run are
> outstanding (remediation plan §6.4 E1–E8). Nothing is "done" until its
> exit criteria pass with evidence.

## 1. Phase 1 audit — verified findings

### 1.1 SRS and SDD located and reviewed

| Document | Location | Status |
| --- | --- | --- |
| SRS v0.1 | Repo root: `DiceUp_SRS_v0.1.docx` (commit `e11ef1b`, Anti's upload, 21 Nov 2026 13:22 UTC) | Draft, not approved. FR-01…FR-82, NFR-01…NFR-39, BR-01…BR-20, UC-01…UC-17, A-01…A-12, OD-01…OD-12, R-01…R-10 |
| SDD v1.0 | Repo root: `DiceUp_Software_Design_Document_v1.0.docx` (commit `e11ef1b`, Anti's upload, 21 Nov 2026 13:22 UTC) | First issue, 21 Nov 2026. 76 pages, 17 sections, 11 UML diagrams, 37 tables, traceability FR-01…FR-82 verified 82/82. **Approval has not been given (SDD Approvals block) — unapproved baseline.** |

Both documents **are** in the GitHub repository, at the root — Anti added
them himself (commit `e11ef1b`, 21 Nov 2026 13:22 UTC; the earlier claim
that neither was in the repo was wrong, M-04). The GitHub connector can
only push UTF-8 text files, so the `.docx` binaries were not committed by
this tooling. D-03 (decided 2026-11-21) moves both files to `docs/` —
**pending Anti** (web upload or plain git push; files must stay
byte-identical, SHA-256 re-verified after the move). Until the move
happens, every location in this plan points at the repo root. The
repository holds this plan and `docs/TRACEABILITY.md` as the living
implementation record. Do not overwrite the source documents with
implementation notes — implementation documentation lives here and in
code-adjacent comments.

### 1.2 Repository and branch status (dated record — status as of 21 Nov 2026, ~22:13 PKT)

This section is a dated historical record. It describes the branch as it
stood at the time stated above; it is not updated to track the live head,
so it cannot go stale when a later commit is created. Later commits are
recorded in the branch history and in the PR #1 description, not by
rewriting this section.

- Repository: `MuhammadAdeel0072/DiceUp` (public). Default branch `main`.
- Commits on `main`: `0713edc` "Initial commit" (README only) and
  `750646d` "chore: initialize Flutter mobile application"
  (21 Nov 2026 12:28 UTC). The audit below is against the branch head
  `e11ef1b` (Phases 2–3 work on `implementation/foundation-phase-2-3`);
  `main` is still `750646d`. The audit baseline is that head — `e11ef1b`,
  six commits above `main`. The M0 documentation/comment commit is
  `52fb52e` (M0 record corrections, 21 Nov 2026), seven commits above
  `main`. The branch head at the time of the previous §1.2 revision was
  `8c067a87` (§1.2 branch-status and M0.4 corrections, 21 Nov 2026),
  eight commits above `main`. The subsequent documentation-only
  correction is `7f158bd` (§1.2 — current head is 8c067a87, eight commits
  above main, 21 Nov 2026), nine commits above `main`.
- Pull requests: **draft PR #1 open, unmerged** — "Phase 2–3: design
  system, app shell, offline engine + AI, playable game screen", head at
  the time of this record: `7f158bd`. The head at audit time was `e11ef1b`
  (unchanged since 21 Nov 2026 13:22 UTC). Branch
  `implementation/foundation-phase-2-3` commits, in order: `9b29d24`
  (33-file snapshot), `27763d6` (main.dart), `4a09b88` (widget tests),
  `2127503` (pubspec), `f0f141e` (analysis_options), `e11ef1b` (Anti's
  `.docx` upload), `52fb52e` (M0 record corrections — docs + comments
  only), `8c067a87` (§1.2 branch-status and M0.4 corrections — docs
  only), `7f158bd` (§1.2 head correction — docs only). PR #1 stays open
  and unmerged until M4 is green; Anti merges it himself (D-19, decided
  2026-11-21).
- Work is done on dedicated implementation branches (never large unreviewed
  changes on `main`). This plan covers branch
  `implementation/foundation-phase-2-3`. Nothing is merged without the
  owner's explicit instruction naming the PR.

### 1.3 Existing Flutter application assessment

`diceup_app/` is a stock `flutter create` template — a valid starting point,
not an implementation:

| Item | Finding |
| --- | --- |
| `lib/main.dart` | Counter demo ("Flutter Demo", deepPurple seed). No DiceUp code. To be replaced by the DiceUp app shell (Phase 2). |
| `pubspec.yaml` | Dart SDK `^3.13.4`; dependencies: `flutter`, `cupertino_icons`; dev: `flutter_test`, `flutter_lints ^6.0.0`. No state management, storage, networking or routing packages yet. |
| `test/widget_test.dart` | Default counter smoke test. To be replaced by real widget tests; the counter test is deleted, not kept. |
| `analysis_options.yaml` | Default `flutter_lints`. **No import-boundary rule exists** (M-07) — the domain-purity comment in the file states intent, not an enforced rule. Enforcement is a check script in M3 (`tool/check_boundaries.sh`) + a CI job. |
| Platform folders | `android/`, `ios/`, `linux/`, `macos/`, `web/` template defaults. SDD scope is Android + iOS; the extra folders are harmless template leftovers and are left in place for now. |
| Backend / admin | Do not exist yet (Phases 4–7). |
| CI | No workflow exists. Adding `.github/workflows/` requires the GitHub App to hold **Workflows: Read and write**, which was missing in the Khareedo installation — verify before promising CI. |

### 1.4 Architecture confirmed from the SDD

- Flutter app: Clean Architecture — presentation → domain → data, dependencies
  pointing inward; domain layer has no Flutter/network/database imports.
- Pure-Dart offline Ludo engine (`lib/domain/engine/`) + rule-based AI
  (`lib/domain/ai/`); SQLite for local data only, never rules (CON-02).
- Backend (later phases): NestJS modular monolith, Socket.IO, server-authoritative
  online game; PostgreSQL for truth, Redis only for ephemeral data.
- Admin panel (later phases): separate Next.js app, admin APIs only.
- State management / DI: Riverpod is the SDD's **proposed** choice (SDD §4.2).
  As built, there is **no** Riverpod, Bloc, Provider or `ChangeNotifier`
  anywhere in `lib/` — `GameScreen`'s `State` owns the engine, AI players
  and timers directly, and `main.dart` (26 lines) wires nothing despite its
  "Composition root only" docstring (H-07). **D-06 (decided 2026-11-21):
  Riverpod** — the controller stays a plain-Dart class bound through
  Riverpod providers; wiring lands in M3. Bloc and manual DI were
  considered and rejected in favour of the SDD default.
- Navigation: built-in named routes
  (`lib/presentation/navigation/app_routes.dart`). The SDD (§4.2) proposes
  go_router; the decision — recorded here (C-17) — is to start with
  built-in routing and adopt go_router when deep links (room invitations)
  land in Phase 5, because nothing in Phases 2–3 needs it. The route names
  are stable, so the switch is mechanical.

### 1.5 Functional requirements and NFR categories

- Functional: FR-01…FR-82 in six groups — A accounts/auth (FR-01…10),
  B offline gameplay (FR-11…32), C AI (FR-33…41), D online multiplayer
  (FR-42…59), E social/player (FR-60…69), F administration (FR-70…82).
  Full mapping: SDD Chapter 16 and `docs/TRACEABILITY.md`.
- Non-functional: performance (NFR-01…06), usability (NFR-07…10),
  reliability (NFR-11…12), security/privacy (NFR-13…21), availability
  (NFR-22…23), scalability (NFR-24…25), maintainability/compatibility/
  portability (NFR-26…29), data integrity (NFR-30…31), recoverability
  (NFR-32…35), other (NFR-36…39). Each NFR needs a measurable test —
  no NFR is claimed satisfied without evidence (see §7).

### 1.6 Conflicts and missing decisions

- **No SRS↔SDD conflict found.** The SDD was derived from the SRS; where the
  SRS is silent the SDD marks the addition `[Proposed]`.
- **Open decisions carried forward (SRS OD-01…OD-12):** ranking algorithm
  (OD-06 — SDD proposes simple points behind a `RankingStrategy` interface);
  final rule defaults (OD-02 — SDD Table §6.2 defaults, confirmed by D-16);
  email/push providers (OD-09, A-04/A-05); hosting provider/budget (OD-07);
  offline→online history import (OD-03 — no sync in baseline); age
  group/retention/region (OD-01, OD-08, OD-10 — legal review before launch);
  matchmaking stage and host-set rule options (OD-05, OD-11); single vs dual
  rule implementation (SDD §6.9 — dual + shared test vectors chosen, with
  the conformance suite as control; **D-05 decided 2026-11-21: D-02 stands,
  Q-08 closed**); additional staff roles, chat, blocking (OD-04 —
  Deferred); competitor/market research (OD-12 — Not included; needs
  sourced research). OD-04 and OD-12 have no Phase 1–3 implementation
  impact.
- **SDD status (draft) + §1.4 qualification:** the SDD is an unapproved
  draft ("Approval has not been given", Approvals block). SDD §1.4 takes
  all requirements from SRS v0.1 and states that where the SDD and the SRS
  appear to disagree, the SRS governs and the discrepancy is listed in
  §17.4. **D-04 (decided 2026-11-21):** proceed against both drafts as the
  baseline, with decisions recorded (see §8); nothing is silently treated
  as approved. A formal freeze/re-issue (SRS v0.2 / SDD v1.1) remains
  possible later once decisions land.
- **Recorded assumptions (L-08, M0):** choices the implementation made
  silently, now recorded with their owner — safe-cell indices
  {0, 8, 13, 21, 26, 34, 39, 47} (D-15 confirmed 2026-11-21; SDD §6.2
  never gave indices); seat colours red/green/yellow/blue
  (`DiceUpColors.playerColors`); per-seat token shapes
  (circle/square/diamond/triangle, board painter); AI pacing 700–1,199 ms
  (D-31 kept; FR-40 band is 600–1,200 ms); splash 900 ms fixed delay
  (replaced by a real settings load in M1.6); iOS target 15.0 (D-08
  decided — NFR-28/A-02 revised to iOS 15+, approved deviation);
  orientation unrestricted as built (D-17 decided 2026-11-21: iPhone
  locked to portrait in M2.13, iPad as-is).
- **Toolchain gap (found in audit, RESOLVED 21 Nov 2026):** this build
  machine had no Flutter/Dart SDK. Installed: standalone Dart SDK 3.14.1
  (`~/workspace/tools/dart-sdk`) and Flutter SDK 3.50.1 stable
  (`~/workspace/tools/flutter`). One environment quirk: the Flutter tool's
  Gradle-wrapper extraction fails on file ownership in this VM
  (`tar: Cannot change ownership`); fixed by extracting the cached
  tarball with `--no-same-owner` and writing the version stamp to
  `bin/cache/gradle_wrapper.stamp`. Only affects Android builds here;
  `analyze`/`test` are unaffected. Note for the owner's Windows machine:
  a normal Flutter install does not hit this.
- **Flutter 3.50 deprecation notice (open, non-blocking):** `flutter
  analyze` reports `package:flutter/material.dart` as deprecated in
  favour of `package:material_ui/material_ui.dart` — but that package
  does not exist in this SDK, so the migration path is not usable yet.
  The app keeps `material.dart`; verify the migration against Flutter
  documentation before any future change. 17 such `info`-level notices,
  zero errors, zero warnings.

## 2. Implementation roadmap

| Phase | Scope (SDD reference) | Exit criteria |
| --- | --- | --- |
| 1 — Audit (this file) | Repo/SRS/SDD review, traceability, roadmap, risks | This document; branch created |
| 2 — Design system & UI foundation | Visual identity, theme, reusable components, navigation, splash/home/mode/setup screens (SDD §11, §4) | Components + screens render; `flutter analyze` clean where runnable |
| 3 — Offline gameplay | Engine + AI + board (CustomPainter) + dice/token animation + local multiplayer + SQLite (SDD §6, §7; FR-11…41) | `flutter test` engine suite green incl. 1,000-match simulation (NFR-12); offline works in airplane mode (NFR-23) |
| 4 — Backend foundation | NestJS setup, PostgreSQL + Redis, auth, users, security/validation, tests (SDD §3.5, §5.2, §13) | Auth + profile APIs tested; no secrets committed |
| 5 — Online multiplayer | Rooms, matchmaking, Socket.IO events, authoritative game, reconnect/forfeit (SDD §8; FR-42…59) | Multi-client tests green; negative tests reject client dice/results 100% (NFR-18) |
| 6 — Platform features | Profiles, friends, stats, history, leaderboard, notifications (FR-60…69) | Feature tests green; leaderboard p95 ≤ 500 ms at 100k users (NFR-25) |
| 7 — Admin dashboard | Next.js panel, secured admin APIs, audit trail (FR-70…82) | Admin auth incl. MFA; audit-completeness test green (FR-82) |
| 8 — Integration & verification | Full integration, performance, security, NFR evidence, final report | All acceptance criteria (§18 of the brief) evidenced |

## 3. Initial folder structure

```text
DiceUp/
├── README.md                      # repo overview (existing, kept)
├── DiceUp_SRS_v0.1.docx           # source requirements — repo root (commit e11ef1b); move to docs/ pending Anti (D-03)
├── DiceUp_Software_Design_Document_v1.0.docx  # design — repo root (commit e11ef1b); move to docs/ pending Anti (D-03)
├── docs/
│   ├── IMPLEMENTATION-PLAN.md     # this file
│   └── TRACEABILITY.md            # FR → SDD → module → location → test → status
├── diceup_app/                    # Flutter mobile app (existing template, evolved)
│   ├── lib/
│   │   ├── main.dart              # app shell: theme + routes (NOT a composition root yet — wiring lands in M3)
│   │   ├── core/
│   │   │   ├── design_system/     # colors, typography, spacing, theme, components
│   │   │   └── errors/            # (target — to be added in M3) Result/error types
│   │   ├── domain/
│   │   │   ├── engine/            # pure Dart Ludo engine (SDD §6)
│   │   │   ├── ai/                # rule-based AI (SDD §7)
│   │   │   ├── entities/          # (target — to be added in M3) value objects
│   │   │   └── repositories/      # (target — to be added in M1) repository interfaces
│   │   ├── data/
│   │   │   ├── local/             # (target — to be added in M1) SQLite repositories
│   │   │   └── remote/            # (target — Phase 4+) REST + Socket.IO clients
│   │   └── presentation/
│   │       ├── navigation/        # routes
│   │       ├── screens/           # splash, home, setup, game, history, …
│   │       └── widgets/           # board painter, dice, tokens, shared widgets
│   ├── test/
│   │   ├── engine/                # engine + AI unit tests (flutter test)
│   │   ├── widget_test.dart       # boot + navigation widget tests
│   │   └── game_screen_test.dart  # gameplay widget test
│   └── pubspec.yaml               # deps added only when a feature needs them
├── backend/                       # (target — Phase 4+) NestJS
└── admin/                         # (target — Phase 7) Next.js
```

## 4. Risks and dependencies

| # | Risk (SRS R-*) | Mitigation in this plan |
| --- | --- | --- |
| R-04 | Dart + TypeScript rule engines diverge | Single ruleset spec + shared test vectors run in CI for both (SDD §6.9); engine tests are the first tests written |
| R-01/R-02 | Online state divergence / cheating | Server authority from day one of Phase 5; no client-trusting shortcut even in prototypes |
| R-10 | Mobile backgrounding drops sockets | Reconnect + grace period + push designed in Phase 5, not retrofitted |
| R-08 | iOS build needs macOS/Xcode | iOS verification happens on the owner's Mac or a cloud build service; flagged early, not at release |
| — | No Flutter SDK on this machine | Dart SDK for engine tests; Flutter install attempted; unverified UI work is labelled unverified |
| — | GitHub App may lack Workflows:write | No CI workflow promised until verified; CI is a follow-up, not assumed |
| R-05 | Scope creep beyond staged plan | Phases gated; anything outside FR-01…FR-82 needs a change request |

## 5. First implementation tasks (in order)

1. ~~Create branch `implementation/foundation-phase-2-3` from `main` (`750646d`).~~ — done (see §7).
2. ~~Add `docs/` (this plan, traceability matrix).~~ — done. (`.docx`
   binaries are at the repo root, commit `e11ef1b` — see §1.1.)
3. ~~Implement the design system (`lib/core/design_system/`) + reusable
   components + navigation + splash/home/mode-selection/offline-setup screens.~~ — done.
4. ~~Implement the pure-Dart engine + AI with unit tests.~~ — done (see §7).
5. Wire the game screen to the engine (board painter, dice, tokens, animations). — done **except AnimationController** (CON-01 outstanding: dice is `Timer.periodic`, tokens teleport, no pulse — M2.7).
6. ~~Replace `main.dart` and the counter widget test.~~ — done
   (`DiceUpApp`, boot/navigation widget tests, gameplay widget test).
7. Push the branch, open a **draft** PR, report results honestly. No merge.
8. SQLite persistence — local match recording, history, statistics,
   persisted settings, resume (FR-29…FR-32, SDD §9.1). — **NOT DONE**
   (M1). Phase 3 is reopened until the §6.4 exit criteria (E1–E8) pass.

## 6. Traceability

See `docs/TRACEABILITY.md` (generated from SDD Chapter 16, extended with
implementation location, test case and status columns). Status values:
`not started` | `in progress` | `implemented` | `verified` (with evidence).
A feature is `verified` only when its tests ran green — never on the basis of
compiling or looking correct.

## 7. Phase 2–3 verification evidence (21 Nov 2026, evening PKT)

- `flutter analyze` — **0 errors, 0 warnings**, 17 `info` (all the
  `material.dart` deprecation notice, §1.6). Exit code 0.
- `flutter test` — **50/50 passed**: 47 engine tests (rules, AI,
  snapshots), 2 app widget tests (boot, navigation), 1 gameplay test
  (roll a fixed 6, release a token by tapping the board). The gameplay
  test caught and fixed two real bugs before the push: an infinite-width
  button constraint in a `Row`, and `BoardToken` missing value equality
  (yard-slot hit-testing mapped every token to the same slot).
- Engine cross-check (WITHDRAWN as evidence, M0 2026-11-21): an ad-hoc run
  of 100/100 full AI matches with 0 rule violations was claimed with no
  artifact — it is not evidence and is withdrawn. The committed 1,000-match
  NFR-12 suite (M4.1) is the evidence; until it exists, NFR-12 is unmet.
- SQLite persistence did not land in Phase 3 — Phase 3 is reopened
  (see §2, §5). Settings, history, statistics and resume are all M1 work.
- Known deviations from the SDD (documented, not silent): Medium AI
  scores marginally above Hard on the 200-position sample because Hard
  deliberately declines suicidal captures (designed behaviour, test
  asserts `hard > easy` and `medium >= easy`). **D-01 (decided
  2026-11-21):** SDD §7.4's criterion is amended to hard>easy,
  medium>=easy as an approved design decision — the Hard weights are
  preserved, not retuned (see §8); the "continue to rank 2nd–3rd"
  variant is not implemented — the SDD specifies no flow for it, so the
  default (first to finish wins, match ends) is used. **D-02 (decided
  2026-11-21):** continue-to-rank is DEFERRED, never falsely marked
  complete (see §8).

## 8. Decisions D-01…D-32 (all decided 2026-11-21) and pending SDD amendments

All 32 decisions were answered by Anti on 2026-11-21 (20:11–21:27 PKT),
one at a time, each against the exact plan wording with verified SRS/SDD
evidence. The full record (wording, evidence, options, conditions) is in
`~/MEMORY.md`; this section is the implementation-side summary. M0 started
2026-11-21 ~21:29 PKT on Anti's go-ahead ("start M0 — record
corrections"). Implementation (M1–M4) still needs Anti's explicit go-ahead.

| # | Decision | Outcome (Anti, 2026-11-21) |
|---|---|---|
| D-01 | SDD §7.4 difficulty-sanity vs Hard weights | **A** — amend §7.4 to hard>easy, medium>=easy. Conditions: preserve all Hard scoring weights + production behaviour; correct the yard-release test oracle; §7.4 defines seeded positions, combined finish/capture metric, sample size, comparison operators explicitly; record original results (Hard 44, Medium 45, Easy 14) + why strict Hard>Medium contradicted the intended scoring design; document as an approved design decision, not a silent weakening; update the traceability entry + test documentation. |
| D-02 | Results screen vs dialog + continue-to-rank | **A** — dedicated results screen; continue-to-rank DEFERRED (never falsely marked complete; recorded as deferred in the SDD + traceability). Play Again reuses the exact settings/config; Main Menu navigates to Home (see D-30). |
| D-03 | `.docx` location — root or `docs/`? | **B** — move to `docs/`, by Anti (web upload or plain git push; byte-identical, SHA-256 re-verified). **Pending — not done yet; until the move, every location in this plan points at the repo root (commit `e11ef1b`).** |
| D-04 | Proceed against unapproved drafts? | **A** — proceed against SRS v0.1 + SDD v1.0 as the baseline, decisions recorded. Nothing silently treated as approved; a formal freeze/re-issue (v0.2/v1.1) remains possible later. |
| D-05 | Single vs dual rule implementation (D-02 vs Q-08) | **A** — two implementations (Dart + TypeScript) kept consistent by shared test vectors; D-02 stands, Q-08 closed. No Dart-on-the-server. |
| D-06 | Riverpod vs Bloc vs manual DI | **A** — Riverpod (SDD's proposed default). Controller stays plain Dart, bound through Riverpod providers. |
| D-07 | Setup pickers (colour + name + ruleset) | **A** — build all three in M2.1. Correction: the plan's "FR-01/02/03 + FR-06 compliance" citation is wrong (FR-01 guest access, FR-02 registration, FR-03 email verification, FR-06 password recovery). Real setup requirements: FR-12 (mode), FR-13 (count), FR-14 (seat colour + type, ≥1 human), FR-41 (AI difficulty), FR-11 (init incl. ruleset), UI-02, UC-01 step 2, UC-02 step 2 (only SRS source for setup names; no FR covers setup names). |
| D-08 | iOS target 13.0 vs 15.0 | **A (as decided: target stays 15.0)** — accept the narrower range. Corrections: iOS 13+ is NFR-28 (Compatibility, Proposed) + A-02, NOT CON-02 (CON-02 is SQLite local storage); there is no `ios/Podfile` — the 15.0 pin is `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in `project.pbxproj`. Record NFR-28/A-02 as revised to iOS 15+ (approved deviation). |
| D-09 | NFR-08 48 dp vs board tokens | **B** — 48 dp for controls, board tokens exempt as game pieces with a documented rationale. Correction: the plan's "~30 dp" tokens are wrong — measured from the code: board side `width.clamp(280, 480)`, cell = boardSide/15, token radius = cell × 0.36, hit-test radius = cell × 0.6; visual token ≈13.4 dp across and tap target ≈22.4 dp on the minimum 280 dp board (≈23 dp / ≈38.4 dp at the 480 dp maximum). 48 dp tokens would need a 720 dp board vs NFR-09's 430 dp max — the exemption is geometric, not a preference. |
| D-10 | Pause semantics | **A** — pause is a freeze (timers + AI stop, state preserved, resume continues the same match). Corrections: SDD §6.8 is "Class responsibilities and suggested Dart structure", not pause design — pause()/resume() are in the SDD §5 GameScreen module description, and §11.1 describes the pause menu as "restart / exit with confirmation" with no resume mentioned, so the SDD is genuinely ambiguous. BR-20 says offline matches have no timer by default, so the harm of menu-only pause is the AI pacing timer firing while the menu is open. |
| D-11 | FR-29 resume trigger | **B** — resume only after unexpected closure (SDD §6.6 as written). Corrections: the plan's claimed §6.6-vs-§3.3 contradiction doesn't exist (§3.3 says nothing about unexpected closure; §6.6 already contains both halves). Deletion IS the clean-exit marker — no extra flag needed. The FR-29 flag inconsistency claim is WRONG: the SRS requirements table marks FR-29 **Proposed** (line 386), SRS appendix A3 says "(FR-29, proposed)", and SDD §6.6/§9.1 agree — no inconsistency exists. |
| D-12 | Record exited offline matches as losses? | **B** — exited offline matches are NOT recorded at all; history shows completed matches only (FR-30's trigger is "on completion"; SDD §9.1 local_matches is "one row per completed offline match"). |
| D-13 | Admin MFA required + TOTP vs proposed | **A** — required + TOTP per SDD, recorded now; no code until Phase 7. Recovery codes remain [Proposed] (SDD §13.1). |
| D-14 | Reference device for NFR-01/02/03/04 | **A** — accept the stand-in: low-end Android, 4 GB RAM (SRS NFR-01 example) + one iPhone (model TBD at M4/D-18). |
| D-15 | Safe-cell star positions 8/21/34/47 | **A** — confirm {0, 8, 13, 21, 26, 34, 39, 47} (starts 0/13/26/39, stars 8/21/34/47). No code change. |
| D-16 | OD-02 rule defaults | **A** — confirm the SDD §6.2 defaults as implemented (release on 6, extra turn on 6/capture/home, third six not played, exact finish, first to 4 home wins). Closes SRS OD-02. |
| D-17 | A-11 portrait lock (incl. iPad?) | **A** — lock iPhone to portrait, leave iPad as-is. Nuances: a Dart `SystemChrome` lock applies to ALL iOS devices including iPad, so the lock must be platform-native only (Info.plist iPhone key + Android manifest); the Android manifest lock is device-wide, so Android tablets get locked to portrait while iPads don't. |
| D-18 | iOS first build — owner/timing | **A** — attempt the first iOS build in M4 (Anti's Mac or a cloud build service). |
| D-19 | DiceUp PR merge policy | **A** — Anti merges PR #1 himself, same as Khareedo. Muse never merges a DiceUp PR. |
| D-20 | Track/home split: 50+5+1 or 51+4+1? | **A** — pin 51 + 4 + 1 (engine as-is; amend the SDD, fix the 5th cell). Recorded as an approved deviation from SRS §7.1 (not just an SDD fix). M-08 closes by amending SDD §6.2 to 4 home-path cells + fixing the wrong `cellAt` comment (done in M0); M3.5 removes/redraws the 5th drawn cell per seat; M3.6 vectors encode 51+4+1. |
| D-21 | Confirm the Proposed items as binding | **A** — confirm ALL Proposed items as binding (FR-29, NFR-35, NFR-36, NFR-08, NFR-09, FR-40's 600–1,200 ms interval, **and NFR-04's 500 ms** — "confirm all" covers it as well as NFR-36's 500-match cap; the plan's M1 entry criteria "+ the 500 number" is ambiguous, both are confirmed binding). |
| D-22 | Snapshot validation: reject vs repair? | **A** — reject outright (`FormatException`, corrupt snapshot deleted, notice shown). M1.1 implements strict `fromJson` FIRST, before any snapshot is ever persisted. |
| D-23 | Is move history required? | **A** — not required for resume (state snapshot is enough). SDD §6.8's GameState row DOES list "move history" among its key members — the adopted reading is that the row's own definition ("everything needed to render or resume") excludes move history, needed for neither; the row is corrected at SDD re-issue (see pending amendments below). |
| D-24 | `matches_won` semantics | **A** — human-seat win labelled per player in `players_json` (an AI win doesn't increment the human total). |
| D-25 | Sound volume default | **A** — default 100 (`sound_volume` '0'..'100', M1.3). |
| D-26 | Confirm sqflite as the plugin | **A** — confirm sqflite (SDD §9.1 [Proposed]). |
| D-27 | Avatar contrast fix — which option? | **A** — white-disc avatar (white fill, navy initial 14.11:1, player-colour ring + shape marker). Board tokens, palette constants and turn banner untouched. |
| D-28 | Player-name validation rules | **Proposal accepted** — 1–12 chars, trim, empty → "Player N", duplicates allowed (identity is seat+colour+shape, not name). The 1–12 cap is the plan's own proposal, adopted as a choice — no name-length rule exists in the SRS or SDD (only UC-02 step 2 requires names; SDD `local_players.display_name` has no length constraint; online `users.display_name VARCHAR(50)` is a different thing). 13th-character behaviour + character set to be pinned in M2.2. |
| D-29 | Ruleset options scope | **B** — curated subset (release-on-1, exact finish, extra turn on six/capture/home, third-six limit). `releaseOnSix` (base rule) and `version` (metadata, BR-14) stay engine-level. "Continue to rank 2nd/3rd" excluded either way (D-02). |
| D-30 | "Back to menu" destination — Home or setup? | **A** — Home (per SDD §11.2). Applies to the pause menu's Exit too (same destination question). |
| D-31 | AI pacing — keep 700–1,199 ms or widen? | **A** — keep 700–1,199 ms. The `game_screen.dart` docstring said "700–1,200 ms" — the true max is 1,199 (corrected in M0). M-16 adds the UI-layer pacing test. The AI timeout fallback (UC-03 E1) stays a separate optional M-16 item. |
| D-32 | Sound/haptics — real sound now, or haptics-only? | **A** — haptics now, sound as a named follow-up. M2.11 builds `FeedbackService` with `HapticFeedback.lightImpact()` on moves (no new dependency); the Sound toggle is removed or shown disabled with an honest note (no placebo settings ship); the volume control (D-25, default 100) is stored as a preference for when sound lands. |

### Pending SDD amendments (recorded here, NOT applied to the .docx)

The SDD is a controlled document; its fixes land at re-issue with Anti's
approval, not by silent edits. Until then, this list is the record of what
the re-issue must contain:

1. §7.4 difficulty-sanity criterion → hard>easy, medium>=easy, with the
   D-01 conditions (weights preserved; seeded positions, combined
   finish/capture metric, sample size, comparison operators defined;
   original results Hard 44 / Medium 45 / Easy 14 recorded with the
   explanation).
2. §6.2 "four home paths of 5 coloured cells each" → 4 home-path cells;
   "home-path index 0…5" → 0…3 (D-20; approved deviation from SRS §7.1).
3. §6.2 safe-cell indices {0, 8, 13, 21, 26, 34, 39, 47} (D-15).
4. §6.8 GameState row — "move history" listed as a key member; adopted
   reading: not required for resume (D-23).
5. §17.4 Q-08 closed; §17.1 D-02 stands (D-05).
6. NFR-28/A-02 revised to iOS 15+ (D-08; approved deviation).
7. §6.5 cites BR-25 (nonexistent) → BR-11 (M-17; needs no decision).
8. §6.2 table caption: cited three ways — "Table 6.1", "Table 6.2", and
   "Table §6.2" (`ruleset_config.dart:3`) — caption it "Table 6.1" or
   renumber the references (M-17).
9. §16.2 → §14.2 dead reference; no crash-reporting mechanism exists —
   crash-reporting design is a Phase 8 item (M-19).
10. Continue-to-rank recorded as DEFERRED (D-02) — never marked complete.
11. FR-29 is **Proposed** in the SRS (requirements table line 386;
    appendix A3 "(FR-29, proposed)"); SDD §6.6/§9.1 agree. The plan's
    C-23 "flag inconsistency" was not re-verified and is now refuted —
    no inconsistency exists.
12. SDD Chapter 12 is API and Communication Design, NOT testing (audit
    premise corrected) — testing requirements are distributed across
    §6.9, §7.4, §9.3, §15.4, §13.

### M0.4 — DONE (PR #1 description updated and verified, 2026-11-21)

PR #1 body text change only (no merge). What M0.4 changed, per the
remediation plan:

- "not in the repo" → "are in the repo at the root (commit `e11ef1b`,
  Anti's upload)".
- Append `e11ef1b` to the commit list.
- Design-system bullet — "NFR-08 measured breaches outstanding (40 dp
  SegmentedButtons, 40 dp dialog buttons, 12 sp `bodySmall`, colour-only
  avatars, white-on-green 3.04:1) — see audit".
- Settings line — "toggles work in-session only; SQLite persistence did
  not land in Phase 3 — Phase 3 reopened".
- Add: "Compliance audit 2026-11-21: NOT COMPLIANT (0 Critical, 10 High,
  23 Medium, 8 Low). Do not merge — remediation plan pending Anti's
  approval."

Completion record (Phase 1, 2026-11-21 ~21:52 PKT): executed and verified
by read-back — PR #1 `updated_at` 2026-11-21T16:52:36Z; title, draft
state, labels and merge state untouched; head SHA unchanged by the update
(`e11ef1b` at the time). The update call timed out at 120 s after
approval, but the write had landed — the state was inspected before any
retry and no retry was attempted. One judgement call: the approved
substitution would have produced a self-contradictory sentence, so the
`.docx` bullet was rewritten as a clean sentence carrying the same
location fact.

### Plan corrections recorded in M0 (remediation plan wording, corrected here)

- Remediation plan §4 M4.6: "if the build fails on iOS 13.0, the decision
  reverts to amending A-02/NFR-28 to 15.0" is **stale** — D-08 already
  decided 15.0 (D-18). To be corrected when the remediation plan is next
  revised.
- Remediation plan §2 C-23 (FR-29 flag inconsistency) was "Not
  re-verified" and is now refuted — see pending amendment 11 above.
- D-03 note: the D-03 decision record said M0 would re-point records at
  `docs/`; the move has not happened, so M0 records the current truth
  (repo root, `e11ef1b`) and the `docs/` move stays pending Anti.

### M1.7 — DONE (persisted settings + statistics UI, haptics D-32; 2026-11-22)

The last M1 milestone. No schema, repository-interface, engine or AI
changes; no audio dependency; no new table. Two append-only commits on
`implementation/foundation-phase-2-3`, parent `596b9e4`:

- `d703bd7f` "feat(app): M1.7 settings persistence + haptics (D-32)" —
  `lib/presentation/feedback/feedback_service.dart` (new
  `FeedbackService` abstraction; `HapticFeedbackService` calls
  `HapticFeedback.lightImpact()`), persisted `settings_screen.dart`
  (vibration toggle + volume slider 0–100 persist immediately,
  loading state first — defaults never flashed; sound toggle DISABLED
  with a Coming Soon note, no audio code; Reset to defaults via
  `resetToDefaults`, which also clears `last_*`), haptics wired into
  `GameScreen._applyMove` gated by the persisted `vibration_enabled`
  setting (startup-loaded value, refreshed from the repository;
  fire-and-forget, never throwing into the turn loop), FR-08
  traceability row updated.
- Statistics commit (SHA in the M1.7 completion report) — new
  `statistics_screen.dart` (route `/statistics`, Home "Statistics"
  entry): reads the PERSISTED lifetime statistics row directly, never
  derives lifetime totals from retained history; per-player breakdown
  is computed from retained history only and labelled "Per-player wins
  from your latest 500 matches." (schema-limited presentation, D-24 —
  no per-player lifetime table exists); players identified by seat
  index + colour, never display name; AI wins never count as human
  wins; loading / empty (zeros + honest note) / error-with-retry /
  unavailable states. FR-32 traceability row added (FR-29–32 row split
  to FR-29–31; its "not started" status is pre-existing and untouched
  by this milestone).

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test --coverage` — **349/349 passed** (baseline 332 + 17 new:
9 settings/haptics in `test/settings_haptics_test.dart`, 8 statistics
in `test/statistics_screen_test.dart`); measured line coverage **86.2%**
(1899/2203 lines — reported only; the ≥90% gate is M3.7's).
`flutter analyze` — **0 errors, 0 warnings, 21 info** (all the
pre-existing `material.dart` deprecation notice, incl. 4 in new M1.7
files; baseline was 0/0/18). New tests prove: seeded settings load
without flashing defaults; toggle/volume persist (fresh-repository
re-read); reset restores D-25 defaults and clears `last_*`; settings
survive a real database reopen; a move triggers the feedback fake
exactly once when enabled and never when disabled; the real service
sends lightImpact on the platform channel; lifetime totals stay 700
after 700 records with only 500 rows retained; AI wins never inflate
human wins; Home → Statistics → back navigation.

Scoping decisions recorded: last-used setup prefill (`last_mode` /
`last_player_count` / `last_difficulties` into the setup flow) is
DEFERRED, not forced — it needs an async load + loading state in the
setup screen, a serialisation format for difficulties (none exists),
and persistence on match start across three screens; small in no
single place, so it stays a deferred item rather than blocking the
milestone. The settings screen loads/saves the three persisted toggles
+ volume and reset; reading/displaying `last_*` there is out of scope.
Sound remains a named follow-up (D-32): disabled toggle + volume
storage only, nothing plays.
