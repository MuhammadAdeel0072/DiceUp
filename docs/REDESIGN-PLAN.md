# DiceUp — Premium Redesign Plan (Stage 1: Audit + Plan)

> **Status:** Stage 1 audit only. No Dart code was edited, no commit, no push.
> **Scope:** visual / presentation redesign of the existing offline Ludo app.
> **Baseline audited:** staging tree `~/workspace/scratch/diceup-foundation/`,
> 60 `lib` files / 48 `test` files, remote head `19e07264`.
> **Sources read:** `docs/IMPLEMENTATION-PLAN.md`, `docs/UI-RESEARCH.md`
> (636 lines, R1–R18+, Q1–Q10 + coordinator decisions), `docs/TRACEABILITY.md`,
> `docs/ruleset.md`, all of `lib/core/design_system/*`,
> `lib/presentation/screens/*` (9 screens), `lib/presentation/widgets/*`,
> `lib/main.dart`, `lib/presentation/navigation/app_routes.dart`,
> `lib/domain/offline_game_controller.dart` (status strings),
> `lib/domain/engine/*`, `lib/domain/ai/*`, `pubspec.yaml`.
> External principles checked 2026-11-23: Apple Motion HIG, Asmodee art/UI,
> Unity UI/UX basics, Board Game Arena Studio Guidelines (all fetched and
> read); Behance "Ludo Vibe" (fetched — project summary only, no detail
> retrievable); Dribbble Ludo case study link **failed to fetch**
> (empty response, HTTP 202) — search-result summaries used instead.
> Nothing was copied from any of them: principles only, no branding,
> artwork, assets, or exact interface copied.

## 0. The one rule for every later stage

**Polish presentation around the existing animation contracts — never
change the contracts.** The premium animations are done and verified
(`test/premium_animation_test.dart`, 7 tests; see §6). Game logic,
engine, AI, Riverpod wiring, SQLite persistence, navigation, and the
offline-only scope are all out of scope for the redesign (§8).

---

## 1. Current-state findings (ranked)

### F1 — The app looks like a stock Material demo, not a game
Every screen is the same recipe: `#F6F7F9` grey background, white
`Card` (elevation 2, radius 16), teal button, navy `AppBar`
(`diceup_colors.dart:21-23`, `diceup_theme.dart:19-33,106-113`).
Navy — the only distinctive brand colour — appears only in the
`AppBar` and splash (`splash_screen.dart:69`). There is no game-table
environment, no brand moment beyond the splash, and nothing that says
"Ludo" until the board itself appears. Home (`home_screen.dart:150-218`)
is four stacked full-width buttons and a footnote; mode selection
(`mode_selection_screen.dart:36-85`) is three identical white cards
distinguished only by a 32 dp outline icon. **Fix is systemic, not
per-screen: a real colour/typography/component system first (§4), then
screens.**

### F2 — The board is flat, washed-out, and has no presence
`ludo_board.dart:399-441`: white background, 1 px `#E2E8F0` grid,
yards in full-strength player colour, home paths at 0.55 alpha,
start cells at 0.35 alpha, centre home as four flat triangles
(`ludo_board.dart:603-620`). The alphas make the most meaningful
cells (home paths, starts) the *palest* on the board — hierarchy is
inverted. Safe cells are pale amber (`amberLight #FEF3C7`) with an
amber star (`ludo_board.dart:559-566`); amber on amberLight is
**2.86:1** — decorative, but weak even as a marker. Tokens are flat
filled shapes with a 2 px white edge (`ludo_board.dart:628-700`),
~13 dp across on the minimum 280 dp board (D-09). No board frame,
no table/felt context, no depth: the board floats on grey as a white
square with a single `raised` shadow (`game_screen.dart:1420-1426`).
**This is the highest-value single change: the board is the product.**

### F3 — "Whose turn is it?" is answered three times, weakly
The turn banner is a white `DiceUpCard` identical to every other card
(`game_screen.dart:1565-1656`); the current player's chip differs
only by a 0.12-alpha teal fill + teal border
(`game_screen.dart:1663-1671`); the on-board current-player marker
is a small white dot inside the token
(`ludo_board.dart`, `_drawToken`, current-seat branch). Each signal
is individually subtle and they do not reinforce each other — no
seat glow, no turn rail, no banner colour shift, no dice-row change.
A player glancing mid-game must read the status *text* to be sure.
(BGA C.2: highlight valid options so the awaited action is obvious;
Unity: critical, constantly changing information goes where it is
easy to see.)

### F4 — The dice does not feel rollable
`dice_widget.dart:110-145`: a plain white rounded square, navy pips,
64 dp (56 dp on short screens). The only "your turn" state is a
steady 2 dp teal border + full opacity; otherwise it is dimmed to
0.45 (`dice_widget.dart:118-126`). There is no depth change, no
lift, no prompt — the dice and the Roll button sit side by side as
two equal affordances (`game_screen.dart:1455-1535`) and neither
reads as *the* action. The steady border is a deliberate, documented
choice (a repeating pulse would break `pumpAndSettle` — see §6), so
the redesign must make the dice feel alive **without** a looping
ticker: stronger rest/active states, not animation.

### F5 — Setup is a wall of identical cards; rules are a wall of toggles
`offline_setup_screen.dart:455-651`: every seat card has the same
white-card treatment (avatar row, name field, 4 colour swatches,
Human/AI segmented control, difficulty dropdown) and the ruleset
card is six bare `SwitchListTile`s in one card
(`offline_setup_screen.dart:604-651`) with no grouping, no
explanation of what changes, and no visual difference between
"house rules" and "who is playing". The screen works, but it scans
as a form, not as "set up your table". Seat cards also repeat the
same 48 dp swatch row with no selected-state beyond a check +
2.5 px border (`offline_setup_screen.dart:544-602`).

### F6 — Typography has no voice
`diceup_typography.dart:19-77`: scale 32/24/20/16/14, weights
w800/w700/w600/w400 only, **no font family named anywhere**
(M2.14 — deliberate: binary `.ttf` files cannot be snapshot-pushed,
`google_fonts` rejected as a runtime network dependency, NFR-23).
`bodySmall` == `bodyMedium` == 14 sp, so there is no real small-text
tier; `displayLarge` (32, w800) is used for "Ready to play?"
(`home_screen.dart:175-178`) with no display treatment anywhere
else. Result: headlines, status, labels, and body all feel the same
weight. **Do not fix this by sneaking in a font** — fix it with
scale, weight, tracking, and colour hierarchy (§4), and treat a
bundled display font as a separately-approved follow-up (§7).

### F7 — Radii, shadows, and dialogs are three different design languages
Only two radii exist (12/16, `diceup_spacing.dart:28-34`); the dice
radius is proportional (`size * 0.18`, `dice_widget.dart:119`) rather
than a token; `Card` elevation 2 is the only elevation in the theme
(`diceup_theme.dart:106-113`); only two shadow tokens exist
(`diceup_shadows.dart`, `raised`/`lifted`); and every dialog is a
stock `AlertDialog` (pause menu `game_screen.dart:1203-1221`,
confirmations in `diceup_components.dart:436-482`, resume
`home_screen.dart:112-130`) whose Material default radius does not
match the 16 dp cards. `SnackBar`s are stock throughout
(`game_screen.dart:1159-1162`). Nothing is broken; nothing is
coherent either.

### F8 — Feedback for failure is the weakest feedback in the app
An illegal tap gets a 2-second `SnackBar` + a status-line change
(`game_screen.dart:1148-1162`, controller `noteIllegalTap`); a
no-legal-move pass is status text only
(`offline_game_controller.dart:588`, `_rollStatus`); a disabled Roll
button is the stock disabled teal. Compare with the success path,
which has steps, capture arcs, haptics, and narration. BGA D.1:
"silence is never acceptable — every failed action must say why."
The *words* exist; the *visual weight* does not. Also: the game
screen's whole column scrolls (`game_screen.dart:1388-1390`), so on
taller content the board can scroll away while the dice row stays —
first paint fits at 320×568 (M2.12), but the scroll contract means
the board is not pinned during play.

### F9 — Accessibility: good bones, four concrete gaps (measured)
1. `textSecondary #64748B` on background `#F6F7F9` is **4.44:1** and
   on `surfaceMuted #F1F5F9` is **4.34:1** — both below WCAG AA 4.5:1
   for normal text (on white it is 4.76:1, passing). It is used for
   subtitles, hints, and the safe-cells hint
   (`home_screen.dart:179`, `game_screen.dart:1542-1547`).
2. Amber `#D97706` on white is **3.19:1** — must never be body text;
   today it is only stars/spinner, but there is no token rule
   forbidding it as text.
3. Player yellow `#F5B301` on white is **1.85:1** — any yellow text,
   ring, or thin marker on a light surface is illegible; the D-27
   white-disc avatar correctly keeps text off player colours, but
   the board's yellow home path / start cell at 0.55/0.35 alpha is
   the palest of the four.
4. Per-token semantics nodes do not exist: the board is one labelled
   node (`game_screen.dart:1334-1344`, "Ludo board. \<name\>'s turn,
   N legal moves") — a recorded M2.9 follow-up, not claimed. And
   iOS Reduce Motion is unreadable on the oldest supported SDKs:
   `isReducedMotion` reads only `MediaQuery.disableAnimationsOf`
   (`reduced_motion.dart`) — documented, but it means iOS users'
   Reduce Motion setting is silently ignored (§7).

### F10 — Responsive: 320 dp is handled; tablets and large phones are not
Board clamps 280–480 dp (`game_screen.dart:1556-1561`) and short-screen
compaction exists (M2.12), but there is no max-width constraint, so
on a tablet (portrait, iPad unrestricted per D-17) cards stretch
full-width and the 480 dp board sits in a sea of grey; there is no
two-column or centred-column layout for ≥600 dp widths. The game
screen has no landscape provision at all (iPhone/Android are
portrait-locked, D-17 — fine), but the iPad case is unaddressed.
Setup keyboard behaviour is unverified: the seat list scrolls
(`ListView.builder`, `offline_setup_screen.dart:418-427`), but no
screen scrolls a focused name field into view or dismisses the
keyboard on Start — check, don't assume (§5).

---

## 2. Visual direction

**A quiet, confident game table — not a casino, not a toy.**

The app becomes a deep navy / indigo table environment: the game
screen sits on a dark navy felt-like field so the ivory board and
the four rich player colours read as objects on a table, while the
out-of-game screens (Home, Setup, History, Statistics, Settings)
use warm ivory surfaces with navy text and restrained gold accents,
so the whole app feels like one room rather than two themes. Teal
stays the action colour (Roll, primary buttons, current-turn
signals) and amber/gold is demoted to a sparing accent — stars,
the winner's mark, one highlight per screen at most — never a
second primary. Player colours stay the classic four but are
deepened and harmonised (a richer red, a deeper green, a warm
gold-yellow that is never used as text, a royal blue), always paired
with the existing per-seat shapes (circle/square/diamond/triangle,
D-27) so identity is never colour alone. Surfaces are flat with
one soft shadow, never glassmorphism, never gradients as decoration,
never glow; buttons stay 48 dp and human-sized, never oversized;
icons are Material/Cupertino glyphs, never emoji. The board gets a
frame and a subtle table shadow so it reads as a physical object;
everything else gets out of its way.

*In one sentence (Asmodee's test): "we are sitting down at a proper
Ludo table in a calm room." If a proposed treatment does not serve
that sentence, it does not ship.*

---

## 3. Screen-by-screen plan

### 3.1 Home (low effort, high first-impression value)
- Replace the four stacked equal buttons with a clear hierarchy:
  one primary "Play" action, secondary rows for History/Statistics,
  settings stays in the `AppBar`. Keep the honest online entry
  (M-13 dialog, `home_screen.dart:222-240`) visually distinct —
  muted, no chevron, no primary styling — so it never reads as
  playable.
- Give the screen a brand header: the navy field with the DiceUp
  wordmark treatment (typography only, no new asset) + the tagline,
  instead of plain `displayLarge` on grey. Keep the resume dialog
  exactly as is (behaviour + copy are M1.6/M2.6 decisions).
- Keep the offline footnote; move it into a quiet caption style
  (see §4 small-text tier) rather than default body text.

### 3.2 Mode selection
- Make the two playable modes visually distinct from each other
  (Vs AI vs Local) with a small, honest differentiator — e.g. a
  one-line "what happens" cue and a distinct icon treatment — while
  the online card stays visibly inert (muted surface, no chevron,
  already correct at `mode_selection_screen.dart:75-85`).
- Cards gain the new surface treatment (§4); keep the single-node
  semantics labels (M2.9) and the `showChevron` rule.

### 3.3 Setup (medium effort — the longest screen, most to gain)
- Group the screen into three visible sections with section
  headings: **Players** (count segmented control), **Seats**
  (seat cards), **House rules** (ruleset card). Today there are two
  bare `titleMedium` labels and then undifferentiated cards
  (`offline_setup_screen.dart:396-427`).
- Seat cards: give the selected colour a stronger selected state
  (filled ring + check + label, not just a 2.5 px border); make the
  Human/AI control read as a choice, not a form field; keep the
  difficulty dropdown but style it as part of the AI seat, not a
  floating field.
- Ruleset card: group the six switches into two clusters
  (release/finish vs extra turns) with one-line plain-language
  descriptions kept; add a short "Stock rules" reset affordance
  only if it reuses the existing defaults (D-16/D-29) — no new rules.
- Verify keyboard behaviour: focused name field scrolls into view,
  keyboard dismisses on Start; pin the Start button above the
  keyboard (it is already pinned at the column foot,
  `offline_setup_screen.dart:443-449` — confirm it survives the
  keyboard, don't assume).

### 3.4 Gameplay — HIGHEST PRIORITY
- **Environment:** dark navy/indigo game field behind the board;
  the board itself becomes an ivory object with a frame (rounded
  outer edge, one soft shadow) instead of a white square on grey.
  Board cells: raise home-path and start-cell fills toward full
  colour (today 0.55/0.35 alpha, F2) so the meaningful cells are
  the *strongest*, not the palest; deepen safe-cell stars (fix the
  2.86:1 amber-on-amberLight pair — darker star, or star on a
  neutral cell with an amber ring).
- **Turn clarity (F3):** one coherent turn system — the banner
  takes the current player's colour as a restrained edge/accent
  (never as a text background; yellow stays text-free), the current
  chip gains a filled state, and the on-board current-player marker
  becomes a ring + shape cue rather than a white dot. All three
  must agree; the status line keeps narrating (Q10).
- **Dice + Roll (F4):** the dice row becomes the action zone —
  larger dice rest state with a real shadow, a distinct active
  state (lifted + teal edge + full opacity) vs a clearly inert
  state, and the Roll button as the single primary action beside
  it. No looping pulse (pumpAndSettle constraint, §6); the states
  themselves must carry the meaning.
- **Chips:** player chips become a compact turn strip — avatar +
  name + "Home n/4" (already shown, `game_screen.dart:1685-1698`)
  with the current chip unmistakable at a glance; keep the
  three-dot AI-thinking pulse exactly where it is.
- **Feedback (F8):** give the illegal-tap and no-move states a
  visible, non-transient home: keep the SnackBar + status text,
  but add a board-level cue (the existing ~150 ms shake stays) and
  make the disabled Roll state unmistakable. Remove the permanent
  safe-cells hint line (`game_screen.dart:1542-1547`, bodySmall on
  grey) from the first paint — it is reference text, not gameplay;
  move it to a help affordance or the pause menu.
- **Layout:** pin the board + dice row as the stable first paint;
  chips/status scroll below if needed, instead of the whole column
  scrolling the board away (F8). Keep the 280–480 dp board clamp
  and the M2.12 short-screen compaction.

### 3.5 Pause (inside `game_screen.dart` — no separate file)
- The pause menu is a stock `AlertDialog` today
  (`game_screen.dart:1203-1221`). Restyle it as the app's dialog
  (§4: ivory surface, navy title, 16 dp radius to match cards,
  Resume as the single primary action, Restart/Main Menu as quiet
  secondary actions — never three equal-weight buttons). Keep the
  exact flow: freeze on open, Resume on dismiss/cancel, confirm
  before Restart/Exit (D-10, M2.6). Consider adding the safe-cells
  hint and the current standings to the pause menu — it is the one
  place a player can read without time pressure — but only as
  display of existing state, no new data.

### 3.6 Results
- Keep the structure (winner headline → winner's mark → info card
  → players card → Play Again / Main Menu,
  `results_screen.dart:155-277`) and the entrance/confetti contracts
  (§6). Premium work here is restraint + hierarchy: the winner's
  mark gets a proper stage (navy field behind it, gold/teal ring
  already exists — do not add a crown, Q5), the info card becomes a
  clean stat row (duration / moves / mode) instead of five
  label/value rows, and the players card keeps "Home n/4" with the
  winner row unmistakable. The record-failed notice
  (`results_screen.dart:235-248`) keeps its warning treatment and
  must stay visible, not decorative.

### 3.7 Settings / Statistics / History (light touch — same tokens, no reinvention)
- **Settings** (`settings_screen.dart:178-207`): section headings
  (Feedback / Sound — coming soon / About), keep the disabled Sound
  toggle + honest note exactly as is (D-32), keep the volume slider
  storing for later (D-25). No new settings in this redesign except
  if §7's animation question is decided separately.
- **Statistics** (`statistics_screen.dart:111-165`): the four totals
  become a 2×2 stat grid with large numerals (new display-numeral
  style, §4) instead of four identical label/value rows; keep the
  "latest 500 matches" caption verbatim (D-24) and the per-seat
  breakdown with shape + colour identity.
- **History** (`history_screen.dart:93-148`): winner rows gain the
  winner's avatar/shape marker instead of text-only; keep the
  "Local" badge and the detail dialog structure; empty/error states
  use the shared `EmptyState`/`ErrorView` with the new surfaces.

### 3.8 Splash
- Keep the 500 ms brand moment, the real load in `main.dart`
  (M1.6), and the navy field. Replace the generic spinner with a
  brand-appropriate mark treatment — **but only after** the
  boot-test `pumpAndSettle` coupling is reworked (recorded M2.10
  follow-up: removing the spinner broke 26 boot tests). Until then,
  splash is explicitly out of the redesign; do not touch it.

---

## 4. Design-system extension plan

Extend `lib/core/design_system/` — no screen invents its own values.
New tokens only; existing tokens change only where §1 proves a defect.

| Area | Change |
|---|---|
| `diceup_colors.dart` | Add the environment palette: deep navy/indigo field (`table`), warm ivory surfaces (`ivory`, `ivoryMuted`), restrained gold accent (distinct from amber `#D97706`, which stays for stars only). Deepen player colours for harmony on ivory *and* navy; add a `playerColorOnDark` mapping if any player colour is used on the navy field. Add a `textSecondary` that passes 4.5:1 on **both** background and `surfaceMuted` (F9 — darken `#64748B` or restrict it to white surfaces only, and encode the restriction in the token docs). Add a rule in code comments: amber and player yellow are **never text colours**. Keep `navy #1B2A4E`, `teal #0E7C7B` (5.01:1 on white — passes), `error #B91C1C` (6.47:1 — passes), and the D-27 avatar (white disc, navy initial 14.11:1) untouched. |
| `diceup_typography.dart` | No new font family without a separate decision (§7). Add hierarchy with what exists: a display-numeral style for stats/results, a caption style (13–14 sp is the floor — **no style below 14 sp**, NFR-08/D-21 — so "caption" means colour + weight, not smaller size), and letter-spacing/weight variants for section headings vs card titles. Keep the 32/24/20/16/14 scale; add the missing middle (e.g. 28) only if a screen needs it. |
| `diceup_spacing.dart` | Add the missing radius steps so dialogs, chips, and the board frame stop improvising: a small radius for chips (8), keep 12/16 for cards, add a dialog radius that matches the card system (16) and a board-frame radius. Add a `maxContentWidth` (e.g. 560 dp) for ≥600 dp layouts (§5). Keep the 4 dp spacing grid and the 48 dp `minTouchTarget` (D-09 exemption for board tokens stands). |
| `diceup_shadows.dart` | Keep `raised`/`lifted` and add exactly one more: a soft `table` shadow for the board-as-object on the navy field. Still black at low alpha, still no colour shadows, no glow. |
| `diceup_theme.dart` | Rebuild the theme from the new tokens: navy `AppBar` stays; `Card` gets the ivory surface + new radius; `ElevatedButton`/`OutlinedButton`/`TextButton` keep 48 dp minimums and gain the pressed/disabled states the redesign defines (disabled must be unmistakable, F8); `AlertDialog` gets the 16 dp radius + ivory surface so dialogs stop looking stock (F7); `SnackBar` gets the app's surface + an icon slot so errors are not bare text. No dark theme in this redesign (M2.14 already decided it is separate work) — the navy game field is an *environment*, not a dark theme: text on it must still pass AA, verified per surface. |
| `diceup_components.dart` | Extend, don't fork: a `SectionHeading` widget (setup/results/settings), a `StatTile` (statistics/results numbers), a `TurnBanner`/`PlayerChip` promotion from game-screen privates to shared components only if a second screen needs them, and a `DiceUpDialog` wrapper so every dialog shares radius/surface/actions. `PrimaryButton`/`SecondaryButton`/`DiceUpCard`/`PlayerAvatar`/`PlayerShapeMarker` keep their APIs — restyle inside them. No emoji anywhere; icons stay Material/Cupertino glyphs. |
| Board painter | Board presentation changes live in `ludo_board.dart` only: cell fills, star treatment, frame, token depth (a subtle top-light edge is allowed; 3D bevels and textures are not — research §3 rejected textured skins). Geometry, `Board` mapping, and hit-testing are untouched (D-15/D-20). |

---

## 5. Responsive / accessibility checklist (acceptance gates for Stage 2+)

- **320 dp phones (NFR-09 floor):** every screen renders with no
  overflow at 320×568 (existing `test/layout_320_test.dart` +
  `test/accessibility_test.dart` stay green); board 280 dp; dice
  row + Roll button fully in viewport on first paint; player chips
  ellipsize at 12-char names (D-28); pause menu fits.
- **360–430 dp phones:** the standard target — board scales to
  width, no dead space, no scroll needed for the game first paint.
- **Tablets portrait (iPad unrestricted, D-17):** content centred in
  a `maxContentWidth` column; board caps at 480 dp and does not
  stretch; cards do not stretch full-width; verify on a real iPad
  width, not just the harness.
- **iPhone portrait:** portrait lock is platform-native (M2.13);
  SafeArea respected on all screens (notch/dynamic island); no
  content under the home indicator.
- **48 dp targets:** all controls ≥ 48 dp (D-09: board tokens
  exempt as game pieces, full-cell hit area stays); ≥ 8 dp gaps
  between adjacent targets; segmented controls and swatches keep
  their 48 dp sizes.
- **SafeArea / keyboard:** setup name fields scroll into view when
  focused; Start stays reachable with the keyboard open; keyboard
  dismisses on Start/submit.
- **Contrast:** every text/background pair verified with
  `DiceUpColors.contrastRatio` (the helper already exists) and
  pinned in `test/design_system_test.dart` — including the new
  navy-field text, the ivory surfaces, the darkened `textSecondary`,
  and every player colour used as a ring/border (never as text).
  Target WCAG AA 4.5:1 for normal text, 3:1 for large text and
  non-text markers.
- **Identity never by colour alone:** shape + name + colour
  everywhere (D-27, NFR-08); the new turn system (§3.4) must add a
  non-colour cue (shape/ring/label), not just a colour wash.
- **Reduced motion:** every new or changed animation gated on
  `isReducedMotion(context)` (`reduced_motion.dart`); reduced-motion
  path is a real static path (crossfade/instant), not a broken
  animation (§6). Note the iOS gap in §7.
- **Text scaling:** layouts survive large system text scales
  (existing scroll fallbacks on Home/mode selection stay; verify
  setup + results at 1.3×).
- **Semantics:** no new screen ships without its labels; the
  per-token semantics follow-up (F9) is a named Stage-2+ item, not
  silently dropped.

---

## 6. Animation polish plan — PRESERVE THE CONTRACTS

These contracts are **frozen**. Polish presentation around them;
never change timings, sequencing, or input-locking behaviour.

| Contract (verified) | Where | Polish allowed |
|---|---|---|
| Per-cell token steps ~110 ms/cell, capped ~600 ms, input locked for the whole sequence; one polyline controller; last-moved ring ~1.5 s fade | `game_screen.dart` (step sequence), `ludo_board.dart` (hop/last-moved params) | Token *rendering* during steps (lift height, settle scale) may be tuned ±small amounts; step timing, cap, and lock must not move. |
| Capture: after the mover settles, lift → shrink/fade → arc to yard → pop-in ~600 ms, overshoot 1.08; mover settles ~1.18 on a capturing move; one haptic per capture | `game_screen.dart`, `ludo_board.dart` (capture params) | Arc path and pop-in rendering only; sequence order and durations frozen. |
| Dice: wind-up/tumble/settle wobble inside the ~540 ms budget, settles on the ENGINE value, input locked; steady teal rollable border (deliberately not oscillating — a repeating ticker breaks `pumpAndSettle`) | `game_screen.dart` (tumble controller), `dice_widget.dart` | Dice *face* rendering (pip weight, edge, shadow states) may change; the 540 ms budget, engine-value settle, lock, and steady border must not. A slow repeating border is a named revisit only if the harness moves off `pumpAndSettle`. |
| AI thinking: three-dot pulse in the current player's chip + status narration; pulse stops the moment the AI acts; AI pacing 700–1,199 ms (D-31) | `game_screen.dart` `_ThinkingDots`, `offline_game_controller.dart` status | Dot size/colour may be tuned to the new palette; placement, narration strings, and pacing frozen. |
| Results: staggered entrance ~500 ms, winner's mark (teal ring + enlarged shape marker, **no crown**), one-shot hand-drawn confetti ~36 rectangles ~1.2 s, "Home n/4" counts | `results_screen.dart` | Entrance *staging* (spacing, card treatment) may change; durations, one-shot behaviour, and the no-crown mark frozen. |
| Pause: FREEZES sequences and RESUMES them (lock = `_sequenceActive` flag; Q2/D-10) | `game_screen.dart`, `offline_game_controller.dart` (`pause`/`resume`) | Pause *menu presentation* only (§3.5); freeze/resume semantics frozen. |
| Reduced motion: steps → instant jump, dice frozen at pre-roll face until settle, capture → fade, confetti never fires, entrance jumps to end state | `game_screen.dart`, `results_screen.dart`, `reduced_motion.dart` | New animations must add their reduced-motion branch in the same pattern; no new animation ships without one. |

General motion rules for any new animation (Apple HIG Motion;
Material M3 via `docs/UI-RESEARCH.md` §2.7): motion must explain
a change, never decorate; feedback animations brief and precise
(100–250 ms for UI feedback, ≤300–500 ms for transitions, never
over ~600 ms for a game sequence that already owns its budget);
ease-out for entrances, ease-in for exits, never linear on position/
scale; no sustained oscillation; no screen shake on capture
(rejected in research §3 — photosensitivity risk); every animation
cancellable or skippable in effect (input never waits on a
decorative animation).

---

## 7. Blockers / open questions for later stages

1. **Bundled display font:** cannot be decided inside the redesign.
   Binary `.ttf` files cannot be snapshot-pushed and `google_fonts`
   is a runtime network dependency (M2.14, NFR-23). If a display
   font is wanted, Anti must approve the delivery route first;
   until then typography work uses scale/weight/tracking only (§4).
2. **iOS Reduce Motion unreadable:** `isReducedMotion` reads only
   Android's `disableAnimations` because `reduceMotion` does not
   exist on the oldest supported Flutter SDKs (2026-11-23 fix).
   Restoring the iOS check requires raising the minimum Flutter
   version — a separate decision, not a redesign task.
3. **Splash spinner coupling:** removing the splash spinner broke
   26 boot tests (`pumpAndSettle` reliance, M2.10). Splash is out
   of this redesign until the boot-test pattern is reworked.
4. **Per-token semantics nodes:** recorded M2.9 follow-up (F9).
   Needs a design (overlay nodes vs board-level list) before
   implementation; do not fake it.
5. **Device verification outstanding (M4):** NFR-09 on real phones,
   screen-reader traversal, 50 fps frame-rate number, and the
   Android/iOS builds were never verified in this VM. The redesign
   must be playtested on the reference device (D-14: low-end
   Android 4 GB + one iPhone) before it is called done.
6. **CI workflows blocked:** `.github/workflows/ci.yml` (and the
   staged `vectors`/`coverage`/`strings` jobs) cannot be pushed —
   the GitHub App lacks Workflows: Read and write (403). Stage 2+
   verification runs locally via `tool/check.sh` until that is fixed.
7. **Known pre-existing follow-ups, untouched by this plan:**
   `LudoGame.fromState` uses the stock ruleset, not a restored
   custom ruleset (needs a decision); the `loadedSettings`
   vibration quirk; the AI timeout fallback is accepted risk
   (D-31/M-16). None of these is a redesign item.
8. **Animation-speed setting:** decided NO in M3 (Q7 — OS flag is
   sufficient). If the redesign wants a "Full / Reduced" in-app
   setting, that is a new product decision, not implied by this plan.

---

## 8. Non-goals and preserves

**Preserve (do not touch):** game rules and engine
(`lib/domain/engine/*`, D-15/D-16/D-20, `docs/ruleset.md`); AI
behaviour, weights, and pacing 700–1,199 ms (D-31);
`OfflineGameController` state machine, status strings, and
snapshot/resume behaviour (D-11/D-12); Riverpod composition root
and provider wiring (D-06, M3.3); SQLite persistence, history,
statistics, and the 500-match cap (NFR-36, D-24); navigation and
route structure (`app_routes.dart` — including the results
fade/slide 300 ms in / 200 ms out, which already exists); the
offline-only scope; all 32 decisions D-01…D-32; all localised
strings (new strings go through `app_en.arb`, M3.10 — no hardcoded
text); the animation contracts in §6; the D-27 white-disc avatar
and per-seat shapes; the 48 dp control minimum and the board-token
exemption (D-09).

**Non-goals:** no backend, online play, accounts, social, payments,
ads, or gambling-adjacent features; no new dependency without a
written justification (none is justified by this plan — no animation
package, no font package, no confetti package); **no sound**
(D-32 — haptics only, `FeedbackService` unchanged); no rule
variants beyond the curated setup subset (D-29); no continue-to-rank
(D-02); no ghost destination preview or auto-move on a single legal
move (Q3/Q4 decided NO); no direction chevrons or reachable-safe-cell
outlines (Q9 decided NO); no dark theme as a separate theme (M2.14);
no 3D dice/board, no board skins, no crown or Ludo King branding
(research §3); no changes to PR #1, `main`, or any branch — Stage 1
writes this plan only.

---

## 9. Suggested Stage 2 order

1. Design-system extension (§4) + contrast tests pinned — everything
   else builds on it.
2. Gameplay (§3.4: environment, board, turn system, dice row) —
   highest priority, largest surface.
3. Pause dialog restyle (§3.5) + feedback weight (F8).
4. Home / Mode / Setup (§3.1–3.3).
5. Results (§3.6), then Settings / Statistics / History (§3.7).
6. Responsive + accessibility gates (§5) on device (D-14) + full
   suite green (`flutter test`, `flutter analyze`, `tool/check.sh`).

*End of Stage 1 plan. No code changed.*

---

## 10. Re-sync to remote head `a36eba4c` (2026-11-23, re-sync worker)

Remote head moved from `19e07264` to `a36eba4c` ("fix(a11y): preserve
iOS reduced motion", Anti + Copilot, 2026-11-22 20:57 UTC) while the
redesign was in flight. The push was correctly stopped: `a36eba4c`
touched 3 files also in the redesign manifest. This section records
the merge of `a36eba4c` into the staging tree — redesign + `a36eba4c`
both preserved, nothing reverted, no other file touched.

**SDK-compat verdict: CLEARED — safe to merge.** `a36eba4c` does NOT
read `MediaQueryData.reduceMotion` (the API that broke Anti's Windows
build at `19e07264`). It reads iOS Reduce Motion via
`WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion`
(`dart:ui.AccessibilityFeatures.reduceMotion`,
`lib/core/accessibility/reduced_motion.dart:11-16` in the merged
file). Evidence: (1) that getter exists in the Flutter engine since
at least 3.13.0 (verified live from `flutter/engine`
`lib/ui/window.dart` at tag `flutter-3.13-candidate.0`, line 877), as
do `PlatformDispatcher.accessibilityFeatures` and
`BindingBase.platformDispatcher` (framework `binding.dart:243` at
3.13.0) — and Anti's SDK must be ≥ 3.13 since the app already uses
`MediaQuery.disableAnimationsOf` (3.13+); (2) `a36eba4c`'s own docs
record the exact SDK — Flutter **3.47.5** / Dart 3.13.4 — and that on
it analysis passed, the two focused test files passed 20/20, and
`flutter build apk --debug` produced the debug APK
(`docs/TRACEABILITY.md`, "Reduced-motion SDK compatibility"
section). No `dynamic` probing anywhere. The old
`disableAnimations`-only helper is superseded by the merged version.

**Adopted wholesale from `a36eba4c`** (redesign never touched them —
verified byte-identical to `19e07264` in staging before adopting):
`lib/core/accessibility/reduced_motion.dart`,
`test/premium_animation_test.dart` (now 8 tests: the iOS
`enableReduceMotion()` case added, `disableAnimations` cases kept),
`docs/IMPLEMENTATION-PLAN.md`, `docs/TRACEABILITY.md`,
`docs/UI-RESEARCH.md`.

**Merged (both sides preserved):** `lib/presentation/screens/game_screen.dart`
(observer mixin + `addObserver`/`removeObserver` +
`didChangeAccessibilityFeatures()` cancelling sequences / stopping
the dice tumble; comment at the reduced-motion doc updated),
`lib/presentation/screens/results_screen.dart` (observer mixin +
`_confettiSuppressed` + entrance jump in
`didChangeAccessibilityFeatures()` + confetti gate
`!reduced && !_confettiSuppressed`),
`test/results_screen_test.dart` (new test "iOS Reduce Motion skips
the entrance and confetti" added alongside the redesign's
`skipOffstage: false` preamble fix).

**Push manifest after this re-sync:** the 27 redesign files + the 5
adopted `a36eba4c` files above (the 3 merged files are already in the
27). Re-verified after the merge (measured 2026-11-23, Flutter
3.50.1 / Dart 3.14.1 in this VM): `dart format` on the 5 touched
Dart files — 0 changed; `flutter analyze` — 0 errors / 0 warnings /
39 infos (baseline unchanged); full `flutter test` — **684/684**
(683 redesign baseline + the 1 genuinely new `a36eba4c` test in
`results_screen_test.dart`; `premium_animation_test.dart` stays at 7
— `a36eba4c` renamed one test there, it did not add one);
`test/results_screen_test.dart` standalone — 13/13 including the new
test; `tool/check.sh` — **all gates passed** (exit 0: pub get,
format, analyze `--no-fatal-infos`, full test 684/684, boundaries,
strings). `flutter build apk --debug` still cannot run in this VM
(no Android SDK); `a36eba4c`'s own docs record it passing on Anti's
Windows Flutter 3.47.5 — Anti re-runs it on Windows after the push.
