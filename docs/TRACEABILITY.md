# DiceUp — Implementation Traceability Matrix

> The full requirement→design traceability matrix (FR-01…FR-82 → SDD
> section → component) is SDD Chapter 16, verified 82/82 at SDD issue.
> This file extends it with **implementation location**, **test case** and
> **status**, per the implementation brief §2. It is the only traceability
> file that changes during implementation; the SDD itself is not edited.

Status values: `not started` | `in progress` | `implemented` |
`verified` (tests ran green — evidence named) | `blocked` (reason given).

## Phase 2 — Design system & UI foundation (in progress)

| SRS ID | SDD § | Module | Implementation location | Test case | Status |
| --- | --- | --- | --- | --- | --- |
| UI-01 | 11.4 | Splash/Home | `diceup_app/lib/presentation/screens/splash_screen.dart`, `home_screen.dart` | `test/widget_test.dart` (boot + navigation) | verified (flutter test 50/50, 21 Nov 2026) |
| UI-02, FR-12–14, FR-41 | 11.4 | Mode/Setup | `mode_selection_screen.dart`, `offline_setup_screen.dart` | `test/widget_test.dart` | verified (flutter test 50/50) |
| FR-31, UI-09 | 11.4 | History UI | `history_screen.dart` | empty state only; list backed by SQLite in Phase 3 | implemented |
| FR-08, FR-32 | 11.1 | Settings UI | `settings_screen.dart` | toggles work in-session; persistence lands with SQLite (Phase 3) | implemented |
| NFR-07–10 | 11.1–11.3 | Design system | `lib/core/design_system/` (colors, typography, spacing, theme, components) | `flutter analyze` 0 errors; manual a11y check still open | implemented |
| FR-17, FR-23, NFR-08 | 6.2, 11.4 | Board | `lib/presentation/widgets/ludo_board.dart` (CustomPainter, safe-cell stars, per-seat token shapes, legal-move highlight) | `test/game_screen_test.dart` (tap-to-move incl. yard slot) | verified (flutter test 50/50) |
| FR-16 | 6.5 | Dice | `lib/presentation/widgets/dice_widget.dart` | `test/game_screen_test.dart` (roll animation settles on engine value) | verified (flutter test 50/50) |

## Phase 3 — Offline gameplay (in progress)

| SRS ID | SDD § | Module | Implementation location | Test case | Status |
| --- | --- | --- | --- | --- | --- |
| FR-15–22, BR-01–14 | 6 | Engine | `diceup_app/lib/domain/engine/` | `test/engine/rules_test.dart`, `snapshot_test.dart` | verified (flutter test 50/50; engine suite 47/47) |
| FR-33–41 | 7 | AI | `diceup_app/lib/domain/ai/` | `test/engine/ai_test.dart` | verified (flutter test 50/50; see IMPLEMENTATION-PLAN §7 for the Medium/Hard note) |
| FR-24–28 | 6.6, 11.4 | Game screen | `lib/presentation/screens/game_screen.dart` | `test/game_screen_test.dart` | verified (flutter test 50/50) |
| FR-29–32 | 9.1 | Local persistence | `lib/data/local/` (SQLite) | integration test | not started |
| NFR-12 | 6.9 | Engine conformance | `test/engine/` 1,000-match simulation | committed suite pending; ad-hoc 100/100 AI matches, 0 rule violations | in progress |
| NFR-23 | 3.2 | Offline availability | manual: airplane-mode run | — | not started (offline by construction; device run pending) |

## Phases 4–8 — not started

All FR-01…FR-10 (accounts/auth), FR-42…FR-59 (online multiplayer),
FR-60…FR-69 (social/player), FR-70…FR-82 (administration) and their
supporting NFRs remain `not started`. Their implementation locations and
test cases are defined in the SDD (§3.5, §5, §8, §9.2, §10) and will be
added to this file when each phase begins. No phase is marked
`implemented` or `verified` until its tests have actually run green.
