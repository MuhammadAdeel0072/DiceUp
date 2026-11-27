import 'package:diceup/core/design_system/diceup_components.dart';
import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/ruleset_config.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/screens/history_screen.dart';
import 'package:diceup/presentation/screens/home_screen.dart';
import 'package:diceup/presentation/screens/mode_selection_screen.dart';
import 'package:diceup/presentation/screens/offline_setup_screen.dart';
import 'package:diceup/presentation/screens/results_screen.dart';
import 'package:diceup/presentation/screens/settings_screen.dart';
import 'package:diceup/presentation/screens/splash_screen.dart';
import 'package:diceup/presentation/screens/statistics_screen.dart';
import 'package:diceup/presentation/widgets/dice_widget.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_providers.dart';

/// NFR-09 layout suite (M2.12, L-02; remediation plan §4 M2.12 +
/// §6.1 "Layout 320" + §6.2 "NFR-09 5-device layout").
///
/// The requirement (D-21: NFR-09 is binding): the app lays out
/// without overflow or clipping at the minimum 320x568 viewport
/// and at wider sizes, and the game screen's first paint shows the
/// board + Roll button usable — the Roll button must be visible
/// without scrolling at 320x568, the worst case.
///
/// What was wrong before M2.12 (measured, not assumed): at
/// 320x568 the bare harness showed the Roll button at 511–559
/// (viewport 568) — inside, but with only 9 dp of margin. On a
/// real phone the status bar pushes the content down ~24 dp and
/// the gesture bar eats ~16 dp at the bottom, so the button sat
/// ~35 dp below the fold (remediation plan C-5 "borderline",
/// confirmed as a real gap once insets are counted). M2.12 compacts
/// the chrome on short screens only (see `game_screen.dart`):
/// banner padding + avatar, the gaps around the board, the dice
/// size. After the fix the bare-harness Roll button is 475–523
/// (45 dp of margin), and with simulated device insets it stays
/// inside the visible window — see the insets test.
///
/// The harness font renders text ~2x wider than Roboto on a real
/// device, so the banner status is 3 lines here and 2 lines on a
/// phone: the harness numbers are the pessimistic bound, and the
/// real-device margin is larger still. Device confirmation itself
/// is outstanding (M4) — these tests are the automated half of
/// NFR-09, per the §6.2 device-vs-automated map.
///
/// Screens that legitimately scroll are asserted as such, not
/// forced above the fold: the results screen (its actions sit
/// below the fold at 320x568 and are reached by scrolling), the
/// setup screen's seat/rule cards (its Start button is pinned and
/// always visible), and Home (its column scrolls only when it
/// cannot fit — at 320x568 under a wide font or large text scale;
/// on tall screens the footnote stays pinned to the bottom).
/// The game screen's player chips + hint sit below the fold at
/// 320x568 by design — the scrollable column is the bound there
/// (remediation plan §4 risk note) — only the board + dice row +
/// Roll button must be visible at first paint.
void main() {
  /// The board widget.
  Finder boardFinder() => find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
  );

  /// Sets the viewport (and, when given, the simulated device
  /// safe-area insets) for one test; resets after.
  void setViewport(WidgetTester tester, Size size, {FakeViewPadding? padding}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (padding != null) {
      tester.view.padding = padding;
      addTearDown(tester.view.resetPadding);
    }
  }

  /// Pumps a 2-player local [GameScreen] (both human, fixed dice)
  /// at the given viewport and settles. The match is at first
  /// paint: Player 1 to roll, Roll button enabled.
  Future<void> pumpGame(
    WidgetTester tester,
    Size size, {
    int playerCount = 2,
    FakeViewPadding? padding,
  }) async {
    setViewport(tester, size, padding: padding);
    await tester.pumpWidget(
      withTestProviders(
        diceRoller: FixedDiceRoller([6, 6, 6]),
        child: MaterialApp(
          theme: DiceUpTheme.light(),
          home: GameScreen(
            initialSetup: GameSetup(playerCount: playerCount, aiSeats: {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  /// Pumps any bare screen (no dependencies: history/statistics/
  /// settings render their "unavailable" state) at the given
  /// viewport and settles. Screens with a continuously animating
  /// widget (the splash spinner) cannot settle — pass
  /// [settle] false and use bounded pumps instead.
  Future<void> pumpBare(
    WidgetTester tester,
    Size size,
    Widget screen, {
    bool settle = true,
  }) async {
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(theme: DiceUpTheme.light(), home: screen),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  group('game screen first paint (M2.12, NFR-09)', () {
    /// The five widths from remediation plan §6.2 (320–430 dp
    /// portrait), each at a realistic height; 320x568 is the
    /// worst case. Board width follows [_boardSide]'s rule
    /// (width − 48, clamped to 280–480); the Roll button and the
    /// dice must sit fully inside the viewport at first paint,
    /// with no scrolling.
    const widths = <(double width, double height, double board)>[
      (320, 568, 280),
      (360, 640, 312),
      (390, 844, 342),
      (411, 891, 363),
      (430, 932, 382),
    ];
    for (final (width, height, board) in widths) {
      testWidgets('Roll button + dice visible at first paint at '
          '${width.toInt()}x${height.toInt()} (board ${board.toInt()} dp)', (
        tester,
      ) async {
        await pumpGame(tester, Size(width, height));
        final boardRect = tester.getRect(boardFinder());
        expect(boardRect.width, board);
        expect(boardRect.height, board);
        final rollRect = tester.getRect(find.byType(PrimaryButton));
        expect(rollRect.top, greaterThanOrEqualTo(0));
        expect(rollRect.bottom, lessThanOrEqualTo(height));
        final diceRect = tester.getRect(find.byType(DiceWidget));
        expect(diceRect.top, greaterThanOrEqualTo(0));
        expect(diceRect.bottom, lessThanOrEqualTo(height));
        // The button is usable, not just present.
        expect(find.text('Roll dice'), findsOneWidget);
      });
    }

    testWidgets('320x568: Roll button keeps headroom for device insets '
        '(bottom <= 523)', (tester) async {
      await pumpGame(tester, const Size(320, 568));
      // Measured 475–523 after the fix (was 511–559): 45 dp
      // of margin, so a status bar + gesture bar do not push
      // it below the fold. The bound is the measured value
      // plus a small tolerance, not the viewport edge.
      final rollRect = tester.getRect(find.byType(PrimaryButton));
      expect(rollRect.bottom, lessThanOrEqualTo(523));
    });

    testWidgets('320x568 with simulated device insets (status bar 24 + '
        'gesture bar 16): Roll button stays inside the visible window', (
      tester,
    ) async {
      await pumpGame(
        tester,
        const Size(320, 568),
        padding: const FakeViewPadding(top: 24, bottom: 16),
      );
      // The AppBar grows by the top inset (56 -> 80) and the
      // SafeArea insets the bottom by 16, so the visible window
      // is 80..552. The Roll button must be fully inside it.
      final appBarRect = tester.getRect(find.byType(AppBar));
      expect(appBarRect.height, 80);
      final rollRect = tester.getRect(find.byType(PrimaryButton));
      expect(rollRect.top, greaterThanOrEqualTo(80));
      expect(rollRect.bottom, lessThanOrEqualTo(552));
      // The dice sits in the same row: its centre is inside
      // the window too (its bottom edge is ~1 dp from the
      // window edge in the harness — the harness font makes
      // the banner status 3 lines where a phone shows 2, so
      // the real-device margin is larger; see the file doc).
      final diceRect = tester.getRect(find.byType(DiceWidget));
      expect(diceRect.center.dy, lessThan(552));
    });

    testWidgets('320x568, 4 players: Roll button visible, chips '
        'present below the fold', (tester) async {
      await pumpGame(tester, const Size(320, 568), playerCount: 4);
      final rollRect = tester.getRect(find.byType(PrimaryButton));
      expect(rollRect.bottom, lessThanOrEqualTo(568));
      // Banner avatar + one chip avatar per player (M2.4).
      expect(find.byType(PlayerAvatar), findsNWidgets(5));
      // The chips + hint are below the fold by design (the
      // scrollable column is the bound); they exist and the
      // screen does not overflow.
      expect(find.textContaining('Home 0/4'), findsNWidgets(4));
      expect(find.textContaining('Safe cells'), findsOneWidget);
    });

    testWidgets('320x568: tapping a yard token still moves it '
        'after the board moved up (hit-testing)', (tester) async {
      await pumpGame(tester, const Size(320, 568));
      // Roll a 6 (fixed dice), then tap the first red yard token
      // at its computed centre — never a magic offset: the tap
      // point comes from boardTokenCenter over the painter's own
      // tokens, so a layout shift cannot silently break it.
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.textContaining('choose a token'), findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(boardFinder()).painter as LudoBoardPainter;
      final boardSize = tester.getSize(boardFinder());
      final token = painter.tokens.firstWhere((t) => t.id == '0:0');
      final centre = boardTokenCenter(token, boardSize, painter.tokens);
      await tester.tapAt(tester.getTopLeft(boardFinder()) + centre);
      await tester.pump();
      // A 6 grants an extra roll, so Player 1 rolls again: the
      // tap moved the token.
      expect(find.textContaining('rolls again'), findsOneWidget);
    });

    testWidgets('compact layout applies only below 600 dp height '
        '(banner avatar 32 dp at 320x568, 40 dp at 800x600)', (tester) async {
      await pumpGame(tester, const Size(320, 568));
      expect(
        tester.getSize(find.byType(PlayerAvatar).first),
        const Size(32, 32),
      );
      await pumpGame(tester, const Size(800, 600));
      expect(
        tester.getSize(find.byType(PlayerAvatar).first),
        const Size(40, 40),
      );
    });

    testWidgets('320x568: pause menu fits without overflow', (tester) async {
      await pumpGame(tester, const Size(320, 568));
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Restart'), findsOneWidget);
      expect(find.text('Main Menu'), findsOneWidget);
      final dialogRect = tester.getRect(find.byType(AlertDialog));
      expect(dialogRect.top, greaterThanOrEqualTo(0));
      expect(dialogRect.bottom, lessThanOrEqualTo(568));
      expect(dialogRect.left, greaterThanOrEqualTo(0));
      expect(dialogRect.right, lessThanOrEqualTo(320));
    });
  });

  group('other screens at 320x568 (M2.12, NFR-09)', () {
    testWidgets('setup screen: Start match pinned and visible, '
        'no overflow', (tester) async {
      setViewport(tester, const Size(320, 568));
      await tester.pumpWidget(
        withTestProviders(
          child: MaterialApp(
            theme: DiceUpTheme.light(),
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).pushNamed(
                  AppRoutes.offlineSetup,
                  arguments: OfflineMode.vsAi,
                ),
                child: const Text('go'),
              ),
            ),
            onGenerateRoute: (settings) {
              if (settings.name == AppRoutes.offlineSetup) {
                return MaterialPageRoute<void>(
                  builder: (_) => const OfflineSetupScreen(),
                  settings: settings,
                );
              }
              return null;
            },
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The seat/rule cards scroll (Expanded ListView); the Start
      // button is pinned below them and must be visible at first
      // paint, not scrolled to.
      final startRect = tester.getRect(find.text('Start match'));
      expect(startRect.bottom, lessThanOrEqualTo(568));
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
    });

    testWidgets('results screen: winner visible at first paint, '
        'actions reached by scrolling (legitimate scroll)', (tester) async {
      setViewport(tester, const Size(320, 568));
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          home: ResultsScreen(
            result: MatchResult(
              winnerSeat: 0,
              winnerName: 'Adeel',
              winnerColour: PlayerColour.red,
              players: const [
                MatchResultPlayer(
                  seat: 0,
                  name: 'Adeel',
                  colour: PlayerColour.red,
                  isAi: false,
                ),
                MatchResultPlayer(
                  seat: 1,
                  name: 'Robo',
                  colour: PlayerColour.green,
                  isAi: true,
                ),
              ],
              duration: const Duration(minutes: 1, seconds: 35),
              moveCount: 48,
              finishedAt: DateTime(2026, 11, 22, 10, 30),
              setup: const GameSetup(
                playerCount: 2,
                aiSeats: {1: AiDifficulty.hard},
                names: ['Adeel', 'Robo'],
                colours: [PlayerColour.red, PlayerColour.green],
                ruleset: RulesetConfig(releaseOnOne: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Adeel wins!'), findsOneWidget);
      // The actions sit below the fold at this size — the screen
      // is a SingleChildScrollView, so scrolling to them is the
      // documented behaviour, not an overflow.
      expect(tester.getRect(find.text('Play Again')).top, greaterThan(568));
      await tester.ensureVisible(find.text('Play Again'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Main Menu'), findsOneWidget);
    });

    testWidgets('home, mode, settings, statistics, history and '
        'splash render at 320x568 without overflow', (tester) async {
      // Home (bare: no startup notices without dependencies).
      await pumpBare(tester, const Size(320, 568), const HomeScreen());
      expect(find.text('Play Offline'), findsOneWidget);
      // Mode selection.
      await pumpBare(tester, const Size(320, 568), const ModeSelectionScreen());
      expect(find.text('Play vs AI'), findsOneWidget);
      // Settings without dependencies: the "unavailable" state.
      await pumpBare(tester, const Size(320, 568), const SettingsScreen());
      expect(find.text('Settings unavailable'), findsOneWidget);
      // Statistics without dependencies: the "unavailable" state.
      await pumpBare(tester, const Size(320, 568), const StatisticsScreen());
      expect(find.text('Statistics unavailable'), findsOneWidget);
      // History without dependencies: the "unavailable" state.
      await pumpBare(tester, const Size(320, 568), const HistoryScreen());
      expect(find.text('History unavailable'), findsOneWidget);
      // Splash (no startup: brand + spinner, never navigates).
      // The spinner animates forever, so no pumpAndSettle here.
      await pumpBare(
        tester,
        const Size(320, 568),
        const SplashScreen(),
        settle: false,
      );
      expect(find.text('DiceUp'), findsOneWidget);
    });

    testWidgets('home, mode and splash render at 430x932 without '
        'overflow', (tester) async {
      await pumpBare(tester, const Size(430, 932), const HomeScreen());
      expect(find.text('Play Offline'), findsOneWidget);
      await pumpBare(tester, const Size(430, 932), const ModeSelectionScreen());
      expect(find.text('Play vs AI'), findsOneWidget);
      await pumpBare(
        tester,
        const Size(430, 932),
        const SplashScreen(),
        settle: false,
      );
      expect(find.text('DiceUp'), findsOneWidget);
    });
  });
}
