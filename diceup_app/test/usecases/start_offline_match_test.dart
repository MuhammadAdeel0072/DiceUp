import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/ruleset_config.dart';
import 'package:diceup/domain/usecases/match_setup.dart';
import 'package:diceup/domain/usecases/start_offline_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StartOfflineMatch', () {
    test('valid vs-AI setup starts a match with fixed dice', () {
      final start = StartOfflineMatch(diceRoller: FixedDiceRoller(const [4]));
      final game = start(
        const MatchSetup(
          playerCount: 2,
          aiSeats: {1: AiDifficulty.hard},
          names: ['Ana', 'CPU'],
          colours: [PlayerColour.red, PlayerColour.green],
        ),
      );

      expect(game.state.phase.name, 'awaitingRoll');
      expect(game.currentPlayerIndex, 0);
      expect(game.state.players[0].isHuman, isTrue);
      expect(game.state.players[0].name, 'Ana');
      final ai = game.state.players[1];
      expect(ai, isA<AiPlayer>());
      expect((ai as AiPlayer).difficulty, AiDifficulty.hard);
      expect(ai.name, 'CPU');
      expect(game.rollDice(), 4);
    });

    test('missing names and colours fall back to Player N / seat order', () {
      final game = StartOfflineMatch()(
        const MatchSetup(playerCount: 2, aiSeats: {}),
      );

      expect(game.state.players[0].name, 'Player 1');
      expect(game.state.players[0].colour, PlayerColour.red);
      expect(game.state.players[1].name, 'Player 2');
      expect(game.state.players[1].colour, PlayerColour.green);
    });

    test('blank names fall back to Player N, chosen names are trimmed', () {
      final game = StartOfflineMatch()(
        const MatchSetup(playerCount: 2, aiSeats: {}, names: ['  Ana  ', '']),
      );

      expect(game.state.players[0].name, 'Ana');
      expect(game.state.players[1].name, 'Player 2');
    });

    test('duplicate colours surface InvalidMatchConfig', () {
      expect(
        () => StartOfflineMatch()(
          const MatchSetup(
            playerCount: 2,
            aiSeats: {},
            colours: [PlayerColour.red, PlayerColour.red],
          ),
        ),
        throwsA(isA<InvalidMatchConfig>()),
      );
    });

    test('zero human seats surface InvalidMatchConfig', () {
      expect(
        () => StartOfflineMatch()(
          const MatchSetup(
            playerCount: 2,
            aiSeats: {0: AiDifficulty.easy, 1: AiDifficulty.hard},
          ),
        ),
        throwsA(isA<InvalidMatchConfig>()),
      );
    });

    test('an invalid ruleset surfaces InvalidRulesetConfig', () {
      expect(
        () => StartOfflineMatch()(
          const MatchSetup(
            playerCount: 2,
            aiSeats: {},
            ruleset: RulesetConfig(releaseOnSix: false, releaseOnOne: false),
          ),
        ),
        throwsA(isA<InvalidRulesetConfig>()),
      );
    });

    test('player counts outside 2–4 surface InvalidMatchConfig', () {
      expect(
        () =>
            StartOfflineMatch()(const MatchSetup(playerCount: 1, aiSeats: {})),
        throwsA(isA<InvalidMatchConfig>()),
      );
      expect(
        () =>
            StartOfflineMatch()(const MatchSetup(playerCount: 5, aiSeats: {})),
        throwsA(isA<InvalidMatchConfig>()),
      );
    });

    test('a custom ruleset passes through to the match', () {
      const ruleset = RulesetConfig(releaseOnOne: true, exactFinish: false);
      final game = StartOfflineMatch()(
        const MatchSetup(playerCount: 2, aiSeats: {}, ruleset: ruleset),
      );

      expect(game.ruleset, ruleset);
    });

    test('no snapshot is saved at match start', () {
      // StartOfflineMatch takes no repository: there is nowhere for
      // a snapshot to go. This test pins the contract — a fresh
      // match leaves no resume state until the first move/roll.
      final game = StartOfflineMatch()(
        const MatchSetup(playerCount: 2, aiSeats: {}),
      );
      expect(game.state.moveCount, 0);
      expect(game.state.lastRoll, 0);
    });
  });
}
