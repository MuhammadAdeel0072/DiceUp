import 'package:diceup/data/online/game_models.dart';
import 'package:diceup/domain/online/connection_state.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/token.dart';
import 'package:diceup/l10n/app_localizations.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/online/online_game_screen.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_providers.dart';
import 'fakes.dart';

void main() {
  const matchId = '00000000-0000-0000-0000-000000000077';
  const hostId = '00000000-0000-0000-0000-000000000001';
  const guestId = '00000000-0000-0000-0000-000000000002';

  late FakeAuthService fakeAuth;
  late FakeGameRoomService fakeGame;

  GameState snapshotFor({
    int currentPlayer = 0,
    TurnPhase phase = TurnPhase.awaitingRoll,
    int lastRoll = 0,
    int token0Steps = 0,
  }) {
    final p0 = Player(
      index: 0,
      name: 'Ada',
      colour: PlayerColour.red,
      type: PlayerType.human,
      tokens: [
        Token(
          playerIndex: 0,
          index: 0,
          colour: PlayerColour.red,
          stepsTaken: token0Steps,
        ),
        const Token(playerIndex: 0, index: 1, colour: PlayerColour.red),
        const Token(playerIndex: 0, index: 2, colour: PlayerColour.red),
        const Token(playerIndex: 0, index: 3, colour: PlayerColour.red),
      ],
    );
    final p1 = Player(
      index: 1,
      name: 'Ben',
      colour: PlayerColour.green,
      type: PlayerType.human,
    );
    return GameState.initial(players: [p0, p1]).copyWith(
      currentPlayerIndex: currentPlayer,
      phase: phase,
      lastRoll: lastRoll,
    );
  }

  Map<String, Object?> statePayload(
    GameState snapshot, {
    int seq = 1,
    String? turnPlayerId,
  }) => <String, Object?>{
    'matchId': matchId,
    'seq': seq,
    'snapshot': snapshot.toJson(),
    'seats': const <Map<String, Object?>>[
      {'userId': hostId, 'seat': 0, 'colour': 'red'},
      {'userId': guestId, 'seat': 1, 'colour': 'green'},
    ],
    'turn': <String, Object?>{
      'playerId': turnPlayerId ?? hostId,
      'turnEndsAt': '2026-11-28T12:00:30.000Z',
    },
    'players': const <Map<String, Object?>>[
      {
        'userId': hostId,
        'seat': 0,
        'colour': 'red',
        'disconnected': false,
        'graceEndsAt': null,
        'missedTurns': 0,
        'result': null,
      },
      {
        'userId': guestId,
        'seat': 1,
        'colour': 'green',
        'disconnected': false,
        'graceEndsAt': null,
        'missedTurns': 0,
        'result': null,
      },
    ],
  };

  /// The screen ticks once a second, so tests drive it with explicit
  /// pumps, never `pumpAndSettle`.
  Future<void> pumpFrames(WidgetTester tester, {int count = 3}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpGame(
    WidgetTester tester, {
    void Function(Object? arguments)? onResultsArguments,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          startupResultProvider.overrideWithValue(testStartup(null)),
          authServiceProvider.overrideWithValue(fakeAuth),
          gameRoomServiceProvider.overrideWithValue(fakeGame),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The game route needs the match id as its arguments;
          // `initialRoute` cannot carry them, so the initial stack
          // is built here instead.
          onGenerateInitialRoutes: (_) => [
            MaterialPageRoute<void>(
              settings: const RouteSettings(
                name: AppRoutes.onlineGame,
                arguments: matchId,
              ),
              builder: (_) => const OnlineGameScreen(),
            ),
          ],
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.results) {
              onResultsArguments?.call(settings.arguments);
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const Text('results-screen'),
              );
            }
            if (settings.name == AppRoutes.home) {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const Text('home-screen'),
              );
            }
            return null;
          },
        ),
      ),
    );
    await pumpFrames(tester);
  }

  Future<void> loadMatch(
    WidgetTester tester, {
    GameState? snapshot,
    int seq = 1,
  }) async {
    fakeGame.emitConnectionState(GameSocketConnectionState.connected);
    fakeGame.emitMatchState(statePayload(snapshot ?? snapshotFor(), seq: seq));
    await pumpFrames(tester);
  }

  setUp(() {
    fakeAuth = FakeAuthService()
      ..restoreResult = FakeAuthService.cannedSession(verified: true);
    fakeGame = FakeGameRoomService()
      ..scriptedRoom = FakeGameRoomService.cannedRoom(
        members: [
          const RoomMember(
            userId: hostId,
            username: 'ada',
            displayName: 'Ada',
            isReady: true,
            isHost: true,
            joinedAt: '2026-11-28T00:00:00.000Z',
          ),
          const RoomMember(
            userId: guestId,
            username: 'ben',
            displayName: 'Ben',
            isReady: true,
            isHost: false,
            joinedAt: '2026-11-28T00:00:01.000Z',
          ),
        ],
      );
  });

  testWidgets('loads the snapshot, shows my turn and the roll action', (
    tester,
  ) async {
    await pumpGame(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await loadMatch(tester);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Roll dice'), findsOneWidget);
    expect(find.text('Ada · You'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);
    // The dice pips also paint with CustomPaint, so the board is
    // identified by its painter, not by type alone.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
      ),
      findsOneWidget,
    );
  });

  testWidgets('roll button sends dice:roll on my turn', (tester) async {
    await pumpGame(tester);
    await loadMatch(tester);
    // The dice row sits below the board, off-screen at the 600 dp test
    // height; scroll it into view before tapping.
    await tester.ensureVisible(find.text('Roll dice'));
    await pumpFrames(tester);
    await tester.tap(find.text('Roll dice'));
    await pumpFrames(tester);
    expect(fakeGame.rollDiceCalls, 1);
    expect(fakeGame.lastRollMatchId, matchId);
  });

  testWidgets('tapping a legal token sends token:move', (tester) async {
    await pumpGame(tester);
    await loadMatch(
      tester,
      snapshot: snapshotFor(
        phase: TurnPhase.awaitingMove,
        lastRoll: 4,
        token0Steps: 1,
      ),
    );
    // The board is 528 dp wide in the 800 dp test viewport
    // (content 560 − padding); tap token 0:0 at its painted centre.
    final boardFinder = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
    );
    final boardTopLeft = tester.getTopLeft(boardFinder);
    const boardSide = 528.0;
    final tokens = <BoardToken>[
      const BoardToken(
        id: '0:0',
        seatIndex: 0,
        stepsTaken: 1,
        colour: PlayerColour.red,
      ),
      const BoardToken(
        id: '0:1',
        seatIndex: 0,
        stepsTaken: 0,
        colour: PlayerColour.red,
      ),
      const BoardToken(
        id: '0:2',
        seatIndex: 0,
        stepsTaken: 0,
        colour: PlayerColour.red,
      ),
      const BoardToken(
        id: '0:3',
        seatIndex: 0,
        stepsTaken: 0,
        colour: PlayerColour.red,
      ),
      for (var i = 0; i < 4; i++)
        BoardToken(
          id: '1:$i',
          seatIndex: 1,
          stepsTaken: 0,
          colour: PlayerColour.green,
        ),
    ];
    final centre = boardTokenCenter(
      tokens.first,
      const Size(boardSide, boardSide),
      tokens,
    );
    await tester.tapAt(boardTopLeft + centre);
    await pumpFrames(tester);
    expect(fakeGame.moveTokenCalls, 1);
    expect(fakeGame.lastMoveTokenId, '0:0');
  });

  testWidgets('disconnected banner shows; retry reconnects', (tester) async {
    await pumpGame(tester);
    await loadMatch(tester);
    fakeGame.emitConnectionState(GameSocketConnectionState.disconnected);
    await pumpFrames(tester);
    expect(
      find.text(
        'You are offline. Moves cannot be sent while you are '
        'disconnected — nothing is queued.',
      ),
      findsOneWidget,
    );
    final connects = fakeGame.connectCalls;
    await tester.tap(find.text('Retry'));
    await pumpFrames(tester);
    expect(fakeGame.connectCalls, connects + 1);
  });

  testWidgets('a rejection shows localised copy, never the raw code', (
    tester,
  ) async {
    await pumpGame(tester);
    await loadMatch(tester);
    fakeGame.emitActionRejected(<String, Object?>{
      'matchId': matchId,
      'code': 'NOT_YOUR_TURN',
      'message': 'It is not your turn.',
    });
    await pumpFrames(tester);
    expect(find.text('It is not your turn.'), findsOneWidget);
    expect(find.text('NOT_YOUR_TURN'), findsNothing);
  });

  testWidgets('presence events toast with the grace countdown', (tester) async {
    await pumpGame(tester);
    await loadMatch(tester);
    final grace = DateTime.now()
        .add(const Duration(seconds: 60))
        .toUtc()
        .toIso8601String();
    fakeGame.emitPlayerDisconnected(<String, Object?>{
      'matchId': matchId,
      'playerId': guestId,
      'graceEndsAt': grace,
      'seq': 2,
    });
    await pumpFrames(tester);
    expect(find.textContaining('Ben disconnected'), findsOneWidget);
    // The player row shows the same countdown as its own status line.
    expect(find.text('59s left to reconnect'), findsOneWidget);
  });

  testWidgets('match:ended navigates to results', (tester) async {
    await pumpGame(tester);
    await loadMatch(tester);
    fakeGame.emitMatchEnded(<String, Object?>{
      'matchId': matchId,
      'winnerId': hostId,
      'standings': const <Map<String, Object?>>[
        {
          'userId': hostId,
          'seat': 0,
          'colour': 'red',
          'rank': 1,
          'result': 'win',
          'tokensHome': 4,
        },
        {
          'userId': guestId,
          'seat': 1,
          'colour': 'green',
          'rank': 2,
          'result': 'loss',
          'tokensHome': 1,
        },
      ],
      'seq': 2,
    });
    await pumpFrames(tester, count: 5);
    expect(find.text('results-screen'), findsOneWidget);
  });

  testWidgets(
    'a future snapshot startedAt still yields a sane results duration',
    (tester) async {
      // Regression test for the Stage 7 gap (server snapshot stamped
      // `startedAt` without a zone, read as the future cross-zone):
      // the screen must fall back to the time since this client first
      // saw the match and never hand results a negative duration.
      MatchResult? captured;
      await pumpGame(
        tester,
        onResultsArguments: (args) => captured = args as MatchResult?,
      );
      final futureSnapshot = snapshotFor().copyWith(
        startedAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await loadMatch(tester, snapshot: futureSnapshot);
      fakeGame.emitMatchEnded(<String, Object?>{
        'matchId': matchId,
        'winnerId': hostId,
        'standings': const <Map<String, Object?>>[
          {
            'userId': hostId,
            'seat': 0,
            'colour': 'red',
            'rank': 1,
            'result': 'win',
            'tokensHome': 4,
          },
          {
            'userId': guestId,
            'seat': 1,
            'colour': 'green',
            'rank': 2,
            'result': 'loss',
            'tokensHome': 1,
          },
        ],
        'seq': 2,
      });
      await pumpFrames(tester, count: 5);
      expect(find.text('results-screen'), findsOneWidget);
      expect(captured, isNotNull);
      expect(captured!.duration.isNegative, isFalse);
      // The fallback measures since first sight of the match (seconds),
      // not since the bogus future stamp.
      expect(captured!.duration.inSeconds, lessThan(120));
    },
  );

  testWidgets('leave asks for confirmation, then forfeits', (tester) async {
    await pumpGame(tester);
    await loadMatch(tester);
    await tester.tap(find.byTooltip('Leave match'));
    await pumpFrames(tester);
    expect(find.text('Leave match?'), findsOneWidget);
    expect(
      find.text(
        'Leaving now forfeits the match for you. '
        'The other players keep playing.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Leave and forfeit'));
    await pumpFrames(tester);
    expect(fakeGame.leaveCalls, 1);
  });
}
