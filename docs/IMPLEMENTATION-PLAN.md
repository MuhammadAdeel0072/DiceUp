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
5. Wire the game screen to the engine (board painter, dice, tokens, animations). — done, including AnimationController (M2.7, CON-01: 540 ms tumble settling on the engine value, ≤250 ms token hop, legal-move pulse, `RepaintBoundary` + content-based `shouldRepaint`).
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
- `d25bff20` "feat(app): M1.7 statistics screen + docs" — new
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

### M3.3 — DONE (Riverpod composition root, D-06; 2026-11-22)

The single wiring point (remediation plan M3.3, SDD §3.2/§4.2–§4.4):
`lib/presentation/providers/app_providers.dart` (new) — one
`ProviderScope` at the app entry ([DiceUpApp] in `lib/main.dart`)
wiring repositories → use cases → [OfflineGameController] → screens.

- Providers: `startupResultProvider` (the awaited [initializeApp]
  result — no default, fails loudly without it),
  `appDependenciesProvider` + the five repository providers (the
  same instances startup built — one construction site),
  `snapshotWriterProvider`, `diceRollerProvider` (null in prod),
  `feedbackServiceProvider`, `vibrationEnabledProvider` (null in
  prod), use-case providers (`startOfflineMatchProvider`,
  `rollDiceProvider`, `applyMoveProvider` — null when degraded),
  and `offlineGameControllerProvider` (`Provider.autoDispose`:
  the game screen's watch keeps it alive; the provider disposes
  it — timers cancelled — when the screen leaves).
- [OfflineGameController] takes the M3.1 use cases by optional
  constructor injection (defaults build the same instances as
  before M3.3, so direct construction behaves identically); the
  haptics hook (`onMoveApplied`) is wired in the provider, so the
  screen never touches haptics directly.
- `GameScreen` is a `ConsumerStatefulWidget` that reads the
  controller via `ref.read` (start the match in
  `didChangeDependencies`) + `ref.watch` (build). The
  optional-constructor-override seam is GONE — exactly one seam
  mechanism, the provider override (decided at implementation
  time, per the M3.2 plan text; no test used the `controller:`
  override). The `diceRoller` / `feedbackService` /
  `vibrationEnabled` widget parameters are gone too; tests
  override the providers (`test/test_providers.dart`). The screen
  holds no copy of the game state.
- `flutter_riverpod: ^3.5.0` added (D-06 names Riverpod; the
  remediation plan M3.3 names `ProviderScope` + providers).
- `tool/check_boundaries.sh` (new): 8 grep checks — domain
  imports no Flutter/Riverpod/storage; only the provider graph
  constructs the controller; no screen constructs a repository,
  the engine or `AppDependencies`; the game screen imports no
  data layer. All pass.
- Behaviour preserved bit-identically: same 700–1,199 ms AI
  pacing, same 6 x 90 ms dice tumble, same status strings, same
  win trigger, same snapshot/completion semantics. The vibration
  resolution keeps the M3.2 screen's exact expression
  (`loadedSettings['vibration_enabled'] != '0'`); note
  `loadedSettings` is currently always empty from
  `AppDependencies.fromDatabase` (startup loads settings into
  `StartupResult.settings` instead), so the effective initial
  value is on and the persisted value is picked up by the
  controller's repository refresh — the quirk is preserved, not
  silently fixed.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **417/417 passed** (baseline 409 + 8 new in
`test/riverpod_composition_root_test.dart`: repository-provider
identity, use-case wiring incl. degraded `applyMove == null`,
controller provision + disposal via container dispose, boot with
in-memory fakes + move persists, single-source-of-truth
(externally driven roll renders), feedback override, no-scope
loud failure, `DiceUpApp` startup wiring with test seams).
`flutter analyze` — **0 errors, 0 warnings, 24 info** (all the
pre-existing `material.dart` deprecation notice, incl. 1 in the
new test file; baseline was 0/0/23). `dart format` clean on all
M3.3-touched files (note: `dart format --set-exit-if-changed`
flags 45 pre-existing files tree-wide — older-formatter style
drift, untouched by this milestone, not reformatted here).
`tool/check_boundaries.sh` — 8/8 checks pass. The M3.2
characterization tests pass unchanged.

Single-scope rule (found by probe during this milestone, recorded
in `lib/main.dart` + `app_providers.dart`): there is exactly one
[ProviderScope] per widget tree. Riverpod owns a non-overridden
provider in the outermost scope, so its transitive watches resolve
there and cannot see an inner scope's overrides — a `DiceUpApp`
wrapped in an outer test scope failed to start a match
(`startupResultProvider` in error state, verified by probe), while
the same tree with a single scope works. [DiceUpApp] therefore
owns the app tree's scope and takes its test seams as named
parameters (`testDiceRoller`, `testFeedbackService`,
`testVibrationEnabled`); `Override` is sealed and not publicly
exported in Riverpod 3.5, so no raw-override parameter is
possible. Bare-screen tests build their own single scope via
`test/test_providers.dart`.

Scoping decisions recorded: game flow + startup wiring only.
Settings, history, statistics, home and setup screens still read
repositories through [AppDependenciesScope] (M1.6) — migrated one
screen at a time, explicit next step, not done here. §1.4's
as-built description ("no Riverpod… GameScreen's State owns the
engine") is superseded by M3.2 (controller extraction) + M3.3
(Riverpod) and is left as the audit-time record; it is not
rewritten in this milestone.

Follow-up decision item (pre-existing M3.2 finding, NOT fixed
here): `LudoGame.fromState` uses the default stock ruleset, not
the restored state's embedded ruleset — a resumed match with
custom ruleset options plays under stock rules, and Play Again
after a resume loses the custom ruleset. Needs a decision (fix
`fromState` to honour the embedded ruleset vs keep stock as the
resumed default) before it is touched; recorded here so it is not
fixed silently.
### M2.3 — DONE (theme tokens, NFR-08; 2026-11-22)

The theme-token half of H-10 (remediation plan §4 M2.3, §6.2
"Theme tokens"):

- `diceup_typography.dart`: `bodySmall` 12 → **14 sp** — the
  14 sp floor now holds for every style in the theme (display 32,
  headline 24, titles 20/16, body 16/14/14, label 14). The header
  doc now states the floor explicitly instead of asserting it
  while `bodySmall` was 12 sp.
- `diceup_theme.dart`: `segmentedButtonTheme` and
  `textButtonTheme` 48 dp minimums added
  (`DiceUpSpacing.minTouchTarget`), alongside the existing
  elevated/outlined 48 dp minimums. Measured under Flutter 3.50.1
  the rendered SegmentedButton/TextButton heights already met
  48 dp — the audit's 40 dp figure is stale under this Flutter
  version — so these entries pin the requirement as tokens rather
  than fixing a currently failing rendered size; the test asserts
  the token as well as the rendered size.
- `offline_setup_screen.dart`: colour swatches 40x40 → **48x48 dp**
  (the one interactive control found below 48 dp by the audit
  beyond the two button themes). Measured 40.0 dp before the fix.
- `diceup_spacing.dart` / `diceup_components.dart`: the false
  blanket claims are corrected — "Touch targets are at least
  48x48 dp" / "All interactive elements meet the 48x48 dp
  minimum" now say the 48 dp token is enforced for *controls*
  through the theme, with board tokens named as the D-09
  exemption (game pieces, not controls).
- `game_screen.dart` `_onBoardTap`: the D-09 mitigation — the
  **full-cell hit area**. Any tap inside a legal token's cell
  selects it; the pre-existing cell×0.6 radius is kept as well,
  so no previously-valid tap is lost (the radius reaches past the
  cell along the axes). Board tokens stay exempt from 48 dp
  (geometric: ~22.4 dp tap target on the minimum 280 dp board;
  48 dp tokens would need a 720 dp board vs NFR-09's 430 dp max).
- Incidental finding fixed in verification: at 320 dp the
  `_PlayerChip` label ("Player 1 · Home 0/4") overflowed its row
  by 29 px — pre-existing (the chip uses `bodyMedium`, untouched
  by this milestone; only the 320 dp viewport exposes it). The
  label is now `Flexible` + `TextOverflow.ellipsis`. No text was
  shortened and no other chip behaviour changed.

Audit of the remaining controls (measured in the new tests, all
≥ 48 dp): Primary/Secondary buttons, IconButton (AppBar), the
setup SwitchListTile rows, Slider, DropdownButtonFormField and
DiceUpTextField. The dice (64 dp, not yet tappable — M2.8) and the
player chips (non-interactive) are not controls. The only
sub-14 sp text in `lib/` was `bodySmall` (the avatar initial
scales with its radius and is not body text).

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **431/431 passed** (baseline 417 + 14 new in
`test/accessibility_test.dart`: 4 typography/token, 4 themed-control,
1 dialog TextButton, 2 real-setup-screen, 1 corner-of-cell tap,
2 320x568 no-overflow smoke). Before/after: the new file failed
5/12 against the unfixed code (`bodySmall` 12.0 sp, no theme
48 dp minimums, swatches 40.0 dp, corner tap missed) and passes
12/12 after; the two 320 dp smoke tests were added after the fix
and caught the chip overflow above. `flutter analyze` — **0 errors,
0 warnings, 25 info** (24 baseline + 1 in the new test file, all the
pre-existing `material.dart` deprecation notice). `dart format`
clean on all M2.3-touched files. The 320 dp checks are smoke-only
(no-overflow); the full 5-width layout suite is M2.12's.

Scoping decisions recorded: avatar contrast + shape markers are
M2.4 (D-27) and Semantics labels are M2.9 — NFR-08 is still
non-compliant overall (see TRACEABILITY NFR-07–10 row), and this
milestone does not claim otherwise. The `LudoGame.fromState`
custom-ruleset follow-up (M3.2/M3.3) is untouched, as instructed.

### M2.4 — DONE (white-disc avatars + turn banner, D-27; 2026-11-22)

The avatar half of H-10 (remediation plan §4 M2.4, §6.1 "Avatars +
contrast"):

- `diceup_components.dart`: `PlayerAvatar` reworked to the D-27
  white disc — white fill, navy initial (`DiceUpColors.navy`,
  0xFF1B2A4E), player-colour ring, per-seat shape marker. The old
  coloured disc + white initial is gone, and with it the false
  shape-marker docstring (the old widget claimed a shape marker it
  never rendered). The initial is navy on white for every seat:
  14.11:1 by the WCAG formula, so the three failing
  white-on-player-colour ratios (red 3.91, green 3.04, yellow 1.85)
  no longer apply — no text sits on a player colour anymore.
  Board tokens and the palette constants are untouched (D-27).
- New `PlayerShape` enum (`circle`/`square`/`diamond`/`triangle`,
  `forSeat` = seat % 4) + `PlayerShapeMarker` widget: the same
  shapes as the board tokens in `LudoBoardPainter`, so shape alone
  identifies the seat. The marker is a small badge in the ring
  colour at the disc's bottom-right corner.
- New `DiceUpColors.contrastRatio` (WCAG relative-luminance
  formula, opaque colours) in `diceup_colors.dart`, so the 14.11:1
  claim is computed in code and asserted in the test, not quoted
  from the decision record.
- `PlayerAvatar` takes an optional `colour` (`PlayerColour`): the
  ring follows the player's *chosen* colour (M2.2) when given, and
  falls back to the seat-order colour otherwise. The shape always
  follows the *seat*, matching the board tokens after a colour swap.
- `game_screen.dart`: the turn banner passes the current player's
  chosen colour, so it shows name + avatar (colour ring + shape +
  initial) — "name + colour + shape" per the remediation plan. The
  `_PlayerChip`'s colour-only 12 dp dot is replaced by a small
  `PlayerAvatar` (radius 12); the M2.3 `Flexible` + ellipsis label
  is unchanged and the 320 dp chip overflow stays fixed.
- `offline_setup_screen.dart`: the seat card passes the seat's
  chosen colour to its avatar, and the redundant 14x14 colour-only
  dot next to the seat title is removed (the avatar in the same row
  already carries colour + shape + initial).
- Not in scope here, unchanged: the results screen is M2.5 (the
  win dialog still shows the winner's name as text; `PlayerAvatar`
  is available for the results screen to use), history/statistics
  identify players by text name / "Seat N · colour name" (no
  colour-only identification there), and Semantics labels are M2.9.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **437/437 passed** (baseline 431 + 6 new in
`test/accessibility_test.dart`, group "avatars + turn banner (M2.4,
D-27)": navy-on-white 14.11:1 unit test, per-seat white disc / navy
initial / ring colour / distinct shape, ring-follows-chosen-colour
vs shape-follows-seat, initial from the real name, turn banner
shows the current player and updates on turn change, 320x568
game screen with 5 avatars without overflow). The new tests assert
the opposite of the old rendering (white disc, navy initial), so
they fail against the pre-M2.4 avatar by construction.
`flutter analyze` — **0 errors, 0 warnings, 25 info** (unchanged
from the M2.3 baseline, all the pre-existing `material.dart`
deprecation notice; no new notice). `dart format` clean on all
M2.4-touched files.

Scoping decisions recorded: NFR-08 is still non-compliant overall
(see TRACEABILITY NFR-07–10 row) — Semantics labels are M2.9, and
this milestone does not claim otherwise. The `LudoGame.fromState`
custom-ruleset follow-up (M3.2/M3.3) is untouched, as instructed.

### M2.5 — DONE (dedicated results screen, H-09; D-02, D-30; 2026-11-22)

The results half of H-09 (remediation plan §3.1 H-09, §4 M2.5,
§6 "Results screen"):

- `lib/presentation/screens/results_screen.dart` (new): the
  dedicated results screen (FR-26), a *route* — the M1.6 win
  dialog is deleted, not kept alongside. Shows exactly what FR-26
  / SDD §11.1 require: the winner (name + large `PlayerAvatar`:
  white disc, navy initial, player-colour ring, per-seat shape —
  M2.4/D-27, never colour alone), duration `mm:ss`, move count,
  mode (`vs AI` / `Local multiplayer`, matching the history
  screen's wording), player count, the participant list (avatar +
  name + `(AI)` + a `Winner` marker), and the finish date
  (`21 Nov 2026, 12:00`, the history screen's format, no `intl`
  dependency). "Finishing order where applicable" is winner-only:
  the match ends at the first finisher (BR-11) and
  continue-to-rank is DEFERRED (D-02) — no 2nd/3rd order, ranking
  or placement is shown or invented. No lifetime statistics live
  here (M1.7 owns those). The record-failure notice
  (`kMatchRecordFailedMessage`, moved here from `game_screen.dart`)
  shows when the completion record failed, never a success presented
  as recorded.
- `lib/presentation/navigation/app_routes.dart`: new route
  `AppRoutes.results` (+ route-table entry); new frozen
  `MatchResult` + `MatchResultPlayer` value objects — winner,
  players, duration, move count, finish time, the exact
  `GameSetup`, `completionFailed`. The duration and finish time
  are frozen at navigation, so a rebuild can never stretch the
  duration; the screen never reads the game controller (it is
  disposed when the results route replaces the game route) and
  never re-records the completion (exactly-once, M1.6). The model
  is shaped so a future `finishOrder` list slots in beside
  `winnerSeat` (D-02 condition 6). `matchResultOf` returns null
  for a route opened without a result — the screen shows an
  honest empty state (`No match result to show.` + Main Menu),
  never an invented result. `gameSetupOf`'s fallback is kept
  only as a deep-link guard: it now logs (release builds
  included) and asserts in debug — never a silent substitute.
- `lib/presentation/screens/game_screen.dart`: `_showWinDialog`
  deleted (with its double-pop: dialog pop, then game-screen pop
  → setup). `_maybeShowResults` navigates once, when the match
  is finished and the completion record is decided, via
  `pushNamedAndRemoveUntil(AppRoutes.results,
  ModalRoute.withName(AppRoutes.home))` — the stack becomes
  Home → Results, so system back lands on Home and there is no
  finished game screen underneath. The duration runs from the
  match's `GameState.startedAt` (which survives resume and
  restart), with a screen-tracked `_matchStartedAt` fallback for
  states built without one — this is the plan's "track
  `_matchStartedAt`", satisfied by the M1.1 `startedAt` field
  rather than a second clock. `_gameSetupOf` converts the
  retained `MatchSetup` back to `GameSetup` field-for-field for
  Play Again. The controller's doc comments now say "results
  screen" where they said "win dialog" (comment-only touch in
  `offline_game_controller.dart`).
- Navigation (D-30, the double-pop fix): **Play Again** reopens
  the game route with the exact retained setup via
  `pushNamedAndRemoveUntil` keeping Home (stack Home → Game).
  **Main Menu** is a single `pop()` to the Home route below
  Results — and a fresh Home is pushed only when nothing is
  below (a deep link straight to the game route). The pop (not
  a fresh Home) is load-bearing, found by probe during this
  milestone: Home offers the resume dialog exactly once per Home
  lifetime from the *frozen* startup snapshot outcome, so a
  fresh Home after Main Menu re-offered resume for the match
  that had just finished (its snapshot was deleted at
  completion) — and resuming that stale snapshot would have
  recorded the finished match a second time. Returning to the
  existing Home never re-offers. The stale-offer hazard remains
  for any *future* flow that pushes a fresh Home mid-lifetime;
  a re-check of snapshot existence in `HomeScreen` belongs with
  that flow, not here (recorded follow-up, not fixed).
- Pause is NOT in this milestone: the D-10 decision record's
  "M2.5 implements the freeze" predates the remediation plan's
  split, which assigns pause to M2.6 ("after M2.5, to avoid two
  authors editing `game_screen` AppBar/dialog code at once") —
  the remediation plan + brief govern, so `_confirmExit` and the
  AppBar restart/close paths are untouched. Note as a
  consequence: from a Play Again match (stack Home → Game) the
  AppBar close/confirm path pops to Home, while from a first
  match (stack Home → Mode → Setup → Game) it still pops to
  setup — M2.6 rationalises the exit flows.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **448/448 passed** (baseline 437 + 11 new in
`test/results_screen_test.dart`: winner avatar + match info,
record-failure notice, empty state, Main Menu lands on Home
exactly once incl. `Navigator.canPop() == false`, Play Again
reuses the exact setup incl. ruleset behaviour (a roll of 1
releases under the reused release-on-1 ruleset), the
Game → Results → Play Again / → Main Menu journeys, a resumed
finished match showing Results without re-recording, the
full-app Home → Resume → Game → Results → Play Again / Main
Menu journeys, and a scripted setup → game → results → Play
Again match driven through the UI with a cycling
`FixedDiceRoller([6, 5, 4, 3, 2, 1])` — the 1s matter: all-6s
would strand tokens at 51–55 under exact finish and the match
could never end). The two `test/app_lifecycle_test.dart`
completion tests were updated to the results route (results
screen, not dialog; `Play Again` label; the results buttons sit
below the fold in the 800x600 test viewport, so the taps use
`ensureVisible` — the same reason the new tests tap results
buttons through a helper). `flutter analyze` — **0 errors, 0
warnings, 27 info** (25 baseline + 2 in new M2.5 files, all the
pre-existing `material.dart` deprecation notice). `dart format`
clean on all M2.5-touched files. `tool/check_boundaries.sh` —
8/8 checks pass.

Scoping decisions recorded: the `LudoGame.fromState`
custom-ruleset follow-up (M3.2/M3.3) is untouched, as
instructed — and is now pinned by a test: Play Again after a
*resumed* custom-ruleset match restarts under the stock ruleset
(the loss happens at resume, not at Play Again); Play Again
after a *normal* match preserves the exact ruleset, proved by
the scripted test. The results screen is scrollable
(`SingleChildScrollView`); the full 5-width layout suite is
M2.12's. D-02's "replace win AlertDialog with a dedicated
results screen" is done; continue-to-rank stays DEFERRED.

### M2.6 — DONE (pause menu + back confirmation, M-01; D-10, D-30; 2026-11-22)

The pause half of H-09 (remediation plan §3.1 M-01, §4 M2.6,
§6 "Pause + back"):

- `lib/domain/offline_game_controller.dart`: `pause()` /
  `resume()` + `isPaused`. Pause is a freeze (D-10): both
  timers are cancelled — the AI pacing timer and the dice
  tumble — so no AI roll or move, no tumble tick and no turn
  change happens while paused, and the snapshot is untouched
  (a paused match stays resumable). State is preserved
  exactly: same turn, same legal moves, same displayed roll.
  The tumble's engine-decided value is kept in
  `_settlingRollValue` (extracted `_settleRoll()`, shared by
  the tumble timer and by `resume()`), so a tumble
  interrupted by pause settles on resume on the same value,
  with the same side effects, exactly once. `resume()` runs
  the turn-change path exactly once: an AI turn re-schedules
  its pacing timer fresh (700–1,199 ms, D-31), a human turn
  schedules nothing. Guards: `rollDice`/`applyMove` ignore
  input while paused, `_afterTurnChange` returns early while
  paused, the AI timer callback checks `_paused`, `pause()`
  is a no-op on a finished match, both are idempotent, and
  `startMatch`/`restoreMatch`/`restart()` clear the paused
  flag. The M3.2 timer-cancellation invariant is kept: no
  stale timer can act on a resumed or restarted match.
- `lib/presentation/screens/game_screen.dart`: the AppBar
  close button is now a pause button (`Icons.pause`, tooltip
  'Pause'; the refresh restart button is gone) opening the
  pause menu — an `AlertDialog` (the remediation plan's
  "bottom sheet or dialog"; dialog chosen to match the
  existing confirmation dialogs) with Resume / Restart /
  Main Menu. Restart and Main Menu reuse the existing
  confirmation dialogs; cancelling either resumes the match,
  and a plain dismissal (back button, tap outside) counts as
  Resume. `PopScope(canPop: false)` while the match is
  unfinished: system back opens the same pause menu instead
  of popping (the old back-pop deleted the snapshot with no
  confirmation at all); once finished the pop is allowed.
  While the pause dialog is open, back dismisses the dialog,
  which resumes. Exit is rationalised (M2.5 note (c)):
  Main Menu always lands on Home via a single
  `pushNamedAndRemoveUntil(AppRoutes.home, (_) => false)` —
  from a first match (Home → Mode → Setup → Game) as well as
  from a Play Again match (Home → Game); the old AppBar-close
  pop landed on setup from a first match. A fresh Home is
  pushed rather than popping to an existing one, so the
  landing is identical from every entry path including a
  deep link straight to the game route. Board taps and the
  Roll button are additionally gated on `isPaused`.
- `lib/presentation/screens/home_screen.dart`: the
  stale-resume re-offer hazard (M2.5 note (b)) is FIXED here,
  because this milestone's exit flow is the flow that pushes
  a fresh Home mid-lifetime. The resume offer re-checks
  snapshot existence (`hasSnapshot(kCurrentMatchKey)`)
  before offering: the startup outcome is frozen at launch,
  but the snapshot may have been deleted since (finished or
  exited), and offering it would restore — and at completion
  re-record — a match that is already gone. When there is
  nothing to check against (degraded startup, no
  repositories) the frozen outcome is offered as before.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **468/468 passed** (baseline 448 + 20 new in
`test/pause_exit_test.dart`: 8 controller — AI timer cancelled
while paused, resume re-schedules exactly once in the 700–1,199
ms band and the AI then acts, human-turn state preserved
exactly, mid-tumble settles on the decided value on resume,
input ignored while paused, pause/resume idempotent, pause
no-op when finished, restart while paused starts fresh
unpaused; 12 widget — pause menu contents, Resume, Restart /
Main Menu with confirmation and with cancel resuming, system
back opens the menu while playing and dismisses it while
paused, no AI move in 5 s paused then AI acts after Resume,
displayed roll + legal moves preserved, Main Menu from a first
match and from a Play Again match lands on Home exactly once,
exiting a resumed match never re-offers its deleted snapshot).
`test/app_lifecycle_test.dart`'s two clean-exit tests were
updated to the pause menu (Main Menu now lands on Home,
'Ready to play?', not the host screen). Two findings from the
re-check, both fixed in the tests, not by weakening the
production code: `test/results_screen_test.dart`'s
`pumpResumedApp` built a `ValidSnapshot` outcome with no row
in the snapshot store — the exact stale offer the re-check
refuses — so it now seeds the store first; the two
`test/app_lifecycle_test.dart` ffi startup tests needed a
real-async drain (`runAsync` + 200 ms delay, then settle)
before the dialog appears, because the re-check is a real
ffi read that does not complete inside the widget-test zone's
`pumpAndSettle` (verified by probe; production async is
unaffected). `flutter analyze` — **0 errors, 0 warnings, 28
info** (27 baseline + 1 in the new test file, all the
pre-existing `material.dart` deprecation notice). `dart
format` clean on all M2.6-touched files.
`tool/check_boundaries.sh` — 8/8 checks pass.

Scoping decisions recorded: the `LudoGame.fromState`
custom-ruleset follow-up (M3.2/M3.3) is untouched, as
instructed. No sound (D-32 follow-up), no Semantics labels
(M2.9), no tappable-dice work (M2.8), no gameplay-rule
changes. Two test-framework notes, recorded for later
milestones: `tester.pageBack()` needs a visible back button
(the game screen's AppBar leading is the pause button), so
system back is simulated with
`tester.binding.handlePopRoute()`; `pumpAndSettle` alone
does not advance the fake clock far enough to fire AI pacing
timers, so AI-turn widget tests drain with explicit
`pump(Duration(seconds: 2))` steps.

### M2.7 — DONE (AnimationController, H-05/CON-01; M-16 UI pacing test; 2026-11-22)

The animation half of H-05 (remediation plan §3.1 H-05, §4 M2.7,
§6.4 "Animation (M2.7)"):

- `lib/presentation/screens/game_screen.dart`: the state is now
  the `TickerProviderStateMixin` host for three
  [AnimationController]s. (a) **Dice tumble** — a 540 ms controller
  started when the controller reports a roll in flight; the
  displayed face cycles 1..6 from the controller's value while the
  engine's decided value is pending, and settles on the engine
  value, never a random one. The domain controller keeps its
  6 x 90 ms timer as the *state-timing* authority — the domain
  layer cannot own a Ticker, and the M2.6 pause/settle semantics
  plus the fake-timer controller tests depend on it — so the two
  run the same 540 ms and settle together; the timer is no longer
  what the user *sees*. (b) **Token hop** — a ≤250 ms controller
  interpolating one token's *rendered* centre from its pre-move
  cell to its post-move cell (endpoints from
  [boardTokenCenter]); the engine state is already final, so the
  hop animates rendering only and can never change the game. A
  move is detected by the move count rising by exactly one since
  the last build, so start/restore/restart (which reset or jump
  the count) never hop; a captured token snaps back to the yard —
  its smooth return is the M3 capture animation, not this hop.
  (c) **Legal-move pulse** — a 1,200 ms controller feeding
  [pulse] into the painter, smoothed to a 0..1..0 oscillation.
- **Pulse design deviation, recorded:** the remediation plan
  says "repeating controller", but the pulse plays **one 1,200 ms
  cycle each time legal moves newly appear** (a roll settles, a
  move leaves moves legal, a resume) and then rests at the static
  ring. A continuously repeating ticker schedules a frame on
  every vsync, so `tester.pumpAndSettle()` — which the existing
  suite uses throughout, and which the plan itself requires to
  keep passing unmodified ("existing `game_screen_test.dart`
  must still pass unmodified") — never terminates while one
  repeats. Verified by probe: with the repeating form,
  `game_screen_test.dart` and the characterization test timed out
  unmodified. The painter still receives a changing pulse and the
  ring radius/alpha oscillate; a continuous pulse is a named M3
  revisit if the harness ever moves off `pumpAndSettle`.
- `lib/presentation/widgets/ludo_board.dart`: new optional
  `pulse` (default 0 — the static ring as before), `hopTokenId` /
  `hopCenter` (rendering-only override, both null when idle); the
  legal ring's radius grows (`+ pulse * 2.5`) and alpha fades
  (`1 - pulse * 0.45`). The board is wrapped in a
  [RepaintBoundary] in the game screen (the pulse/hop repaint the
  board and nothing else). [shouldRepaint] is now content-based
  ([listEquals] on tokens — [BoardToken] implements `==`, its
  `colour` deliberately excluded — [setEquals] on the legal-move
  and safe-cell sets, plus seat/pulse/hop); the old version
  compared the token list and legal set by identity, so a new list
  (which the screen builds on every rebuild) always repainted.
- **Pause/dispose (M2.6 discipline, applied to animations):**
  pause stops all three controllers where they are — the tumble's
  engine value is kept in the controller and settles on resume,
  the hop's destination is already the engine position — and
  resume restarts the turn flow exactly once; a hop in flight is
  replaced, never overlapped; all controllers are disposed with
  the screen; a controller swap (new match) cancels the hop and
  resets the tumble. Input is locked while the tumble or a hop is
  in flight (Roll button + board taps; the hop is ≤250 ms).
- **M-16 (FR-40, D-31):** the UI-layer pacing test is DONE — the
  AI acts within 700–1,199 ms of its turn starting, asserted at
  widget level with the real pacing (not started at 699 ms,
  started by 1,199 ms, measured in 100 ms steps). The AI timeout
  fallback (UC-03 E1 — a random legal move when AI calculation
  exceeds NFR-04) is **accepted risk, NOT implemented**: Hard is
  O(4) and practically unreachable, and the remediation plan marks
  it Optional; recorded here and in TRACEABILITY rather than built.
- `lib/presentation/widgets/dice_widget.dart`: doc comment
  updated — the tumble is AnimationController-driven now; the
  CON-01 note is closed for the dice.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **490/490 passed** (baseline 468 + 22 new:
14 in `test/animation_test.dart` — tumble duration/settle/
face-cycling/input lock, hop interpolation/end-state/no-hop-
on-restart/pause-mid-hop, pulse presence/stop-on-pause,
RepaintBoundary presence, pause-mid-tumble freeze + resume
settle, restart mid-tumble, dispose mid-tumble, M-16 pacing —
and 8 in `test/ludo_board_test.dart` — shouldRepaint same
content → false, changed tokens/legal set/seat/safe cells/
pulse/hop → true, parameter defaults). The M3.2
characterization tests and the M2.6 pause tests pass
unchanged. `flutter analyze` — **0 errors, 0 warnings, 29
info** (28 baseline + 1 in the new test file, all the
pre-existing `material.dart` deprecation notice; one new
`unnecessary_import` in the first draft of the painter test was
fixed, not left). `dart format` clean on all M2.7-touched
files. `tool/check_boundaries.sh` — 8/8 checks pass.

Scoping decisions recorded: the M3 token-movement upgrade
(brief §4(C) — smooth one-cell-at-a-time movement, capture
animation returning the token to base) is still to come; this
milestone's hop is the foundation for it, not the final
movement. The `LudoGame.fromState` custom-ruleset follow-up
(M3.2/M3.3) is untouched, as instructed. No sound (D-32
follow-up), no Semantics labels (M2.9), no tappable-dice work
(M2.8), no gameplay-rule changes. Two test-framework notes,
recorded for later milestones: `pumpAndSettle` times out while
the turn banner's `CircularProgressIndicator` is spinning
(infinite animation while `rolling` is true), so tests that
open the pause menu mid-tumble use bounded pumps; after a
Resume, `pumpAndSettle` advances fake time through the whole
1,200 ms pulse cycle, so a mid-cycle pulse read needs bounded
pumps instead.

### M2.8 — DONE (illegal-tap feedback + tappable dice, M-02/FR-21; 2026-11-22)

The illegal-tap half of H-05's follow-on (remediation plan §3.1
M-02, §4 M2.8, §6.1 "Illegal-tap + tappable dice (M2.8)"):

- `lib/presentation/widgets/dice_widget.dart`: new `enabled`
  (default true, visual only) + `onTap` parameters. When `onTap`
  is given the dice is wrapped in a [GestureDetector]; when
  enabled it also carries a `Tooltip` ('Tap to roll'). Opacity is
  1.0 when a roll is available, 0.6 while rolling, 0.45 when a
  roll is not available (AI turn, paused, finished) — so the dice
  reads as disabled, not tappable, when it cannot roll. The dice
  stays 64 dp (D-09: already above the 48 dp control minimum).
  `enabled` never decides whether a tap rolls — the screen's
  handler does that — so a tap on the dimmed dice still gets
  brief feedback instead of silence.
- `lib/presentation/screens/game_screen.dart`: the dice is wired
  to [_onDiceTap] with `enabled: canRoll`, where `canRoll` is
  exactly the Roll button's condition (`isHumanTurn &&
  phase == awaitingRoll`), so the two affordances can never
  disagree about whether a tap rolls. [_onDiceTap] rolls under
  those guards; a tap that cannot roll gets SnackBar + status
  feedback naming the reason — "It's not your turn yet." (AI
  turn), "Wait for the dice to settle." (rolling), "Wait for the
  move to finish." (hop in flight), "Choose a token to move."
  (already rolled, awaiting a move) — and never rolls, never
  queues, never changes game state. The controller's own guards
  are the second line of defence (a tap racing the tumble start
  is ignored there too). [_onBoardTap] keeps the legal path
  bit-identical (legal moves hit-tested first, in engine order,
  with the M2.3 full-cell + radius area) and adds feedback only
  when no legal move was taken: a tap on any token that cannot
  move — a non-legal token of the current player, an opponent's
  token, a token tapped during the AI's turn or mid-tumble — gets
  the plan's exact message, "That token can't move now", via
  [_showIllegalTapFeedback] (SnackBar, 2 s, latest message wins
  over any showing one, plus the status line through
  [OfflineGameController.noteIllegalTap]). Taps on empty board
  area stay silent: the plan requires feedback for token taps
  only. Finished / paused taps are silent: the results screen
  (finished) and the pause dialog (paused) already own the
  screen, so no feedback path exists there. Feedback never breaks
  the M2.7 input lock and never lets a second action through.
- `lib/domain/offline_game_controller.dart`: new
  [noteIllegalTap] — display only, it replaces the status line
  until the next roll or move overwrites it. No roll, no move, no
  turn change, nothing persisted, no vibration.
- No haptic on illegal taps: the plan names the SnackBar + status
  only, and haptics are reserved for completed moves (M1.7,
  D-32). No gameplay-rule change, no new feedback channel, no
  sound.
- **Semantics deviation, recorded:** the remediation plan's M2.8
  row names a `Semantics` label ('Dice, tap to roll') for the
  dice, but this milestone's brief explicitly forbids adding
  Semantics labels (M2.9 scope, separate milestone) — so no
  Semantics widget was added here. The tooltip ('Tap to roll')
  and the GestureDetector are done; the dice label lands with
  the rest of semantics in M2.9, whose row already covers the
  dice labels ("Dice, showing X" / "tap to roll"). Nothing is
  lost — M2.9 owns it.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **503/503 passed** (baseline 490 + 13 new: 12
in `test/game_screen_test.dart` — dice tap rolls when allowed,
dice looks disabled while rolling, rapid double-tap rolls exactly
once, Roll-button-then-dice-tap rolls exactly once (shared
guard), dice tap on the AI turn ignored with feedback, dice tap
after rolling names the move, non-legal token / opponent token /
AI-turn token / mid-tumble token taps give "That token can't move
now" with SnackBar + status and unchanged state, empty-area tap
silent, feedback does not consume the turn (a legal tap still
moves afterwards) — and 1 in
`test/offline_game_controller_test.dart` —
`noteIllegalTap` changes status only, no roll/move/turn change,
no vibration). The M3.2 characterization tests, the M2.6 pause
tests and the M2.7 animation tests pass unchanged.
`flutter analyze` — **0 errors, 0 warnings, 29 info** (unchanged
from the M2.7 baseline, all the pre-existing `material.dart`
deprecation notice; no new notice). `dart format` clean on all
M2.8-touched files. `tool/check_boundaries.sh` — 8/8 checks pass.

Scoping decisions recorded: the `LudoGame.fromState`
custom-ruleset follow-up (M3.2/M3.3) is untouched, as instructed.
No sound (D-32 follow-up), no Semantics labels (M2.9), no AI
timeout fallback, no gameplay-rule changes. Two test-framework
notes, recorded for later milestones: the M2.8 widget tests run
at a tall 800x1400 viewport so the whole column fits with no
scrolling (no `ensureVisible` needed); a SnackBar lives 2 s in
fake time, so illegal-tap tests assert it right after the tap
with a bounded pump — a later `pumpAndSettle` would dismiss it
first — and dice taps on the AI turn are made with no settle at
all, since settling would fire the AI pacing timer.

### M2.9 — DONE (semantics labels, NFR-08; 2026-11-22)

The Semantics half of H-10 (remediation plan §4 M2.9, §6
"Semantics (M2.9)"), completing the plan's M2.9 acceptance
criteria — dice, Roll button, turn banner, board — plus the
honest extras the brief asked for where the framework already
provides them (avatar name + shape, setup swatches, mode cards,
icon-button tooltips, disabled states). No visual change, no
gameplay change, no haptic, no sound.

- `lib/presentation/widgets/dice_widget.dart`: one `Semantics`
  node for the whole dice (the M2.8 deferred item): 'Dice, tap
  to roll' before the first roll, 'Dice, showing X. Tap to roll'
  while a roll is available, 'Dice, showing X' when it is not,
  'Dice, rolling' mid-tumble (a passing face is never announced
  as a value), 'Dice, no roll yet' when no value exists and no
  roll is available. Button role + tap action exactly when
  `onTap` is given, through the same handler as the sighted tap
  — a screen-reader activation rolls (or gets the same brief
  feedback) — and `excludeSemantics: true`, so the decorative
  pips and the tooltip contribute no second node.
- `lib/presentation/screens/game_screen.dart`: the turn banner
  carries the plan's label ("<name>'s turn") with the name and
  status texts still readable as child nodes (the status line is
  the illegal-tap feedback channel and must never be hidden);
  the board is one labelled node — "Ludo board. <name>'s turn,
  N legal moves", updated on every build from the controller
  state (a finished match names the winner instead) — with the
  painted board contributing no semantics of its own
  (`CustomPaint` draws, it does not label).
- `lib/core/design_system/diceup_components.dart`:
  `PlayerAvatar` is one labelled node — "<name>, <shape> token,
  <colour>" (e.g. "Adeel, circle token, red") — so a screen
  reader identifies the player by name and shape, never by
  colour alone (D-27), and never hears the bare initial letter
  the disc draws. The shape follows the seat, the colour name
  follows the ring's colour (chosen colour when given, else the
  seat-order colour — `DiceUpColors.playerColor` is ordered to
  match `PlayerColour.values`).
- `lib/presentation/screens/offline_setup_screen.dart`: each
  colour swatch is a labelled button — the colour *name*, never
  the colour alone — with its state: 'Colour red, selected',
  'Colour green, taken by Player 2', 'Colour blue'. The check
  icon is decorative inside the node; the visual tooltip is
  unchanged.
- `lib/presentation/screens/mode_selection_screen.dart`: each
  tappable mode card is one labelled button (title + subtitle in
  a single node) with the same navigation as its InkWell; the
  online card is not tappable (Phase 5) and keeps its plain
  text, whose title + subtitle merge into one readable node
  with no button role.
- Not changed, verified by the tests instead: the Roll button
  (its text is its label; `onPressed: null` exposes the
  disabled state — no code change needed), the icon-only
  buttons (the pause and Home settings buttons carry their
  `tooltip` as their accessible name — `Tooltip` exposes the
  message as the node's `tooltip` property, not its `label`,
  which is the framework's own mechanism for icon buttons, so
  no extra wrapper was added), the setup SegmentedButtons /
  switches / dropdown / name fields and the settings switches
  (headings and `labelText` / titles already name them).
- **Per-token semantics nodes: out of scope, as the plan
  requires.** The remediation plan's M2.9 row says explicitly:
  "Per-token semantics nodes are out of scope this pass —
  record as a follow-up, do not fake it." The tokens are
  canvas-painted, not widgets; no overlay nodes were faked.
  The board-level node (turn + legal-move count) plus the
  avatar nodes (name + shape + colour per player) are what
  this milestone delivers for board identity. Follow-up: real
  per-token nodes (positioned semantics nodes at the token
  centres, routed through the same tap logic) — needs its own
  milestone, it is not claimed here.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **512/512 passed** (baseline 503 + 9 new in
`test/accessibility_test.dart`, group "semantics labels (M2.9,
NFR-08)": dice label before the first roll + Roll enabled +
pause tooltip, dice shows the rolled value + Roll disables +
board counts 4 legal moves after a 6, semantics tap on the
dice rolls, banner + board labels follow the turn to Player 2
after a dead 3, avatar label carries name/shape/colour with no
bare-initial node, setup swatches labelled with
selected/taken state incl. a tap moving the selection, mode
cards labelled buttons with the online card not a button, Home
settings button labelled, disabled Sound switch exposes its
disabled state vs the enabled Vibration switch). The 9 new
tests initially failed 8/8 and taught three framework facts,
recorded here: (1) a `SemanticsHandle` must be disposed inline
at the end of the test body — the end-of-test verification
runs before `tearDown` callbacks, so `addTearDown(handle
.dispose)` still leaks; (2) `find.bySemanticsLabel` only
matches nodes owned by a render object with its own semantics
— plain title texts are found through `tester.getSemantics`
on the text widget, and `find.semantics.byPredicate` over the
real tree; title + subtitle merge into one node joined by
`\n` (mode cards, switch titles); (3) `Tooltip` exposes its
message as the semantics `tooltip`, not the `label`, so
icon-button tooltips are verified with `find.byTooltip`, and
`SemanticsNode.hasFlag` is deprecated — flag assertions now
use `getSemanticsData().flagsCollection` (`isButton` bool,
`isEnabled` / `isSelected` `Tristate`).
`flutter analyze` — **0 errors, 0 warnings, 29 info** (unchanged
from the M2.8 baseline, all the pre-existing `material.dart`
deprecation notice; no new notice — one `unintended_html`
notice from angle brackets in a new doc comment was fixed
during the milestone). `dart format` clean on all
M2.9-touched files (`--set-exit-if-changed` passes on the 6
files). No device screen-reader verification — automated
semantics tests only; device traversal is outstanding (M4).

Scoping decisions recorded: NFR-08's three clauses now each have
named passing tests — 48 dp controls (M2.3), 14 sp body text
(M2.3), distinguishable-by-more-than-colour avatars/tokens
(M2.4) and semantics labels (this milestone, automated tests
only — device screen-reader traversal is outstanding, M4, so
the accessibility fix is not claimed complete on a device).
Board tokens stay exempt from 48 dp per D-09 (geometric).
The `LudoGame.fromState` custom-ruleset follow-up (M3.2/M3.3)
is untouched, as instructed. No sound (D-32 follow-up), no
AI timeout fallback, no gameplay-rule changes.
