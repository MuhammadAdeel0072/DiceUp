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

### M3.4 — DONE (import boundary rule, M-07; 2026-11-22)

Option A from remediation plan M3.4 (script + CI job), M-07 / SDD
§4.2. The M3.3 script was verified both ways first, then extended
from 8 to 12 checks.

Rules enforced by `tool/check_boundaries.sh` (12 checks, all pass on
the clean tree):

- Domain purity: no Flutter, no Riverpod, no storage (`sqflite` /
  `package:diceup/data`), no `dart:io` / network (`package:http`,
  `package:dio`) — the last two are NEW in M3.4; the M3.3 script did
  not check them — and no import of the presentation/data layers
  (NEW; M3.3 only covered `package:diceup/data` via the storage
  check, not relative `../data/` / `../presentation/` imports).
- `RandomDiceRoller` used only in the engine + tests (NEW; NFR-18
  online boundary guard — no presentation file uses it today).
- No NEW presentation → data import (NEW): only the six
  grandfathered files may import `data/` — see the gap note below.
- Unchanged from M3.3: only the provider graph constructs
  `OfflineGameController`; no screen constructs a SQLite repository,
  the engine, or `AppDependencies`; the game screen imports no data
  layer.

Both-ways evidence (scratch copies, deleted afterwards — never in
staging):

- Clean tree: script exits 0, 12/12 checks pass.
- Negative probe (the plan §6 case): `import
  'package:flutter/material.dart';` added to
  `lib/domain/engine/board.dart` → script fails, exit 1.
- One probe per NEW check, each failing with exit 1: `dart:io`
  in `board.dart`; `package:diceup/presentation/foo.dart` in
  `board.dart`; `RandomDiceRoller` referenced in
  `game_screen.dart`; a `data/local` import added to
  `settings_screen.dart`. The scratch copy passed again once the
  probes were reverted, then was deleted.

Gap found in the M3.3 script, and two deliberate deviations from
the M-07 letter (also recorded in the script header):

- The blanket "presentation imports no data" ban is NOT enforceable
  yet: five screens (`app_routes`, `splash_screen`, `home_screen`,
  `offline_setup_screen`, `app_dependencies_scope`) still import the
  data layer through `AppDependenciesScope` (M3.3 deferred their
  migration one screen at a time), and the provider graph
  legitimately imports it as the composition root. The M3.4 check
  therefore enforces "no NEW presentation → data import" against
  that grandfathered list of six files; the blanket ban replaces
  the list once those screens migrate.
- The `RandomDiceRoller` check is stricter than M-07's letter,
  which also allows offline-presentation: nothing there uses it
  today, so the check allows engine + tests only. If offline
  presentation ever needs it, add an explicit allowlist entry with
  a reason — do not silently widen the grep.

`analysis_options.yaml` comment correction (no analyzer setting
changed): the old comment sat under `linter: rules:` next to
`depend_on_referenced_packages: true`, implying that lint rule
enforces the boundary. It does not — it only requires directly
imported packages to be listed in `pubspec.yaml`. The corrected
comment states the boundary is enforced by
`tool/check_boundaries.sh` (CI job `boundaries`), and that
`depend_on_referenced_packages` does something different and must
not be mistaken for the boundary rule. `depend_on_referenced_packages`
stays, per M-07.

Local check script + CI (new):

- `diceup_app/tool/check.sh` (new): `flutter pub get`, `dart
  format --output=none --set-exit-if-changed .`, `flutter analyze
  --no-fatal-infos`, `flutter test`, `sh tool/check_boundaries.sh`;
  run as `sh tool/check.sh` from anywhere. Exit 0 end to end.
- `.github/workflows/ci.yml` (new, repo root): jobs `test`,
  `analyze`, `format`, `boundaries`; Flutter 3.50.1 via
  `subosito/flutter-action@v2`; the `boundaries` job needs no
  toolchain (pure grep). The `vectors` (M3.6) and `coverage`
  (M3.7) jobs are deliberately NOT added — later milestones extend
  the workflow; the same note is in the workflow file's comments.
- Analyze-gate nuance (found by probe during this milestone):
  plain `flutter analyze` exits 1 on the 33 known info-level
  notices, so both `check.sh` and the CI `analyze` job use
  `flutter analyze --no-fatal-infos`. The gate is therefore "0
  errors / 0 warnings" — errors and warnings stay fatal by default
  and still fail the gate. The 33 infos are all the same
  pre-existing `material.dart` deprecation notice
  (known/unactionable; the count was 17 at audit time, 24 at M3.3,
  33 now — it grows as files are added, same notice each time).

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local
only): `flutter test` — **539/539 passed** (no new tests: M3.4
adds enforcement, not behaviour). `flutter analyze` — **0 errors,
0 warnings, 33 info** (all the pre-existing `material.dart`
notices). `dart format --output=none --set-exit-if-changed .` —
**0 changed** (97 files; the M3.3-era 45-file drift is gone, format
is clean tree-wide). `tool/check_boundaries.sh` — **12/12, exit 0**.
`tool/check.sh` — **exit 0 end to end**. No new dependencies; no
code file touched except the boundary script; M2.13's platform
files and M2.14's design-system files untouched.

Deliberately left for later (not this milestone):

- Option B (`custom_lint` + `import_lint` for in-editor
  enforcement) — documented follow-up, not implemented.
- CI jobs `vectors` (M3.6) and `coverage` (M3.7, gated only after
  the measured number is ≥90% locally).
- The blanket presentation → data ban (gated on the M3.3 screen
  migration off `AppDependenciesScope`).
- The Workflows permission is not verifiable from this
  environment: the workflow file is pushed separately from the
  code, and a 403 on that push is a blocker to report (and resolve
  via Anti), not a reason to drop the workflow. The pubspec.lock
  stash + `../.vscode/` on Anti's Windows machine (D:\DiceUp) are
  likewise not verifiable from this environment; untouched.

### M3.5 — DONE (painter geometry, M-08/D-20; 2026-11-22)

Push landed as `411e04e560f89a2b4ad5e0566485f8d78addc25e` (verified live
via `list_commits`; remote head `411e04e56`). The first push attempt was
interrupted by a runtime restart with no confirmed result; the coordinator
verified the remote head was unchanged (`6e3ad9ec`) and the saved log was
empty before retrying the identical push.

What was wrong (remediation plan §3.2 M-08, §2 C-15): three
defects, all in the painter except the pinned constant.

- Dead 5th home-path cell: the painter drew 5 home-path cells per
  seat, but the engine only ever occupies indices 0..3 (steps
  52..55; step 56 is home). `Cell.homePath(4)` occurred nowhere in
  `lib/` or `test/` — a drawn cell no token could ever reach.
- Duplicated geometry: the painter mapped tokens by
  `seatIndex * 13` and carried its own hardcoded copy of the safe
  set. The game screen already passed each token's chosen colour
  into `BoardToken`, but `boardCellForToken` ignored it — a latent
  FR-14 break once users pick colours (M2.2): a seat-0 token that
  picked green would still travel red's path.
- `Board.homePathLength` was 5, pinning the wrong split, and
  `test/engine/snapshot_test.dart:93` asserted 5.

Property / equivalence tests FIRST (`test/board_geometry_test.dart`,
13 tests), run against the unfixed painter: **9 passed, 4 failed**
— the failures are the known failures the fix resolves, recorded
here, never skipped:

- "each colour has exactly Board.homePathLength home-path cells"
  (`homePathLength` still 5, 5 drawn cells per seat).
- "every drawn home-path cell is reachable (no dead cells)": red
  home-path cell 4 `Point(7, 5)` is never occupied
  (`boardCellForToken` returns null — step 56 is home).
- "the last home-path cell leads into home via the approach cell"
  (the last drawn cell WAS the approach cell, distance 0).
- "token positions follow the chosen colour, not the seat": seat 0
  with colour green at step 1 — painter `(6, 1)` (red start),
  engine `(1, 8)` (green start).

The fix (D-20 already decided: 51 track + 4 home-path + home =
56; engine as-is):

- `Board.homePathLength` 5 → 4; `snapshot_test.dart:93` updated
  5 → 4 — corrected to the decided value, not weakened.
  `homePathLength` never fed the engine's `cellAt` (it uses
  `lastTrackStep` = 51; the only reader of the constant was the
  snapshot test), so no engine rule changed. `Cell` docstrings
  corrected (home-path index 0..3).
- `_homePaths` is now 4 cells per seat, keyed by `PlayerColour`
  (a `Map`, not a seat-indexed list). The former 5th cell is
  redrawn as part of home (`_homeApproachCells`: red `(7, 5)`,
  green `(5, 7)`, yellow `(7, 9)`, blue `(9, 7)`) in the seat's
  full colour, so the home column flows into the centre instead of
  ending one cell short — and it is NOT a token cell:
  `boardCellForToken` never returns it.
- Colour-based mapping: `BoardToken.effectiveColour` (chosen
  colour, seat-order default when null) is the mapping key
  everywhere — `boardCellForToken` uses
  `board.startCell(colour)` instead of `seatIndex * 13`, home
  paths are looked up by colour, yard slots group by colour
  (the quadrants are fixed colour positions), the start-cell tint
  comes from `_colourByStartCell`, derived from
  `Board.startCells` (no second copy of the mapping), and the
  painter takes a `board` parameter (default `const Board()`)
  with `safeTrackIndices` defaulting to `Board.safeCells`.
  New public accessors for the tests: `trackCells`,
  `homePathCells(colour)`, `homeApproachCell(colour)`.
- No behaviour change beyond the fix: token shape stays
  per-seat (matching `PlayerAvatar`), the `currentSeat` marker,
  hop and pulse are untouched, and `game_screen.dart` needed no
  change — it already passed `colour` into every `BoardToken`,
  so default colour assignments render byte-identically.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local
only): `test/board_geometry_test.dart` — **13/13 passed**,
including the 4 previously-failing tests. `flutter test` —
**552/552 passed** (539 baseline + 13 new). `flutter analyze` —
**0 errors, 0 warnings, 33 info** (all the pre-existing
`material.dart` deprecation notices; the new test file carries
none). `dart format --output=none --set-exit-if-changed .` —
**0 changed** (98 files). `tool/check_boundaries.sh` —
**12/12, exit 0** (the painter's new `board.dart` import is
presentation → domain, allowed). No new dependencies; no rule
changes; no schema changes; no sound.

Deliberately left for later (not this milestone):

- The SDD §6.2 text amendment ("four home paths of 5 coloured
  cells each" → 4) is an Anti-approved SDD edit, not applied to
  the `.docx` here — D-20 is already recorded in §8 as an
  approved deviation from SRS §7.1.
- The M3 smooth per-cell token movement + capture-return
  animation (brief §4(C)) are premium work, not this milestone;
  the M2.7 hop is still the movement foundation.
- No device claims; no iOS/Android build run.

### M3.6 — DONE (shared rule vectors, H-06/D-05; 2026-11-22)

The shared rule vectors (remediation plan §4 M3.6, §3.1 H-06, §6
verification "Vectors (M3.6)"):

- `docs/ruleset.md` (new): the single language-neutral rule
  specification (SDD §6.9, NFR-39). SDD Table 6.2 reproduced
  faithfully (all 14 rows, BR-01…BR-14) + the pinned board geometry
  (52-cell track; starts red 0 / green 13 / yellow 26 / blue 39;
  stars 8 / 21 / 34 / 47; safe set {0, 8, 13, 21, 26, 34, 39, 47}
  per D-15) + the pinned split **51 track + 4 home-path + home =
  56** (D-20) + the pinned `RulesetConfig` version **`1.0.0`**
  (BR-14) + five worked examples (release on six; third six;
  capture vs safe cell; exact finish; home-path entry + win).
  §5 records every SDD/SRS-vs-engine disagreement explicitly —
  the engine wins in each case, nothing silently resolved:
  (1) the "5 home-path cells" wording (SDD §6.2, SRS §7.1) vs the
  D-20 4-cell split; (2) SDD §6.5 cites BR-25 for winning — no
  BR-25 exists, winning is BR-11; (3) SDD §6.5 Algorithm 1
  pseudocode would release a yard token to step 6 — the engine
  releases to step 1 (BR-04); (4) the §6.2 table is uncaptioned
  ("Table 6.1" / "Table §6.2" elsewhere) — reproduced here as
  Table 6.2; (5) SDD §6.4 lists a MOVING phase the engine does
  not have (animation-only); (6) third-six precedence is
  engine-defined (checked before legal moves); (7) safe-cell
  indices are engine-pinned (D-15), the SDD/SRS name none;
  (8) forfeit (BR-15) has no engine vector — offline forfeit is
  forfeit-by-exit (SDD §6.3), not an engine transition, so the
  SDD §6.9 "forfeit" edge case is out of scope for the Dart suite
  and recorded as such, not a gap.
- `diceup_app/test/vectors/rules.json` (new): **23 cases** (≥14
  required), each self-contained — a strict `GameState` snapshot,
  the full ruleset in one place, a fixed dice sequence, and the
  expected legal moves + outcome after every replayed roll/move.
  Cases per rule family: BR-04 release — `release-only-on-six`,
  `release-on-six`, `release-on-one-variant`; BR-05 movement —
  `passing-over-never-captures`; BR-06 extra turn —
  `extra-turn-on-six-disabled`, `extra-turn-on-capture`,
  `extra-turn-on-capture-disabled`, `extra-turn-on-home`,
  `extra-turn-on-home-disabled` (one disabled case per trigger);
  BR-07 third six — `third-consecutive-six`,
  `third-six-limit-off`, `three-sixes-in-sequence` (six, move,
  six, move, six across three rolls); BR-08 capture —
  `capture-on-track`, `multi-token-capture`; BR-09 safe cells —
  `no-capture-on-safe-start` (track 13), `no-capture-on-safe-star`
  (track 8); BR-10 home/exact — `exact-finish-overshoot-illegal`,
  `exact-finish-off-overshoot-lands-home`, `home-path-entry`
  (step 53 = home-path index 1); BR-11 win —
  `win-first-to-four-home`; BR-12 stacking —
  `same-colour-stacking`; BR-13 no legal move —
  `release-only-on-six`, `no-legal-move-six-extra-roll` (a six
  with no legal move still grants its extra roll, same player
  re-rolls); FR-21 — `illegal-move-rejected` (applying a
  non-legal move throws `ArgumentError`, state byte-identical).
  No vector contradicts the engine: every expectation was
  hand-computed from `docs/ruleset.md` §1 step arithmetic and
  passed first run — no vector was "fixed" to match the engine
  after the fact.
- `diceup_app/test/vectors/rules_vectors_test.dart` (new): loads
  `rules.json`, validates its shape strictly (exact key sets at
  every level — unknown fields/cases/ops fail loudly via a
  dedicated `rules.json is a valid vector file` test; the
  embedded ruleset must deep-equal the case ruleset and the
  `rulesetVersion`; dice must be 1..6; token/step ranges
  checked), then replays each case through
  `LudoGame.fromState` + `rollDice` / `legalMoves` / `applyMove`
  with a `FixedDiceRoller`, asserting the expected roll, legal
  moves, `MoveResult` fields, phase/current player after every
  step, and the final state (tokens, `lastRoll`,
  `consecutiveSixes`, `lastRollWasThirdSix`,
  `lastRollHadNoLegalMove`, winner). The runner passes each
  case's ruleset explicitly to `fromState` — the engine does not
  infer it from the snapshot (the M3.2/M3.3 follow-up that
  `fromState` uses the stock ruleset, not the restored state's
  embedded ruleset, is untouched, as instructed). A meta-test
  asserts ≥14 cases and coverage of BR-04…BR-13.
- CI job `vectors` added to the **staged** `.github/workflows/ci.yml`
  (runs `flutter test test/vectors/rules_vectors_test.dart` on
  Flutter 3.50.1). The workflow file itself is **not in this
  milestone's push manifest**: it is still unpushed because the
  GitHub App lacks Workflows: Read and write (the push 403s —
  same blocker as M3.4). Until the permission is fixed, the gate
  is the full local suite via `tool/check.sh`, which includes
  the vector runner. The `coverage` job stays deferred to M3.7.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local
only): `test/vectors/rules_vectors_test.dart` — **25/25 passed**
(23 cases + the ≥14-cases test + the rule-family coverage test).
`flutter test` — **577/577 passed** (552 baseline + 25 new).
`flutter analyze` — **0 errors, 0 warnings, 33 info** (all the
pre-existing `material.dart` deprecation notices; the new test
file carries none). `dart format --output=none
--set-exit-if-changed .` — **0 changed** (99 files).
`tool/check_boundaries.sh` — **12/12, exit 0** (no `lib/` file
touched). No new dependencies; no engine rule changed; no schema
changes; no sound.

Negative evidence (both probes in scratch, file regenerated
afterwards, suite green again): (1) corrupting one expectation
(`capture-on-track` `toSteps` 26→24) failed exactly that case — 24 passed / 1 failed, no other case
affected; (2) adding an unknown field (`bogusField`) to a case
failed the load-validation test with the whole file rejected
(0 passed / 1 failed) — unknown fields are never silently
ignored. The mutations were reverted by regenerating
`rules.json` from the authoring spec and re-verifying the
restored values (`capture-on-track` 23→26, no stray fields).

Runner bug found during development (fixed, no engine or vector
change): a local variable named `expect` in the `move` branch
shadowed the test framework's `expect` across the whole `switch`
body (Dart switch cases share scope), so the `moveIllegal`
branch failed to compile — renamed to `moveExpect`.

Deliberately left for later (not this milestone):

- The TypeScript side of the shared vectors (Phase 4, D-05) —
  the Dart side is the conformance target; the vectors are
  written language-neutrally for it.
- The `coverage` CI job (M3.7, gated only after the measured
  number is ≥90% locally).
- The SDD §6.2 text amendment ("5 coloured cells" → 4) is an
  Anti-approved SDD edit, not applied to the `.docx` here — D-20
  is already recorded in §8 as an approved deviation from
  SRS §7.1, and `docs/ruleset.md` §5.1 records it again.
- No device claims; no iOS/Android build run.

### M3.7 — DONE (coverage gate, NFR-26; 2026-11-22)

Coverage to ≥90% over the rule logic (remediation plan §4 M3.7, §6.1
exit criteria, §6.2 NFR-26; M-09). Measured first, then tested the
gaps — no production code changed, no threshold weakened, no test
edited to force green. The CI `coverage` job is still NOT added to
`.github/workflows/ci.yml` — workflow files are blocked (Workflows
403); the local `flutter test --coverage` measurement below is the
gate until the permission is fixed.

Starting coverage (measured before any new test, `flutter test
--coverage`, full suite 591/591 green): **89.9% over
`lib/domain/engine/` + `lib/domain/ai/` (523/582 lines)** — just
below the gate, with four files below the 80% floor. Whole-app
coverage at the same point was 93.7% (3644/3890).

| file | LF | LH | % | uncovered lines |
| --- | --- | --- | --- | --- |
| `lib/domain/ai/ai_player.dart` | 97 | 96 | 99.0% | 60 |
| `lib/domain/engine/board.dart` | 27 | 20 | 74.1% | 45–46, 52–53, 55–56, 119 |
| `lib/domain/engine/dice_roller.dart` | 17 | 15 | 88.2% | 33, 54 |
| `lib/domain/engine/game_state.dart` | 92 | 92 | 100.0% | — |
| `lib/domain/engine/json_validation.dart` | 62 | 60 | 96.8% | 160–161 |
| `lib/domain/engine/ludo_game.dart` | 131 | 124 | 94.7% | 148, 341–343, 345–346, 348 |
| `lib/domain/engine/move.dart` | 25 | 14 | 56.0% | 15–16, 18–19, 31, 39–40, 83–86 |
| `lib/domain/engine/player.dart` | 43 | 39 | 90.7% | 28, 56, 150–151 |
| `lib/domain/engine/player_colour.dart` | 1 | 1 | 100.0% | — |
| `lib/domain/engine/ruleset_config.dart` | 55 | 43 | 78.2% | 130–139, 147–148 |
| `lib/domain/engine/token.dart` | 32 | 19 | 59.4% | 31–32, 55, 85, 87–91, 93–94, 96, 98 |

What the gaps were (every uncovered line mapped to its code before
any test was written): value-object boilerplate (`Token`/`Move`/
`TokenRef`/`Cell`/`RulesetConfig` `==`/`hashCode`/`toString`,
`Move.tokenRef`, `MoveResult.toString`, `Cell.isYard`/`isHome`,
`Token.isInHomePath`, `Token`/`Player`/`AiPlayer.copyWith` no-arg
fallbacks, `InvalidMatchConfig`/`InvalidRulesetConfig.toString`);
`Board.cellAt` throw on steps > 56 and `isSafe` on home-path/home
cells; `FixedDiceRoller` empty-list and exhaustion throws; the
`LudoGame` invalid-dice guard and the whole of `nextTurn()` (FR-19,
never called by any test); `Player` 3-token constructor guard.

What was done (73 new tests, all asserting behaviour):

- `test/engine/ruleset_config_test.dart` (new, 15 tests): SDD
  defaults, `releaseRolls` for all four flag combinations, all
  three `validate()` throws with exact messages, `toJson` field
  set, `fromJson` round-trip + missing/wrong-typed field rejects +
  invalid embedded ruleset wrapped as `FormatException`, `==` /
  `hashCode` / Set collapse, one-field-at-a-time inequality,
  `InvalidRulesetConfig.toString`.
- `test/engine/value_objects_test.dart` (new, 34 tests): `Cell`
  constructors / `isYard` / `isHome` / equality / `toString`;
  `Board.cellAt` throw + negative-steps yard + every home-path step
  + `isSafe` on home-path/home/track/yard + all four start cells;
  `Token` position predicates at the 0/51/52/56 boundaries, `cell`,
  `canMove` (yard release, exact-finish boundary, non-exact home
  token), `copyWith` no-arg + steps, `sentToYard`, JSON round-trip,
  equality, `toString`; `Move`/`TokenRef` conversion, equality,
  `toString`; `MoveResult` defaults, winning-move and home-move
  exact strings via real `applyMove` results; `Player` 3-token
  guard, `tokensHome`/`hasWon`, `copyWith` no-arg + tokens,
  `toJson`; `AiPlayer.copyWith` no-arg + difficulty/tokens;
  `InvalidMatchConfig.toString`.
- `test/engine/variants_test.dart` (new, 20 tests): invalid dice
  values 7 and 0 rejected with `StateError` and the state unchanged
  (via a test-only constant roller); `FixedDiceRoller` empty list,
  exhaustion, cycling; `nextTurn` happy path (clockwise, wrap,
  sixes-count reset, play continues), both `StateError` guards
  (roll outstanding, finished); non-exact-finish overshoot lands
  home from the track and from the home path; the three
  extra-turn switches off (`extraTurnOnSix` / `extraTurnOnCapture` /
  `extraTurnOnHome` — capture/home still reported, turn passes);
  release-on-1-only (a 6 offers no move but keeps the roll);
  `maxConsecutiveSixes` 1, 2 and 0.
- `test/engine/ai_test.dart` (+4 tests, "Hard scoring weights"):
  `scoreMove` pins the documented SDD §7.3 weights with a full
  jitter of slack on each side — finish 100 + safe 15, capture 60
  over a release, danger −40 against a safe landing, leaving a
  teammate exposed −10 against the same move alone.

No dead code was removed. `nextTurn`, `Move.tokenRef`,
`Token.isInHomePath` and `Cell.isYard`/`isHome` have no production
callers (verified by whole-app grep), but they are public engine
API implementing documented rules, so they are pinned by tests
rather than deleted — removing public API is out of scope for a
coverage task. One line pair stays uncovered by design:
`json_validation.dart:160–161`, the belt-and-braces `tryParse ==
null` throw in `requireIso8601DateTime` — the regex + component
checks guarantee `tryParse` succeeds for any input that reaches
it, so the guard is genuinely unreachable; it protects the
invariant and is kept, not counted as covered.

One test expectation was wrong, not the engine: the first
`maxConsecutiveSixes: 1` test assumed the second six would be the
unplayed one, but the engine forfeits the six that *reaches* the
limit — with a limit of 1 that is already the first six (the same
rule as the default-3 third six, confirmed by the snapshot tests'
`consecutiveSixes` bounds). The test was corrected to pin the
actual behaviour; no engine code was touched.

Final coverage (`flutter test --coverage`, full suite green):
**99.7% over `lib/domain/engine/` + `lib/domain/ai/` (580/582
lines)** — gate ≥90% passed, per-file floor 80% passed. Whole-app
coverage 95.1% (3701/3890).

| file | LF | LH | % | uncovered lines |
| --- | --- | --- | --- | --- |
| `lib/domain/ai/ai_player.dart` | 97 | 97 | 100.0% | — |
| `lib/domain/engine/board.dart` | 27 | 27 | 100.0% | — |
| `lib/domain/engine/dice_roller.dart` | 17 | 17 | 100.0% | — |
| `lib/domain/engine/game_state.dart` | 92 | 92 | 100.0% | — |
| `lib/domain/engine/json_validation.dart` | 62 | 60 | 96.8% | 160–161 (unreachable guard, see above) |
| `lib/domain/engine/ludo_game.dart` | 131 | 131 | 100.0% | — |
| `lib/domain/engine/move.dart` | 25 | 25 | 100.0% | — |
| `lib/domain/engine/player.dart` | 43 | 43 | 100.0% | — |
| `lib/domain/engine/player_colour.dart` | 1 | 1 | 100.0% | — |
| `lib/domain/engine/ruleset_config.dart` | 55 | 55 | 100.0% | — |
| `lib/domain/engine/token.dart` | 32 | 32 | 100.0% | — |

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **664/664 passed** (baseline 591/591 + 73 new,
0 failed, 0 skipped); `flutter test --coverage` — **580/582 =
99.7%** scoped (see table), whole app 3701/3890 = 95.1%;
`flutter analyze` — **0 errors, 0 warnings, 37 info** (the
coordinator's baseline; all 37 are the pre-existing `material.dart`
deprecation notices — the new files initially added 4 warnings +
1 info, all fixed before verification: an unused import, three
const-duplicate set literals, one unrelated-type equality);
`dart format --output=none --set-exit-if-changed .` — **0 changed**
(107 files); `tool/check.sh` — **exit 0 end to end** (pub get,
format, analyze `--no-fatal-infos`, test 664/664, boundaries 12/12,
strings 3/3). No pre-existing test failed; no test was weakened,
deleted or reworded. Environment note: every flutter invocation
ran with `TMPDIR` on the big volume and a hard `timeout` (300
targeted / 900 full-suite), per the M3.7 brief.

Outstanding: the CI `coverage` job (blocked on the Workflows
permission, same wall as the `vectors`/`strings` jobs — the gate
is measured locally until it is fixed); `nextTurn` has no
production callers (public FR-19 API, retained + tested — a
decision to remove it, if ever wanted, belongs to Anti).

### M3.8 — DONE (NFR-04 per-call + NFR-02 repaint, M-09; 2026-11-22)

**NFR-04 per-call test + NFR-02 repaint fix (M-09).**
- NFR-04: new test "Hard decides a single move within 500 ms (p95)" in
  `diceup_app/test/engine/ai_test.dart` — one Hard decision over the 200
  seeded positions (`Random(1234)`), each call timed, p95 asserted
  < 500 ms. Measured on the VM host: n=200, median 50 µs,
  **p95 = 0.12 ms**, max 62.9 ms (first-call warmup). The old aggregate
  test ("Hard decides within the 500 ms budget (NFR-04)") is kept as a
  smoke check only (1,000 calls in 74 ms).
- NFR-02: M2.7's `RepaintBoundary` + content-based `shouldRepaint`
  verified in place (7 tests in `test/ludo_board_test.dart`, wrap test
  in `test/animation_test.dart`). The missing half was the dice-tick
  rebuild assertion: the first version of the new test failed, exposing
  that `OfflineGameController.rollDice()` notified listeners on every
  90 ms tumble tick, rebuilding the whole screen including the board.
  Fix: the intermediate `_notify()` was removed
  (`lib/domain/offline_game_controller.dart`); the timer, 6×90 ms
  schedule, 540 ms settle, and intermediate `_displayedRoll`
  bookkeeping are unchanged — the screen renders its own tumble face
  while rolling, so nothing visible changed on those ticks. New test
  "a dice-tumble tick does not rebuild the board" in
  `test/animation_test.dart` (painter identity across tumble pumps)
  passes.
- Verification: `flutter test` 579/579, `flutter analyze` 0/0/33 info
  (pre-existing), `dart format` clean, `tool/check_boundaries.sh`
  12/12.
- Outstanding: the 50 fps number itself is device-only (DevTools frame
  timing on the reference device) — M4 item, not measured here.

### M3.9 — DONE (dart test story, M-06 / H-02a; 2026-11-22)

`dart test` story (M-06 / H-02a). Option A verified and corrected: the M0
pubspec comment ("`dart test` fails, exit 65") was inaccurate as a blanket
statement. Bare `dart test` was re-run: with a standalone Dart SDK it fails
at version solving on `flutter_test` from the SDK (exit 65, reproduced);
with the Flutter-bundled `dart` the pure-Dart engine tests pass
(`test/engine/rules_test.dart` 27/27, rules+AI+snapshot 48/48, including
from a clean checkout with no `.dart_tool/`). The whole `test/engine/`
directory does NOT pass under `dart test` (exit 1): `seat_ai_difficulty_test.dart`
imports `package:flutter_test` and fails to load (`dart:ui` is not available
on the plain Dart VM), although it only uses `group`/`test`/`expect`.
Fixes (comment/doc only): corrected the `pubspec.yaml` comment to the
verified truth, added a header note to `test/engine/test_helpers.dart`
(imported by all engine tests), added a "Running tests" section to
`docs/README.md`. Canonical runner remains `flutter test`.
Verification: `flutter test` — **579/579 passed**; `flutter test test/engine/` —
**52/52 passed**; `flutter analyze` 0 errors / 0 warnings / 33 info
(pre-existing material.dart notices); `dart format` clean;
`tool/check_boundaries.sh` 12/12.

Option B (pure-Dart package split, `packages/diceup_engine/`) recorded as
DEFERRED — decision needed from Anti. New evidence weakens its payoff:
`dart test` already runs the pure engine tests with Flutter installed, so
the split would buy only a Flutter-free/standalone-Dart runner and CI
variant, at the cost of a second pubspec, a package boundary to police,
and re-verification while CI pushes are blocked (Workflows 403). Do the
split only if Anti wants a Flutter-free engine runner. Possible trivial
first step if approved: swap the `flutter_test` import in
`seat_ai_difficulty_test.dart` to `package:test` (it uses only
`group`/`test`/`expect`).

### M3.10 — DONE (strings externalisation, M-10/NFR-38; 2026-11-22)

Strings externalisation (remediation plan §4 M3.10, §6.1 Strings row,
§6.2 NFR-38; M-10). Game screen first, then the rest, after the M3.2
controller extraction so the same strings were not touched twice.

What was done:

- `pubspec.yaml`: `flutter_localizations` (SDK) added;
  `flutter: generate: true` added. `l10n.yaml` (new) pins the codegen:
  `arb-dir: lib/l10n`, template `app_en.arb`, output
  `app_localizations.dart`. Flutter 3.50 removed the synthetic
  `flutter_gen` package (`--synthetic-package` is deprecated and cannot
  be enabled), so the generated classes live in `lib/l10n/` next to the
  `.arb` file and are committed like any other source file — verified
  by probe: with the generated files removed, `flutter test`
  cannot load the widget tests (compile error), and neither
  `flutter pub get` nor `flutter test` regenerates them in this
  environment, so committing them is the mechanism, not a convenience.
  Re-run `flutter gen-l10n` after editing `app_en.arb`.
- `lib/l10n/app_en.arb` (new): **179 keys**, every user-visible
  string in `lib/presentation/` plus the shared components that render
  UI copy, each with a description and typed placeholders where
  ambiguous. All rendered strings are byte-identical to before — no
  test was edited, weakened or reworded.
- `lib/l10n/app_strings.dart` (new): `stringsOf(context)` — the
  `AppLocalizations` for the context's locale, falling back to
  `AppLocalizationsEn()` when no delegates are registered above the
  context. The fallback exists because many widget tests pump bare
  `MaterialApp`s without `localizationsDelegates`; English is the
  initial language (NFR-38), so the fallback renders exactly the
  strings the tests assert. Plus the enum→localised-name mappings
  (`colourName`, `shapeName`, `difficultyName`, `monthNames`).
- `lib/main.dart`: `localizationsDelegates` +
  `supportedLocales` on both `MaterialApp`s (loading splash and ready
  app).
- Migrated per screen, game screen first: `game_screen.dart`
  (pause/restart/leave dialogs, Roll button, safe-cells hint, illegal
  tap + dice-tap feedback, board/turn-banner semantics, player chips),
  `home_screen.dart` (resume dialog, startup snackbars, online
  login-prompt), `mode_selection_screen.dart`, `offline_setup_screen.dart`
  (seat cards, colour swatches + semantics, difficulty names, ruleset
  switches, validation errors), `results_screen.dart`, `history_screen.dart`
  (list, detail dialog, date/duration formats, month names),
  `statistics_screen.dart`, `settings_screen.dart`, `splash_screen.dart`,
  `dice_widget.dart` (tooltip + semantics labels), and the shared
  components in `diceup_components.dart` (`PlayerAvatar` semantics label,
  `ErrorView` retry action, `ConfirmationDialog` default cancel action —
  now nullable, resolved to the localised "Cancel" in `build`).
- The startup/record/caption messages are now rendered from the `.arb`
  in the UI (`homeDatabaseError`, `homeDatabaseRecovered`,
  `homeSnapshotCorrupt`, `resultsRecordFailed`,
  `statisticsPerPlayerCaption`) with byte-identical English; the
  data/presentation-layer constants (`kDatabaseRecoveryMessage`,
  `kCorruptSnapshotMessage`, `kStartupDatabaseErrorMessage`,
  `kMatchRecordFailedMessage`, `kPerPlayerWinsCaption`) stay as the
  data layer's source of truth and the values the tests assert against
  (`find.text(k…)`, unchanged). The guard's third check forbids
  rendering those constants directly in `Text()`.
- `MatchResult.modeLabel` removed (results screen renders the mode via
  `AppLocalizations` now; it had no other reader and no test used it).
- `tool/check_strings.sh` (new): 3 grep checks — no raw literal in
  `Text()`, no raw literal in a title/subtitle/hint/message/label/
  labelText/tooltip copy parameter, no data-layer message constant
  rendered directly. Scope is `lib/presentation/` +
  `diceup_components.dart`; generated code is outside the scope.
  Wired into `tool/check.sh` (after the boundaries gate). The CI
  `strings` job is NOT added to `.github/workflows/ci.yml` — workflow
  files are blocked (Workflows 403); the local gate is the
  enforcement until the permission is fixed.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **579/579 passed** (baseline 579/579, no test added,
none edited); `flutter analyze` — **0 errors, 0 warnings, 35 info**
(baseline 0/0/33; the +2 are the generated `app_localizations.dart`
referencing deprecated `GlobalMaterialLocalizations` /
`GlobalCupertinoLocalizations` — the same unactionable deprecation
family, in generated code); `dart format --output=none
--set-exit-if-changed .` — **0 changed** (102 files);
`tool/check_boundaries.sh` — **12/12**; `tool/check_strings.sh` —
**3/3, exit 0**; `tool/check.sh` — **exit 0 end to end**.
Both-ways evidence for the guard (scratch copies, deleted
afterwards): a `const Text('Paused')` probe in `game_screen.dart`
fails check 1 (exit 1); a `tooltip: 'Pause'` probe fails check 2
and a `Text(kMatchRecordFailedMessage)` probe fails check 3 (exit
1); the real tree passes again afterwards.

Two implementation findings, recorded not hidden:

- `gen-l10n` orders multi-parameter methods alphabetically, not in
  message order (`gameBoardTurnOther(int count, String name)`,
  `gamePlayerHome(int home, String name)`,
  `statisticsSeatWins(String colour, int seat)`,
  `avatarLabel(String colour, String name, String shape)`). The
  analyser caught three (type errors); the fourth (`avatarLabel`,
  all-`String`) would have silently rendered "red, Adeel token,
  circle" — fixed by reordering, and the avatar semantics test
  (`'Adeel, circle token, red'`) passes. The call sites carry a
  comment noting the ordering.
- Deliberately excluded, with reasons (see TRACEABILITY NFR-38 row):
  the domain controller's status strings
  (`OfflineGameController.status` — the domain layer cannot import
  generated Flutter code, M-07, and its tests assert the exact
  strings; externalising them needs a status-key refactor plus test
  updates, a separate decision); the domain ruleset validation
  messages (`InvalidRulesetConfig`, unreachable from the UI — the
  setup toggles always leave a release roll on); the `GameSetup` /
  `MatchSetup` `nameFor` "Player N" model defaults (asserted by
  tests; the user-facing setup flow localises the same default via
  `playerName`); developer-only strings (logs, `debugPrint`,
  exception messages). The `MaterialApp` title `'DiceUp'` in
  `lib/main.dart` stays a literal (OS task label, proper noun,
  outside the guard's scope). The guard's allowlist is the bare
  numerals `Text('2'/'3'/'4')` (setup player-count segments).

Outstanding: the CI `strings` job (blocked on the Workflows
permission, same wall as the `vectors`/`coverage` jobs); the
status-key refactor for the controller status strings (needs a
decision — it changes the controller API and its tests).

### Premium animation (§4) — DONE (per-cell steps, capture, dice, feedback, results, all-screens; 2026-11-22)

Brief §4 premium work (research `docs/UI-RESEARCH.md` §2–§3,
coordinator decisions on Q1–Q10 at the end of that file). All
seven items, in priority order, with the decisions applied as
specified. No new packages, no sound (D-32), no engine rule change
— the engine state stays final-first throughout; only the
presentation of already-decided state changed.

1. **Per-cell token movement (§2.2, Q1 — ~110 ms/cell, cap
   ~600 ms).** The M2.7 straight hop is replaced by a step sequence
   in `game_screen.dart`: the token walks each intermediate cell in
   `boardCellForToken` order (corners turn naturally), one small
   hop per step (scale 1.0 → ~1.12, `outBack`-lite settle), input
   locked for the whole sequence. One controller drives the whole
   sequence; its value maps onto the step polyline
   (`_stepSegmentIndex` / `_stepSegmentFraction`), so a segment
   boundary is hit exactly at its pump time. Last-moved ring (§2.2.6):
   a ~1.5 s fading teal ring under the moved token after it
   settles (static under reduced motion).
2. **Capture animation (§2.3, Q6 — arc as proposed).** Sequenced
   after the mover settles (~150 ms cause→effect beat is inherent):
   lift → shrink/fade → arc to the yard → pop-in (~600 ms,
   `outBack` overshoot 1.08 → 1.0), driven by a second painter
   override (`captureTokenId`/`captureCenter`/`captureScale`/
   `captureOpacity`). The mover settles slightly larger on a
   capturing move (mid-step lift peaks ~1.18, not ~1.12). One
   haptic per capture as a whole (the move's single light haptic,
   D-32); the status line names the event.
3. **Dice polish (§2.4).** Wind-up (~120–180 ms anticipatory dip,
   scale → 0.92, ~−6° rotation) folded into the existing ~540 ms
   budget, tumble with a physical shake (rotation ±8°, translate
   ±2 dp), damped settle wobble (scale 1.06 → 1.0, no bounce), and
   a steady teal rollable border while `canRoll` (deliberately
   steady, not oscillating — an oscillating border needs a
   continuously repeating ticker, which makes `pumpAndSettle`
   never terminate; a slow repeating border is the named revisit
   if the harness ever moves off `pumpAndSettle`). Engine value
   fixed before the animation, input locked, semantics unchanged.
4. **Feedback (§2.5, Q10).** Three-dot thinking pulse in the
   current player's chip (replaces the banner spinner as the
   primary AI-thinking indicator), driven by the one-shot 1,200 ms
   pulse controller — the dots stop the moment the AI acts. The
   status line narrates AI actions (`OfflineGameController.status`:
   "Green (AI) rolled 6, choose a token to move", "…rolled a six
   and rolls again", "…moved a token. Player 1, roll the dice")
   and the no-legal-move pass ("No legal move — turn passes").
   Illegal-tap shake: ~150 ms, ±1.5 dp on the tapped token or
   dice (existing SnackBar + status line unchanged, still no
   haptic for illegal taps).
5. **Results (§2.6, Q5, Q8).** Winner's mark (Q5): an enlarged
   per-seat shape marker in a teal ring around the winner's avatar
   (no crown — Ludo King's crown is its brand), entrance
   staggered headline → avatar (`outBack` scale-in) → cards
   (~500 ms, finite). One-shot hand-drawn confetti (Q5): ~36
   seeded rectangles over ~1.2 s from a tiny `CustomPainter`, no
   package, fires once on entry, never loops. "Home n/4" counts
   (Q8): `MatchResultPlayer.tokensHome` (small model addition,
   display data from the final state, no schema change) shown next
   to each player's name. Play Again / Main Menu unchanged (D-02,
   D-30).
6. **All-screens polish (§2.7).** Game → results navigation via
   `PageRouteBuilder` fade + slight slide, 300 ms in / 200 ms out
   (M3 durations). Shadow tokens formalised in the design system
   (`DiceUpShadows.raised` for board/dice, `lifted` for a token
   mid-hop). OS reduced-motion flag honoured everywhere (Q7 — NO
   new in-app setting): `MediaQuery.disableAnimations` collapses
   steps/capture/dice to an instant settle, freezes the dice face
   at its pre-roll value, skips confetti, and jumps the results
   entrance to its end state. (The iOS-only `reduceMotion` flag is
   not read — it does not exist on the oldest supported SDKs;
   2026-11-23 SDK-compatibility fix, see `isReducedMotion`.)
7. **Pause (Q2 + D-10).** Step/capture sequences FREEZE on pause
   and RESUME from where they paused — superseding the old
   hop-cancel on pause. The input lock is the sequence flag
   (`_sequenceActive`), not any controller's `isAnimating`, so a
   controller stopped by pause does not read as "finished".

**The stall and the replacement fix (2026-11-22 ~20:41 PKT).**
The first premium worker was closed after its
`flutter test test/premium_animation_test.dart
test/animation_test.dart test/ludo_board_test.dart` run hung 53+
minutes (summary stuck at +1 −7, flutter_tester at 134% CPU).
The hung processes were killed; the tree was clean. The
replacement worker's diagnosis, from the hung run's log
(`/tmp/premium2.log`, 531 lines) and the code:

- **Root cause 1 — infinite self-nesting widget tree, not a slow
  test.** `pumpGame` in `test/premium_animation_test.dart`
  reassigned its `screen` variable to a `Builder` whose builder
  closure captured that same variable (`child: screen`), so the
  `MediaQuery`'s child was the wrapper itself. Every
  reduced-motion pump built a ~54,000-deep tree and threw
  `StackOverflowError` while building that `MediaQuery`
  (test line 103); rendering the 54k-frame trace is what consumed
  the 53 minutes. Fixed by capturing the `GameScreen` in its own
  `final` before the wrapper is built (`child: gameScreen`). No
  other test helper has the pattern (grep for `child: screen` —
  none). The "Roll dice" finder failure in the reduced-motion dice
  test was a consequence: the screen never mounted, so the control
  was absent — the widget was not wrong.
- **Root cause 2 — the step sequence lagged one segment at every
  boundary.** Two framework behaviours, both in the old
  per-segment-restart driver: (a) when an `AnimationController`
  completes its ticker stops, so `forward(from: 0.0)` from the
  status listener only ticks on the NEXT frame; (b) a controller
  reports `completed` only once elapsed strictly exceeds the
  duration (its simulation's `isDone` is `time > duration`), so a
  segment pumped to exactly its length sits at value 1.0 with no
  status event. The off-by-one (expected the step-3 centre, got
  step-2) and the capture settle reading 1.12 instead of 1.18
  were the same lag. Fixed by replacing the restart driver with
  the polyline form the research already blessed (§2.2: "a single
  controller whose value maps onto a polyline"): one controller
  for the whole sequence, segment + fraction derived from its
  value, plus a value listener (`_onStepValue`) that finishes the
  step phase at value 1.0 — the late `completed` status is then a
  no-op via `_finishStepPhase`'s guard, so the capture can never
  start twice. No test was changed to accommodate this; the tests
  encode the specified boundary timing.
- **Known failure (d).** Unused import
  `package:diceup/domain/ai/ai_player.dart` in
  `test/premium_animation_test.dart:2` — removed (nothing in the
  file uses it). Also fixed: `dart format` drift in the four
  premium-touched files (`game_screen.dart`,
  `test/ludo_board_test.dart`,
  `test/offline_game_controller_test.dart`,
  `test/premium_animation_test.dart`) — reformatted, check clean.
- **Environment note.** The hung run's log opens with a load
  failure ("No space left on device" copying the test dill):
  `/tmp` is a 512 MB tmpfs and was full at the time. All
  replacement-run verification used `TMPDIR` on the big volume
  (`diceup_app/.flutter-tmp`, removed afterwards); every
  `flutter test` invocation also carried a hard `timeout`
  (300 s targeted, 900 s full suite).

**SDK-compatibility fix (2026-11-23).** After the M3.7 push
(`31b7aea`), Anti pulled onto Windows and `flutter build apk
--debug` failed with real compilation errors:
`MediaQuery.of(context).reduceMotion` does not exist on his
installed Flutter SDK (`game_screen.dart:794`,
`results_screen.dart:104`, `results_screen.dart:119`). The
project declares Dart `sdk: ^3.13.4` and no Flutter pin, and
`MediaQueryData.reduceMotion` is a recent addition (present in
the VM's Flutter 3.50.1, absent from Anti's SDK). Fix: one
shared helper, `isReducedMotion` in
`lib/core/accessibility/reduced_motion.dart`, reading only
`MediaQuery.disableAnimationsOf(context)` (Android "Remove
animations", available since Flutter 3.13, and already used at
the same sites — it compiled on Anti's SDK). Reduced-motion
support is preserved, not removed. Honest limitation recorded
in the helper: on SDKs without `reduceMotion`, the iOS Reduce
Motion flag cannot be read through MediaQuery at all — restore
the check in that one place if the minimum Flutter is ever
raised to a release that has it; no `dynamic` probing. The two
`reduceMotion: true` test cases in
`test/premium_animation_test.dart` were converted to drive the
behaviour through `MediaQueryData(disableAnimations: true)`
(same assertions; the converted step-collapse case now
duplicates the existing `disableAnimations` step-collapse case)
and renamed to describe the supported API. Sweep (req 5): the
only other `MediaQueryData` members accessed anywhere in
`lib/`/`test/` are `size` and `disableAnimations`; no
`AccessibilityFeatures` member is read; `Color.withValues`
(Flutter 3.22+) is used in 10 places but is proven compatible —
Anti's build reported only the three `reduceMotion` errors in
the very same files. `reduceMotion` was the only too-new API.
The Android build itself is still unverified in this VM (no
Android SDK); Anti must re-run `flutter build apk --debug` on
Windows. The Maven DNS/dependency-download failure is a
separate Gradle network issue, untouched by this fix.

**Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local
only):** `flutter test` — **591/591 passed** (579 at M3.10 + 7
new premium tests + 4 new `ludo_board` shouldRepaint cases + 1
new results-rendering test; 0 failed, 0 skipped), full suite
1:57. `flutter analyze` — **0 errors, 0 warnings, 37 info**
(all the pre-existing `material.dart` deprecation notice; the
single warning is gone). `dart format --output=none
--set-exit-if-changed .` — **0 changed**. `flutter pub get` —
clean. `tool/check.sh` — **exit 0** (boundaries 12/12, strings
3/3). Per-file: `premium_animation_test` 7/7,
`animation_test` 15/15, `ludo_board_test` 12/12,
`game_screen_characterization_test` 2/2,
`offline_game_controller_test` 17/17, `results_screen_test`
12/12, `game_screen_test` 13/13.

**Files changed (vs the M3.10 baseline, confirmed by diff):**
`lib/core/design_system/diceup_shadows.dart` (new),
`lib/domain/offline_game_controller.dart` (AI narration status
strings), `lib/l10n/app_en.arb` + generated
`app_localizations*.dart` (new narration / results strings),
`lib/main.dart`, `lib/presentation/navigation/app_routes.dart`
(results transition + `MatchResultPlayer.tokensHome`),
`lib/presentation/screens/game_screen.dart` (step/capture/dice/
feedback/pause), `lib/presentation/screens/results_screen.dart`
(winner's mark, confetti, Home n/4, entrance),
`lib/presentation/widgets/dice_widget.dart` (rollable border),
`lib/presentation/widgets/ludo_board.dart` (capture + last-moved
+ shake painter parameters), `test/premium_animation_test.dart`
(new, 7 tests in 4 groups),
`test/animation_test.dart`, `test/ludo_board_test.dart`,
`test/game_screen_characterization_test.dart`,
`test/offline_game_controller_test.dart`,
`test/results_screen_test.dart`.

**Test changes, with reasons (no test weakened to force
green):** `animation_test.dart` — the hop group rewritten to
the step sequence (straight hop → per-cell steps is the specified
behaviour change) and the pause test rewritten from hop-cancel
to freeze/resume (Q2 supersedes M2.7); `offline_game_controller_
test.dart` + `game_screen_characterization_test.dart` — status
strings updated to the Q10 AI narration (the strings themselves
are the specified change; the characterization test still pins
the exact sequence and the 700–1,199 ms pacing bounds);
`results_screen_test.dart` — the scripted-match drive loop now
exits when the results screen is showing, not only when the
provider reports finished (the `autoDispose` provider is disposed
after the results navigation, so a fresh read yields a controller
with no game whose `state` throws; the results screen itself is
proof the match finished) — plus, by the replacement worker, one
new test asserting the premium results rendering (winner's mark
key, "Home 4/4" / "Home 1/4", confetti painter on entry), because
no existing test asserted those three; `ludo_board_test.dart` —
4 new `shouldRepaint` cases (capture/shake/last-moved
parameters); `premium_animation_test.dart` — new, 7 tests:
multi-cell step order at exact segment boundaries, capture
sequencing + settle scale, reduced-motion capture collapse,
dice settle + input lock, reduced-motion step collapse
(`disableAnimations` — the two `reduceMotion` cases were converted
to `disableAnimations` in the 2026-11-23 SDK-compatibility fix),
reduced-motion dice-face freeze.

**Deliberately NOT done (per the brief / Q decisions):**
auto-move on a single legal move (Q3 — NO), destination ghost
preview (Q4 — NO), direction chevrons / reachable-safe-cell
outline (Q9 — NO), in-app animation setting (Q7 — NO), sound
(D-32 — NOT implemented, no audio code), the pure-Dart package
split (deferred pending Anti), `test/seat_ai_difficulty_test.dart`
untouched. The dice's rollable border is steady, not
oscillating, and the legal-move pulse stays one-shot — both are
named revisits if the harness ever moves off `pumpAndSettle`
(see the code comments); neither is a behaviour gap in this
phase.

**Outstanding (not this milestone):** the ~110 ms/cell feel is
verified only in the test harness — play-tuning on the low-end
reference device (D-14) is still owed; CI jobs (`vectors`,
`coverage`, `strings`) still blocked on the Workflows
permission; device screen-reader + layout confirmation stays
M4.

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

### M2.10 — DONE (honesty fixes, M-12/M-13; 2026-11-22)

The batch verification pass (remediation plan §4 M2.10, §6.1
"Honesty fixes (M2.10)"): each item checked against the code
one by one — fixed where it was wrong, proved where M1 had
already made it true, recorded where the plan itself defers
it. No visual redesign, no gameplay change, no sound, no new
dependency (`package_info_plus` sourcing is still a later
step, not this milestone).

Item-by-item verdicts:

- **Session-only settings note — already-correct via M1, no
  note added.** The plan item asked for the visible note
  "Settings apply for this session and reset when the app
  closes" *until M1's persistence lands*. M1.6/M1.7 landed
  persistence (settings load from `SettingsRepository` and
  persist immediately), so the note would now be false — it
  was deliberately NOT added, and the new test asserts its
  absence (`test/widget_test.dart`, "no session-only note:
  settings persist (M1.7)": no "reset when the app closes"
  / "this session" text on the screen). Persistence itself is
  proved by the M1.7 tests in `test/settings_haptics_test.dart`.
- **Footer version — FIXED.** The settings footer claimed
  "DiceUp 1.0.0" while `pubspec.yaml` says `0.1.0+1`; it now
  reads "DiceUp 0.1.0+1". The literal is kept in sync with
  the pubspec by the new test ("settings footer reads the
  pubspec version 0.1.0+1"); runtime sourcing from the
  pubspec via `package_info_plus` is the plan's later step.
- **"Not hidden from the user" doc comment — already
  correct.** No such comment exists anywhere in `lib/` or
  `test/` (verified by grep): the settings doc comment
  already describes real persistence (M1.7), so there is
  nothing to remove or make true.
- **Online card chevron — FIXED.** `_ModeRow` takes a
  `showChevron` flag (default true); the non-tappable online
  card passes `showChevron: false`. The new test asserts
  exactly 2 chevrons across the 3 mode rows ("online mode
  card renders no chevron").
- **Play Online login prompt — FIXED.** The button showed a
  transient "coming soon" snackbar; it now shows the
  login-prompt dialog with the exact M-13 copy ("Log in to
  play online — online play arrives in Phase 5.", OK button),
  and the old snackbar copy is gone. The new test taps Play
  Online, asserts the dialog + OK, dismisses it, and asserts
  the snackbar text is absent.
- **False FR-42 doc comment — FIXED with the dialog.** The
  audit's M-22 comment (a guest tapping Play Online "is
  asked to log in (FR-42)" while the behaviour was a
  snackbar) was already softened in M0 to describe the
  snackbar honestly; the behaviour is now the dialog, and
  the Home doc comment describes the dialog, so comment and
  code agree again. No `FR-42` string remains anywhere in
  `lib/` or `test/` (verified by grep) — online play itself
  is still Phase 5, correctly absent.
- **Home subtitle — FIXED.** "Classic Ludo — offline, with
  friends, or online." is now "Classic Ludo — offline, with
  friends." (new test asserts the new subtitle and that no
  "or online" text remains on Home).
- **Settings menu row — already-correct, not added.** The
  M-13 entry is optional: the AppBar settings icon already
  satisfies "one tap from home" (SDD §11.2), so no menu row
  was added. No code change; the existing boot test proves
  the icon's presence via navigation.
- **Splash real load — already-correct via M1.6.** The
  900 ms fixed delay is gone: `main()` awaits
  `initializeApp()` before the first frame and the splash is
  a 500 ms brand moment after a real load. Proved by the
  existing boot test (DiceUpApp reaches Home through the
  real startup path), not re-implemented.
- **Splash typography tokens — FIXED.** The title/tagline
  used raw `TextStyle`s (44 sp w800 / 16 sp); they now use
  the theme's `displayLarge` (32 sp, w800) and `bodyLarge`
  (16 sp) with only the on-dark colour applied (new test
  asserts 32 sp / w800 / white and 16 sp).
- **Splash loading implication — DEFERRED with reason, not
  fixed.** The spinner should show only while the real load
  runs, but removing it from the ready splash broke 26
  `pumpAndSettle` boot tests across the suite: with nothing
  animating, the harness returns as soon as no frame is
  scheduled, before the 500 ms navigation timer fires
  (verified by probe — ready splash shown, spinner absent,
  Home never reached; restoring the spinner restores all 26).
  The spinner's animation frames are what keep the harness
  pumping until the real-async startup completes and the
  timer fires. Removing the spinner needs the boot tests'
  `pumpAndSettle` reliance reworked first — a test-harness
  change, out of scope for this milestone. The spinner
  therefore stays through the brand moment, recorded as a
  known imperfection in the splash doc comment, and locked
  in by the new test ("splash spinner stays through the
  brand moment (M2.10)") so a future removal re-breaks
  loudly instead of silently. The substantive honesty — a
  real load, no fake delay — is done (M1.6).

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **519/519 passed** (baseline 512 + 7 new in
`test/widget_test.dart`, group "honesty fixes (M2.10)": home
subtitle, Play Online dialog, online card chevron count,
settings footer version, no session-only note, splash
typography tokens, splash spinner stays through the brand
moment). The milestone's own verification caught the spinner
regression first: the first full-suite run with the
conditional spinner failed 26 tests (493 passed); the
revert + follow-up record restored 519/519. `flutter
analyze` — **0 errors, 0 warnings, 30 info** (29 at the
M2.9 baseline + 1 in the rewritten `test/widget_test.dart`,
all the pre-existing `material.dart` deprecation notice).
`dart format` clean on all M2.10-touched files
(`--set-exit-if-changed` passes on the 5 files).
`tool/check_boundaries.sh` — 8/8 checks pass. No device
verification — no devices paired, no Mac, no iOS/Android
folders in staging.

Scoping decisions recorded: no "session-only" note was
added anywhere (it would be false now that settings
persist); no `package_info_plus` dependency was added (the
plan names it as a later step); the splash spinner removal
is deferred as above, not silently kept. The
`LudoGame.fromState` custom-ruleset follow-up (M3.2/M3.3)
is untouched, as instructed. No sound (D-32 follow-up), no
AI timeout fallback, no gameplay-rule changes.

### M2.11 — DONE (haptics coverage, M-12/D-32; 2026-11-22)

The gap-fill pass for remediation plan §4 M2.11 + §6 "Haptics
(M2.11)": M1.7 had already built the `FeedbackService`
abstraction and wired haptics into the move path, so this
milestone re-verified each plan item against the code and
implemented only what was still missing. No new dependency,
no sound, no gameplay change, no splash-spinner change
(M2.10 deferred follow-up, out of scope).

Item-by-item verdicts:

- **`FeedbackService` with `HapticFeedback.lightImpact()` on
  moves — already covered (M1.7), proved again here.**
  `lib/presentation/feedback/feedback_service.dart`:
  `HapticFeedbackService.vibrateMove()` sends one light impact;
  the abstraction covers haptics only and deliberately has no
  audio method. The M1.7 channel-mock test
  (`test/settings_haptics_test.dart`, "HapticFeedbackService
  calls HapticFeedback.lightImpact") still passes unchanged.
- **Gated by the vibration toggle — already covered, now
  proved end to end (the one real gap).** The gate lives in
  `OfflineGameController._vibrateOnMove` (skipped when
  `_vibrationEnabled` is false, refreshed from the persisted
  setting after start) and is wired in the composition root
  (`offlineGameControllerProvider`'s `onMoveApplied` → the
  provider's `FeedbackService`; the screen never touches
  haptics). The M1.7 tests proved the two halves separately
  (fake: 1 call enabled / 0 disabled; real service: channel
  call), but the remediation plan §6 criterion — "toggle off
  → no call, on → call" via a `TestDefaultBinaryMessenger`
  channel mock — was never proved through the production
  wiring. New `test/haptics_gate_test.dart` closes it: with
  the REAL service (no feedback override) a move sends
  exactly one `HapticFeedback.vibrate` /
  `HapticFeedbackType.lightImpact` call on
  `SystemChannels.platform` when vibration is on, and zero
  calls when it is off.
- **Haptic failure never wedges a move — IMPLEMENTED
  (hardening).** The controller doc claimed `_vibrateOnMove`
  is "never throwing into the turn loop", but no test proved
  it — and the new test failed first: a synchronously
  throwing `onMoveApplied` hook propagated out of
  `applyMove` (`Bad state: haptics boom`), skipping the
  turn-change path. `_vibrateOnMove` now wraps the call in
  try/catch and logs (`DiceUpOfflineGameController`); the
  provider closure's `catchError` already covered async
  failures. Test: "a throwing feedback hook never wedges a
  move" — the move lands, status becomes "Six! Player 1
  rolls again.", same player stays on.
- **Sound — DEFERRED per D-32, with reason.** No audio
  dependency exists in `pubspec.yaml` (verified: no audio
  package, no sound assets, no sound code path — only the
  `sound_enabled` / `sound_volume` preference keys and the
  disabled toggle). The Sound toggle stays DISABLED with the
  honest note "Coming soon — sound does not play anything
  yet." (M1.7 test proves disabled + note); the volume slider
  persists `sound_volume` (default 100, D-25) for when sound
  lands. No bundled click asset: Anti has not approved the
  dependency/asset (the plan's alternative (b)), so none was
  added and no placebo setting ships.
- **No haptics on illegal taps, dice rolls, captures or wins
  beyond the one per completed move — already correct, not
  changed.** M2.8 decided illegal taps get SnackBar + status
  only; the plan names haptics "on moves" only. Captures and
  wins vibrate exactly once as completed moves (the same
  `_vibrateOnMove` call — verified: the five-move
  controller test counts 3 human + 2 AI moves, one each).
- **`loadedSettings`-always-empty vibration quirk — NOT
  fixed here, with reason.** M3.3 documented it as
  preserved, not silently fixed: the provider's initial value
  resolves to on (empty map → `!= '0'`) and the controller's
  repository refresh picks up the persisted value after
  start. The M2.11 plan row does not assign it, and changing
  startup/settings resolution is outside this milestone's
  gap-fill scope. It stays recorded in `app_providers.dart`
  and the M3.3 plan section.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local only):
`flutter test` — **522/522 passed** (baseline 519 + 3 new in
`test/haptics_gate_test.dart`: channel-mock gate on/off, throwing
hook). The throwing-hook test failed before the fix (proved the
gap) and passes after; the two gate tests passed against the
unmodified wiring (proving coverage, not a fix).
`flutter analyze` — **0 errors, 0 warnings, 31 info** (30 at the
M2.10 baseline + 1 in the new test file, all the pre-existing
`material.dart` deprecation notice). `dart format` clean on all
M2.11-touched files (`--set-exit-if-changed` passes on the 2
files). `tool/check_boundaries.sh` — 8/8 checks pass. No device
verification — no devices paired, no Mac, no iOS/Android folders
in staging; haptics are asserted via fakes and the platform
channel mock, never claimed felt on a device.

Scoping decisions recorded: no sound work of any kind (D-32
named follow-up); no splash-spinner removal (M2.10 deferred);
no `loadedSettings` quirk fix (see above); no haptics added to
illegal taps, dice rolls, captures or wins; no gameplay-rule
changes; the `LudoGame.fromState` custom-ruleset follow-up
(M3.2/M3.3) is untouched, as instructed; no AI timeout
fallback.

### M2.12 — DONE (NFR-09 layout, 320x568 first-paint; L-02; 2026-11-22)

The layout pass for remediation plan §4 M2.12 + §6.1 "Layout
320" + §6.2 "NFR-09 5-device layout" (D-21: NFR-09 binding).

What was wrong (measured, not assumed): at 320x568 the bare
harness showed the board 207–487 and the Roll button 511–559
(viewport 568) — inside, but with only 9 dp of margin. On a
real phone the status bar pushes content down ~24 dp and the
gesture bar eats ~16 dp at the bottom, so the button sat ~35 dp
below the fold (remediation plan C-5 "borderline", confirmed as
a real gap once insets are counted). The board itself was
already right: 280 wide with 8 dp to spare (C-3), so no board
fix was needed and the board keeps its width rule.

Game screen (`game_screen.dart`, layout changes only — no
gameplay-rule, copy or visual-redesign change):

- Short-screen compaction, gated on viewport height < 600 dp
  (the 320x568 worst case; the 800x600 default viewport and
  every taller screen keep the full layout exactly as before):
  the turn banner uses tighter card padding (16 → 8 dp
  vertical) and a smaller avatar (radius 20 → 16 dp), and the
  gaps above/below the board shrink from 16 to 8 dp. The dice
  renders at 56 dp instead of 64 dp on short screens (still
  above the 48 dp control minimum). The board side keeps its
  width rule (`_boardSide`: 280 dp at 320 dp wide, the plan §6.1
  criterion) and the column padding is untouched. The board does
  move up the screen (its top goes 207 → 183) — that is what
  "reduce the chrome around the board" means, and hit-testing is
  unaffected: every tap test computes its point from
  `boardTokenCenter` over the painter's tokens, never a magic
  offset (see the new tap test below).
- `DiceUpCard` takes an optional `padding` (default unchanged
  `cardPadding`); only the turn banner passes the compact
  padding.

Measured after the fix at 320x568 (bare harness): board
183–463 (280x280), dice 471–527, Roll button 475–523 — 45 dp
of margin (was 9 dp). With simulated device insets (status bar
24 + gesture bar 16) the Roll button stays inside the visible
window (80..552). One harness artifact, recorded honestly: the
test font renders text ~2x wider than Roboto, so the banner
status is 3 lines here and 2 lines on a real phone — the
harness numbers are the pessimistic bound and the real-device
margin is ~21 dp larger still. Device confirmation itself is
outstanding (M4); these tests are the automated half of NFR-09
per the §6.2 device-vs-automated map.

Two more real overflows found by the suite (same milestone,
same fix pattern — scroll instead of overflow):

- Home (`home_screen.dart`): the plain Column + Spacer
  overflowed by 27 px at 320x568 in the harness (title and
  subtitle wrap under the wide test font). Now a
  `SingleChildScrollView` + `ConstrainedBox` (min-height =
  viewport − padding) + `IntrinsicHeight`, so the column scrolls
  only when it cannot fit; on tall screens the layout is
  identical and the footnote stays pinned to the bottom.
- Mode selection (`mode_selection_screen.dart`): the plain
  Column overflowed by 74 px at 320x568 (subtitles wrap to 5–6
  lines in the harness). Now a `SingleChildScrollView` with the
  same padding; unchanged where everything fits.

Screens that legitimately scroll (asserted as such, recorded
here): the results screen — winner headline visible at first
paint, Play Again / Main Menu reached by scrolling at 320x568;
the setup screen — seat/rule cards scroll, Start match is
pinned and visible without scrolling; the game screen's player
chips + hint sit below the fold at 320x568 by design (the
scrollable column is the bound). Setup, results, home, mode,
settings, statistics, history and splash all render at 320x568
without overflow; home/mode/splash also at 430x932.

Verification (2026-11-22, Flutter 3.50.1 / Dart 3.14.1, local
only): `flutter test test/layout_320_test.dart` — **15/15
passed** (5-width first-paint suite 320x568 / 360x640 /
390x844 / 411x891 / 430x932 with board widths 280 / 312 / 342
/ 363 / 382; 320x568 headroom bound; simulated-insets test;
4-player first paint; yard-token tap after the board moved;
compact-gate test; pause menu fits; setup Start pinned;
results scroll; other-screens no-overflow at 320x568 and
430x932). A full-suite run covering the final code exited 0
(522 baseline + 15 new = 537); the exact summary count was not
captured in the delivered output (truncated). `dart analyze`
via the standalone SDK — **0 errors, 0 warnings, 32 info**
(31 at the M2.11 baseline + 1 in the new test file, all the
pre-existing `material.dart` deprecation notice) — run this
way because `flutter analyze` cannot start while shell writes
are blocked (see the environment note). `dart format
--set-exit-if-changed` clean on all 5 touched Dart files
(the formatter's own diff hunks applied by hand, since shell
writes are blocked and `dart format` cannot write; verified
with `--output=none`: 0 changed). `tool/check_boundaries.sh`
— 8/8 checks pass. Push landed as
`20722ad03b3a2e53ba50a220e9fb64011551e549` ("feat(layout):
M2.12 NFR-09 320x568 first-paint", verified live, sync record
entry 22). No device verification — no devices paired, no Mac,
no iOS/Android folders in staging; device layout confirmation
(at least 2 real phones, §6.2) remains outstanding (M4).

Environment note (2026-11-22 ~09:01 PKT): a service restart
during this session broke shell-level file writes VM-wide
(`write()` to any regular file fails EPERM "Operation not
permitted", while file creation still works) — so `flutter`
itself cannot start (its startup writes `bin/cache/engine.stamp`
and aborts) and `dart format` cannot write. The failure is in
the VM/sandbox, not in the code or the SDK: `flutter
--version` fails the same way on an untouched invocation, and
the stamp files show the restart time (09:01). The M2.12 code
and tests were verified green before the restart (layout suite
15/15; full suite exit 0); after the restart, analyze + format
+ boundaries were re-verified via the read-only fallbacks above
(`dart analyze`, `dart format --output=none`,
`check_boundaries.sh`). Still outstanding until the VM write
path recovers: a `flutter test` re-run for the exact full-suite
count on the final formatted tree, and `flutter analyze` itself
(`dart analyze` is the same analysis, but the milestone
verification names the Flutter command).

Scoping decisions recorded: layout changes only — no gameplay
rules, no copy changes, no visual redesign, no board-width
change, no column-padding change; the `LudoGame.fromState`
custom-ruleset follow-up (M3.2/M3.3) is untouched, as
instructed; no AI timeout fallback; no splash-spinner removal
(M2.10 deferred); 3-button-navigation bottom insets (~48 dp)
are not covered by the inset simulation — under those the Roll
button would need a scroll, which the scrollable column
provides (nothing is clipped); device layout confirmation is
M4, not claimed here.

### M2.13 — DONE (iOS target + portrait lock, D-08/D-17; 2026-11-22)

The platform-config pass for remediation plan §4 M2.13 + §1.2
("orientation unrestricted as built (D-17 decided 2026-11-21:
iPhone locked to portrait in M2.13, iPad as-is)").

Correction to the brief's file paths, found while doing the
work: the platform folders do NOT live at the repo root. The
repo layout is `diceup_app/` (Flutter app) + `docs/`; the
platform files are `diceup_app/ios/Runner/Info.plist`,
`diceup_app/android/app/src/main/AndroidManifest.xml` and
`diceup_app/ios/Runner.xcodeproj/project.pbxproj`. The staging
directory mirrors that layout, so the two changed files were
written to staging at `diceup_app/ios/Runner/Info.plist` and
`diceup_app/android/app/src/main/AndroidManifest.xml` and pushed
from there. No `ios/` or `android/` folder exists at the repo
root, and none was created.

What was there before (read from the remote at head e28fea583
before changing anything):

- `diceup_app/ios/Runner/Info.plist` —
  `UISupportedInterfaceOrientations` (iPhone) =
  `[UIInterfaceOrientationPortrait,
  UIInterfaceOrientationLandscapeLeft,
  UIInterfaceOrientationLandscapeRight]` (unrestricted);
  `UISupportedInterfaceOrientations~ipad` = `[Portrait,
  PortraitUpsideDown, LandscapeLeft, LandscapeRight]`.
- `diceup_app/android/app/src/main/AndroidManifest.xml` — the
  `.MainActivity` element carried no `android:screenOrientation`
  attribute (unrestricted).
- `diceup_app/ios/Runner.xcodeproj/project.pbxproj` —
  `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in all 3 build configs
  (verified by reading the remote file; D-08 already satisfied).
- No Dart `SystemChrome.setPreferredOrientations` lock exists
  anywhere in `diceup_app/lib/` (grep: 0 matches) — nothing to
  remove.

What changed (config only, no Dart code touched):

- Info.plist iPhone key restricted to Portrait only:
  `UISupportedInterfaceOrientations` =
  `[UIInterfaceOrientationPortrait]` (the LandscapeLeft and
  LandscapeRight entries were removed; diff verified against the
  remote content — those two lines are the only change in the
  file, and the file still parses as a valid plist).
- AndroidManifest `.MainActivity` gained
  `android:screenOrientation="portrait"` (the only change in
  the file, verified by diff against the remote content; the
  file still parses as valid XML). Note this lock is
  device-wide on Android, so Android tablets are locked to
  portrait too — that asymmetry is D-17 as decided (iPad
  as-is, Android tablet lock accepted).
- `project.pbxproj` NOT changed and NOT included in the push:
  the 15.0 target was already correct in all 3 configs, so
  there was nothing to change (D-08 verified, not re-applied).
- iPad key `UISupportedInterfaceOrientations~ipad` left
  EXACTLY as-is (all four orientations), per D-17.

Conflict resolution (D-17 vs the remediation plan's M2.13 row):
the plan row also mentions a Dart
`SystemChrome.setPreferredOrientations` lock. D-17 — Anti's
decided decision, recorded in plan §D-17 — says the lock must
be platform-native ONLY, because a Dart lock applies to ALL
iOS devices including iPad. D-17 wins: NO Dart lock was added,
and none exists. The plan row should be read as
platform-native-only; this section is the record of that
resolution.

Verification (2026-11-22, after the change, on the final tree):
`flutter test` — 537/537 passed ("All tests passed!");
`flutter analyze` — 0 errors, 0 warnings, 32 info (all the
pre-existing `material.dart` deprecation notices);
`dart format --output=none --set-exit-if-changed .` — 96 files,
0 changed. The change is config-only (no Dart file changed),
so the suite is a regression guard, not a test of the lock
itself: no test asserts plist/manifest values. The lock itself
was verified by reading the pushed files back from the remote
after the push (see below).

Push: the two platform files, `docs/UI-RESEARCH.md` (the M3
UI/UX research deliverable from the parallel research task,
previously unpushed; it belongs on the branch), this plan
section and the TRACEABILITY row were pushed together in one
snapshot, "feat(platform): M2.13 iPhone portrait lock (D-17) +
docs: UI research". Push landed as `5eda724473a7b7d33a5b1979537e102fee83ecca`
(verified live via `list_commits`; remote head `5eda72447`), and the pushed
files were read back at that head: iPhone
`UISupportedInterfaceOrientations` = [`UIInterfaceOrientationPortrait`]
only, iPad key all four orientations unchanged, `.MainActivity`
`android:screenOrientation="portrait"` present. Sync record entry 24 (5
paths).

Scoping decisions recorded: config only — no Dart code, no
schema changes, no rule changes, no new dependencies, no
sound; no iOS build was run (no Mac in this VM) and no
Android build was run (no `android/` folder in staging, and
no Android SDK here) — both are NOT RUNNABLE in this
environment, never claimed. Device confirmation that the
portrait lock behaves on a real iPhone/iPad is outstanding
(M4), as is the rest of device verification. The pubspec.lock
stash + `../.vscode/` on Anti's Windows machine (D:\DiceUp)
are not verifiable from this environment; untouched.

### M2.14 — DONE (small fixes: Roboto fallback, dark-theme comment, dead tokens; L-01, L-04; 2026-11-22)

The small-fixes pass for remediation plan §4 M2.14 + §3.3
L-01/L-04. Three items, each resolved in the smallest way that
is honest about what the app actually ships. Push landed as
`fc4d3982d0d9c5388527455bc1778245a9e41858` (verified live via
`list_commits`; remote head `fc4d3982d`).

**1. Roboto — named the actual fallback instead of bundling
(L-04).** What was found: `diceup_typography.dart` named
`fontFamily: 'Roboto'` on all eight text styles
(`_fontFamily = 'Roboto'`), but no Roboto file was ever
bundled — `pubspec.yaml` has no `fonts:` section and no font
assets exist in the repo. On Android the name resolved to the
system Roboto, so it looked correct there; on iOS it resolved
to Flutter's system fallback font, so the name promised a font
the app did not ship. The file's own header comment even
contradicted the code, claiming the app "uses the platform
default font family deliberately" while the code named Roboto.
What was decided: name the actual fallback — i.e. name no font
at all. The `_fontFamily` constant and all eight `fontFamily:`
entries were removed, so text renders in Flutter's platform
default (Roboto on Android, the system fallback font on iOS).
Bundling Roboto was rejected, not overlooked: it would need
binary `.ttf` files in the repo, which the snapshot-push route
cannot carry (UTF-8 text only), so a bundled-font commit could
not be pushed this way. The `google_fonts` package was also
rejected: it downloads fonts at runtime, a network dependency
at first run that conflicts with the offline-by-construction
property (NFR-23), for a cosmetic gain. Both rejections and the
before/after state are recorded in the `diceup_typography.dart`
header comment, so a future bundled-font decision starts from
this record rather than re-discovering it. Observable change:
none intended — the rendered font on each platform is the same
as before (Android Roboto, iOS fallback); what changed is that
the code no longer claims otherwise. New test
`test/design_system_test.dart` (2 tests) pins it: every style
in `DiceUpTypography.textTheme` has `fontFamily == null`, and
the applied `DiceUpTheme.light().textTheme` adds no font choice
of its own — its family equals a stock `ThemeData.light()`
textTheme's, because `ThemeData` fills an unspecified family
from Flutter's own Material defaults (`'Roboto'`); that is the
framework's default, identical to a stock Material app, not an
app choice. (An earlier draft of the second test asserted
`fontFamily == null` on the applied theme and failed: the
framework fills `'Roboto'` in. The test was corrected, not the
code — the app names no font either way.)

**2. Dark-theme comment — removed, theme NOT implemented
(L-04).** What was found: the `diceup_theme.dart` header said
"A dark theme follows the same tokens (navy surfaces, teal
accents) and is added with the settings screen". No dark theme
exists anywhere in the app — no `ThemeData.dark()`, no
brightness switch, no settings toggle for it — and the settings
screen never gained one. What was decided: remove the comment
rather than implement the theme. Implementing a real dark theme
(new colour scheme, per-widget dark variants, a settings toggle
with persistence, tests) is more than a small fix and is not
approved M2.14 scope, so the honest fix is to stop promising
it. The replacement comment records that the theme was
deliberately not implemented and why. The two tokens the
comment pointed at (`navyDark`, `tealDark` — the dark theme's
intended surfaces/accents) were dead and were removed with the
other dead tokens below, which is consistent: nothing in the
app references a dark palette any more.

**3. Dead design tokens — removed (L-01).** Each token below
was verified unused by grepping the whole app (`lib/`,
`test/`, `tool/`) plus `docs/` before removal — definition
only, zero references — and removal is enforced going forward
by compilation itself: any remaining reference would fail the
build. Removed from `diceup_colors.dart`: `navyDark`
(`0xFF121D36`), `tealDark` (`0xFF0A5E5D`), `success`
(`0xFF15803D`), `errorBackground` (`0xFFFEE2E2`). Removed from
`diceup_spacing.dart`: `xxl` (48 — a duplicate of the live
`minTouchTarget = 48`), `radiusXl` (24), `radiusSm` (8) and
its only consumer `radiusSmBorder`, which was itself unused
(no call site) and could not survive `radiusSm`'s removal.
Deliberately kept: every other token in both files is
referenced — `amberLight` (board star cells), `surfaceMuted`
(game screen), `radiusMd`/`radiusLg` + `radiusMdBorder`/
`radiusLgBorder` (theme + components). Nothing else from
L-01 was touched in this pass: `cupertino_icons` is still in
`pubspec.yaml` (still unused — removal is a dependency change,
out of M2.14's token scope, and is recorded here rather than
done silently), and the L-01 bug items (`didChangeDependencies`
init, `gameSetupOf` loud failure) were already fixed in
earlier milestones (M2.1/M2.5), not re-done here.

Verification (2026-11-22, after the change, on the final
tree): `flutter test` — 539/539 passed ("All tests passed!";
537 baseline + 2 new in `test/design_system_test.dart`);
`flutter analyze` — 0 errors, 0 warnings, 33 info (the 32
pre-existing `material.dart` deprecation notices plus 1 of the
same kind from the new test file's `material.dart` import,
which it needs for `ThemeData` — same pattern as every other
test file); `dart format --output=none --set-exit-if-changed .`
— 97 files, 0 changed (one formatting fix applied to the new
test file during verification, then re-checked clean; the new
test file re-run green, 2/2, after the format fix).

Scoping decisions recorded: no new dependency, no binary
assets, no schema changes, no rule changes, no sound, no
dark theme, no device claims. The pubspec.lock stash +
`../.vscode/` on Anti's Windows machine (D:\DiceUp) are not
verifiable from this environment; untouched. M2.13's staged
platform files (`diceup_app/ios/`, `diceup_app/android/`)
were not touched. No push was made by this worker — manifest
prepared for the coordinator (see report).
