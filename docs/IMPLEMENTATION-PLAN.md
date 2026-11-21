# DiceUp — Implementation Plan (Phase 1 Audit)

> Status: Phase 1 audit complete. Phases 2–3 in progress on branch
> `implementation/foundation-phase-2-3`. Source of truth: SRS v0.1
> (16 Nov 2026, draft) and SDD v1.0 (21 Nov 2026). If SRS and SDD ever
> conflict, stop and ask — do not silently pick an interpretation.

## 1. Phase 1 audit — verified findings

### 1.1 SRS and SDD located and reviewed

| Document | Location | Status |
| --- | --- | --- |
| SRS v0.1 | `docs/DiceUp_SRS_v0.1.docx` (copy; original supplied by the team) | Draft, not approved. FR-01…FR-82, NFR-01…NFR-39, BR-01…BR-20, UC-01…UC-17, A-01…A-12, OD-01…OD-12, R-01…R-10 |
| SDD v1.0 | `docs/DiceUp_Software_Design_Document_v1.0.docx` | First issue, 21 Nov 2026. 76 pages, 17 sections, 11 UML diagrams, 37 tables, traceability FR-01…FR-82 verified 82/82 |

Neither document was in the GitHub repository. The GitHub connector can
only push UTF-8 text files, so the `.docx` binaries themselves are **not**
committed by this tooling — see `docs/README.md` for where the source
documents live and how to add the binaries with a plain git push. The
repository holds this plan and `docs/TRACEABILITY.md` as the living
implementation record. Do not overwrite the source documents with
implementation notes — implementation documentation lives here and in
code-adjacent comments.

### 1.2 Repository and branch status (verified 21 Nov 2026, ~17:35 PKT)

- Repository: `MuhammadAdeel0072/DiceUp` (public). Default branch `main`.
- Commits on `main`: `0713edc` "Initial commit" (README only) and
  `750646d` "chore: initialize Flutter mobile application"
  (21 Nov 2026 12:28 UTC). The second commit landed after the first
  repository check — the audit below is against HEAD `750646d`.
- Pull requests: none (open or closed). Branches: `main` only at audit time.
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
| `analysis_options.yaml` | Default `flutter_lints`. Kept, plus an import-boundary rule for the domain layer (CI follow-up). |
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
- State management / DI: Riverpod is the SDD's **proposed** choice (SDD §4.2),
  not a confirmed SRS decision. Phase 2 uses Flutter's built-in named-route
  navigation and plain `ChangeNotifier`-free providers first; Riverpod is
  adopted at the Phase 3 wiring step, or the team may substitute Bloc without
  changing layer boundaries. This is recorded here, not decided silently.

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
  no NFR is claimed satisfied without evidence (see §5).

### 1.6 Conflicts and missing decisions

- **No SRS↔SDD conflict found.** The SDD was derived from the SRS; where the
  SRS is silent the SDD marks the addition `[Proposed]`.
- **Open decisions carried forward (SRS OD-01…OD-12):** ranking algorithm
  (OD-06 — SDD proposes simple points behind a `RankingStrategy` interface);
  final rule defaults (OD-02 — SDD Table §6.2 defaults); email/push providers
  (OD-09, A-04/A-05); hosting provider/budget (OD-07); offline→online history
  import (OD-03 — no sync in baseline); age group/retention/region (OD-01,
  OD-08, OD-10 — legal review before launch); matchmaking stage and host-set
  rule options (OD-05, OD-11); single vs dual rule implementation (SDD §6.9 —
  dual + shared test vectors chosen, with the conformance suite as control).
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
| 3 — Offline gameplay | Engine + AI + board (CustomPainter) + dice/token animation + local multiplayer + SQLite (SDD §6, §7; FR-11…41) | `dart test` engine suite green incl. 1,000-match simulation (NFR-12); offline works in airplane mode (NFR-23) |
| 4 — Backend foundation | NestJS setup, PostgreSQL + Redis, auth, users, security/validation, tests (SDD §3.5, §5.2, §13) | Auth + profile APIs tested; no secrets committed |
| 5 — Online multiplayer | Rooms, matchmaking, Socket.IO events, authoritative game, reconnect/forfeit (SDD §8; FR-42…59) | Multi-client tests green; negative tests reject client dice/results 100% (NFR-18) |
| 6 — Platform features | Profiles, friends, stats, history, leaderboard, notifications (FR-60…69) | Feature tests green; leaderboard p95 ≤ 500 ms at 100k users (NFR-25) |
| 7 — Admin dashboard | Next.js panel, secured admin APIs, audit trail (FR-70…82) | Admin auth incl. MFA; audit-completeness test green (FR-82) |
| 8 — Integration & verification | Full integration, performance, security, NFR evidence, final report | All acceptance criteria (§18 of the brief) evidenced |

## 3. Initial folder structure

```text
DiceUp/
├── README.md                      # repo overview (existing, kept)
├── docs/
│   ├── DiceUp_SRS_v0.1.docx       # source requirements (do not edit)
│   ├── DiceUp_Software_Design_Document_v1.0.docx  # design (do not edit)
│   ├── IMPLEMENTATION-PLAN.md     # this file
│   └── TRACEABILITY.md            # FR → SDD → module → location → test → status
├── diceup_app/                    # Flutter mobile app (existing template, evolved)
│   ├── lib/
│   │   ├── main.dart              # composition root (replaced in Phase 2)
│   │   ├── core/
│   │   │   ├── design_system/     # colors, typography, spacing, theme, components
│   │   │   └── errors/            # Result/error types
│   │   ├── domain/
│   │   │   ├── engine/            # pure Dart Ludo engine (SDD §6)
│   │   │   ├── ai/                # rule-based AI (SDD §7)
│   │   │   ├── entities/          # value objects
│   │   │   └── repositories/      # repository interfaces
│   │   ├── data/
│   │   │   ├── local/             # SQLite repositories
│   │   │   └── remote/            # REST + Socket.IO clients (Phases 4–5)
│   │   └── presentation/
│   │       ├── navigation/        # routes
│   │       ├── screens/           # splash, home, setup, game, history, …
│   │       └── widgets/           # board painter, dice, tokens, shared widgets
│   ├── test/
│   │   ├── engine/                # engine + AI unit tests (dart test)
│   │   └── widget_test.dart       # replaced by real widget tests (Phase 2+)
│   └── pubspec.yaml               # deps added only when a feature needs them
├── backend/                       # NestJS (Phase 4+)
└── admin/                         # Next.js (Phase 7)
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
2. ~~Add `docs/` (this plan, traceability matrix).~~ — done; `.docx` binaries
   excluded for the connector reason in §1.1.
3. ~~Implement the design system (`lib/core/design_system/`) + reusable
   components + navigation + splash/home/mode-selection/offline-setup screens.~~ — done.
4. ~~Implement the pure-Dart engine + AI with unit tests.~~ — done (see §7).
5. ~~Wire the game screen to the engine (board painter, dice, tokens, animations).~~ — done.
6. ~~Replace `main.dart` and the counter widget test.~~ — done
   (`DiceUpApp`, boot/navigation widget tests, gameplay widget test).
7. Push the branch, open a **draft** PR, report results honestly. No merge.

## 7. Phase 2–3 verification evidence (21 Nov 2026, evening PKT)

- `flutter analyze` — **0 errors, 0 warnings**, 17 `info` (all the
  `material.dart` deprecation notice, §1.6). Exit code 0.
- `flutter test` — **50/50 passed**: 47 engine tests (rules, AI,
  snapshots), 2 app widget tests (boot, navigation), 1 gameplay test
  (roll a fixed 6, release a token by tapping the board). The gameplay
  test caught and fixed two real bugs before the push: an infinite-width
  button constraint in a `Row`, and `BoardToken` missing value equality
  (yard-slot hit-testing mapped every token to the same slot).
- Engine cross-check: 100/100 full AI matches completed with 0 rule
  violations in an ad-hoc run (not a committed test; the committed
  1,000-match NFR-12 suite is a Phase 3 follow-up).
- Known deviations from the SDD (documented, not silent): Medium AI
  scores marginally above Hard on the 200-position sample because Hard
  deliberately declines suicidal captures (designed behaviour, test
  asserts `hard > easy` and `medium >= easy`); the "continue to rank
  2nd–3rd" variant is not implemented — the SDD specifies no flow for
  it, so the default (first to finish wins, match ends) is used.

## 6. Traceability

See `docs/TRACEABILITY.md` (generated from SDD Chapter 16, extended with
implementation location, test case and status columns). Status values:
`not started` | `in progress` | `implemented` | `verified` (with evidence).
A feature is `verified` only when its tests ran green — never on the basis of
compiling or looking correct.
