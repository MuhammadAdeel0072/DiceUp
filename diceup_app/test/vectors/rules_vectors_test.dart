import 'dart:convert';
import 'dart:io';

import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/engine/ruleset_config.dart';
import 'package:test/test.dart';

/// Shared rule vectors (remediation plan §4 M3.6, SDD §6.9, NFR-39).
///
/// Loads `test/vectors/rules.json`, replays every case through
/// [LudoGame.fromState] + `rollDice` / `legalMoves` / `applyMove` with a
/// [FixedDiceRoller], and asserts the expected legal moves and outcome.
/// A vector that fails fails the build: there are no silent skips and
/// no lenient matching.
///
/// The file's shape is validated strictly, before any case runs:
/// unknown fields, unknown cases/ops, missing keys and wrong types all
/// fail loudly instead of being silently ignored. The starting states
/// are strict `GameState` snapshots (M1.1/D-22), so a malformed state
/// fails here through [GameState.fromJson] rather than being repaired.
///
/// The runner passes each case's ruleset explicitly to
/// [LudoGame.fromState]: the engine does not infer the ruleset from the
/// snapshot, so a case whose embedded ruleset disagrees with its
/// `ruleset` field is a vector error, not an engine behaviour.
void main() {
  final List<Map<String, Object?>> cases;
  try {
    cases = _loadCases();
  } on FormatException catch (e) {
    test('rules.json is a valid vector file', () {
      fail('rules.json failed validation: $e');
    });
    return;
  }

  test('rules.json contains at least 14 cases', () {
    expect(cases.length, greaterThanOrEqualTo(14));
  });

  test('rules.json covers every rule family (D-16)', () {
    final covered = <String>{
      for (final c in cases) ..._asList(c['rules'], 'rules').cast<String>(),
    };
    for (final rule in [
      'BR-04',
      'BR-05',
      'BR-06',
      'BR-07',
      'BR-08',
      'BR-09',
      'BR-10',
      'BR-11',
      'BR-12',
      'BR-13',
    ]) {
      expect(covered, contains(rule), reason: 'no vector covers $rule');
    }
  });

  group('rule vectors (docs/ruleset.md)', () {
    for (final c in cases) {
      test(c['id'] as String, () => _replayCase(c));
    }
  });
}

/// Loads and strictly validates the whole vector file.
///
/// Throws [FormatException] on the first problem found, naming the
/// case and field. Nothing is defaulted, coerced, or skipped.
List<Map<String, Object?>> _loadCases() {
  const path = 'test/vectors/rules.json';
  final file = File(path);
  if (!file.existsSync()) {
    throw FormatException('vector file not found: $path');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  final doc = _asMap(decoded, 'top level');
  _exactKeys(doc, {'formatVersion', 'rulesetVersion', 'cases'}, 'top level');
  if (doc['formatVersion'] != 1) {
    throw const FormatException('top level: formatVersion must be 1.');
  }
  final rulesetVersion = _asString(doc['rulesetVersion'], 'rulesetVersion');
  if (rulesetVersion != '1.0.0') {
    throw FormatException(
      'top level: rulesetVersion must be 1.0.0 (got "$rulesetVersion").',
    );
  }
  final rawCases = _asList(doc['cases'], 'cases');
  if (rawCases.isEmpty) {
    throw const FormatException('cases must not be empty.');
  }
  final ids = <String>{};
  final cases = <Map<String, Object?>>[];
  for (var i = 0; i < rawCases.length; i++) {
    final c = _asMap(rawCases[i], 'cases[$i]');
    _exactKeys(c, {
      'id',
      'title',
      'rules',
      'ruleset',
      'initial',
      'dice',
      'steps',
      'expectFinal',
    }, 'cases[$i]');
    final id = _asString(c['id'], 'cases[$i].id');
    if (id.isEmpty) {
      throw FormatException('cases[$i].id must not be empty.');
    }
    if (!ids.add(id)) {
      throw FormatException('duplicate case id "$id".');
    }
    final title = _asString(c['title'], 'cases[$i].title');
    if (title.isEmpty) {
      throw FormatException('case "$id": title must not be empty.');
    }
    final rules = _asList(c['rules'], 'case "$id".rules');
    if (rules.isEmpty) {
      throw FormatException('case "$id": rules must not be empty.');
    }
    for (final rule in rules) {
      final label = _asString(rule, 'case "$id".rules entry');
      if (!RegExp(r'^(BR|FR)-\d+$').hasMatch(label)) {
        throw FormatException(
          'case "$id": bad rule label "$label" (expected BR-NN/FR-NN).',
        );
      }
    }
    final rulesetJson = _asMap(c['ruleset'], 'case "$id".ruleset');
    _exactKeys(rulesetJson, {
      'releaseOnSix',
      'releaseOnOne',
      'extraTurnOnSix',
      'extraTurnOnCapture',
      'extraTurnOnHome',
      'maxConsecutiveSixes',
      'exactFinish',
      'version',
    }, 'case "$id".ruleset');
    final ruleset = RulesetConfig.fromJson(rulesetJson);
    if (ruleset.version != rulesetVersion) {
      throw FormatException(
        'case "$id": ruleset version "${ruleset.version}" does not match '
        'top-level rulesetVersion "$rulesetVersion".',
      );
    }
    final initial = _asMap(c['initial'], 'case "$id".initial');
    // Strict snapshot validation (M1.1): malformed states throw here.
    final state = GameState.fromJson(initial);
    if (!_deepEquals(initial['ruleset'], c['ruleset'])) {
      throw FormatException(
        'case "$id": initial.ruleset does not match the case ruleset.',
      );
    }
    if (initial['rulesetVersion'] != rulesetVersion) {
      throw FormatException(
        'case "$id": initial.rulesetVersion does not match '
        'rulesetVersion "$rulesetVersion".',
      );
    }
    final dice = _asList(c['dice'], 'case "$id".dice');
    if (dice.isEmpty) {
      throw FormatException('case "$id": dice must not be empty.');
    }
    for (final value in dice) {
      if (value is! int || value < 1 || value > 6) {
        throw FormatException(
          'case "$id": dice values must be integers in 1..6.',
        );
      }
    }
    final steps = _asList(c['steps'], 'case "$id".steps');
    if (steps.isEmpty) {
      throw FormatException('case "$id": steps must not be empty.');
    }
    for (var s = 0; s < steps.length; s++) {
      _validateStep(_asMap(steps[s], 'case "$id".steps[$s]'), id, s);
    }
    final expectFinal = _asMap(c['expectFinal'], 'case "$id".expectFinal');
    _exactKeys(expectFinal, {
      'currentPlayerIndex',
      'phase',
      'winnerIndex',
      'lastRoll',
      'consecutiveSixes',
      'lastRollWasThirdSix',
      'lastRollHadNoLegalMove',
      'tokens',
    }, 'case "$id".expectFinal');
    _asPhase(expectFinal['phase'], 'case "$id".expectFinal.phase');
    final tokens = _asList(expectFinal['tokens'], 'case "$id".tokens');
    if (tokens.length != state.players.length) {
      throw FormatException(
        'case "$id": expectFinal.tokens must have one entry per player '
        '(${state.players.length}).',
      );
    }
    for (var p = 0; p < tokens.length; p++) {
      final row = _asList(tokens[p], 'case "$id".tokens[$p]');
      if (row.length != 4) {
        throw FormatException(
          'case "$id": expectFinal.tokens[$p] must have 4 entries.',
        );
      }
      for (final stepsTaken in row) {
        if (stepsTaken is! int || stepsTaken < 0 || stepsTaken > 56) {
          throw FormatException(
            'case "$id": expectFinal.tokens[$p] entries must be '
            'integers in 0..56.',
          );
        }
      }
    }
    cases.add(c);
  }
  return cases;
}

/// Validates one replay step. Throws [FormatException] on any problem.
void _validateStep(Map<String, Object?> step, String caseId, int index) {
  final where = 'case "$caseId".steps[$index]';
  final op = _asString(step['op'], '$where.op');
  switch (op) {
    case 'roll':
      _exactKeys(
        step,
        {
          'op',
          'expectRoll',
          'expectLegalMoves',
          'expectPhase',
          'expectCurrentPlayer',
          'expectLastRollWasThirdSix',
          'expectLastRollHadNoLegalMove',
        },
        where,
        optional: {'expectLastRollWasThirdSix', 'expectLastRollHadNoLegalMove'},
      );
      final roll = step['expectRoll'];
      if (roll is! int || roll < 1 || roll > 6) {
        throw FormatException('$where.expectRoll must be an integer 1..6.');
      }
      final legal = _asList(step['expectLegalMoves'], '$where.legal');
      var previous = -1;
      for (final token in legal) {
        if (token is! int || token < 0 || token > 3 || token <= previous) {
          throw FormatException(
            '$where.expectLegalMoves must be token indices 0..3 in '
            'increasing order.',
          );
        }
        previous = token;
      }
      _asPhase(step['expectPhase'], '$where.expectPhase');
      _asNonNegativeInt(step['expectCurrentPlayer'], '$where.currentPlayer');
      _asOptionalBool(step, 'expectLastRollWasThirdSix', where);
      _asOptionalBool(step, 'expectLastRollHadNoLegalMove', where);
    case 'move':
      _exactKeys(step, {'op', 'token', 'expect'}, where);
      _asTokenIndex(step['token'], '$where.token');
      final expect = _asMap(step['expect'], '$where.expect');
      _exactKeys(
        expect,
        {
          'fromSteps',
          'toSteps',
          'captured',
          'enteredHomePath',
          'reachedHome',
          'extraTurn',
          'winnerIndex',
          'expectPhase',
          'expectCurrentPlayer',
        },
        '$where.expect',
        optional: {'expectPhase', 'expectCurrentPlayer'},
      );
      _asSteps(expect['fromSteps'], '$where.expect.fromSteps');
      _asSteps(expect['toSteps'], '$where.expect.toSteps');
      final captured = _asList(expect['captured'], '$where.expect.captured');
      for (final ref in captured) {
        final pair = _asList(ref, '$where.expect.captured entry');
        if (pair.length != 2 ||
            pair[0] is! int ||
            pair[1] is! int ||
            (pair[0] as int) < 0 ||
            (pair[1] as int) < 0 ||
            (pair[1] as int) > 3) {
          throw FormatException(
            '$where.expect.captured entries must be [playerIndex, '
            'tokenIndex] pairs.',
          );
        }
      }
      for (final key in ['enteredHomePath', 'reachedHome', 'extraTurn']) {
        if (expect[key] is! bool) {
          throw FormatException('$where.expect.$key must be a bool.');
        }
      }
      final winner = expect['winnerIndex'];
      if (winner != null && (winner is! int || winner < 0)) {
        throw FormatException(
          '$where.expect.winnerIndex must be null or a non-negative int.',
        );
      }
      if (expect.containsKey('expectPhase')) {
        _asPhase(expect['expectPhase'], '$where.expect.expectPhase');
      }
      if (expect.containsKey('expectCurrentPlayer')) {
        _asNonNegativeInt(
          expect['expectCurrentPlayer'],
          '$where.expect.expectCurrentPlayer',
        );
      }
    case 'moveIllegal':
      _exactKeys(step, {'op', 'token'}, where);
      _asTokenIndex(step['token'], '$where.token');
    case 'nextTurn':
      // Passes the turn explicitly (FR-19). Only valid between turns.
      _exactKeys(step, {'op', 'expectCurrentPlayer', 'expectPhase'}, where);
      _asNonNegativeInt(
        step['expectCurrentPlayer'],
        '$where.expectCurrentPlayer',
      );
      _asPhase(step['expectPhase'], '$where.expectPhase');
    case 'rollStateError':
      // Rolling while a move is pending must throw StateError and
      // leave the state unchanged (FR-21).
      _exactKeys(step, {'op'}, where);
    case 'moveStateError':
      // Moving before any roll must throw StateError and leave the
      // state unchanged (FR-21).
      _exactKeys(step, {'op', 'token'}, where);
      _asTokenIndex(step['token'], '$where.token');
    case 'moveWrongPlayer':
      // A move naming a player other than the active player must
      // throw ArgumentError and leave the state unchanged (FR-17).
      _exactKeys(step, {'op', 'playerIndex', 'token'}, where);
      _asNonNegativeInt(step['playerIndex'], '$where.playerIndex');
      _asTokenIndex(step['token'], '$where.token');
    case 'snapshotRoundTrip':
      // Serialise the current state and restore a fresh game from it;
      // the restored state must be identical, and play continues from
      // it (FR-29). The dice sequence restarts on restore, so this op
      // must precede any roll step in a case.
      _exactKeys(step, {'op'}, where);
    default:
      throw FormatException('$where: unknown op "$op".');
  }
}

/// Replays one validated case through the engine.
void _replayCase(Map<String, Object?> c) {
  final id = c['id'] as String;
  final ruleset = RulesetConfig.fromJson(_asMap(c['ruleset'], 'ruleset'));
  final dice = _asList(c['dice'], 'dice').cast<int>();
  var game = LudoGame.fromState(
    GameState.fromJson(_asMap(c['initial'], 'initial')),
    ruleset: ruleset,
    diceRoller: FixedDiceRoller(dice),
  );
  for (final rawStep in _asList(c['steps'], 'steps')) {
    final step = _asMap(rawStep, 'step');
    switch (step['op']) {
      case 'nextTurn':
        game.nextTurn();
        expect(
          game.state.phase.name,
          step['expectPhase'],
          reason: '$id: phase after nextTurn',
        );
        expect(
          game.currentPlayerIndex,
          step['expectCurrentPlayer'],
          reason: '$id: current player after nextTurn',
        );
      case 'rollStateError':
        final beforeRoll = game.state.toJson();
        expect(
          () => game.rollDice(),
          throwsStateError,
          reason: '$id: rolling while a move is pending must throw StateError',
        );
        expect(
          game.state.toJson(),
          beforeRoll,
          reason: '$id: state must be unchanged after a rejected roll',
        );
      case 'moveStateError':
        final beforeMove = game.state.toJson();
        expect(
          () => game.applyMove(
            Move(
              playerIndex: game.currentPlayerIndex,
              tokenIndex: step['token'] as int,
            ),
          ),
          throwsStateError,
          reason: '$id: moving before a roll must throw StateError',
        );
        expect(
          game.state.toJson(),
          beforeMove,
          reason: '$id: state must be unchanged after a rejected move',
        );
      case 'moveWrongPlayer':
        final beforeWrong = game.state.toJson();
        expect(
          () => game.applyMove(
            Move(
              playerIndex: step['playerIndex'] as int,
              tokenIndex: step['token'] as int,
            ),
          ),
          throwsArgumentError,
          reason: '$id: a move by the wrong player must throw ArgumentError',
        );
        expect(
          game.state.toJson(),
          beforeWrong,
          reason: '$id: state must be unchanged after a wrong-player move',
        );
      case 'snapshotRoundTrip':
        final beforeSnapshot = game.state.toJson();
        game = LudoGame.restore(
          game.snapshot(),
          ruleset: ruleset,
          diceRoller: FixedDiceRoller(dice),
        );
        expect(
          game.state.toJson(),
          beforeSnapshot,
          reason: '$id: restored state must equal the snapshot',
        );
      case 'roll':
        final value = game.rollDice();
        expect(value, step['expectRoll'], reason: '$id: rolled value');
        expect(
          game.legalMoves().map((m) => m.tokenIndex).toList(),
          _asList(step['expectLegalMoves'], 'expectLegalMoves').cast<int>(),
          reason: '$id: legal moves after rolling $value',
        );
        expect(
          game.state.phase.name,
          step['expectPhase'],
          reason: '$id: phase after rolling $value',
        );
        expect(
          game.currentPlayerIndex,
          step['expectCurrentPlayer'],
          reason: '$id: current player after rolling $value',
        );
        if (step.containsKey('expectLastRollWasThirdSix')) {
          expect(
            game.state.lastRollWasThirdSix,
            step['expectLastRollWasThirdSix'],
            reason: '$id: lastRollWasThirdSix after rolling $value',
          );
        }
        if (step.containsKey('expectLastRollHadNoLegalMove')) {
          expect(
            game.state.lastRollHadNoLegalMove,
            step['expectLastRollHadNoLegalMove'],
            reason: '$id: lastRollHadNoLegalMove after rolling $value',
          );
        }
      case 'move':
        final moveExpect = _asMap(step['expect'], 'expect');
        final result = game.applyMove(
          Move(
            playerIndex: game.currentPlayerIndex,
            tokenIndex: step['token'] as int,
          ),
        );
        expect(
          result.fromSteps,
          moveExpect['fromSteps'],
          reason: '$id: fromSteps',
        );
        expect(result.toSteps, moveExpect['toSteps'], reason: '$id: toSteps');
        expect(
          result.captured.map((t) => [t.playerIndex, t.tokenIndex]).toList(),
          (_asList(moveExpect['captured'], 'captured') as List)
              .map((p) => (_asList(p, 'captured entry')).cast<int>())
              .toList(),
          reason: '$id: captured tokens',
        );
        expect(
          result.enteredHomePath,
          moveExpect['enteredHomePath'],
          reason: '$id: enteredHomePath',
        );
        expect(
          result.reachedHome,
          moveExpect['reachedHome'],
          reason: '$id: reachedHome',
        );
        expect(
          result.extraTurn,
          moveExpect['extraTurn'],
          reason: '$id: extraTurn',
        );
        expect(
          result.winnerIndex,
          moveExpect['winnerIndex'],
          reason: '$id: winnerIndex',
        );
        if (moveExpect.containsKey('expectPhase')) {
          expect(
            game.state.phase.name,
            moveExpect['expectPhase'],
            reason: '$id: phase after move',
          );
        }
        if (moveExpect.containsKey('expectCurrentPlayer')) {
          expect(
            game.currentPlayerIndex,
            moveExpect['expectCurrentPlayer'],
            reason: '$id: current player after move',
          );
        }
      case 'moveIllegal':
        final before = game.state.toJson();
        expect(
          () => game.applyMove(
            Move(
              playerIndex: game.currentPlayerIndex,
              tokenIndex: step['token'] as int,
            ),
          ),
          throwsArgumentError,
          reason: '$id: illegal move must throw ArgumentError',
        );
        expect(
          game.state.toJson(),
          before,
          reason: '$id: state must be unchanged after an illegal move',
        );
    }
  }
  final expectFinal = _asMap(c['expectFinal'], 'expectFinal');
  expect(
    game.currentPlayerIndex,
    expectFinal['currentPlayerIndex'],
    reason: '$id: final current player',
  );
  expect(
    game.state.phase.name,
    expectFinal['phase'],
    reason: '$id: final phase',
  );
  expect(
    game.state.winnerIndex,
    expectFinal['winnerIndex'],
    reason: '$id: final winner',
  );
  expect(
    game.state.lastRoll,
    expectFinal['lastRoll'],
    reason: '$id: final lastRoll',
  );
  expect(
    game.state.consecutiveSixes,
    expectFinal['consecutiveSixes'],
    reason: '$id: final consecutiveSixes',
  );
  expect(
    game.state.lastRollWasThirdSix,
    expectFinal['lastRollWasThirdSix'],
    reason: '$id: final lastRollWasThirdSix',
  );
  expect(
    game.state.lastRollHadNoLegalMove,
    expectFinal['lastRollHadNoLegalMove'],
    reason: '$id: final lastRollHadNoLegalMove',
  );
  expect(
    game.state.players
        .map((p) => p.tokens.map((t) => t.stepsTaken).toList())
        .toList(),
    (_asList(expectFinal['tokens'], 'tokens') as List)
        .map((row) => (_asList(row, 'tokens row')).cast<int>())
        .toList(),
    reason: '$id: final token positions',
  );
}

/// Rejects unknown or missing keys. [allowed] lists every permitted
/// key; [optional] lists the permitted keys that may be absent.
void _exactKeys(
  Map<String, Object?> map,
  Set<String> allowed,
  String where, {
  Set<String> optional = const {},
}) {
  for (final key in map.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$where: unknown field "$key".');
    }
  }
  for (final key in allowed.difference(optional)) {
    if (!map.containsKey(key)) {
      throw FormatException('$where: missing required field "$key".');
    }
  }
}

Map<String, Object?> _asMap(Object? value, String where) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  throw FormatException('$where must be an object.');
}

List<Object?> _asList(Object? value, String where) {
  if (value is List<Object?>) return value;
  if (value is List) return value.cast<Object?>();
  throw FormatException('$where must be a list.');
}

String _asString(Object? value, String where) {
  if (value is String) return value;
  throw FormatException('$where must be a string.');
}

void _asNonNegativeInt(Object? value, String where) {
  if (value is! int || value < 0) {
    throw FormatException('$where must be a non-negative integer.');
  }
}

void _asTokenIndex(Object? value, String where) {
  if (value is! int || value < 0 || value > 3) {
    throw FormatException('$where must be a token index 0..3.');
  }
}

void _asSteps(Object? value, String where) {
  if (value is! int || value < 0 || value > 56) {
    throw FormatException('$where must be a step count 0..56.');
  }
}

void _asPhase(Object? value, String where) {
  if (value is! String ||
      !{'awaitingRoll', 'awaitingMove', 'finished'}.contains(value)) {
    throw FormatException(
      '$where must be awaitingRoll, awaitingMove, or finished.',
    );
  }
}

void _asOptionalBool(Map<String, Object?> map, String key, String where) {
  if (map.containsKey(key) && map[key] is! bool) {
    throw FormatException('$where.$key must be a bool.');
  }
}

/// Deep equality for JSON values (key-order independent for objects).
bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
