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
| UI-01 | 11.4 | Splash/Home | `diceup_app/lib/presentation/screens/splash_screen.dart`, `home_screen.dart` | `test/widget_test.dart` (boot + navigation) | implemented |
| UI-02, FR-12–14, FR-41 | 11.4 | Mode/Setup | `mode_selection_screen.dart`, `offline_setup_screen.dart` | `test/widget_test.dart` | implemented (partial) |
| FR-31, UI-09 | 11.4 | History UI | `history_screen.dart` (list via `LocalMatchRepository.listMatches()`) | `test/app_lifecycle_test.dart` (history screen group: lists matches newest first with Local labels + detail view; empty state; unavailable state) + `test/data/local/sqlite_repository_contract_test.dart` (contract suite vs SQLite: listMatches reverse-chron + id-DESC tiebreak) | verified (flutter test 349/349; M1.4/M1.6) |
| FR-08 | 11.1 | Settings UI | `settings_screen.dart`, `lib/presentation/feedback/feedback_service.dart`, `game_screen.dart` (haptics in `_applyMove`) | `test/settings_haptics_test.dart` (seeded load without flashing defaults; vibration toggle + volume slider persist; reset to defaults; settings survive restart; haptics fake 1 call enabled / 0 disabled; `HapticFeedbackService` sends lightImpact) | implemented (partial) — vibration persisted + haptics real (D-32); sound toggle disabled with Coming Soon note, no audio code (named follow-up) |
| NFR-07–10 | 11.1–11.3 | Design system | `lib/core/design_system/` (colors, typography, spacing, theme, components) | `flutter analyze` 0 errors; manual a11y check still open | implemented (partial) — NFR-08 **non-compliant** (measured: 40 dp SegmentedButtons/dialog buttons, 12 sp `bodySmall`, avatar contrast 3 of 4 colours fail AA 4.5:1; board-token hit ~22 dp @320 — tokens exempt per D-09, D-21 confirms NFR-08 binding) |
| FR-17, FR-23, NFR-08 | 6.2, 11.4 | Board | `lib/presentation/widgets/ludo_board.dart` (CustomPainter, safe-cell stars, per-seat token shapes, legal-move highlight) | `test/game_screen_test.dart` (tap-to-move incl. yard slot) | implemented (partial) |
| FR-15 | 6.5 | Dice | `lib/presentation/widgets/dice_widget.dart` | `test/game_screen_test.dart` (roll animation settles on engine value) | verified (flutter test 50/50) |

## Phase 3 — Offline gameplay (in progress)

| SRS ID | SDD § | Module | Implementation location | Test case | Status |
| --- | --- | --- | --- | --- | --- |
| FR-15–22, BR-01–14 | 6 | Engine | `diceup_app/lib/domain/engine/` | `test/engine/rules_test.dart`, `snapshot_test.dart` | verified (flutter test 50/50; engine suite 47/47) |
| FR-16 | 6.5 | Engine (legal-move computation) | `diceup_app/lib/domain/engine/` | `test/engine/rules_test.dart` (legal moves) | verified (split out from the mislabelled FR-16/FR-15 row, H-03; the row above covers the FR-15–22 range) |
| FR-35–39 | 7 | AI | `diceup_app/lib/domain/ai/` | `test/engine/ai_test.dart` | verified (flutter test 50/50; see IMPLEMENTATION-PLAN §7 for the Medium/Hard note) |
| FR-33, FR-34, FR-40 | 7 | AI | `diceup_app/lib/domain/ai/` | `test/engine/ai_test.dart` | implemented (partial) — FR-40 UI-layer pacing test missing (M-16; D-31 keeps 700–1,199 ms); FR-33/34 over-claimed per H-03. D-01 (2026-11-21): §7.4 criterion amended (hard>easy, medium>=easy); test oracle fix + SDD re-issue pending — see IMPLEMENTATION-PLAN §8. |
| FR-24–28 | 6.6, 11.4 | Game screen | `lib/presentation/screens/game_screen.dart` | `test/game_screen_test.dart` | implemented (partial) — FR-26 results screen is a dialog today (dedicated screen in M2.5); continue-to-rank variant DEFERRED per D-02, never marked complete. |
| FR-29–31 | 9.1 | Local persistence | `lib/data/local/` (SQLite) | `test/app_lifecycle_test.dart` (startup resume/discard with exact copy; snapshot saved after every completed move; resume restores exact state incl. AI difficulty; completion records exactly once; history list/detail/empty/unavailable) + `test/data/local/sqlite_repositories_test.dart` (recordMatch transaction rollback at all four writes; 501/502/700 lifetime totals) + `test/data/local/sqlite_repository_contract_test.dart` (contract suite vs SQLite) | verified (flutter test 349/349; M1.3–M1.7) |
| FR-32 | 9.1, 11.4 | Local statistics + settings UI | `statistics_screen.dart`, `settings_screen.dart` | `test/statistics_screen_test.dart` (persisted lifetime totals incl. 700-recorded/500-retained pruning case; AI wins excluded from human wins; per-player breakdown labelled as latest 500; settings persist + survive restart) | verified (flutter test 349/349; M1.7) |
| NFR-30 | 9.1 | Local persistence | `lib/data/local/sqlite_local_match_repository.dart` (recordMatch transaction), `sqlite_settings_repository.dart`, `diceup_database.dart` | `test/data/local/sqlite_repositories_test.dart` (transaction rollback (NFR-30) group: recordMatch rolls back when the insert / statistics update / prune / snapshot delete fails; clearHistory rolls back; resetToDefaults rolls back) + `test/data/local/diceup_database_test.dart` (a transaction that fails partway rolls back fully) | verified (flutter test 349/349; M1.4) |
| NFR-35 | 9.1 | Local persistence | `lib/data/local/database_recovery.dart` (`openDatabaseWithRecovery`, `kDatabaseRecoveryMessage`), `database_factory.dart`, `app_startup.dart` | `test/data/local/database_recovery_test.dart` (garbage file recovers with fresh schema v1; dropped statistics table triggers recovery; defaults after recovery; a single failed query does NOT trigger recovery; a mid-match failure does NOT trigger recovery) + `test/app_lifecycle_test.dart` (startup after recovery shows the recovery message once) | verified (flutter test 349/349; M1.5) |
| NFR-36 | 9.1 | Local persistence | `lib/data/local/sqlite_local_match_repository.dart` (prune in recordMatch), `lib/domain/repositories/local_match_repository.dart` (`kMaxLocalMatches = 500`) | `test/data/local/sqlite_repositories_test.dart` (501/502/700: totals stay exact, rows stay capped; recompute cannot overwrite lifetime totals after pruning; a diverged cache is NOT repaired after pruning) + `test/data/local/diceup_database_test.dart` (prune keeps the newest 500 and leaves statistics untouched) | implemented (partial) — 500-match cap verified (named tests); ≤100 MB installed-app size is a build-size check, pending M4.5 |
| NFR-12 | 6.9 | Engine conformance | `test/engine/` 1,000-match simulation | committed suite pending (M4.1); exit criterion is `flutter test` (H-02a — `dart test` unexecutable, exit 65); ad-hoc 100/100 claim WITHDRAWN as evidence (no artifact) | in progress |
| NFR-23 | 3.2 | Offline availability | manual: airplane-mode run | — | not started (offline by construction; device run pending) |

## Phases 4–8 — not started

All FR-01…FR-10 (accounts/auth), FR-42…FR-59 (online multiplayer),
FR-60…FR-69 (social/player), FR-70…FR-82 (administration) and their
supporting NFRs remain `not started`. Their implementation locations and
test cases are defined in the SDD (§3.5, §5, §8, §9.2, §10) and will be
added to this file when each phase begins. No phase is marked
`implemented` or `verified` until its tests have actually run green.
