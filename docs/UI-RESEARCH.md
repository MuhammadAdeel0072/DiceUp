# DiceUp UI/UX Research — Ludo & Mobile Board-Game Interfaces

- **Status:** READ-ONLY research for M3 (premium UI/UX). No code was changed.
- **Date checked:** 2026-11-22 (all references below were checked on this date).
- **Scope:** what high-quality Ludo games and professional mobile board-game
  interfaces do, and what DiceUp should adapt — in its own identity — vs.
  what it should deliberately not copy.
- **Method note (honest):** research was done with text web search and
  fetching page text. No live browser session was used, no app was installed
  or played, and no gameplay video was watched frame-by-frame: Instagram /
  Facebook results below were read only as their search-result summaries
  (title + description text). Where a claim rests on a summary rather than a
  fetched page, that is stated. Nothing here is a claim about a live visit.
- **Inspiration only:** no proprietary artwork, assets, branding, or exact
  interface is copied. Ludo King / Ludo Star / Ludo Master are cited as
  observed patterns (board geometry, feedback, animation), never as art to
  reproduce. DiceUp keeps its own identity: navy `#1B2A4E` / teal `#0E7C7B` /
  amber `#D97706`, white-disc avatars with navy initial + colour ring +
  per-seat shape (D-27), Roboto/system type, 4 dp spacing scale.
- **Code baseline read for this research:**
  `diceup_app/lib/presentation/widgets/ludo_board.dart` (15×15
  `CustomPainter`, safe cells {0, 8, 13, 21, 34, 39, 47} per D-15,
  51+4+1 = 56 steps per D-20, per-seat token shapes, one-shot 1,200 ms
  legal-move pulse, ≤250 ms straight-line hop),
  `diceup_app/lib/presentation/widgets/dice_widget.dart` (64 dp widget-drawn
  pip dice, 540 ms tumble cycling faces, tappable, dimmed when not rollable),
  `diceup_app/lib/presentation/screens/game_screen.dart` (Riverpod
  controller, three `AnimationController`s, input locked during tumble/hop,
  AI pacing 700–1,199 ms per D-31, haptics only per D-32, 48 dp controls
  per D-09 with board tokens exempt, 280–480 dp board clamp, 320×568
  first-paint compaction in M2.12),
  `diceup_app/lib/presentation/screens/results_screen.dart` (dedicated
  results route per D-02, winner + duration + moves + players, Play Again /
  Main Menu per D-30),
  `diceup_app/lib/core/design_system/` (colours, typography with 14 sp
  floor per D-21, spacing, Material 3 theme, shared components).
  `diceup_app/pubspec.yaml` has no animation/audio packages — only
  `flutter_riverpod`, `sqflite`, `path`, `cupertino_icons`.

---

## 1. References

| # | Game / app / site | URL | Date checked | What was observed (and how) |
|---|---|---|---|---|
| R1 | Ludo King® — Google Play listing (Gametion) | https://play.google.com/store/apps/details?id=com.ludo.king | 2026-11-22 | Search-result text of the official listing: "THIS IS OFFICIAL LUDO KING® GAME, 2 Billion Downloads"; offline mode vs computer or local pass-and-play; 2–6 player online, 8-player tournament, Snakes and Ladders; "traditional rules and the old school look"; many purchasable themes (Disco/Night, Nature, Egypt, Pinball, Candy, Christmas, Penguin, Battle, Diwali, Pirate, Marble, Alien, Octopus, Taj Mahal); "Low end devices support". Informs: classic board is the expected default; themes/ads/social are a monetisation layer DiceUp does not need. |
| R2 | Ludo King complete guide — Voyanta | https://www.voyanta.site/game/ludo-king | 2026-11-22 | Search-result text: board described as "cross-shaped board with four coloured home areas, a ring of track squares around the outside, and a centre triangle"; tokens "start in their home area, travel around the track, and finish in the centre"; release on 6, home column needs exact roll. Confirms DiceUp's 15×15 geometry matches the genre default. |
| R3 | Ludo King offline beginner guide — Kaobe Games | https://kaobegames.com/en/g/ludo-king-offline-ludo-game-33893 | 2026-11-22 | Search-result text: "Tap the dice icon to roll; the result appears instantly, and the game highlights the token(s) eligible for movement. If you have multiple tokens that can move, each eligible token lights up"; capture sends the opponent's token "back to its start"; "bright colors to differentiate players while keeping the board layout clean enough to assess risks at a glance". Informs: legal-move lighting is the genre's primary affordance, and board legibility beats decoration. |
| R4 | Ludo King gameplay screenshots — Instagram posts (Shazib Rayeen; aman_yadav_ji; nitaanitin; md ifathakar king; raajn1066; pramod803596) | https://www.instagram.com/p/DfWFc5NBOaU/ (representative; others in search results) | 2026-11-22 | Search-result summaries only (images not inspected pixel-by-pixel): four corner yards (red top-left, green top-right, yellow bottom-right, blue bottom-left), circular tokens, star-marked safe squares, directional arrows on the track, four coloured triangles in the centre, a gold crown + rank number over the winning player's yard, dark-blue patterned background with faint dice motifs, "LUDO KING" wordmark with crown. Informs: centre = four triangles (DiceUp already does this); winner is marked *on the board* with a crown + rank (adapted, not copied — see §2.6); arrows on the track are a legibility aid DiceUp currently lacks. |
| R5 | Ludo gameplay screen recordings — Instagram reels (Pankaj Maharshi) | https://www.instagram.com/reel/DfJ5i4QBq33/ (representative) | 2026-11-22 | Search-result summaries only: per-player dice shown at each player's side of the board (top/bottom/left/right), turn indicator moving between players, player labels ("You", "Computer 2/3/4"), rank crown over a finished player's base, tokens advancing along the track, dice values visible per seat. Informs: turn ownership is shown *at the player's seat*, not only in a banner — DiceUp's turn banner + player chips are the equivalent, but a seat-anchored indicator is worth considering (see §2.5). |
| R6 | Ludo Star gameplay + dice collections — Facebook reel (Salma Shah) | https://www.facebook.com/reel/1547362950751206/ | 2026-11-22 | Search-result summary only: home screen offers 2 Player / 4 Player / Private Table / Streak Stars / Team Up; a COLLECTIONS → Dice → FUSION tab with collectible dice skins (Unicorn, Bow, Brain, Hallo…), a spin-and-merge animation into a bright light, falling confetti, and a COLLECT button. Informs: dice skins + confetti celebration are proven delight patterns; the skins/monetisation half is out of scope (§3), the confetti half is adaptable with hand-drawn particles (§2.6). |
| R7 | Ludo Star League gameplay — Facebook reel (Garvit k k Gupta) | https://www.facebook.com/reel/1127792900043626/ | 2026-11-22 | Search-result summary only: circular wooden-textured board, standard cross track, red/green/yellow/blue paths to a central home, dice rolled per player in turn, pawns advancing, occasional captures. Informs: a wooden/real-material board skin is a recognised premium direction — but DiceUp's flat navy/teal identity is the cheaper, more legible alternative; do not chase texture. |
| R8 | Ludo Master — Real Club King — App Store listing (Phoenix Mind Games) | https://apps.apple.com/bf/app/ludo-master-real-club-king/id1396381574 | 2026-11-22 | Search-result text: "Option to show safe cells (square) which is represented by star icon"; "New modern design with wooden board" and a white/paper board option; "classic wood and neo-Ludo Master boards"; "sketch marks and crystal clear tokens". Informs: safe cells as star icons is the cross-game convention (DiceUp already does this); offering a board-skin choice is a known pattern but adds scope DiceUp does not need in M3. |
| R9 | Ludo.now — Classic Ludo rules & how-to-play | https://ludo.now/ | 2026-11-22 | Search-result text: "Star squares and start squares are safe ground where nobody can be captured"; "Land exactly on a square holding a single enemy token and you knock it back to its yard"; "Park on star squares when opponents are close… A turn spent safe beats a turn spent respawning"; "Every enemy token projects a capture zone one to six squares ahead of it". Informs: safe cells are *strategic*, not decorative — the UI should make the next safe cell readable at a glance (see §2.1). |
| R10 | MixoGame — Ludo (classic, browser) | https://mixogame.com/games/ludo/ | 2026-11-22 | Search-result text: "Board Geometry: four 6×6 corner yards…, a cross-shaped track containing 52 perimeter squares, four 5-square colored home columns, and a central triangular goal area. Safe Squares: the 4 starting squares (Red index 0, Green index 13, Yellow index 26, Blue index 39) and the 4 star-marked squares (indices 8, 21, 34, 47)"; "glowing piece indicators, and high-contrast color badges". Note: its "5-square home columns" contradicts DiceUp's decided 51+4+1 (D-20) — DiceUp's 4 home-path cells are the decided geometry; the safe-cell indices independently confirm D-15. Informs: glowing legal-piece indicators + high-contrast badges are the genre norm. |
| R11 | flutter_ludo — Flutter package (pub.dev, v. updated 2026-09-25) | https://pub.dev/packages/flutter_ludo | 2026-11-22 | Page text fetched and read in full. Advertises: "Step-by-step piece animation, dice shake, a highlight on the last moved piece, and stacked pieces fanned out so each one can be seen"; "Screen-reader labels on the dice, pieces, and setup controls"; `botThinkDuration: 500 ms` default; light/dark themes; `stepAnimationDuration: Duration.zero` for instant moves in tests; `suggestMove()` move hints; 8 event callbacks (`onPieceMoved`, `onPieceCaptured`, `onTurnChanged`, …). Board: "standard 15×15 board with a 52-cell shared path… 8 safe cells: each start cell plus one star per arm" — matches DiceUp. Informs: the three most directly adoptable patterns in this report (step-by-step movement, last-moved highlight, stacked-piece fan-out). NOT a dependency to adopt (§3). |
| R12 | opolyx — "Dice that actually tumble: the new 3D roll" (12 Jun 2026) | https://www.opolyx.com/product-updates/3d-dice | 2026-11-22 | Page text fetched and read in full. State machine idle → windup → loop → settle → jitter → landed; "180 ms wind-up the instant you tap Roll, so it feels responsive right away"; "dice keep spinning only while the game works out your move, then drop and land on the exact numbers you rolled. There is no padded, fake pause"; "smooth landing onto your actual numbers, with your token starting to move the moment the dice settle"; "decaying landing bounces were dropped (restitution 0), so the settle is one smooth accelerating descent… leaving only a short damped wobble"; "If your device is set to reduce motion, the dice skip the tumble entirely and simply show your numbers". Informs: the dice pattern DiceUp already approximates (value fixed before animation, 540 ms tumble) and how to finish it — wind-up, settle wobble, reduced-motion skip. The 3D cube itself is NOT adopted (§3). |
| R13 | JackpotKit — Dice component docs | https://jackpotkit.vercel.app/docs/dice | 2026-11-22 | Search-result text: "Roll D4 to D20… with values resolved before animation"; "Core resolves every value before React Native starts its roll animation"; default animation 700 ms; "Dice motion uses an upright lift, tumble, and settle sequence"; "supports… reduce motion… screen-reader announcements"; "Custom dice must preserve readable values, labels, contrast, and non-color-only state". Informs: "resolve first, animate second" is the cross-framework rule DiceUp already follows; the lift → tumble → settle *sequence* (not just face-cycling) is the gap to close. |
| R14 | CSS 3D Dice Roller — WebDevPuneet | https://mail.webdevpuneet.com/ui-snippets/dice-roller/ | 2026-11-22 | Search-result text: pick the result with `Math.random()` *before* any animation; rotate to the face's base rotation plus a growing multiple of 360° so the cube "visibly tumbles forward and always lands exactly on the chosen face, never snapping backward"; "Disable the roll trigger for the duration of the roughly one-second CSS transition and only report the rolled number in the UI once the transition's timeout fires, so the displayed result can never desync". Informs: the anti-desync discipline (input lock + report-after-settle) DiceUp already has; the "never snap backward" detail matters if DiceUp ever adds rotation to the dice. |
| R15 | 2D Board Game Rendering & Animation in the Browser (2025–2026) — marcus-skills research | https://github.com/marcus/marcus-skills/blob/HEAD/research/2d-board-game-rendering-2025.md | 2026-11-22 | Page text fetched (first ~545 of 2,161 lines read). Recommends hybrid DOM + Canvas: "DOM for UI/text/buttons, Canvas for the board surface and animated pieces"; "Board games have discrete, infrequent animations… These are not complex choreographed sequences"; "Build custom with WAAPI + requestAnimationFrame. Skip the animation libraries"; easing recipes — `outCubic` "smooth deceleration — piece slides and gently stops", `inOutCubic`, `outBack` "overshoot then settle — playful piece snap", `outBounce` "dice landing, token dropping"; "Piece slide (grid to grid)" recipe. Informs: DiceUp's existing split (CustomPainter board + widget UI) is the right architecture; no animation library is needed (§3); easing vocabulary for §2.2. |
| R16 | Building Low-Latency Turn-Based Game Clients (Canvas Rendering…) — dev.to | https://dev.to/payamprivate/building-low-latency-turn-based-game-clients-canvas-rendering-coordinate-systems-and-state-3lk5 | 2026-11-22 | Search-result text: canvas-first architecture with layered rendering — "Static Base… Dynamic Ground: placed pieces… Interactive Layer: actively dragged piece, ghost destination indicators, valid move highlights… Overlay/Particle Layer: dice physics, capture effects"; "define your board geometry in a normalized bounding box… hit-testing… O(1) mathematical lookup"; "asymmetric gravity wells… snap the preview highlight" so a touch need not be pixel-perfect. Informs: DiceUp's full-cell hit area (D-09 mitigation) is the same idea; a "ghost destination" preview (where the tapped token *would* land) is a candidate addition (open question §4). |
| R17 | Build an Arrow Puzzle Game in Flutter — dev.to | https://dev.to/uzairxdev/build-an-arrow-puzzle-game-in-flutter-2fki | 2026-11-22 | Search-result text: "Animate the glide with an AnimationController and a Tween… Scale the duration to the distance — about 90 milliseconds per cell, capped at roughly half a second — so a short hop feels snappy and a long glide across the board still feels fast. Draw the board with a CustomPainter and render each arrow as a positioned widget on top of it"; "Respect the player's reduce-motion setting: when MediaQuery disables animations, skip the tween". Informs: the concrete per-cell timing number (≈90 ms/cell, cap ≈500 ms) used in §2.2 — the only sourced per-cell figure found. |
| R18 | chessground 10.3.0 changelog — pub.dev | https://pub.dev/packages/chessground/versions/10.3.0/changelog | 2026-11-22 | Search-result text: replaced widget-tree board rendering with a CustomPainter-based approach "to bypass Flutter's build and layout phases for frequent interactions"; "Position updates now go through the controller instead of rebuilding… with animation"; "Preserve the piece animation behaviour even if the system is requesting the animations to be reduced or disabled" (noted as a deliberate choice there — DiceUp should do the opposite for non-essential motion, §2.7). Informs: DiceUp's painter + `shouldRepaint` + `RepaintBoundary` approach is the established performant pattern for board games in Flutter. |
| R19 | Material Design 3 motion tokens + duration guidance (via design-os canon; ShotCanvas "How long should a UI animation take?", Oct 2026) | https://github.com/cgallic/design-os/blob/HEAD/design_os/canon/motion-design.md and https://www.shotcanvas.app/blog/animation-duration | 2026-11-22 | Search-result text: M3 duration tokens short 50/100/150/200 ms, medium 250/300/350/400 ms, long 450–600 ms, extra-long 700–1,000 ms; "transitions that exceed 400 ms may feel too slow" (mobile standard ≈300 ms; entering 225 ms, leaving 195 ms, full-screen up to 375 ms); "No linear easing on any animation of position, scale, or size"; "duration should scale with how far something travels"; "start the response within a frame, keep most motion between 150 and 300 ms". Informs: the timing budget for every recommendation in §2 (per-cell steps, dice settle, transitions, SnackBar feedback). |
| R20 | Game-feel / "juice" sources — agent-games CLAUDE.md; GameDev Academy "How To Improve Game Feel"; tableplace cross-game juice research (Balatro et al.) | https://github.com/inman-sebastian/agent-games/blob/HEAD/CLAUDE.md ; https://gamedevacademy.org/game-feel-tutorial/ ; https://github.com/jollygrin/tableplace/blob/HEAD/docs/research/raw-cross-game-juice.md | 2026-11-22 | Search-result text. agent-games: "Separate simulation from presentation. Resolve what happened in logic…, then animate toward that already-decided result"; "Nothing important teleports. State changes get a transition"; "Impacts need a reaction… A brief squash/stretch or knockback sells an impact… Keep it short and always return to rest"; "Anticipation and follow-through beat instant, linear motion". GameDev Academy: "Emphasize the player's success… Throw confetti… Combine all these effects"; "Add randomness… a bit of randomness can spice up repetitive gameplay". tableplace/Balatro: "Spring wobble / over-rotation on settle (±~3°)"; "Selection as a second, higher lift tier — hover ≈ translateY(-12px)/scale(1.05); selected ≈ translateY(-24px)/scale(1.08) with intensified shadow"; "Adjustable animation speed setting — juice can be dialed down… juice that can't be skipped becomes friction on the 500th hand". Informs: the governing principle of §2 (engine decides, animation performs) and the restraint rule (juice must be skippable/short). |
| R21 | Accessibility syntheses — gamestack U4 UI/UX & feedback; accessibility-design skill; game-ui-ux skill; M3 Accessibility foundations | https://github.com/rondorkerin/gamestack/blob/HEAD/docs/research/round1-universal/U4-ui-ux-and-feedback.md ; https://github.com/rbergman/dark-matter-marketplace/blob/HEAD/plugins/game-dev/skills/accessibility-design/SKILL.md ; https://github.com/manthan-13521/gesturekart-ai-racing/blob/HEAD/GAME%20UI:UX%20SKILL/game-ui-ux-skill.md ; https://github.com/fluttely/material_design/blob/HEAD/documentation/material_design/en_US/foundations/Accessibility.md | 2026-11-22 | Search-result text: "Every color-encoded signal… must have a redundant shape or label signal" (WCAG 1.4.1; ~8% of males colour-vision deficient); "WCAG contrast ratios (4.5:1 body text, 3:1 large UI) are the minimum floor"; "Fitts's Law… Android HIG: 48×48 dp"; "primary actions in bottom 60–70% of screen (comfortable thumb reach)"; "Touch targets: minimum 44×44 pt (iOS) or 48×48 dp (Material), with at least 8 dp between adjacent targets. Pad the invisible tap area past the visible icon"; "Provide a reduced-motion / reduced-flash toggle that kills screen shake, camera kick, and strobing". Informs: DiceUp's existing decisions (D-09, D-21, D-27) are aligned with the genre consensus; the remaining gap is reduced-motion handling (§2.7). |
| R22 | Reduce-motion in Flutter — Flutter API docs (`MediaQueryData.disableAnimations` / `reduceMotion`); colin.flutter "flutter_animate and Reduced Motion"; reduce-motion skill | https://api.flutter.dev/flutter/widgets/MediaQueryData/reduceMotion.html ; https://colinchflutter.github.io/2026-06-26/22-00-00-507612-flutter-animate-reduced-motion-accessibility/ ; https://github.com/almasumdev/awesome-mobile-accessibility-agent-skills/blob/HEAD/.github/skills/motion/reduce-motion/SKILL.md | 2026-11-22 | Search-result text: `disableAnimations` "is read directly from the engine… it is used by framework-level animation APIs such as AnimationController"; `reduceMotion` (iOS Reduce Motion) "does not set this flag" and must be read separately — "you should check this property and adjust behavior accordingly; for example, by preferring a fade over movement"; recommended pattern: "Disable parallax… Replace slide/zoom transitions with crossfade… Shorten durations… keep timing for feedback (e.g. button press) but prefer < 100 ms". Informs: the concrete implementation note in §2.7 — DiceUp must check *both* flags, and `AnimationController` behaviour under `disableAnimations` needs a test, not an assumption. |
| R23 | Ludo web implementation styling — dojoVader/ludo (DeepWiki) | https://deepwiki.com/dojoVader/ludo/4.2-styling-system | 2026-11-22 | Search-result text: pawn focus = "blinking animation + cursor pointer" per colour; dice focus = "container border animation" when rollable; "Pawn Movement: top .1s linear, left .1s linear"; "dice.throw: opacity reduced to 0.3" after rolling; player list with a dynamic arrow indicator for the current player. Informs: the two cheapest turn signals in the genre — a blinking/pulsing legal token and an animated border on the rollable dice — both directly portable to DiceUp's existing pulse + dice opacity. (Its 100 ms *linear* pawn movement is explicitly not copied: linear motion on position violates the M3 rule in R19.) |

### Sources searched but not usable

- **Ludo Star / Ludo Classic / Ludo Master gameplay detail:** searches
  returned store listings, rule summaries, and short-form video summaries,
  but no written teardown of their turn indicators, dice animation timing,
  or results screens. The gameplay observations above (R4–R7) therefore
  rest on search-result summaries of screenshots/reels, not on inspected
  frames — recorded as such, not overstated.
- **"Token capture animation" as a standalone topic:** no source described
  a Ludo capture-return animation in implementable detail. The capture
  recommendation in §2.3 is therefore a synthesis (game-feel principles
  R20 + the per-cell timing in R17 + opolyx's settle in R12), labelled
  as original DiceUp design, not as an observed pattern.
- **DiceUp's own competitors' results screens:** no source described a
  Ludo results screen beyond Ludo King's crown-over-yard (R4) and the
  generic "WINNER celebration with confetti and trumpets" in a Ludo King
  promo (search result, Facebook reel 2025-02-18). §2.6 is accordingly
  mostly original design constrained by D-02/D-30.

---

## 2. Patterns worth adopting for DiceUp

Each pattern states the **observed pattern**, the **DiceUp-specific
adaptation** (concrete, implementable in the current architecture), and
whether it is **adapted** (genre pattern, DiceUp execution) or
**original** (DiceUp invention informed by a principle).

### 2.1 Board — keep the classic geometry; add direction and safe-cell legibility

- **Observed (R1–R4, R8–R10):** every Ludo game uses the same board:
  four 6×6 corner yards with 2×2 token slots, a 52-cell cross track,
  coloured home columns, four triangles meeting in the centre, 8 safe
  cells (4 starts + 4 stars). Safe cells are star-marked; start cells
  carry their seat colour; the centre is four triangles, not a logo.
  Ludo King / Ludo Master add small directional arrows on the track arms.
- **DiceUp today:** already matches this exactly (D-15 safe cells,
  D-20 51+4+1, star markers, amber safe-cell fill, 0.35-alpha start
  cells, four centre triangles). Nothing to fix geometrically.
- **Adaptation (adapted):**
  1. **Direction chevrons.** Add one small chevron per track arm
     (e.g. on the cell just after each start cell, or centred on the
     middle cell of each arm) pointing clockwise, drawn in the painter
     in `DiceUpColors.border` / low-alpha navy. Pure painter work, no
     engine change; helps first-time players more than any tutorial
     text. Keep them subtle — they must not compete with the star.
  2. **Safe-cell legibility.** Keep the amber fill + star, but make
     the *next* safe cell from a legal token's position faintly
     distinguishable (e.g. a slightly stronger amber outline on safe
     cells reachable by the current roll). This is a painter-only
     highlight driven by the legal-move set the screen already passes
     in; it teaches the R9 strategy ("hop from one safe square toward
     the next") without any new UI chrome.
  3. **Depth, not texture.** R7's wooden board is a recognised premium
     look, but DiceUp should stay flat: add depth with what it already
     has — a soft drop shadow under the whole board (the dice already
     uses `BoxShadow … blur 6, offset (0, 3)`; reuse that token), a
     1 dp inner border, and a slightly raised token shadow (see §2.2).
     No image assets, no texture files, no new dependency.
- **Do not change:** yard layout, centre triangles, player colours,
  280–480 dp board clamp (M2.12).

### 2.2 Token movement — replace the straight hop with sequenced per-cell stepping

This is the highest-priority change in the brief, and the research
converges on one answer.

- **Observed (R11, R17, R15, R20):** flutter_ludo's headline feature
  is "step-by-step piece animation"; the Flutter arrow-puzzle guide
  quantifies it at "about 90 milliseconds per cell, capped at roughly
  half a second"; the board-game rendering research recommends
  `outCubic` ("piece slides and gently stops") and `outBack`
  ("overshoot then settle — playful piece snap") per step; the
  game-feel sources insist "nothing important teleports" and "scale
  transition time with magnitude so a big change feels bigger".
- **DiceUp today:** one ≤250 ms straight-line hop from the pre-move
  cell to the post-move cell (`Curves.easeOut`), engine state already
  final, input locked during the hop. A 6-step move therefore reads as
  a single slide that cuts corners — the "cheap" feeling the brief
  warns about. The painter already supports a `hopCenter` override,
  so the mechanism exists; only the *path* is wrong.
- **Adaptation (adapted):**
  1. **Path:** walk the token through each intermediate cell in
     `boardCellForToken` order (track → home path → centre), one
     segment per cell. Reuse the existing `hopTokenId`/`hopCenter`
     painter override; the screen drives a sequence of short tweens
     (one `AnimationController`, re-targeted per step, or a single
     controller whose value maps onto a polyline — either fits; the
     polyline form keeps one ticker and matches the existing
     `Listenable.merge` board animation).
  2. **Timing (starting point, to be tuned by play, not by fiat):**
     ~110 ms per cell (between R17's 90 ms and the need for the hop
     to read at 280 dp board size), capped at ~600 ms total for a
     6-step move, ~250 ms minimum for a 1-step move. A 6 therefore
     takes ~600 ms, a 1 takes ~250 ms — magnitude scales with distance
     (R19/R20). These numbers must be verified on the low-end
     reference device (D-14); see open question Q1.
  3. **Per-step feel (original execution of an adapted pattern):**
     each step is a small *hop*, not a slide — the token lifts
     (scale 1.0 → ~1.12, with a soft shadow growing under it) at the
     start of the step and settles (`outBack`-lite / `Curves.easeOut`)
     onto the next cell. The lift is what makes it read as a physical
     piece being moved rather than a dot sliding on glass. Keep the
     lift small: at 280 dp a cell is ~18.7 dp and the token radius is
     ~6.7 dp, so a 12% scale + 1–2 dp shadow is visible without
     obscuring neighbours.
  4. **Corners:** because the path follows cells, the token naturally
     turns at the track corners — no special-casing. The current
     straight hop visibly cuts the corner on the two-cell turns
     (e.g. track indices 5→6, 17→18); stepping fixes this for free.
  5. **Stacking:** when a token lands on an occupied cell, keep the
     existing horizontal fan (offset `cell * 0.4`), but add the
     flutter_ludo fan-out idea (R11): if 3+ tokens share a cell, fan
     them in a tiny 2×2 cluster instead of a horizontal line, so no
     token is pushed outside its cell. Painter-only.
  6. **Last-moved highlight (adapted from R11):** after a move
     settles, draw a short-lived (∼1.5 s, fading) teal ring under the
     moved token — the same amber/teal vocabulary as the legal ring,
     but thinner and non-pulsing, so "where did it just go" is
     answerable after an AI move at 700–1,199 ms pacing. Pass the last
     moved token id through the painter the way `legalTokenIds` is
     passed today.
  7. **Input locking stays:** input is already locked during the hop;
     keep it locked for the whole step sequence, and keep the engine
     state final throughout (R20's "resolve first, animate second" —
     DiceUp already does this; the animation must never be able to
     change the game, including if it is interrupted by pause).
  8. **Pause:** freeze mid-sequence exactly as the current hop freezes
     (stop the controller; destination is already the engine position).
     On resume, either resume the sequence or snap to the destination
     — snap is acceptable and simpler; see Q2.
- **What makes it feel satisfying vs cheap (synthesis):** satisfying =
  per-cell rhythm the eye can count (you can *see* a 6), a lift on
  each step, a settle on arrival, and a brief rest before the next
  turn. Cheap = one linear slide, constant speed, no settle, or a
  duration that does not scale with distance (a 1-step move taking as
  long as a 6).

### 2.3 Capture — a distinct return-to-base animation (original design, principle-informed)

- **Observed:** no source described a Ludo capture-return animation in
  implementable detail (see "Sources searched but not usable"). The
  genre fact is undisputed (R2/R3/R9: landing on an opponent sends it
  "back to its start" / "all the way back to its yard"), but *how* it
  is shown is DiceUp's to design.
- **DiceUp today:** the captured token snaps to the yard
  (`game_screen.dart` `_maybeStartHop` doc: "a capture's returning
  token snaps to the yard — its smooth return is the M3 capture
  animation"). The mover's hop also currently fires, so the two events
  can visually collide.
- **Adaptation (original):**
  1. **Sequence, don't overlap:** mover steps cell-by-cell (§2.2) and
     settles; *then* the captured token animates (∼150 ms beat so the
     eye registers cause → effect, R20's "stagger cause and effect").
  2. **Return path:** animate the captured token along the track
     backwards is too slow and reads as a second move. Instead: the
     token lifts, shrinks slightly (scale → ~0.7), fades to ~40%
     opacity, and travels in a gentle arc (ease-in-out, ∼450–550 ms)
     from its cell to its yard slot, then pops back in with a small
     `outBack` overshoot (scale 0.7 → 1.08 → 1.0 over ∼150 ms). The
     arc is the key: a straight line reads as a slide; an arc reads
     as "picked up and put back".
  3. **Feedback chorus (one haptic, one message):** the existing
     single light haptic on a completed move (D-32) should fire once
     for the capture as a whole, not once per token; the status line
     (already the illegal-tap channel) names the event —
     e.g. "<Name>'s token was captured" — in plain words, never colour
     alone. No sound (D-32). No screen shake (photosensitivity; §3).
  4. **Safe-cell guard is already visible:** because safe cells are
     amber + starred, a capture can never surprise the player as
     "unfair" — the board already explains why *this* cell was not
     safe. Do not add a separate "capture warning" UI.
- **Implementation shape:** a second painter override alongside
  `hopCenter` (e.g. `captureTokenId` + `captureCenter` + progress),
  driven by the same merged `Listenable`; engine state stays final.

### 2.4 Dice — wind-up, tumble, settle with a wobble (finish what exists)

- **Observed (R12–R14):** the state machine is idle → windup →
  loop → settle → jitter → landed; "180 ms wind-up the instant you
  tap Roll"; "no padded, fake pause — the moment your result is ready,
  they fall"; "one smooth accelerating descent… leaving only a short
  damped wobble"; reduced motion "skip the tumble entirely and simply
  show your numbers"; "values resolved before animation" (R13);
  "disable the roll trigger for the duration… only report the rolled
  number once the transition fires" (R14).
- **DiceUp today:** already does the hard parts — engine fixes the
  value on tap, the 540 ms tumble cycles faces 1–6, it settles on the
  engine value, input is locked, the dice is tappable with the same
  guards as the Roll button, semantics read "Dice, rolling" mid-tumble.
  What it lacks is the *physicality*: the dice only fades faces and
  dims (opacity 0.6); it does not move.
- **Adaptation (adapted):**
  1. **Wind-up (∼120–180 ms, adapted from R12):** on tap, before the
     face-cycling starts, the dice does a quick anticipatory dip —
     scale 1.0 → 0.92 and a tiny rotation (∼−6°) with `easeIn`. This
     is the "response within a frame" (R19): the player feels the tap
     land immediately, even though the value is not shown yet. Fold
     the wind-up into the existing 540 ms budget (wind-up + tumble +
     settle ≈ 540–600 ms total), do not add it on top — the AI pacing
     band (D-31) and the turn rhythm do not need a slower dice.
  2. **Tumble (existing 540 ms, keep):** keep face-cycling, but add a
     small physical shake to the *widget* while cycling — rotation
     jitter ±8° and translate jitter ±2 dp, driven by the same
     tumble controller (a `Transform.rotate` + `Transform.translate`
     around the existing `DiceWidget`, so the widget itself is
     untouched). This is R11's "dice shake" and R12's "tumble" in
     2D. Keep the jitter random-seeded per roll, never per frame in
     a way that could show the final face early: the displayed face
     during the tumble is the cycling face, the settled face is the
     engine value — exactly as today.
  3. **Settle (original execution):** on landing, one damped wobble —
     scale 1.06 → 1.0 with `Curves.elasticOut`-lite or two decaying
     scale keyframes over ∼180 ms — plus the shadow tightening under
     the dice. This is R12's "short damped wobble" and R15's
     `outBack`. Deliberately *not* a bounce (R12 dropped landing
     bounces by owner decision; DiceUp should too — a bounce reads
     as a ball, not a die).
  4. **Rollable affordance (adapted from R23):** when a roll is
     available, the dice already sits at full opacity with a "Tap to
     roll" tooltip. Add a slow, subtle animated border (teal, 1.5 dp,
     alpha oscillating 0.4 → 1.0 over ∼1.2 s — the same period as the
     legal-move pulse, so the two signals feel like one system) while
     `canRoll` is true. When not rollable, the dice stays dimmed
     (0.45) exactly as today. This mirrors the web Ludo pattern
     (R23: "dice-wrap.focused — container border animation") and
     gives the dice a visible "your turn" state that does not depend
     on reading the banner.
  5. **Keep:** 64 dp (56 dp on short screens, M2.12), pip layout,
     white face / navy pips, input lock, semantics labels, no sound.
- **Do not add:** a 3D cube (R12's implementation is a CSS 3D cube;
  in Flutter that means a new rendering path for one widget), dice
  skins / collectibles (R6, §3), a second die.

### 2.5 Turn / AI-thinking / invalid-action feedback — make the current seat visible on the board

- **Observed (R5, R23, R3):** per-player dice at each seat with the
  turn indicator moving between players; a dynamic arrow pointing at
  the current player's area; legal tokens "light up" / blink when
  selectable; the dice container animates when rollable. In Ludo King
  (R3) the eligible tokens light up and the player taps one.
- **DiceUp today:** a turn banner (avatar + name + status + a 20 dp
  spinner while `rolling`), player chips with "Home n/4", a one-shot
  1,200 ms amber pulse ring on legal tokens, SnackBar + status-line
  feedback for illegal taps with the reason named. This is good; the
  gap is that *nothing on the board itself* says whose turn it is —
  the banner is above the board and the chips are below it.
- **Adaptation (adapted):**
  1. **Current-seat yard glow (adapted):** give the current player's
     yard a subtle treatment — a 2 dp teal outline (or a soft outer
     glow in the player's colour at low alpha) around that yard only,
     drawn by the painter from `currentSeat` (already a painter
     input). This is the board-anchored equivalent of R5's moving
     turn indicator, and it survives the banner scrolling away. Use
     teal for the outline regardless of seat so the signal is "it's
     this seat's turn", not "this colour is special"; the yard's own
     colour already identifies the player.
  2. **AI thinking (adapted):** the 700–1,199 ms AI pacing (D-31) is
     already inside FR-40's band — do not shorten it to make the game
     feel faster. What the player needs during that window is proof
     the game has not stalled: keep the banner spinner, but add a
     three-dot "thinking" pulse *inside the current player's chip*
     (or next to their avatar in the banner) that animates while an
     AI turn is pending, and make the status line name the AI's action
     when it lands ("Adeel (AI) rolled 4" — the controller already
     knows this; it is a status-text change, not a new system).
     The thinking indicator must stop the moment the AI acts — a
     spinner that outlives its turn reads as a bug.
  3. **Legal-move pulse (refine, don't replace):** the one-shot
     1,200 ms pulse exists because a repeating controller broke
     `pumpAndSettle` in tests (see `game_screen.dart`). Keep the
     one-shot mechanism, but make the *resting* state more visible:
     the static amber ring (already drawn at pulse 0) plus a slight
     token lift (scale ~1.06) on legal tokens, so a legal token is
     recognisable even after the pulse has finished and the human is
     still thinking. If the test harness ever moves off
     `pumpAndSettle`, a slow repeating pulse (∼1.2 s period, alpha
     0.5 → 1.0) is the named revisit — not a change to make now.
  4. **Invalid action (adapted from R20/R23):** keep the SnackBar +
     status line (it names the reason — the best part of the current
     design). Add a *visual* echo on the thing that was tapped: a
     150 ms shake of the tapped token (translate ±1.5 dp, two
     oscillations, `Curves.easeInOut`) or, for the dice, the same
     shake on the dice widget. 150 ms is inside the "simple feedback
     ∼100 ms" band (R19) and is short enough to never feel like a
     delay. No haptic for illegal taps (already decided in code:
     haptics are for completed moves, D-32) and no red flash on the
     whole board — the feedback belongs to the tapped object.
  5. **No-legal-move pass:** when a roll has no legal move, the turn
     already passes automatically (engine). Say so in the status line
     ("No move possible — turn passes") for ∼1 s before the next
     turn's banner appears; otherwise the pass looks like a skipped
     turn. This is a status-text change only.

### 2.6 Results — a winner's moment, not a form (adapted + original)

- **Observed (R4, R6):** Ludo King marks the winner on the board
  with a gold crown + rank number over their yard, and its promo ends
  in a "'WINNER' celebration with confetti and trumpets". Ludo Star's
  collection reveal uses "falling confetti" (R6). The genre's win
  language is: crown, confetti, the winner's name large.
- **DiceUp today:** a clean, correct results screen (D-02): "<Name>
  wins!", large avatar (radius 36), an info card (mode, players,
  duration mm:ss, moves, finished date), a player card with a "Winner"
  label in teal, Play Again / Main Menu. It is informative but flat —
  it reads as a receipt, not a celebration.
- **Adaptation (adapted, with DiceUp's own marks — no crown copying):**
  1. **Winner hero (original):** keep the layout, but animate the
     entrance — the winner's avatar scales in from 0.8 → 1.0 with an
     `outBack` overshoot over ∼400 ms, and the "<Name> wins!" headline
     fades/slides up over ∼300 ms (M3 durations, R19). Stagger: name
     first, avatar second, cards third (∼80 ms stagger). This is
     standard M3 choreography, not Ludo King imitation.
  2. **DiceUp winner's mark (original — do NOT copy the crown):**
     Ludo King's crown is its brand. DiceUp's winner mark should be
     its own: a teal laurel-ish ring or a navy disc with the winner's
     shape marker enlarged, drawn around the winner's avatar — reusing
     the per-seat shape system (D-27) that already identifies players.
     Decide the exact mark with the coordinator (Q5); do not ship a
     crown.
  3. **Confetti (adapted):** a short (∼1.2 s) burst of small
     navy/teal/amber/player-colour rectangles falling from the top of
     the results screen, drawn by a tiny `CustomPainter` (no package
     — no `confetti` / Lottie dependency, §3) and gated by reduced
     motion (§2.7). It fires once on entry, never loops. This is the
     one place where "juice" is allowed to be visible rather than
     subtle, because the match is over and nothing is waiting on it.
  4. **Player rows (keep + one addition):** keep the per-player rows
     and the "Winner" label; add each player's tokens-home count
     ("Home 3/4") next to their name — the game screen's chips
     already show this, and on the results screen it is the only
     record of how close the losers were. This is data the
     `MatchResult` already carries (players + `tokensHome` is
     derivable from the finished state the controller holds at
     navigation time — verify at implementation; if it is not in
     `MatchResult`, that is a small model addition, not a redesign).
  5. **Keep:** Play Again reusing the exact setup (D-02), Main Menu
     to Home (D-30), the "couldn't be saved" warning card, the
     empty-state for a missing result. No ranking / 2nd–3rd places —
     continue-to-rank is deferred (D-02).

### 2.7 Transitions, responsive layout, accessibility — the professional baseline

- **Observed (R19, R21, R22, R15–R18):** M3 durations (enter
  225 ms / exit 195 ms / full-screen ≤375 ms, "exceed 400 ms may feel
  too slow"); duration scales with distance; no linear easing on
  position/scale; "every color-encoded signal must have a redundant
  shape or label"; 48 dp touch targets with ≥8 dp gaps; primary
  actions in the bottom 60–70% (thumb reach); reduced motion = replace
  slide/zoom with crossfade, shorten feedback to <100 ms, keep
  functional indicators; Flutter exposes *two* flags —
  `MediaQuery.disableAnimations` (Android "Remove animations") and
  `MediaQueryData.reduceMotion` (iOS Reduce Motion) — which must both
  be checked.
- **DiceUp today:** already strong here — 48 dp controls, 14 sp
  floor, shape + colour + name identity, full-cell token hit areas,
  board 280–480 dp clamp, short-screen compaction (M2.12), one
  semantics node for the board and one for the dice. The gaps are
  narrow and specific.
- **Adaptation (adapted):**
  1. **Reduced motion (the main gap — adapted from R22):** gate the
     new animations on `MediaQuery.disableAnimationsOf(context)` *and*
     `MediaQuery.of(context).reduceMotion`. When either is set: token
     steps become instant jumps (state is already final, so nothing
     breaks); the dice skips wind-up/tumble/shake and shows the
     settled face (R12's rule, verbatim); capture becomes a fade, not
     an arc; confetti does not fire; the legal ring stays static.
     Keep the *functional* feedback (status text, SnackBar, the
     thinking indicator) — R22: "keep essential feedback (progress
     indicator)". Note the API trap in R22: `disableAnimations` is
     read from the engine and cannot be overridden by wrapping a
     `MediaQuery`, so the screen must read it and branch explicitly,
     and the behaviour needs a widget test with animations disabled
     (not an assumption that `AnimationController` handles it).
     There is no in-app animation-speed setting yet; R20's Balatro
     lesson ("juice that can't be skipped becomes friction on the
     500th hand") supports adding one later — see Q7.
  2. **Transitions (adapted from R19):** the game → results
     navigation is already a route replacement; give it the M3
     treatment — results fades/slides in over ∼300 ms
     (emphasised-decelerate), and Play Again / Main Menu exits are
     shorter (∼200 ms). The pause dialog already uses the standard
     `AlertDialog` entrance; leave it alone. No custom page-route
     class is needed — `PageRouteBuilder` with a fade + slight slide
     is enough, and it is already the Flutter-idiomatic form.
  3. **Narrow widths (keep + verify):** the 320 dp floor (NFR-09) is
     already handled by the board clamp and M2.12 compaction. The
     research adds one check: at 320 dp the dice row (dice + Roll
     button) and the player chips `Wrap` must not overflow when a
     player name is 12 characters (D-28 cap) — the chips already
     ellipsize, but verify with the longest names at 320×568 rather
     than assuming. Also keep the Roll button in the bottom thumb
     zone (it already is, below the board — R21's 60–70% rule).
  4. **Depth/shadow tokens (original, small):** formalise the shadows
     DiceUp already uses ad hoc (dice `blur 6, offset (0, 3)`;
     card elevation 2) into two named values in the design system —
     e.g. `DiceUpShadows.raised` (board/dice) and
     `DiceUpShadows.lifted` (a token mid-hop) — so M3 polish does not
     invent a third shadow per widget. No new colours; shadows stay
     black at low alpha.
  5. **Typography (keep):** the 14 sp floor and the current scale
     (32/24/20/16/14) already meet the accessibility guidance (R21);
     the only addition is to use `titleMedium` (16 sp, w600) for the
     status line's *action* word if the status ever carries one
     ("Your turn — roll the dice"), so the instruction is scannable.
     Do not introduce a display font in M3 — the plan already notes a
     font can come later through `diceup_typography.dart` alone.

### 2.8 What the research says about DiceUp's existing architecture

- The CustomPainter board + widget UI split is the recommended
  architecture (R15's hybrid, R18's chessground migration). Keep it.
- No animation library is needed (R15: "Skip the animation
  libraries"; R17/R20 show `AnimationController` + tweens suffice).
  DiceUp's three controllers + painter overrides are the right shape;
  M3 adds *sequencing* on top of them, not a new framework.
- The engine-decides / animation-performs split (R20) is already
  DiceUp's rule. Every recommendation above preserves it: the painter
  overrides (`hopCenter`, and the proposed capture override) only move
  the *drawing*; the engine position is final throughout.
- The per-cell timing source (R17, ~90 ms/cell) and the M3 duration
  tokens (R19) give the implementer numbers to start from instead of
  guessing — but they are starting points to tune on the reference
  device (D-14), not constants to hard-code without playing.

---

## 3. Patterns explicitly NOT adopted (and why)

| Pattern | Source | Why not |
|---|---|---|
| Ludo King themes (Disco/Night, Egypt, Candy…), dice/coin/diamond economy, daily goals, seasons, Adda/clubs, chat, 5–6 player and 8-player tournament modes, Snakes and Ladders | R1, R6 | Monetisation/social/online scope. DiceUp M3 is the offline game (M1–M4 brief); these would add assets, servers, and moderation. The classic board is the only thing taken from Ludo King. |
| Ludo Star collectible/fusion dice skins | R6 | Same reason: a collection/monetisation system. The dice stays one white pip die; its *animation* is improved instead (§2.4). |
| The crown as winner's mark; Ludo King wordmark, gold-on-dark branding, dice-motif background | R4 | Proprietary branding. DiceUp's winner mark must be its own (§2.6, Q5). The navy/teal/amber identity is kept. |
| 3D dice cube (real 3D tumbling cube) | R12 | A 3D rendering path for one 64 dp widget, on a low-end reference device (D-14, 4 GB RAM). The 2D wind-up + shake + settle (§2.4) delivers the feel at a fraction of the cost. Revisit only if a 3D board is ever commissioned. |
| `flutter_ludo` package (whole game) | R11 | DiceUp already has its own engine, controller, Riverpod composition root, persistence, and tests. Adopting the package would duplicate the engine and discard the M1–M3 investment. Only its *patterns* (step-by-step, last-moved highlight, fan-out) are adopted. |
| Animation libraries (GSAP, anime.js, Framer Motion, `flutter_animate`, Lottie/`confetti` packages) | R15, R22 | No new dependencies. Board games have "discrete, infrequent animations" (R15); `AnimationController` + `CustomPainter` already do the job, and every added package is a low-end-device and maintenance cost. Confetti is hand-drawn (§2.6). |
| Screen shake on capture / big impacts | R20 (game-feel sources list it) | Photosensitivity / vestibular risk (R21/R22: reduced-motion must kill shake). A token-scale + arc + haptic sells the impact without moving the whole frame. |
| Linear 100 ms pawn slides | R23 | Linear motion on position violates the M3 rule (R19: "No linear easing on any animation of position, scale, or size"). DiceUp already uses `Curves.easeOut`; per-cell steps use `outCubic`/`outBack` (§2.2). |
| Wooden / textured board skin; board-skin chooser | R7, R8 | Texture assets + a skin system for a look DiceUp's flat identity already beats on legibility. Flat + shadow (§2.1) is the premium direction here. |
| Sound effects for dice / capture / win | R5, R6 (videos imply dice sounds) | D-32: sound is a named follow-up, not in M3. Haptics + visual feedback carry the feel until sound is designed. Do not add a sound toggle that does nothing. |
| Blockade rule, "3×1 kills a coin", "3×6 brings a coin out", release-on-1 variants | R8, R10 | Ruleset variants outside the decided defaults (D-16) and the curated setup subset (D-29). The board research does not change the rules. |
| Auto-move when only one legal move exists | R11 (`autoMoveSingleChoice` option) | Not observed as a universal genre default, and it removes the player's only decision in the common single-move case. DiceUp keeps tap-to-move; if the coordinator wants it, it is a product decision (Q3), not a research conclusion. |
| Dark theme (as a board-game default) | R11 | DiceUp's light theme is the Phase 2 baseline and the dark theme is a separate, later piece of work (see `diceup_theme.dart`). M3 polish should not silently re-theme the game. |
| "Ghost destination" preview (show where a tapped token would land before confirming) | R16 | Attractive, but it adds a second interaction step (preview → confirm) to a game whose current contract is tap-token-to-move. Worth a product decision (Q4), not an adoption by default. |
| Move hints (`suggestMove()`) | R11 | A hint system is a feature (AI explaining its pick), not polish. It would also need a decision about whether hints are shown unprompted. Out of M3 scope; note for a later milestone. |
| Real-money / gambling-adjacent features | R1 search comments (spam for Teen Patti apps around Ludo King) | Out of scope and off-brand. Noted only because the research surfaced it: DiceUp must not accept gambling-adjacent monetisation. |

---

## 4. Open questions for the coordinator

Do NOT treat these as decided. Each needs a product decision before
implementation.

1. **Q1 — Per-cell step timing.** Starting point proposed: ~110 ms per
   cell, cap ~600 ms total, min ~250 ms (§2.2). Is that the right
   budget, or should a 6-step move be allowed up to ~900 ms (6 ×
   150 ms) for a more deliberate feel? Who tunes it — implementer by
   play on the reference device (D-14), or a fixed number from the
   coordinator? (Affects the highest-priority M3 item.)
2. **Q2 — Pause mid-sequence.** If the player pauses during a
   multi-cell step sequence or a capture arc, should resume continue
   the animation from where it froze, or snap to the final engine
   position? (Snap is simpler and already the hop's behaviour; resume
   is smoother but needs the sequence state to survive the pause.)
3. **Q3 — Single legal move.** When a roll leaves exactly one legal
   move, should tapping be required (today), or should the token move
   automatically after a short beat (~300 ms) so the player can watch
   rather than tap? (flutter_ludo offers this as an option; the genre
   is split. Auto-move speeds up AI-adjacent turns but removes agency.)
4. **Q4 — Destination preview.** Should tapping a legal token first
   show a ghost/highlight on its destination cell, with a second tap
   (or the same tap) confirming — or keep single-tap-to-move? (R16's
   "ghost destination" pattern; changes the tap contract, so it needs
   a decision, not an implementation assumption.)
5. **Q5 — Winner's mark.** Ludo King's crown is off-limits (§3).
   What is DiceUp's winner mark: an enlarged per-seat shape marker in
   a teal ring around the avatar (§2.6), a navy disc, or something
   else? And is confetti on the results screen wanted at all, or is
   it too noisy for DiceUp's restrained identity?
6. **Q6 — Capture arc vs. fade.** Is the proposed capture animation
   (lift → shrink/fade → arc to yard → pop-in, §2.3) the right weight,
   or should a capture be quieter (fade out at the cell, fade in at
   the yard) so it never upstages the mover's step sequence? (Also:
   should the *mover* get any extra emphasis on a capturing move —
   e.g. a slightly larger settle — or is the status text enough?)
7. **Q7 — Animation-speed setting.** Balatro's lesson (R20) is that
   juice needs a dial. Should M3 add an in-app "Animation: Full /
   Reduced" setting (in addition to honouring the OS reduced-motion
   flags, §2.7), or is the OS setting sufficient for now? (Affects
   settings-screen scope; the persisted-settings machinery from M1.3
   already exists.)
8. **Q8 — Last-moved highlight + "Home n/4" on results.** Is the
   teal last-moved ring (§2.2) wanted, and should the results screen
   show each player's tokens-home count (§2.6)? The second depends on
   whether `MatchResult` already carries per-player home counts — if
   not, is a small model addition acceptable in M3?
9. **Q9 — Direction chevrons + reachable-safe-cell outline (§2.1).**
   Are these wanted, or is the board already busy enough at 280 dp?
   (At minimum board size a cell is ~18.7 dp; a chevron + star +
   token in one cell risks clutter. A device check at 320×568 would
   settle it.)
10. **Q10 — AI thinking indicator style.** Banner spinner (today) vs.
    three-dot pulse in the player's chip vs. both (§2.5)? And should
    the status line narrate AI actions ("Adeel (AI) rolled 4, moved
    …") or stay minimal ("Adeel (AI) is thinking…")? (Narration helps
    the player follow fast AI turns at 700–1,199 ms, but it is more
    text to maintain.)

---

## Appendix — How this maps to the M3 brief (§4 premium work)

| Brief item | Covered here |
|---|---|
| Per-cell token movement (highest priority) | §2.2 — step-by-step, ~110 ms/cell, hop-per-step, corners free, stacking fan-out, last-moved highlight |
| Capture animation (smooth return to base) | §2.3 — sequenced after the mover, arc + shrink/fade + pop-in, one haptic, status text |
| Dice animation (correct final value, input locking) | §2.4 — wind-up, tumble + shake, damped settle wobble, rollable border, keep 540 ms budget and locks |
| Feedback (turn / AI / invalid / win) | §2.5, §2.6 — seat glow, AI thinking indicator, no-move pass text, illegal-tap shake, results celebration |
| All screens | §2.6 (results), §2.7 (transitions, narrow widths, typography) — home / setup / history / statistics screens were not the focus of this research; their polish follows the same tokens |
| Online research, no copying | §1 (23 references, method note, unusable sources) and §3 (explicit rejections) |
| Hard constraints respected | 48 dp controls / token exemption (D-09), shape+colour+name identity (D-27), 320 dp floor (M2.12), no sound (D-32), AI 700–1,199 ms (D-31), no new dependencies unless justified (none justified) |

*End of research. No code changed.*

---

## Coordinator decisions on §4 open questions (2026-11-22, M3 resume)

Decided by the coordinator within the approved scope (design details only —
no rule, schema, or product-decision changes). Animation workers: implement
these as specified.

- **Q1 — Per-cell timing: ~110 ms/cell, cap ~600 ms.** As proposed in §2.2.
  A 6 reads as six countable steps; corners turn naturally.
- **Q2 — Pause mid-sequence: freeze, then resume.** Pause is a freeze (D-10):
  the animation sequence freezes in place and resumes from where it paused.
  No snap-to-final on pause.
- **Q3 — Auto-move on a single legal move: NO.** The player must tap. Keep
  input explicit; do not remove agency.
- **Q4 — Destination preview: NO ghost in this phase.** Single-tap-to-move
  stays. A ghost preview is a follow-up, not M3 scope.
- **Q5 — Winner's mark: enlarged per-seat shape marker in a teal ring
  around the avatar (§2.6). Confetti: YES** — one-shot, hand-drawn,
  restrained, no new package.
- **Q6 — Capture: the arc as proposed (§2.3).** Lift → shrink/fade → arc to
  yard → pop-in. The mover gets a slightly larger settle on a capturing
  move (small emphasis only — it must not upstage the step sequence).
- **Q7 — Animation-speed setting: NO new in-app setting this phase.** The
  OS reduced-motion flags (both `disableAnimations` and `reduceMotion`)
  are sufficient; honour them everywhere. A custom speed dial is a
  follow-up.
- **Q8 — "Home n/4" counts on results: YES.** A small `MatchResult`
  addition is acceptable (display data derived from the final state, no
  schema change). Last-moved ring on the results screen: NO (the match
  is over); the in-game last-moved ring (§2.2) stays.
- **Q9 — Direction chevrons: NO. Reachable-safe-cell outline: NO.** The
  board is busy enough at 280 dp; safe cells already carry stars.
  Follow-up only if user feedback asks.
- **Q10 — AI thinking: three-dot pulse in the player's chip** (replaces the
  banner spinner as the primary indicator) **+ status line narrates AI
  actions** ("Green (AI) rolled 4, moved …"). Narration helps the player
  follow fast AI turns at 700–1,199 ms (D-31).
