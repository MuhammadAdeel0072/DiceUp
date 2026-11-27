#!/bin/sh
# Import-boundary checks (M3.4, M-07; SDD §4.2/§4.4).
#
# Enforces the layering the composition root relies on:
# * the domain layer stays pure Dart (no Flutter, Riverpod, storage,
#   network, or imports of the presentation/data layers);
# * no screen constructs a repository, the engine or the controller
#   — the provider graph (lib/presentation/providers/) is the only
#   construction site, and the game screen reads it, never the data
#   layer directly;
# * RandomDiceRoller (the nondeterministic roller, NFR-18) is used
#   only inside the engine and in tests;
# * no presentation file gains a NEW import of the data layer — the
#   six files that still import it are grandfathered (see below).
#
# Two deliberate deviations from the M-07 letter, recorded here and in
# docs/IMPLEMENTATION-PLAN.md (M3.4):
# * RandomDiceRoller: M-07 also allows offline-presentation, but no
#   presentation file uses it today, so the check allows engine +
#   tests only. If offline presentation ever needs it, add an explicit
#   allowlist entry with a reason — do not silently widen the grep.
# * Presentation -> data: M-07 states the blanket ban, but it cannot
#   be enforced yet — five screens plus the scope still read the data
#   layer through AppDependenciesScope (M3.3 deferred their migration
#   one screen at a time), and the provider graph legitimately imports
#   it as the composition root. The check below therefore enforces
#   "no NEW presentation -> data import" against the grandfathered
#   list; the blanket ban lands when those screens migrate.
#
# Run from anywhere: `sh diceup_app/tool/check_boundaries.sh`
# (or from inside diceup_app: `sh tool/check_boundaries.sh`).
# Exit code 0 = all checks pass; 1 = a violation was found.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0

# fail_when <description> <grep-output>: a non-empty grep output
# means a forbidden pattern was found.
fail_when() {
  desc="$1"
  out="$2"
  if [ -n "$out" ]; then
    echo "FAIL: $desc"
    echo "$out"
    fail=1
  else
    echo "ok: $desc"
  fi
}

# -- Domain purity (SDD §4.2/§4.4; import lines only, so doc
#    comments that merely name a package do not trip the check) ------
fail_when "domain imports no Flutter" \
  "$(grep -rn --include='*.dart' '^import.*package:flutter/\|^import.*dart:ui' lib/domain)"
fail_when "domain imports no Riverpod" \
  "$(grep -rn --include='*.dart' '^import.*riverpod' lib/domain)"
fail_when "domain imports no storage" \
  "$(grep -rn --include='*.dart' '^import.*sqflite\|^import.*package:diceup/data' lib/domain)"
fail_when "domain imports no dart:io / network" \
  "$(grep -rn --include='*.dart' '^import.*dart:io\|^import.*package:http\|^import.*package:dio' lib/domain)"
fail_when "domain imports no presentation/data layer" \
  "$(grep -rn --include='*.dart' '^import.*\(data/\|presentation/\)' lib/domain)"

# -- RandomDiceRoller stays in the engine (M-07, NFR-18) -------------------
# Allowed: lib/domain/engine (the default roller lives in LudoGame)
# and test/ (seeded rollers). Stricter than M-07's letter, which also
# allows offline-presentation — nothing there uses it today (see header).
fail_when "RandomDiceRoller used only in engine + tests" \
  "$(grep -rn --include='*.dart' 'RandomDiceRoller' lib \
    | grep -v 'lib/domain/engine/')"

# -- No NEW presentation -> data import (M-07, grandfathered) --------------
# Grandfathered (M3.3-deferred AppDependenciesScope consumers + the
# composition root, which legitimately imports the data layer):
# app_routes, splash_screen, home_screen, offline_setup_screen,
# app_dependencies_scope, app_providers. Any other presentation file
# importing data/ fails. The blanket ban replaces this list once those
# screens migrate off AppDependenciesScope.
fail_when "no new presentation file imports the data layer" \
  "$(grep -rn --include='*.dart' '^import.*data/' lib/presentation \
    | grep -v -e 'app_routes.dart' \
              -e 'splash_screen.dart' \
              -e 'home_screen.dart' \
              -e 'offline_setup_screen.dart' \
              -e 'app_dependencies_scope.dart' \
              -e 'app_providers.dart')"

# -- No construction outside the composition root ----------------------------
fail_when "only the provider graph constructs OfflineGameController" \
  "$(grep -rn --include='*.dart' 'OfflineGameController(' lib \
    | grep -v 'lib/presentation/providers/app_providers.dart' \
    | grep -v 'lib/domain/offline_game_controller.dart')"
fail_when "no screen constructs a SQLite repository" \
  "$(grep -rn --include='*.dart' -E 'Sqlite[A-Za-z]+Repository\(' lib/presentation)"
fail_when "no screen constructs the engine directly" \
  "$(grep -rn --include='*.dart' -E 'LudoGame\.(newMatch|fromState)\(' lib/presentation)"
fail_when "no screen constructs AppDependencies" \
  "$(grep -rn --include='*.dart' 'AppDependencies(' lib/presentation)"

# -- Game flow is provider-driven (M3.3) -------------------------------------
fail_when "game_screen imports no data layer" \
  "$(grep -n 'data/local' lib/presentation/screens/game_screen.dart)"

if [ "$fail" -eq 0 ]; then
  echo "check_boundaries: all checks passed"
else
  echo "check_boundaries: VIOLATIONS FOUND" >&2
  exit 1
fi
