#!/bin/sh
# Strings-externalisation guard (M3.10, M-10 / NFR-38).
#
# Fails if any raw user-visible literal remains in the UI code:
# * a literal directly in a Text widget (Text('...') / Text("..."));
# * a literal in a named copy parameter (title:/subtitle:/hint:/
#   message:/label:/labelText:/tooltip:) of a widget or a shared
#   component call;
# * a data-layer message constant rendered directly (Text(k...)):
#   the UI must render the localised copy from AppLocalizations
#   instead — the constants stay as the data layer's source of
#   truth and the values the tests assert against.
#
# Scope: lib/presentation/ plus lib/core/design_system/
# diceup_components.dart — the one core file that renders UI copy
# (PlayerAvatar semantics label, ErrorView retry action,
# ConfirmationDialog cancel action). Generated code
# (lib/l10n/app_localizations*.dart) is outside the scope, so
# nothing in it can trip the guard. lib/l10n/app_en.arb is the
# single source of the English strings; lib/l10n/app_strings.dart
# only maps enums to localised names and carries no UI literals.
#
# Deliberate allowlist (each entry has a reason, recorded here):
# * Text('2') / Text('3') / Text('4') — the setup player-count
#   segments. Bare numerals, not words; they render identically
#   in every locale.
# * MaterialApp title 'DiceUp' (lib/main.dart, outside the scope)
#   — the OS task label, a proper noun.
# * Storage keys and JSON values ('sound_enabled', 'last_mode',
#   'vs_ai', ...) — never rendered; the named-parameter patterns
#   do not match them.
# * Log / debugPrint / assert strings and exception messages —
#   developer-only, never shown in the UI; the patterns below
#   only match Text widgets and named copy parameters.
#
# NOT covered by this guard (named gaps, see
# docs/IMPLEMENTATION-PLAN.md §M3.10): the domain controller's
# status strings (lib/domain/offline_game_controller.dart — the
# domain layer cannot import generated Flutter code, M-07, and
# its tests assert the exact strings) and the domain ruleset
# validation messages (unreachable from the UI); the GameSetup /
# MatchSetup nameFor "Player N" model defaults (asserted by
# tests; the user-facing setup flow localises the same default).
# Those need a status-key refactor and test updates, not a grep.
#
# Run from anywhere: `sh diceup_app/tool/check_strings.sh`
# (or from inside diceup_app: `sh tool/check_strings.sh`).
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

SCOPE="lib/presentation lib/core/design_system/diceup_components.dart"

# -- 1. No literal in a Text widget ------------------------------------
# Matches Text('...') / Text("..."); the allowlist drops the bare
# numeral segments (player count 2/3/4).
# shellcheck disable=SC2086
text_literals="$(grep -rnE --include='*.dart' "Text\( *['\"]" $SCOPE | grep -vE "Text\('[0-9]+'\)" || true)"
fail_when "no raw literal in Text() (allowlist: bare numerals only)" \
  "$text_literals"

# -- 2. No literal in a named copy parameter ---------------------------
# title:/subtitle:/hint:/message:/label:/labelText:/tooltip: followed
# by a quote. Covers AppBar/AlertDialog/SwitchListTile titles,
# EmptyState/ErrorView copy, button and field labels, Semantics
# labels, tooltips and dialog messages.
# shellcheck disable=SC2086
copy_literals="$(grep -rnE --include='*.dart' "(title|subtitle|hint|message|label|labelText|tooltip): *['\"]" $SCOPE | grep -vE "^\s*[0-9]+:\s*//" || true)"
fail_when "no raw literal in a title/subtitle/hint/message/label/tooltip copy parameter" \
  "$copy_literals"

# -- 3. No data-layer message constant rendered directly ---------------
# The UI renders the AppLocalizations copy; the constants stay in
# the data/presentation layer as the values the tests assert.
# shellcheck disable=SC2086
const_render="$(grep -rnE --include='*.dart' "Text\(k(DatabaseRecoveryMessage|CorruptSnapshotMessage|StartupDatabaseErrorMessage|MatchRecordFailedMessage|PerPlayerWinsCaption)\)" $SCOPE || true)"
fail_when "no data-layer message constant rendered directly in Text()" \
  "$const_render"

if [ "$fail" -ne 0 ]; then
  echo "check_strings: FAILED"
  exit 1
fi
echo "check_strings: all checks passed"
