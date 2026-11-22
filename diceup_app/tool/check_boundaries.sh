#!/bin/sh
# Import-boundary checks (M3.3, H-07; SDD §4.2/§4.4).
#
# Enforces the layering the composition root relies on:
# * the domain layer stays pure Dart (no Flutter, Riverpod, storage);
# * no screen constructs a repository, the engine or the controller
#   — the provider graph (lib/presentation/providers/) is the only
#   construction site, and the game screen reads it, never the data
#   layer directly.
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
