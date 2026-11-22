#!/bin/sh
# Local mirror of the CI jobs (M3.4): pub get, format, analyze, test,
# boundaries, strings. Run from anywhere: `sh diceup_app/tool/check.sh`
# (or from inside diceup_app: `sh tool/check.sh`).
# Exit code 0 = every gate passed; non-zero = the first failing gate.
# Requires Flutter on PATH (the repo toolchain is Flutter 3.50.1).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

echo "==> flutter pub get"
flutter pub get

echo "==> dart format --output=none --set-exit-if-changed ."
dart format --output=none --set-exit-if-changed .

echo "==> flutter analyze --no-fatal-infos"
# Plain `flutter analyze` exits 1 on the 33 known info-level
# `material.dart` deprecation notices (pre-existing, unactionable —
# see the M3.4 plan section), so the gate is "0 errors / 0 warnings":
# --no-fatal-infos keeps info non-fatal while errors and warnings
# (fatal by default) still fail the gate.
flutter analyze --no-fatal-infos

echo "==> flutter test"
flutter test

echo "==> sh tool/check_boundaries.sh"
sh tool/check_boundaries.sh

echo "==> sh tool/check_strings.sh"
sh tool/check_strings.sh

echo "check: all gates passed"
