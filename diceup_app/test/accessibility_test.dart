import 'dart:ui';

import 'package:diceup/core/design_system/diceup_colors.dart';
import 'package:diceup/core/design_system/diceup_components.dart';
import 'package:diceup/core/design_system/diceup_spacing.dart';
import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/core/design_system/diceup_typography.dart';
import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/offline_game_controller.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/presentation/app_dependencies_scope.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/screens/home_screen.dart';
import 'package:diceup/presentation/screens/mode_selection_screen.dart';
import 'package:diceup/presentation/screens/offline_setup_screen.dart';
import 'package:diceup/presentation/screens/settings_screen.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repositories/fakes/fakes.dart';
import 'test_providers.dart';

/// NFR-08 theme-token conformance (M2.3, H-10, D-09, D-21).
///
/// NFR-08 (confirmed binding by D-21) requires touch targets of at
/// least 48x48 dp and body text of at least 14 sp. The remediation
/// plan's M2.3 item is the theme-token half of H-10: the
/// `segmentedButtonTheme` / `textButtonTheme` 48 dp minimums,
/// `bodySmall` 12 -> 14 sp, and the false "all targets are 48 dp" /
/// "body text is never below 14 sp" doc claims made true.
///
/// Board tokens are EXEMPT from the 48 dp rule by D-09 (geometric:
/// a 48 dp token would need a 720 dp board vs NFR-09's 430 dp max;
/// measured tap target ~22.4 dp on the minimum 280 dp board).
/// The decided mitigation is the full-cell hit area: any tap inside
/// a legal token's cell selects it. The last test pins that.
///
/// NOT covered here: device screen-reader traversal (M4) and
/// per-token board semantics nodes (remediation plan M2.9: out of
/// scope this pass — the tokens are canvas-painted, and no overlay
/// nodes are faked). Avatar contrast + shape markers are M2.4
/// (D-27) — see the group below. Semantics labels are M2.9 — see
/// the last group.
void main() {
  group('typography tokens (NFR-08: body text >= 14 sp)', () {
    test('bodySmall is 14 sp', () {
      final textTheme = DiceUpTheme.light().textTheme;
      expect(textTheme.bodySmall!.fontSize, 14);
    });

    test('no text style in the theme is below 14 sp', () {
      final textTheme = DiceUpTheme.light().textTheme;
      final styles = <String, TextStyle?>{
        'displayLarge': textTheme.displayLarge,
        'headlineMedium': textTheme.headlineMedium,
        'titleLarge': textTheme.titleLarge,
        'titleMedium': textTheme.titleMedium,
        'bodyLarge': textTheme.bodyLarge,
        'bodyMedium': textTheme.bodyMedium,
        'bodySmall': textTheme.bodySmall,
        'labelLarge': textTheme.labelLarge,
      };
      for (final entry in styles.entries) {
        final size = entry.value?.fontSize;
        expect(size, isNotNull, reason: '${entry.key} has no fontSize');
        expect(
          size!,
          greaterThanOrEqualTo(14),
          reason: '${entry.key} is $size sp, below the 14 sp minimum',
        );
      }
      // The typography token itself agrees (not just the theme copy).
      expect(
        DiceUpTypography.textTheme(DiceUpTheme.light().colorScheme)
            .bodySmall!
            .fontSize,
        14,
      );
    });

    test('minTouchTarget token is 48 dp', () {
      expect(DiceUpSpacing.minTouchTarget, 48);
    });

    test('theme carries 48 dp minimums for segmented and text buttons', () {
      final theme = DiceUpTheme.light();
      final segmentedMinimum = theme.segmentedButtonTheme.style?.minimumSize
          ?.resolve({});
      expect(segmentedMinimum, isNotNull);
      expect(segmentedMinimum!.height, 48);
      final textMinimum = theme.textButtonTheme.style?.minimumSize?.resolve({});
      expect(textMinimum, isNotNull);
      expect(textMinimum!.height, 48);
    });
  });

  group('controls under the app theme (NFR-08: >= 48 dp)', () {
    /// Every interactive control used by the screens, pumped once
    /// under [DiceUpTheme.light] so the theme minimums — not a
    /// per-widget size — are what is measured.
    Future<void> pumpControls(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(label: 'Primary', onPressed: () {}),
                  SecondaryButton(label: 'Secondary', onPressed: () {}),
                  TextButton(
                    key: const ValueKey('probe-text-button'),
                    onPressed: () {},
                    child: const Text('Text'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: () {},
                  ),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                      ButtonSegment(value: 4, label: Text('4')),
                    ],
                    selected: const {2},
                    onSelectionChanged: (_) {},
                  ),
                  SwitchListTile(
                    title: const Text('Switch'),
                    subtitle: const Text('A switch row'),
                    value: true,
                    onChanged: (_) {},
                  ),
                  Slider(value: 50, min: 0, max: 100, onChanged: (_) {}),
                  DropdownButtonFormField<String>(
                    initialValue: 'Easy',
                    decoration: const InputDecoration(labelText: 'Difficulty'),
                    items: const [
                      DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                    ],
                    onChanged: (_) {},
                  ),
                  const DiceUpTextField(label: 'Name'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('buttons are at least 48 dp tall', (tester) async {
      await pumpControls(tester);
      for (final (label, finder) in [
        ('ElevatedButton', find.byType(ElevatedButton)),
        ('OutlinedButton', find.byType(OutlinedButton)),
        ('probe TextButton', find.byKey(const ValueKey('probe-text-button'))),
      ]) {
        expect(finder, findsOneWidget);
        expect(
          tester.getSize(finder).height,
          greaterThanOrEqualTo(48),
          reason: '$label is below 48 dp tall',
        );
      }
    });

    testWidgets('SegmentedButton is at least 48 dp tall', (tester) async {
      await pumpControls(tester);
      final segments = find.byType(SegmentedButton<int>);
      expect(segments, findsOneWidget);
      expect(tester.getSize(segments).height, greaterThanOrEqualTo(48));
    });

    testWidgets('IconButton is at least 48x48 dp', (tester) async {
      await pumpControls(tester);
      final button = find.byType(IconButton);
      expect(button, findsOneWidget);
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('switch row, slider, dropdown and text field are >= 48 dp '
        'tall', (tester) async {
      await pumpControls(tester);
      for (final (label, finder) in [
        ('SwitchListTile', find.byType(SwitchListTile)),
        ('Slider', find.byType(Slider)),
        (
          'DropdownButtonFormField',
          find.byType(DropdownButtonFormField<String>),
        ),
        ('TextField', find.byType(TextField)),
      ]) {
        expect(finder, findsOneWidget);
        expect(
          tester.getSize(finder).height,
          greaterThanOrEqualTo(48),
          reason: '$label is below 48 dp tall',
        );
      }
    });

    testWidgets('dialog TextButton is at least 48 dp tall', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ConfirmationDialog.show(
                  context,
                  title: 'Leave the match?',
                  message: 'Your progress will be lost.',
                  confirmLabel: 'Leave',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The dialog's Cancel action is the TextButton (the confirm
      // action is an ElevatedButton, already 48 dp by theme).
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      expect(cancel, findsOneWidget);
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(48));
    });
  });

  group('setup screen controls (real screen, app theme)', () {
    /// Pumps the setup screen the way the mode-selection screen
    /// navigates to it (same shape as `test/setup_screen_test.dart`'s
    /// `appWidget`, without the AppDependenciesScope prefill).
    Future<void> pumpSetup(WidgetTester tester) async {
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
    }

    testWidgets('player-count SegmentedButton is at least 48 dp tall', (
      tester,
    ) async {
      await pumpSetup(tester);
      final segments = find.byType(SegmentedButton<int>);
      expect(segments, findsOneWidget);
      expect(tester.getSize(segments).height, greaterThanOrEqualTo(48));
    });

    testWidgets('colour swatches are 48x48 dp', (tester) async {
      await pumpSetup(tester);
      final swatch = find.byKey(const ValueKey('seat-0-colour-red'));
      await tester.ensureVisible(swatch);
      await tester.pumpAndSettle();
      expect(swatch, findsOneWidget);
      final size = tester.getSize(swatch);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('board tokens (D-09 exemption + full-cell hit area)', () {
    testWidgets('a tap in the corner of a legal token\'s cell selects it', (
      tester,
    ) async {
      await tester.pumpWidget(
        withTestProviders(
          diceRoller: FixedDiceRoller([6, 6, 6]),
          child: MaterialApp(
            theme: DiceUpTheme.light(),
            home: const GameScreen(
              initialSetup: GameSetup(playerCount: 2, aiSeats: {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.textContaining('choose a token'), findsOneWidget);

      final board = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
      );
      expect(board, findsOneWidget);
      await tester.ensureVisible(board);
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(board);

      // Yard slot 0 sits at (64, 64) inside the 480 dp board
      // (cell 32 dp). The old hit test was a circle of radius
      // cell x 0.6 = 19.2 dp around the centre; (78, 78) is
      // 19.8 dp away — outside the old circle — but still inside
      // the token's cell (48..80 on both axes), so the full-cell
      // hit area (D-09) must select it.
      await tester.tapAt(origin + const Offset(78, 78));
      await tester.pump();

      // A 6 grants an extra roll, so Player 1 rolls again: the
      // corner tap moved the token.
      expect(find.textContaining('rolls again'), findsOneWidget);
    });
  });

  group('320 dp reflow check (M2.3 risk)', () {
    testWidgets('setup screen renders at 320x568 without overflow', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
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
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
    });

    testWidgets('game screen renders at 320x568 without overflow', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        withTestProviders(
          diceRoller: FixedDiceRoller([6, 6, 6]),
          child: MaterialApp(
            theme: DiceUpTheme.light(),
            home: const GameScreen(
              initialSetup: GameSetup(playerCount: 2, aiSeats: {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Roll dice'), findsOneWidget);
    });
  });

  group('avatars + turn banner (M2.4, D-27)', () {
    /// Four avatars in a row, one per seat, with distinct names.
    Future<void> pumpAvatars(WidgetTester tester) async {
      const names = ['Adeel', 'Bilal', 'Cleo', 'Dana'];
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          home: Scaffold(
            body: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  PlayerAvatar(name: names[i], seatIndex: i),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    test('navy initial on white is 14.11:1 (AA 4.5:1)', () {
      final ratio = DiceUpColors.contrastRatio(DiceUpColors.navy, Colors.white);
      expect(ratio, greaterThanOrEqualTo(4.5));
      expect(ratio, closeTo(14.11, 0.05));
      // The ratio is symmetric in its arguments.
      expect(
        DiceUpColors.contrastRatio(Colors.white, DiceUpColors.navy),
        ratio,
      );
    });

    testWidgets('each seat shows a white disc, navy initial, its own '
        'ring colour and its own shape', (tester) async {
      await pumpAvatars(tester);
      const names = ['Adeel', 'Bilal', 'Cleo', 'Dana'];
      const shapes = ['circle', 'square', 'diamond', 'triangle'];
      for (var i = 0; i < 4; i++) {
        final avatar = find.byType(PlayerAvatar).at(i);
        expect(avatar, findsOneWidget);

        final disc = find.descendant(
          of: avatar,
          matching: find.byKey(const ValueKey('player-avatar-disc')),
        );
        expect(disc, findsOneWidget);
        final decoration =
            tester.widget<Container>(disc).decoration! as BoxDecoration;
        expect(
          decoration.color,
          Colors.white,
          reason: 'seat $i disc must be white (D-27)',
        );
        expect(
          (decoration.border! as Border).top.color,
          DiceUpColors.playerColor(i),
          reason: 'seat $i ring must be the seat colour',
        );

        final initial = find.descendant(
          of: avatar,
          matching: find.text(names[i][0]),
        );
        expect(initial, findsOneWidget);
        expect(
          tester.widget<Text>(initial).style!.color,
          DiceUpColors.navy,
          reason: 'seat $i initial must be navy, never white-on-colour',
        );

        // One shape marker per seat, distinct across seats — the
        // same shapes as the board tokens (circle/square/diamond/
        // triangle), so shape alone identifies the seat.
        expect(
          find.byKey(ValueKey('player-avatar-shape-${shapes[i]}')),
          findsOneWidget,
          reason: 'seat $i must carry the ${shapes[i]} marker',
        );
      }
    });

    testWidgets('ring follows the chosen colour, shape follows the seat', (
      tester,
    ) async {
      // Seat 0 chose blue (a colour swap, M2.2): the ring is blue,
      // but the shape stays the seat-0 circle, matching the seat's
      // board tokens.
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          home: const Scaffold(
            body: PlayerAvatar(
              name: 'Adeel',
              seatIndex: 0,
              colour: PlayerColour.blue,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final disc = find.byKey(const ValueKey('player-avatar-disc'));
      expect(disc, findsOneWidget);
      final decoration =
          tester.widget<Container>(disc).decoration! as BoxDecoration;
      expect(
        (decoration.border! as Border).top.color,
        DiceUpColors.forColour(PlayerColour.blue),
      );
      expect(
        find.byKey(const ValueKey('player-avatar-shape-circle')),
        findsOneWidget,
      );
    });

    testWidgets('initial comes from the real name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          home: const Scaffold(
            body: Row(
              children: [
                PlayerAvatar(name: 'adeel', seatIndex: 0),
                PlayerAvatar(name: '', seatIndex: 1),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
      // No avatar ever shows a white initial on a player colour.
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.style!.color, isNot(Colors.white));
      }
    });

    testWidgets('turn banner shows the current player avatar + name, and '
        'updates on turn change', (tester) async {
      await tester.pumpWidget(
        withTestProviders(
          diceRoller: FixedDiceRoller([3]),
          child: MaterialApp(
            theme: DiceUpTheme.light(),
            home: const GameScreen(
              initialSetup: GameSetup(
                playerCount: 2,
                aiSeats: {},
                names: ['Adeel', 'Bilal'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Banner: Player 1's exact name (the chips carry
      // 'Adeel · Home 0/4', a different Text) + the seat-0 circle
      // marker (banner avatar + chip avatar = two widgets).
      expect(find.text('Adeel'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player-avatar-shape-circle')),
        findsWidgets,
      );

      // A 3 with every token in the yard is no legal move, so the
      // turn passes to Player 2.
      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.textContaining('No legal move'), findsOneWidget);

      expect(find.text('Bilal'), findsOneWidget);
      expect(find.text('Adeel'), findsNothing);
      expect(
        find.byKey(const ValueKey('player-avatar-shape-square')),
        findsWidgets,
      );
    });

    testWidgets('game screen with avatars renders at 320x568 without '
        'overflow', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        withTestProviders(
          diceRoller: FixedDiceRoller([6, 6, 6]),
          child: MaterialApp(
            theme: DiceUpTheme.light(),
            home: const GameScreen(
              initialSetup: GameSetup(playerCount: 4, aiSeats: {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Banner avatar + one chip avatar per player.
      expect(find.byType(PlayerAvatar), findsNWidgets(5));
      expect(find.text('Roll dice'), findsOneWidget);
    });
  });

  // -- Semantics labels (M2.9, NFR-08; remediation plan §4 M2.9) -----
  //
  // Labels for the dice ("Dice, showing X" / "tap to roll"), the
  // Roll button (label verified, disabled state exposed), the turn
  // banner ("Player 1's turn"), and the board ("Ludo board.
  // Player 1's turn, N legal moves", updated per state) — via
  // `tester.getSemantics` / `find.bySemanticsLabel`, the
  // remediation plan's §6 verification for this milestone. Avatar
  // nodes carry name + shape + colour name (D-27: never colour
  // alone); setup swatches and mode cards are labelled buttons.
  // Per-token semantics nodes are out of scope (see the file doc):
  // these tests assert the board-level node instead, and assert
  // nothing about individual tokens.
  group('semantics labels (M2.9, NFR-08)', () {
    /// Pumps a 2-player local [GameScreen] on a tall viewport (the
    /// whole column fits, no scrolling) with a fixed dice roller,
    /// and returns the provider-owned controller. Same shape as
    /// `test/animation_test.dart`'s `pumpGame`.
    Future<OfflineGameController> pumpGame(
      WidgetTester tester, {
      required List<int> dice,
      List<String>? names,
    }) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      late final ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            startupResultProvider.overrideWithValue(testStartup(null)),
            diceRollerProvider.overrideWithValue(
              FixedDiceRoller(dice, cycle: true),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: DiceUpTheme.light(),
                home: GameScreen(
                  initialSetup: GameSetup(
                    playerCount: 2,
                    aiSeats: {},
                    names: names ?? const ['Player 1', 'Player 2'],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container.read(offlineGameControllerProvider);
    }

    /// Taps Roll and lets the ~540 ms tumble settle.
    Future<void> roll(WidgetTester tester) async {
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
    }

    testWidgets('dice label before the first roll is "Dice, tap to roll" '
        'and is a button; Roll button is enabled; pause button labelled', (
      tester,
    ) async {
      await pumpGame(tester, dice: const [6]);
      final handle = tester.ensureSemantics();

      final dice = find.bySemanticsLabel('Dice, tap to roll');
      expect(dice, findsOneWidget);
      expect(
        tester.getSemantics(dice).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      // The Roll button's own label, enabled while a roll is
      // available (M2.8's shared `canRoll` condition).
      final rollButton = find.bySemanticsLabel('Roll dice');
      expect(rollButton, findsOneWidget);
      expect(
        tester
            .getSemantics(rollButton)
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isTrue,
      );
      // The turn banner names the current player (plan's label).
      expect(find.bySemanticsLabel("Player 1's turn"), findsOneWidget);
      // The board node: no legal moves before any roll.
      expect(
        find.bySemanticsLabel("Ludo board. Player 1's turn, 0 legal moves"),
        findsOneWidget,
      );
      // Icon-only navigation: the pause button's tooltip is its
      // accessible name (Tooltip exposes the message as the node's
      // `tooltip`, not its `label` — so `find.byTooltip` is the
      // finder for it, not `find.bySemanticsLabel`).
      final pause = find.byTooltip('Pause');
      expect(pause, findsOneWidget);
      expect(
        tester.getSemantics(pause).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('dice label shows the rolled value and the Roll button '
        'disables after a roll; board label counts the legal moves', (
      tester,
    ) async {
      await pumpGame(tester, dice: const [6]);
      final handle = tester.ensureSemantics();

      await roll(tester);
      expect(find.bySemanticsLabel('Dice, tap to roll'), findsNothing);
      expect(find.bySemanticsLabel('Dice, showing 6'), findsOneWidget);
      // Awaiting a move, not a roll: the Roll button is disabled.
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Roll dice'))
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
      // A 6 releases any of the four yard tokens: 4 legal moves.
      expect(
        find.bySemanticsLabel("Ludo board. Player 1's turn, 4 legal moves"),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel("Player 1's turn"), findsOneWidget);
      handle.dispose();
    });

    testWidgets('semantics tap on the dice rolls exactly as the Roll '
        'button does', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsLabel('Dice, tap to roll'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(controller.displayedRoll, 6);
      expect(find.textContaining('choose a token'), findsOneWidget);
      expect(find.bySemanticsLabel('Dice, showing 6'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('banner and board labels follow the turn to the next '
        'player', (tester) async {
      await pumpGame(tester, dice: const [3], names: const ['Adeel', 'Bilal']);
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsLabel("Adeel's turn"), findsOneWidget);
      expect(
        find.bySemanticsLabel("Ludo board. Adeel's turn, 0 legal moves"),
        findsOneWidget,
      );
      // A 3 with every token in the yard is no legal move, so the
      // turn passes to Player 2.
      await roll(tester);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel("Adeel's turn"), findsNothing);
      expect(find.bySemanticsLabel("Bilal's turn"), findsOneWidget);
      expect(
        find.bySemanticsLabel("Ludo board. Bilal's turn, 0 legal moves"),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('avatar label carries name, shape and colour — never '
        'the bare initial', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PlayerAvatar(name: 'Adeel', seatIndex: 0),
                PlayerAvatar(
                  name: 'Bilal',
                  seatIndex: 1,
                  colour: PlayerColour.blue,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();

      // Shape follows the seat (circle / square); the colour name
      // follows the chosen colour when given (blue, not seat 1's
      // green), never the colour alone.
      expect(find.bySemanticsLabel('Adeel, circle token, red'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Bilal, square token, blue'),
        findsOneWidget,
      );
      // The drawn initial letters are decorative inside those
      // nodes — no bare "A" / "B" node exists.
      expect(find.bySemanticsLabel('A'), findsNothing);
      expect(find.bySemanticsLabel('B'), findsNothing);
      handle.dispose();
    });

    testWidgets('setup colour swatches are labelled buttons with '
        'selected/taken state', (tester) async {
      await tester.pumpWidget(
        withTestProviders(
          child: MaterialApp(
            theme: DiceUpTheme.light(),
            home: const OfflineSetupScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();

      // Seat 0 holds red; green is taken by seat 1 (Player 2).
      final selected = find.bySemanticsLabel('Colour red, selected');
      expect(selected, findsOneWidget);
      final selectedNode = tester.getSemantics(selected);
      expect(selectedNode.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(
        selectedNode.getSemanticsData().flagsCollection.isSelected ==
            Tristate.isTrue,
        isTrue,
      );
      expect(
        find.bySemanticsLabel('Colour green, taken by Player 2'),
        findsOneWidget,
      );
      // Picking blue for seat 0 moves the selected state with it.
      await tester.tap(find.byKey(const ValueKey('seat-0-colour-blue')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Colour blue, selected'), findsOneWidget);
      expect(find.bySemanticsLabel('Colour red, selected'), findsNothing);
      handle.dispose();
    });

    testWidgets('mode cards are labelled buttons; the online card is '
        'not a button', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ModeSelectionScreen()));
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();

      final vsAi = find.bySemanticsLabel(
        'Play vs AI. You against computer opponents (Easy, Medium, Hard).',
      );
      expect(vsAi, findsOneWidget);
      expect(
        tester.getSemantics(vsAi).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      final local = find.bySemanticsLabel(
        'Local multiplayer. 2–4 players sharing this device.',
      );
      expect(local, findsOneWidget);
      expect(
        tester.getSemantics(local).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      // The online card is plain text (Phase 5): readable, but with
      // no button role and no tap action. Its title + subtitle
      // merge into one semantics node (the card merges its texts),
      // so the label is the joined string, not the title alone.
      const onlineLabel =
          'Online multiplayer\n'
          'Rooms, friends and live matches — coming in Phase 5.';
      final online = find.bySemanticsLabel(onlineLabel);
      expect(online, findsOneWidget);
      expect(
        tester.getSemantics(online).getSemanticsData().flagsCollection.isButton,
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('home settings button is labelled', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();

      // The Home settings button is icon-only: its tooltip is its
      // accessible name (see the pause-button note above).
      final settings = find.byTooltip('Settings');
      expect(settings, findsOneWidget);
      expect(
        tester
            .getSemantics(settings)
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('the disabled Sound switch exposes its disabled state', (
      tester,
    ) async {
      // The settings screen needs real dependencies: the Sound
      // toggle is disabled by design (D-32, no audio code), and
      // that must be visible to a screen reader, not just visually
      // greyed. (A separate test from the Home one: the semantics
      // finders search the first pumped tree, so a second
      // `pumpWidget` in the same test leaves them looking at the
      // stale tree.)
      final store = InMemoryStore();
      final deps = AppDependencies(
        matches: InMemoryLocalMatchRepository(store),
        statistics: InMemoryLocalStatisticsRepository(store),
        settings: InMemorySettingsRepository(store),
        players: InMemoryLocalPlayerRepository(store),
        snapshots: InMemorySnapshotRepository(store),
      );
      final startup = StartupResult(
        dependencies: deps,
        settings: Map<String, String>.of(kDefaultSettings),
        snapshotOutcome: const NoSnapshot(),
        databaseRecovered: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [startupResultProvider.overrideWithValue(startup)],
          child: AppDependenciesScope(
            startup: startup,
            child: const MaterialApp(home: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();
      await tester.pumpAndSettle();
      // The switch titles are their own label nodes — title and
      // subtitle merged with a newline, as the framework joins
      // them — and the Switch widgets themselves are separate
      // nodes carrying the toggled state. The enabled flag lives
      // on the switch node, not the title node, so the flag is
      // read off the switches in screen order (Sound first,
      // Vibration second). (The tree-search finders —
      // `find.bySemanticsLabel` / `find.semantics.byPredicate` —
      // need the exact merged label, so the titles are read
      // through `tester.getSemantics` on the text widgets, the
      // same path the remediation plan names.)
      expect(
        tester.getSemantics(find.text('Sound')).label,
        'Sound\nComing soon — sound does not play anything yet.',
      );
      expect(
        tester.getSemantics(find.text('Vibration')).label,
        'Vibration\nHaptic feedback on moves',
      );
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(2));
      expect(
        tester
            .getSemantics(switches.first)
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
      expect(
        tester
            .getSemantics(switches.last)
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isTrue,
      );
      handle.dispose();
    });
  });
}
