/// Row/JSON codecs shared by the SQLite repositories (M1.4, SDD §9.1).
///
/// The domain layer never traffics in raw strings or row maps: this
/// file is the single place that knows the storage formats, so the
/// repositories stay thin. All timestamps are stored as UTC ISO-8601
/// strings (see [toUtcIso]); normalising to UTC on write keeps
/// lexicographic ordering equal to chronological ordering for the
/// `played_at DESC` / `last_used_at DESC` lists. Parsing is strict:
/// an unknown mode, colour or difficulty label throws
/// [FormatException] — never silently defaults — mirroring the
/// domain's `fromLabel` behaviour (D-22: reject corrupt data
/// outright). Snapshot JSON and settings values are opaque strings
/// and are never parsed here.
///
/// No database type leaks into the domain layer: these helpers take
/// and return domain value objects and plain row maps only.
library;

import 'dart:convert';

import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/local_player_repository.dart';
import 'package:diceup/domain/repositories/local_statistics_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';

/// Formats [value] as a UTC ISO-8601 string for storage.
String toUtcIso(DateTime value) => value.toUtc().toIso8601String();

/// Parses a storage label back to a [PlayerColour]. Throws
/// [FormatException] on an unknown label — never silently defaults.
PlayerColour parsePlayerColourLabel(String label) {
  for (final colour in PlayerColour.values) {
    if (colour.label == label) return colour;
  }
  throw FormatException('Unknown player colour "$label".');
}

/// Parses a storage label back to an [AiDifficulty]. Throws
/// [FormatException] on an unknown label — never silently defaults.
AiDifficulty parseAiDifficultyLabel(String label) {
  for (final difficulty in AiDifficulty.values) {
    if (difficulty.name == label) return difficulty;
  }
  throw FormatException('Unknown AI difficulty "$label".');
}

/// Serialises [players] to the `local_matches.players_json` format:
/// a JSON array of seat objects `{name, colour, isAi, difficulty}`
/// where `colour` is the [PlayerColour] label and `difficulty` is
/// the [AiDifficulty] label or null (null for human seats and for AI
/// seats with an unspecified difficulty).
String encodePlayersJson(List<LocalMatchPlayer> players) => jsonEncode(
      players
          .map(
            (player) => <String, Object?>{
              'name': player.name,
              'colour': player.colour.label,
              'isAi': player.isAi,
              'difficulty': player.difficulty?.name,
            },
          )
          .toList(),
    );

/// Parses `local_matches.players_json` back to seats. Strict: the
/// JSON must be an array of seat objects with a non-empty string
/// name, a known colour label, a boolean `isAi` and a null-or-known
/// difficulty label; a human seat must not carry a difficulty.
/// Anything else throws [FormatException].
List<LocalMatchPlayer> decodePlayersJson(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! List) {
    throw const FormatException('players_json must be a JSON array.');
  }
  return decoded.map<LocalMatchPlayer>((entry) {
    if (entry is! Map) {
      throw const FormatException(
        'players_json entries must be JSON objects.',
      );
    }
    final name = entry['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException(
        'players_json entries need a non-empty string name.',
      );
    }
    final colourLabel = entry['colour'];
    if (colourLabel is! String) {
      throw const FormatException(
        'players_json entries need a string colour.',
      );
    }
    final isAi = entry['isAi'];
    if (isAi is! bool) {
      throw const FormatException(
        'players_json entries need a boolean isAi.',
      );
    }
    final difficultyLabel = entry['difficulty'];
    AiDifficulty? difficulty;
    if (difficultyLabel != null) {
      if (difficultyLabel is! String) {
        throw const FormatException(
          'players_json difficulty must be a string or null.',
        );
      }
      difficulty = parseAiDifficultyLabel(difficultyLabel);
    }
    if (!isAi && difficulty != null) {
      throw const FormatException(
        'A human seat in players_json cannot have a difficulty.',
      );
    }
    return LocalMatchPlayer(
      name: name,
      colour: parsePlayerColourLabel(colourLabel),
      isAi: isAi,
      difficulty: difficulty,
    );
  }).toList();
}

/// Builds a `local_matches` row map from [match] (no `id` — the
/// database assigns it on insert; any id on the argument is ignored).
Map<String, Object?> matchToRow(LocalMatch match) => <String, Object?>{
      'played_at': toUtcIso(match.playedAt),
      'mode': match.mode.label,
      'player_count': match.playerCount,
      'players_json': encodePlayersJson(match.players),
      'winner_index': match.winnerIndex,
      'winner_name': match.winnerName,
      'duration_seconds': match.durationSeconds,
      'ruleset_version': match.rulesetVersion,
      'created_at': toUtcIso(match.createdAt),
    };

/// Builds a [LocalMatch] from a `local_matches` row. Strict parsing
/// (see [decodePlayersJson]; unknown mode labels throw via
/// [LocalMatchMode.fromLabel]).
LocalMatch matchFromRow(Map<String, Object?> row) => LocalMatch(
      id: row['id'] as int,
      playedAt: DateTime.parse(row['played_at'] as String),
      mode: LocalMatchMode.fromLabel(row['mode'] as String),
      playerCount: row['player_count'] as int,
      players: decodePlayersJson(row['players_json'] as String),
      winnerIndex: row['winner_index'] as int?,
      winnerName: row['winner_name'] as String?,
      durationSeconds: row['duration_seconds'] as int?,
      rulesetVersion: row['ruleset_version'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );

/// Builds a [LocalStatistics] from the single `local_statistics`
/// row (id = 1).
LocalStatistics statisticsFromRow(Map<String, Object?> row) =>
    LocalStatistics(
      matchesPlayed: row['matches_played'] as int,
      matchesWon: row['matches_won'] as int,
      matchesVsAi: row['matches_vs_ai'] as int,
      matchesLocal: row['matches_local'] as int,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );

/// Builds a [SavedSnapshot] from a `saved_match_snapshots` row. The
/// snapshot JSON is returned verbatim, never parsed.
SavedSnapshot snapshotFromRow(Map<String, Object?> row) =>
    SavedSnapshot(
      matchKey: row['match_key'] as String,
      snapshotJson: row['snapshot_json'] as String,
      savedAt: DateTime.parse(row['saved_at'] as String),
    );

/// Builds a `local_players` row map from [seat]. The `id` is
/// included only when present (a null id means "assign a fresh id"
/// on insert); `lastUsedAt` is stored exactly as given, never
/// stamped with the clock.
Map<String, Object?> seatToRow(LocalPlayerSeat seat) {
  final row = <String, Object?>{
    'display_name': seat.displayName,
    'colour': seat.colour.label,
    'is_ai': seat.isAi ? 1 : 0,
    'difficulty': seat.difficulty?.name,
    'last_used_at':
        seat.lastUsedAt == null ? null : toUtcIso(seat.lastUsedAt!),
  };
  final id = seat.id;
  if (id != null) row['id'] = id;
  return row;
}

/// Builds a [LocalPlayerSeat] from a `local_players` row. Strict
/// parsing: unknown colour/difficulty labels throw [FormatException].
LocalPlayerSeat seatFromRow(Map<String, Object?> row) {
  final difficultyLabel = row['difficulty'] as String?;
  final lastUsedAt = row['last_used_at'] as String?;
  return LocalPlayerSeat(
    id: row['id'] as int,
    displayName: row['display_name'] as String,
    colour: parsePlayerColourLabel(row['colour'] as String),
    isAi: (row['is_ai'] as int) != 0,
    difficulty: difficultyLabel == null
        ? null
        : parseAiDifficultyLabel(difficultyLabel),
    lastUsedAt: lastUsedAt == null ? null : DateTime.parse(lastUsedAt),
  );
}
