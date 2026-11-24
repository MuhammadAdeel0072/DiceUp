# DiceUp Premium UI/UX Redesign v2

Scope: **presentation only**. Engine, AI, controllers, use cases,
repositories, SQLite, settings semantics, route names and every
behavioural contract are untouched. Based on
`implementation/foundation-phase-2-3` @ `102884a`.

## 1. UI/UX audit (before this redesign)

The branch already carried a documented redesign pass (navy table
field, ivory surfaces, gold accent, M3 premium animations: per-cell
token steps, capture-return arc, dice tumble with wind-up/settle,
one-shot legal-move pulse, staggered results entrance + confetti).

Remaining weak spots this redesign targets:

1. **Flat visuals** — board cells, yards, tokens and the dice were
   flat fills; the app read as a clean wireframe, not a physical
   game. No gradient, gloss or pedestal depth anywhere.
2. **No brand mark** — the app name is plain text on the splash and
   home hero; no logo moment.
3. **Flat environment** — out-of-game screens sat on a single ivory
   fill; the navy field was one flat colour. No layered light.
4. **Generic mode selection** — settings-like rows; the two playable
   modes did not read as game tiles.
5. **Press feedback** — ink ripples only; big cards and CTAs did not
   acknowledge the touch physically.
6. **Stock-feeling controls** — switches, sliders, tooltips,
   progress bars used Material defaults, not the palette.
7. **Default platform page transitions** — only the results route had
   a custom entrance.

## 2. What changed (all presentation-layer)

**New design-system files**
- `core/design_system/diceup_motion.dart` — motion tokens (durations,
  curves, pressed-scale). Gameplay budgets are explicitly NOT tokens
  (they are pinned by tests and unchanged).
- `core/design_system/diceup_decor.dart` — `TableBackground` /
  `IvoryBackground` (static layered washes, no tickers), `BrandMark`
  (widget-built five-pip die with gold ring), `PressableScale`
  (raw-`Listener` press scale — never competes in the gesture arena,
  schedules no frames at rest, instant under reduced motion).

**Tokens (additive only)**
- `diceup_colors.dart` — new `ivoryAlt` (alternate ivory for cell
  rhythm/sockets). Every existing constant untouched, so all
  documented contrast figures in tests keep holding.
- `diceup_shadows.dart` — new `button`, `floating`, `boardRim`
  tokens. Existing shadows untouched (`design_system_test` pins
  `raised`/`lifted` lengths).

**Theme (`diceup_theme.dart`)**
- Buttons: elevation + shadow + transparent surface tint. The pinned
  fields (teal/white foreground, disabled greys, 48 dp minimum,
  padding, radius) are byte-identical.
- Cards: `surfaceTintColor: transparent` (stops the M3 teal wash on
  ivory); colour/shape/elevation unchanged.
- Switches, sliders, progress indicators, dividers, tooltips now
  speak the palette.
- New `_FadeThroughTransitionsBuilder`: every named route enters with
  a finite fade-and-rise (the results route's language), collapsing
  to an instant handover under reduced motion (Android
  disableAnimations + iOS Reduce Motion).

**Shared components (`diceup_components.dart`)**
- `PrimaryButton` wraps in `PressableScale` (enabled only when the
  action is available); `DiceUpCard` tappable variant too.
- `StatTile` icon sits in a tinted disc. Styles unchanged.

**Board painter (`widgets/ludo_board.dart`)**
- Lit board: ivory gradient background, alternating ivory track
  cells, yards as shaded colour trays with rounded ivory inner
  panels and per-slot pedestal sockets, centre home framed with a
  navy hairline.
- Tokens as lit domes: radial colour gradient, deep under-rim under
  the white edge, stronger shadow/gloss. Shapes, radius formula,
  legal/current rings, and every geometry table are untouched; no
  new painter fields, so `ludo_board_test.dart`'s `shouldRepaint`
  suite is unaffected. Safe cells keep the documented surface fill
  (amber star contrast 3.19:1 verbatim).

**Dice (`widgets/dice_widget.dart`)**
- Top-lit face gradient, domed pips with seat shadows. The opacity
  contract (1.0 / 0.6 rolling / 0.45 inert), rollable teal border,
  size, semantics, tooltip and gesture flow are unchanged.

**Screens**
- Splash: layered table background + gold rule (spinner kept — the
  boot path depends on it).
- Home: brand header becomes a clipped `TableBackground` panel with
  the `BrandMark`; body gets `IvoryBackground`. All pinned texts and
  styles (32 sp w800 white title, 16 sp tagline) unchanged.
- Mode selection: gradient icon badges with tinted ring, chevron in a
  tinted circle, press scale via `DiceUpCard`. Semantics/chevron
  count unchanged; online card stays visibly inert.
- Offline setup: colour swatches rendered as lit domes with shadows
  (48 dp, keys, selection logic untouched).
- Game screen: `TableBackground` behind the column, board frame gains
  a dark rim (zero-blur spread) under the ivory border, dice tray on
  a gradient with the floating shadow. Board side rule, first-paint
  pins, banner/chips/animation architecture untouched.
- Results: winner stage on the layered table background, winner ring
  gold (the screen's one accent; gold-on-navy 5.39:1 as a non-text
  marker), stat tiles gain icons. Content order/height preserved
  (Play Again stays below the fold at 320x568, as pinned).
- Settings / History / Statistics: `IvoryBackground` behind content;
  controls inherit the themed palette. All texts, keys, states
  unchanged.

## 3. Verification (constraints checked by inspection)

No Flutter/Dart SDK is available in the editing environment, so the
suite could not be executed here. Verification performed instead:

- All ~9,500 lines of tests were read for contracts touching the
  modified files: pinned board sizes (`_boardSide` rule untouched),
  dice opacity states, typography sizes/weights, radius tokens,
  shadow token lengths, palette contrast relations, semantics keys
  (`player-avatar-*`, `winner-shape-marker`, `seat-N-*`),
  `pumpAndSettle` safety (no continuously repeating animation was
  added anywhere), touch-target minimums, results content height at
  320x568.
- Delimiter-balance check on every modified file.
- Usage scan confirming every new import is referenced.
- Diff review confirming zero changes under `lib/domain/`,
  `lib/data/`, `lib/l10n/`, `pubspec.yaml`, and platform folders.
- Byte-exact blob-SHA verification of every pushed file against the
  working tree (all 15 match).

Remaining risk (documented, not silent): a full `flutter analyze` +
`flutter test` run on a machine with the SDK is the final gate; the
changes were written to compile against the same Flutter version the
branch already targets (`withValues(alpha:)` era APIs only, no
dot-shorthands, no new packages).

## 4. Explicitly not done

- No new user-facing strings (l10n untouched).
- No new dependencies, no assets.
- No dark theme (documented decision M2.14 stands).
- No changes to navigation contracts, settings behaviour, save/
  restore, AI, rules, or capture logic.
