# DiceUp docs

## Source documents (at the repo root)

The SRS and SDD **are** in the GitHub repository, at the root — Anti added
them himself (commit `e11ef1b`, 21 Nov 2026 13:22 UTC; the earlier claim
that they were not in the repo was wrong, M-04):

- **SRS v0.1** (16 Nov 2026, draft) — `DiceUp_SRS_v0.1.docx` at the repo
  root.
- **SDD v1.0** (21 Nov 2026) — `DiceUp_Software_Design_Document_v1.0.docx`
  at the repo root; 76 pages, 17 sections, 11 UML diagrams, traceability
  FR-01…FR-82 verified 82/82. Approval has not been given (SDD Approvals
  block) — unapproved baseline.

D-03 (decided 2026-11-21) moves both files to `docs/` — **pending Anti**
(web upload or plain git push; files must stay byte-identical, SHA-256
re-verified after the move). Until the move happens, every location in
`IMPLEMENTATION-PLAN.md` points at the repo root.

## Running tests

The canonical runner is `flutter test` (all gates: `sh diceup_app/tool/check.sh`).
The pure-Dart engine tests (`diceup_app/test/engine/`) also run under the
Flutter-bundled `dart test`, except `seat_ai_difficulty_test.dart`, which
imports `package:flutter_test` and loads only under `flutter test`. A
standalone Dart SDK (no Flutter SDK) cannot run `dart test` here at all:
version solving fails on `flutter_test` from the SDK (exit 65).

## Living implementation docs (committed)

- `IMPLEMENTATION-PLAN.md` — Phase 1 audit, roadmap, risks, verification
  evidence. The plan of record for the implementation.
- `TRACEABILITY.md` — SRS ID → SDD section → module → implementation
  location → test case → status.
