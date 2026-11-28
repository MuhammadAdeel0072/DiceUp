import 'package:diceup/data/online/game_models.dart';
import 'package:diceup/domain/online/connection_state.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/token.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
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
  late ProviderContainer container;

  /// Flush microtasks + stream deliveries.
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  GameState snapshotFor({
    int currentPlayer = 0,
    TurnPhase phase = TurnPhase.awaitingRoll,
    int lastRoll = 0,
    int token0Steps = 0,
    int moveCount = 0,
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
      moveCount: moveCount,
    );
  }

  Map<String, Object?> statePayload(
    GameState snapshot, {
    int seq = 1,
    String? turnPlayerId,
    String? turnEndsAt,
    List<Map<String, Object?>>? players,
  }) => <String, Object?>{
    'matchId': matchId,
    'seq': seq,
    'snapshot': snapshot.toJson(),
    'seats': const <Map<String, Object?>>[
      {'userId': hostId, 'seat': 0, 'colour': 'red'},
      {'userId': guestId, 'seat': 1, 'colour': 'green'},
    ],
    'turn': <String, Object?>{
      'playerId': turnPlayerId,
      'turnEndsAt': turnEndsAt,
    },
    'players':
        players ??
        const <Map<String, Object?>>[
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
    container = ProviderContainer(
      overrides: [
        startupResultProvider.overrideWithValue(testStartup(null)),
        authServiceProvider.overrideWithValue(fakeAuth),
        gameRoomServiceProvider.overrideWithValue(fakeGame),
      ],
    );
    // A listener keeps the autoDispose provider alive for the test.
    container.listen(onlineGameControllerProvider(matchId), (_, _) {});
  });

  tearDown(() {
    container.dispose();
  });

  OnlineGameState state() =>
      container.read(onlineGameControllerProvider(matchId));

  OnlineGameController notifier() =>
      container.read(onlineGameControllerProvider(matchId).notifier);

  Future<void> startAndLoad({
    GameState? snapshot,
    int seq = 1,
    String? turnPlayerId,
    String? turnEndsAt,
  }) async {
    await notifier().start();
    await settle();
    fakeGame.emitConnectionState(GameSocketConnectionState.connected);
    fakeGame.emitMatchState(
      statePayload(
        snapshot ?? snapshotFor(),
        seq: seq,
        turnPlayerId: turnPlayerId ?? hostId,
        turnEndsAt: turnEndsAt,
      ),
    );
    await settle();
  }

  test('start connects, remembers the match, requests state', () async {
    await notifier().start();
    await settle();
    expect(fakeGame.connectCalls, 1);
    expect(fakeGame.setActiveMatchCalls, 1);
    expect(fakeGame.lastActiveMatchId, matchId);
    expect(fakeGame.requestStateCalls, 1);
    expect(fakeGame.lastStateMatchId, matchId);
    expect(fakeGame.lastStateSeq, 0);
    expect(state().isLoading, isTrue);
  });

  test('start is idempotent', () async {
    await notifier().start();
    await notifier().start();
    await settle();
    expect(fakeGame.connectCalls, 1);
    expect(fakeGame.requestStateCalls, 1);
  });

  test('match:state loads the snapshot; my turn can roll', () async {
    await startAndLoad();
    final s = state();
    expect(s.isLoading, isFalse);
    expect(s.snapshot, isNotNull);
    expect(s.localSeat, 0);
    expect(s.isMyTurn, isTrue);
    expect(s.canRoll, isTrue);
    expect(s.canMove, isFalse);
    expect(s.displayNameOf(hostId), 'Ada');
    expect(s.displayNameOf(guestId), 'Ben');
    expect(s.connectionState, GameSocketConnectionState.connected);
  });

  test('dice:rolled shows the value and refreshes state', () async {
    await startAndLoad();
    fakeGame.emitDiceRolled(<String, Object?>{
      'matchId': matchId,
      'playerId': hostId,
      'value': 4,
      'seq': 2,
    });
    await settle();
    expect(state().lastDiceValue, 4);
    expect(state().lastDicePlayerId, hostId);
    expect(fakeGame.requestStateCalls, 2);
    expect(fakeGame.lastStateSeq, 2);
    fakeGame.emitMatchState(
      statePayload(
        snapshotFor(phase: TurnPhase.awaitingMove, lastRoll: 4, token0Steps: 1),
        seq: 2,
        turnPlayerId: hostId,
      ),
    );
    await settle();
    expect(state().canMove, isTrue);
    expect(state().legalTokenIds, {'0:0'});
  });

  test('rollDice sends the intent only on my turn', () async {
    await startAndLoad();
    notifier().rollDice();
    expect(fakeGame.rollDiceCalls, 1);
    expect(fakeGame.lastRollMatchId, matchId);
    expect(state().isBusy, isTrue);
    // The answering dice:rolled clears the busy flag.
    fakeGame.emitDiceRolled(<String, Object?>{
      'matchId': matchId,
      'playerId': hostId,
      'value': 3,
      'seq': 2,
    });
    await settle();
    expect(state().isBusy, isFalse);
    // The guest's turn: no roll is sent.
    fakeGame.emitMatchState(
      statePayload(
        snapshotFor(currentPlayer: 1),
        seq: 3,
        turnPlayerId: guestId,
      ),
    );
    await settle();
    expect(state().isMyTurn, isFalse);
    notifier().rollDice();
    expect(fakeGame.rollDiceCalls, 1);
  });

  test('moveToken sends only legal tokens', () async {
    await startAndLoad(
      snapshot: snapshotFor(
        phase: TurnPhase.awaitingMove,
        lastRoll: 4,
        token0Steps: 1,
      ),
    );
    notifier().moveToken('0:0');
    expect(fakeGame.moveTokenCalls, 1);
    expect(fakeGame.lastMoveTokenId, '0:0');
    // Token 0:1 sits in the yard; a 4 cannot release it.
    notifier().moveToken('0:1');
    expect(fakeGame.moveTokenCalls, 1);
  });

  test('action:rejected surfaces the code and clears busy', () async {
    await startAndLoad();
    notifier().rollDice();
    expect(state().isBusy, isTrue);
    fakeGame.emitActionRejected(<String, Object?>{
      'matchId': matchId,
      'code': 'NOT_YOUR_TURN',
      'message': 'It is not your turn.',
    });
    await settle();
    expect(state().errorCode, 'NOT_YOUR_TURN');
    expect(state().isBusy, isFalse);
  });

  test('turn:changed updates the turn and deadline', () async {
    await startAndLoad();
    const deadline = '2026-11-28T12:00:30.000Z';
    fakeGame.emitTurnChanged(<String, Object?>{
      'matchId': matchId,
      'playerId': guestId,
      'turnEndsAt': deadline,
      'seq': 2,
    });
    await settle();
    expect(state().turnPlayerId, guestId);
    expect(state().turnEndsAt, DateTime.parse(deadline));
    expect(fakeGame.lastStateSeq, 2);
  });

  test('presence events update players and raise notices', () async {
    await startAndLoad();
    const grace = '2026-11-28T12:01:00.000Z';
    fakeGame.emitPlayerDisconnected(<String, Object?>{
      'matchId': matchId,
      'playerId': guestId,
      'graceEndsAt': grace,
      'seq': 2,
    });
    await settle();
    var s = state();
    expect(s.players[1].disconnected, isTrue);
    expect(s.players[1].graceEndsAt, grace);
    expect(s.notice?.kind, 'disconnected');
    expect(s.notice?.playerId, guestId);
    expect(s.notice?.graceEndsAt, DateTime.parse(grace));
    fakeGame.emitPlayerReconnected(<String, Object?>{
      'matchId': matchId,
      'playerId': guestId,
      'seq': 3,
    });
    await settle();
    s = state();
    expect(s.players[1].disconnected, isFalse);
    expect(s.players[1].graceEndsAt, isNull);
    expect(s.notice?.kind, 'reconnected');
    fakeGame.emitPlayerForfeited(<String, Object?>{
      'matchId': matchId,
      'playerId': guestId,
      'seq': 4,
    });
    await settle();
    s = state();
    expect(s.players[1].result, 'forfeit');
    expect(s.notice?.kind, 'forfeited');
  });

  test('match:ended sets the result', () async {
    await startAndLoad();
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
    await settle();
    final ended = state().ended;
    expect(ended, isNotNull);
    expect(ended!.winnerId, hostId);
    expect(ended.standings.length, 2);
    expect(ended.standings.first.rank, 1);
    expect(state().isMyTurn, isFalse);
    expect(state().canRoll, isFalse);
  });

  test('an out-of-order snapshot never rewinds the board', () async {
    await startAndLoad(snapshot: snapshotFor(moveCount: 5), seq: 5);
    expect(state().seq, 5);
    expect(state().snapshot?.moveCount, 5);
    fakeGame.emitMatchState(statePayload(snapshotFor(moveCount: 1), seq: 3));
    await settle();
    expect(state().seq, 5);
    expect(state().snapshot?.moveCount, 5);
  });

  test('an unparsable snapshot reports a load error', () async {
    await notifier().start();
    await settle();
    fakeGame.emitMatchState(<String, Object?>{
      'matchId': matchId,
      'seq': 1,
      'snapshot': const <String, Object?>{},
      'seats': const <Map<String, Object?>>[],
    });
    await settle();
    expect(state().snapshotError, isTrue);
    expect(state().isLoading, isFalse);
    expect(state().snapshot, isNull);
  });

  test('a disconnect clears a busy intent; retry reconnects', () async {
    await startAndLoad();
    notifier().rollDice();
    expect(state().isBusy, isTrue);
    fakeGame.emitConnectionState(GameSocketConnectionState.disconnected);
    await settle();
    expect(state().isBusy, isFalse);
    expect(state().connectionState, GameSocketConnectionState.disconnected);
    final connects = fakeGame.connectCalls;
    final requests = fakeGame.requestStateCalls;
    await notifier().retryConnection();
    await settle();
    expect(fakeGame.connectCalls, connects + 1);
    expect(fakeGame.requestStateCalls, requests + 1);
  });
}
