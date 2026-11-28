import 'package:diceup/data/online/auth_models.dart';
import 'package:diceup/data/online/game_models.dart';
import 'package:diceup/domain/online/connection_state.dart';
import 'package:diceup/l10n/app_localizations.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/online/matchmaking_screen.dart';
import 'package:diceup/presentation/screens/online/online_lobby_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_providers.dart';
import 'fakes.dart';

void main() {
  const hostId = '00000000-0000-0000-0000-000000000001';
  const guestId = '00000000-0000-0000-0000-000000000002';

  late FakeAuthService fakeAuth;
  late FakeGameRoomService fakeGame;

  Widget testApp({required Widget home, Map<String, WidgetBuilder>? routes}) {
    return ProviderScope(
      overrides: [
        startupResultProvider.overrideWithValue(testStartup(null)),
        authServiceProvider.overrideWithValue(fakeAuth),
        gameRoomServiceProvider.overrideWithValue(fakeGame),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
        routes: {
          AppRoutes.onlineGame: (_) => const Text('online-game'),
          ...?routes,
        },
      ),
    );
  }

  Future<void> pumpLobby(WidgetTester tester) async {
    await tester.pumpWidget(testApp(home: const OnlineLobbyScreen()));
    await tester.pumpAndSettle();
  }

  setUp(() {
    fakeAuth = FakeAuthService()
      ..restoreResult = FakeAuthService.cannedSession(verified: true);
    fakeGame = FakeGameRoomService();
  });

  RoomView twoPlayerRoom({bool hostReady = false, bool guestReady = false}) {
    return FakeGameRoomService.cannedRoom(
      members: [
        RoomMember(
          userId: hostId,
          username: 'ada',
          displayName: 'Ada',
          isReady: hostReady,
          isHost: true,
          joinedAt: '2026-11-28T00:00:00.000Z',
        ),
        RoomMember(
          userId: guestId,
          username: 'ben',
          displayName: 'Ben',
          isReady: guestReady,
          isHost: false,
          joinedAt: '2026-11-28T00:00:01.000Z',
        ),
      ],
    );
  }

  group('OnlineLobbyScreen entry', () {
    testWidgets('renders create + join + matchmaking entry', (tester) async {
      await pumpLobby(tester);
      expect(find.text('Create a room'), findsOneWidget);
      expect(find.text('Join a room'), findsOneWidget);
      expect(find.text('Find a match'), findsOneWidget);
      expect(
        find.text('Ruleset 1.0.0 — standard DiceUp rules, 4 players max.'),
        findsOneWidget,
      );
      expect(find.text('Create room'), findsOneWidget);
      expect(find.text('Join room'), findsOneWidget);
    });

    testWidgets('create room opens the lobby with the code', (tester) async {
      await pumpLobby(tester);
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      expect(fakeGame.createCalls, 1);
      expect(fakeGame.lastMaxPlayers, 4);
      expect(find.text('K7Q2XA'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Host · You'), findsOneWidget);
      expect(find.text('Copy code'), findsOneWidget);
      expect(find.text('Share code'), findsOneWidget);
      expect(find.text('Leave room'), findsOneWidget);
    });

    testWidgets('a 2-player create passes the chosen limit', (tester) async {
      await pumpLobby(tester);
      await tester.tap(find.text('2'));
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      expect(fakeGame.lastMaxPlayers, 2);
    });

    testWidgets('join with a malformed code shows a local error', (
      tester,
    ) async {
      await pumpLobby(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Room code'),
        'BAD',
      );
      await tester.tap(find.text('Join room'));
      await tester.pumpAndSettle();
      expect(fakeGame.joinCalls, 0);
      expect(find.text('No open room has that code.'), findsWidgets);
    });

    testWidgets('join with an unknown code shows the server error', (
      tester,
    ) async {
      fakeGame.joinError = const ApiException(
        code: 'ROOM_NOT_FOUND',
        message: 'No open room has that code.',
      );
      await pumpLobby(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Room code'),
        'ZZZZZZ',
      );
      await tester.tap(find.text('Join room'));
      await tester.pumpAndSettle();
      expect(fakeGame.joinCalls, 1);
      expect(find.text('No open room has that code.'), findsOneWidget);
      expect(find.text('Create a room'), findsOneWidget);
    });

    testWidgets('join with a full-room error shows ROOM_FULL copy', (
      tester,
    ) async {
      fakeGame.joinError = const ApiException(
        code: 'ROOM_FULL',
        message: 'That room is full.',
      );
      await pumpLobby(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Room code'),
        'K7Q2XA',
      );
      await tester.tap(find.text('Join room'));
      await tester.pumpAndSettle();
      expect(find.text('That room is full.'), findsOneWidget);
    });
  });

  group('OnlineLobbyScreen lobby', () {
    testWidgets('start is blocked until 2 players are present', (tester) async {
      await pumpLobby(tester);
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      expect(
        find.text('At least 2 players are needed to start.'),
        findsOneWidget,
      );
      final start = find.widgetWithText(ElevatedButton, 'Start match');
      expect(tester.widget<ElevatedButton>(start).onPressed, isNull);
    });

    testWidgets('ready toggle enables start when everyone is ready', (
      tester,
    ) async {
      await pumpLobby(tester);
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      fakeGame.emitRoom(twoPlayerRoom(hostReady: false, guestReady: true));
      await tester.pumpAndSettle();
      expect(
        find.text('Every player must be ready before the match starts.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(fakeGame.setReadyCalls, 1);
      expect(fakeGame.lastReady, isTrue);
      final start = find.widgetWithText(ElevatedButton, 'Start match');
      expect(tester.widget<ElevatedButton>(start).onPressed, isNotNull);
      // The room view is taller than the 600 dp test viewport.
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(fakeGame.startCalls, 1);
      // Stage 7: match:started navigates to the online game screen
      // (the started banner is gone).
      expect(find.text('online-game'), findsOneWidget);
    });

    testWidgets('connection banner shows in a room; retry reconnects', (
      tester,
    ) async {
      await pumpLobby(tester);
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'You are offline. Moves cannot be sent while you are '
          'disconnected — nothing is queued.',
        ),
        findsOneWidget,
      );
      final connectBefore = fakeGame.connectCalls;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(fakeGame.connectCalls, connectBefore + 1);
    });

    testWidgets('connection banner hides once connected', (tester) async {
      await pumpLobby(tester);
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      fakeGame.emitConnectionState(GameSocketConnectionState.connected);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(
        find.text(
          'You are offline. Moves cannot be sent while you are '
          'disconnected — nothing is queued.',
        ),
        findsNothing,
      );
    });

    testWidgets('leave returns to the entry view', (tester) async {
      await pumpLobby(tester);
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      // The room view is taller than the 600 dp test viewport.
      final leave = find.text('Leave room');
      await tester.ensureVisible(leave);
      await tester.pumpAndSettle();
      await tester.tap(leave);
      await tester.pumpAndSettle();
      expect(fakeGame.leaveCalls, 1);
      expect(find.text('Create a room'), findsOneWidget);
    });

    testWidgets('a room:updated broadcast refreshes the member list', (
      tester,
    ) async {
      await pumpLobby(tester);
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      expect(find.text('Ben'), findsNothing);
      fakeGame.emitRoom(twoPlayerRoom(hostReady: true, guestReady: false));
      await tester.pumpAndSettle();
      expect(find.text('Ben'), findsOneWidget);
    });
  });

  group('MatchmakingScreen', () {
    Future<void> pumpMatchmaking(WidgetTester tester) async {
      await tester.pumpWidget(
        testApp(
          home: const MatchmakingScreen(),
          routes: {AppRoutes.onlineLobby: (_) => const OnlineLobbyScreen()},
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the find-a-match entry', (tester) async {
      await pumpMatchmaking(tester);
      expect(find.text('Matchmaking'), findsWidgets);
      expect(find.text('Find a match'), findsOneWidget);
    });

    testWidgets('join shows the queue position; cancel leaves', (tester) async {
      await pumpMatchmaking(tester);
      await tester.tap(find.text('Find a match'));
      await tester.pumpAndSettle();
      expect(fakeGame.connectCalls, 1);
      expect(fakeGame.queueJoinCalls, 1);
      expect(find.text('You are #1 in the queue.'), findsOneWidget);
      expect(find.text('Leave queue'), findsOneWidget);
      await tester.tap(find.text('Leave queue'));
      await tester.pumpAndSettle();
      expect(fakeGame.queueLeaveCalls, 1);
      expect(find.text('Find a match'), findsOneWidget);
    });

    testWidgets('match found shows the code and opens the lobby', (
      tester,
    ) async {
      fakeGame.scriptedStatus = const MatchmakingStatus(
        status: 'matched',
        position: 0,
        queueSize: 0,
        groupSize: 4,
        roomId: '00000000-0000-0000-0000-000000000099',
        roomCode: 'K7Q2XA',
      );
      await pumpMatchmaking(tester);
      expect(find.text('Match found! Room code: K7Q2XA'), findsOneWidget);
      await tester.tap(find.text('Go to lobby'));
      await tester.pumpAndSettle();
      expect(find.text('K7Q2XA'), findsWidgets);
      expect(find.text('Ada'), findsOneWidget);
    });

    testWidgets('queue unavailable shows the server error', (tester) async {
      fakeGame.queueError = const ApiException(
        code: 'MATCHMAKING_UNAVAILABLE',
        message: 'Matchmaking is temporarily unavailable.',
      );
      await pumpMatchmaking(tester);
      await tester.tap(find.text('Find a match'));
      await tester.pumpAndSettle();
      expect(
        find.text('Matchmaking is temporarily unavailable.'),
        findsOneWidget,
      );
    });
  });
}
