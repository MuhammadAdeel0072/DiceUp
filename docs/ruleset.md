# DiceUp — Shared Ruleset

**Status:** the single language-neutral rule specification for DiceUp
(SDD §6.9, NFR-39). The Dart offline engine and the future TypeScript
online engine must both pass the shared test vectors in
`diceup_app/test/vectors/rules.json` against this document. A vector
that passes in one language and fails in the other fails the build.

**Sources:** SDD v1.0 §6.2 (Table 6.2), §6.4, §6.5, §6.9; SRS v0.1
§7.1 (board geometry), §7.2 (rule catalog BR-01…BR-14), §7.4
(ruleset configuration). Both source documents are unapproved
drafts; where they disagree with the engine, §5 records the
disagreement and the engine wins — nothing here is silently resolved.

**Decisions pinned by this document:**

- **D-05** — two rule implementations (Dart + TypeScript) kept
  consistent by the shared vectors; the vector suite is the control.
- **D-16** — the SDD §6.2 defaults below are the approved rule set
  (release on 6, extra turn on 6 / capture / home, third six not
  played, exact finish, first to 4 home wins). They close SRS OD-02.
- **D-20** — the track/home split is **51 track + 4 home-path + home
  = 56 steps**. The SDD/SRS wording "5 home-path cells" is an
  approved deviation, not the rule (see §5.1).
- **D-15** — safe cells are track indices **{0, 8, 13, 21, 26, 34, 39,
  47}** (4 start cells + 4 star cells).

**Ruleset version: `1.0.0`** (BR-14). The version is frozen at match
start, stored with the match, and a ruleset change is a new version,
never an edit. The Dart `RulesetConfig` default `version` is
`'1.0.0'`; every vector states its ruleset in full.

## 1. Board geometry (SRS §7.1, SDD §6.2, assumption A-03)

- A cross-shaped board with a **shared outer track of 52 cells**
  (track indices 0…51), four yards (one per colour), and four home
  paths, one per colour.
- Colours are red, green, yellow, blue (the SRS does not name
  colours; these are the SDD's proposed defaults).
- **Start cells** are 13 apart: red 0, green 13, yellow 26,
  blue 39. A released token is placed on its own colour's start cell.
- **Star cells** sit 8 steps after each start: 8, 21, 34, 47.
- **Safe cells** are the 4 start cells + the 4 star cells = **8 in
  total: {0, 8, 13, 21, 26, 34, 39, 47}** (BR-09, D-15). Tokens on
  safe cells cannot be captured; tokens of different colours may
  share a safe cell.
- Each player has **4 tokens**, starting in the yard.
- A token's journey from its start cell to home is **56 steps**
  (D-20): step 0 is the yard, step 1 is the token's start cell,
  steps 1…51 are the outer track, steps 52…55 are the token's own
  home path (home-path indices 0…3), step 56 is home.
- A token travels clockwise along the outer track, then into its own
  home path. Only the owner may enter its home path.

Step map (for a token of any colour; the track index is
`(startCell + stepsTaken − 1) mod 52` while on the track):

| stepsTaken | Position |
|---|---|
| 0 | Yard |
| 1 | Own start cell |
| 2…51 | Outer track |
| 52…55 | Own home path, indices 0…3 |
| 56 | Home |

## 2. Rules (SDD Table 6.2, reproduced faithfully)

| Rule | SRS | Default in this design | Configurable? |
|---|---|---|---|
| Players / tokens | BR-01 | 2–4 players, distinct colours, 4 tokens each, ≥ 1 human | No (player count is a setup choice, not a rule variant) |
| Dice | BR-02 | Uniform 1–6 | No |
| Turn order | BR-03 | Clockwise, fixed seat order; roll only on your own turn | No |
| Token release | BR-04 | Yard → start cell only on a 6 | Yes — also on 1 (variant) |
| Movement | BR-05 | Advance exactly the roll; must move if a legal move exists; may pass over tokens | Passing: blockade variant |
| Extra turn | BR-06 | After a 6, a capture, or a token reaching home | Yes — each trigger can be disabled |
| Consecutive sixes | BR-07 | Third consecutive six is not played; turn passes | Yes — limit or off |
| Capture | BR-08 | Landing on a non-safe cell sends opponent token(s) there to their yard | Multi-token cell handling |
| Safe cells | BR-09 | 8 safe cells; different colours may share one | Positions |
| Home path / finish | BR-10 | Own tokens only; exact roll required to reach home | Exact roll |
| Winning | BR-11 | First player with all 4 tokens home wins; match ends | Yes — continue to rank 2nd/3rd |
| Own-token stacking | BR-12 | Same-colour tokens may share a cell; no blockade by default | Yes — blockade on/off |
| No legal move | BR-13 | Turn passes; a rolled 6 still grants its extra roll (SRS assumption) | Yes |
| Ruleset versioning | BR-14 | Frozen at match start; stored with the match | No |

Detail per rule (SRS §7.2 + SDD §6.5):

- **BR-01** — a match has 2–4 players with distinct colours; each
  has 4 tokens; a match shall contain at least one human.
- **BR-02** — a die yields an integer 1–6 with equal probability.
  Offline it is generated on-device; online by the server only.
- **BR-03** — players act clockwise in fixed seat order; a player
  may roll only on their own turn, once per roll opportunity.
- **BR-04** — a token leaves the yard only on a roll of 6 and is
  placed on its start cell. Variant: also on a roll of 1.
- **BR-05** — a moving token advances exactly the rolled number of
  steps along its path, never backwards. If at least one legal move
  exists the player must move one token; if several exist the player
  chooses. Tokens may pass over other tokens. (No blockade variant
  is implemented: same-colour tokens may stack, BR-12.)
- **BR-06** — a player rolls again after: a roll of 6, capturing an
  opponent token, or moving a token to home. Each trigger can be
  disabled independently.
- **BR-07** — a third consecutive six in one turn sequence is not
  played and the turn passes to the next player. The limit can be
  changed or switched off (`maxConsecutiveSixes: 0` disables it).
- **BR-08** — a token landing on a non-safe cell occupied by
  opponent token(s) sends those tokens to their yards. All opponent
  tokens on the landing cell are captured, not just one. Passing
  over tokens never captures.
- **BR-09** — tokens on safe cells cannot be captured; tokens of
  different colours may share a safe cell.
- **BR-10** — only a token's owner may enter its home path. A token
  reaches home only with an exact roll; a roll larger than the
  remaining distance makes that token's move illegal. Variant: with
  exact finish off, an overshooting roll still lands the token home.
- **BR-11** — the first player to bring all four tokens home wins
  and the match ends. (Continue-to-rank 2nd/3rd has no mechanics
  and is not implemented; the match ends at the first win.)
- **BR-12** — tokens of the same colour may share a cell. No
  blockade effect by default.
- **BR-13** — if a roll gives no legal move the turn passes, except
  that a rolled six still grants its extra roll (SRS assumption).
- **BR-14** — the ruleset is chosen and fixed before a match starts
  and shall not change during it.

Legal moves (SDD §6.5, FR-16): a token can move if it is in the
yard and the roll is a release roll (BR-04), or it is on the
track/home path and `stepsTaken + roll ≤ 56` with exact finish
enforced (BR-10). A move is applied atomically: advance the token,
resolve captures on the landing cell, enter the home path, reach
home, or win — and the result reports exactly what happened
(captures, extra turn, winner). An illegal move is rejected with
the state unchanged (FR-21).

## 3. The approved defaults as a `RulesetConfig`

These are the D-16 defaults (the `RulesetConfig` constructor
defaults, version `1.0.0`):

```json
{
  "releaseOnSix": true,
  "releaseOnOne": false,
  "extraTurnOnSix": true,
  "extraTurnOnCapture": true,
  "extraTurnOnHome": true,
  "maxConsecutiveSixes": 3,
  "exactFinish": true,
  "version": "1.0.0"
}
```

Variants available as configuration (not defaults): release on 1,
each extra-turn trigger disabled, `maxConsecutiveSixes: 0` (limit
off) or another limit, `exactFinish: false`. Changing a default is
a configuration change (a new `RulesetConfig` version), never a
code change.

## 4. Worked examples

All examples use the default ruleset (`1.0.0`) unless stated
otherwise. Steps are `stepsTaken` as in §1.

### 4.1 Release on six — and only on six (BR-04, BR-13)

Red has all four tokens in the yard. Red rolls 3: no token can
move (3 is not a release roll), so the turn passes to the next
player. Red rolls 6 instead: all four yard tokens are legal moves;
Red moves one to its start cell (step 1, track 0) and, because a 6
was rolled, rolls again (BR-06).

### 4.2 Third consecutive six is not played (BR-07)

Red has already rolled two sixes in this turn sequence
(`consecutiveSixes: 2`). Red rolls a third 6: the roll is shown,
no move is offered — even though Red has tokens that could move —
and the turn passes to the next player. The sixes counter resets
to 0 for the next player. With the limit disabled
(`maxConsecutiveSixes: 0`) the third 6 is an ordinary roll: yard
tokens may be released and the counter keeps counting.

### 4.3 Capture — and no capture on a safe cell (BR-08, BR-09)

Green's token sits at step 10, which is track
`(13 + 10 − 1) = 22` — not a safe cell. Red's token sits at step
20 (track 19). Red rolls 3 and moves to step 23 (track 22):
Green's token is sent back to its yard, and Red rolls again
(BR-06, capture trigger).

If instead Green's token sits on its start cell (step 1, track
13 — a safe cell) and Red lands on track 13 (step 14), no capture
happens: both tokens share track 13, and Red does not get an
extra turn for it. The same holds on a star cell: track 8 is safe,
so a token landing there never captures.

Two opponent tokens on one non-safe cell are both captured by a
single landing token. Passing over a token never captures it: Red
moving from step 18 to step 23 passes over track 20…22 and lands
on track 22; a Green token on track 23 is untouched.

### 4.4 Exact finish (BR-10)

Red's token sits at step 54 (two steps from home). Red rolls 3:
54 + 3 = 57 > 56, so that token has no legal move. If another Red
token can move, Red must move that one; if no Red token can move,
the turn passes (a 6 would still grant its extra roll, BR-13).
Red rolls 2 instead: 54 + 2 = 56, the token reaches home and Red
rolls again (BR-06, home trigger). With `exactFinish: false`, the
roll of 3 would land the token home anyway (overshoot lands home).

### 4.5 Home-path entry and winning (BR-10, BR-11)

Red's token sits at step 50 (track 49). Red rolls 3: 50 + 3 = 53,
which is home-path index 1 (steps 52…55 map to indices 0…3).
The token has entered its home path; it can no longer be captured
(home-path cells belong to one owner only).

Red has three tokens home (step 56 each) and the fourth at step
53. Red rolls 3: the fourth token reaches step 56, all four Red
tokens are home, Red wins and the match ends immediately — no
further rolls or moves are possible.

## 5. Where the sources disagree — the engine wins

The engine is correct (remediation plan §2, §5); these
disagreements are recorded here, not silently resolved. In every
case the vector suite encodes the engine behaviour.

### 5.1 Home-path split: 5 cells (SDD/SRS) vs 4 cells (engine, D-20)

SDD §6.2 says "four home paths of 5 coloured cells each plus a
home cell" and "home-path index 0…5"; SRS §7.1 says a token travels
"into its own home path (5 coloured cells) ending at the home
cell". On the literal reading that is 50 track + 5 home-path + home.
The engine implements **51 track + 4 home-path + home = 56**
(steps 52…55 are home-path indices 0…3; step 56 is home), and
D-20 pins that split as approved by Anti. The SDD/SRS wording is
the error; the SDD text is amended at re-issue. The vectors encode
51+4+1 — including a home-path entry case landing on step 53
(home-path index 1) and exact-finish cases at steps 54–56.

### 5.2 Winning is BR-11, not BR-25 (SDD §6.5 citation error)

SDD §6.5 says a player wins when all four tokens are home and
cites "(BR-25, FR-25)". No BR-25 exists: the SRS rule catalog runs
BR-01…BR-20, and winning is **BR-11**. The engine implements
BR-11 (first player with all four tokens home wins; the match
ends). The citation is an SDD error.

### 5.3 Yard release lands on step 1, not step 6 (SDD §6.5 pseudocode)

SDD §6.5 Algorithm 1 writes `t.stepsTaken += s.lastRoll` for every
move, which for a yard release on a 6 would land the token on step
6. The engine releases a yard token to **step 1** (its start cell),
spending the roll on entering the board (BR-04); any other move
advances by exactly the roll (BR-05). The pseudocode is imprecise;
the engine is right.

### 5.4 The Table 6.2 caption

The rules table in SDD §6.2 is uncaptioned in the SDD text: other
SDD passages call it "Table 6.1", and `RulesetConfig`'s doc comment
cites it a third way ("Table §6.2"). This document reproduces it
as **Table 6.2** (its section number), matching the remediation
plan. Naming only; no rule is affected.

### 5.5 No MOVING phase in the engine (SDD §6.4)

SDD §6.4 describes the turn machine as
`AWAITING_ROLL → ROLLED → AWAITING_MOVE → MOVING → TURN_END`.
The engine has three phases — `awaitingRoll`, `awaitingMove`,
`finished` — and no MOVING phase: movement animation is a
presentation concern (SDD §6.7) that never changes engine state.
No behavioural effect; the vectors use the engine's three phases.

### 5.6 Third-six precedence is engine-defined

The SDD does not state what wins when the third consecutive six
also offers legal moves (remediation plan M-17). The engine
checks the third six **before** computing legal moves: a third six
is shown but never played, even if tokens could move. The vectors
pin this precedence.

### 5.7 Safe-cell indices are engine-pinned (D-15)

SDD §6.2 and SRS §7.1 define safe cells only as "the 4 start
cells + 4 star cells (default positions)" and name no indices.
The engine pins the conventional layout — starts {0, 13, 26, 39},
stars {8, 21, 34, 47}, safe set {0, 8, 13, 21, 26, 34, 39, 47} —
and D-15 confirms it. The vectors pin the indices, including a
no-capture case on a start cell (track 13) and one on a star cell
(track 8).

### 5.8 Forfeit (BR-15) has no engine vector

SDD §6.9 lists forfeit among the vector edge cases, but offline
forfeit is forfeit-by-exit (SDD §6.3): leaving an unfinished match
ends it by confirmation (FR-28); there is no in-engine forfeit
transition for a vector to replay, and `LudoGame` exposes no
forfeit operation. BR-15's token-removal / loss-recording /
match-continues mechanics are online rules (the TypeScript engine's
scope). No forfeit vector exists in this suite; the omission is
deliberate and recorded here, not a gap in the Dart coverage.

## 6. The vector suite

- **Vectors:** `diceup_app/test/vectors/rules.json` — one case per
  rule family, each self-contained: a starting snapshot (strict
  `GameState` JSON), a fixed dice sequence (`FixedDiceRoller`), and
  the expected legal moves + outcome after each replayed roll/move.
  Every case states its ruleset in full; the runner passes it
  explicitly to `LudoGame.fromState` (the engine does not infer the
  ruleset from the snapshot).
- **Runner:** `diceup_app/test/vectors/rules_vectors_test.dart` —
  loads `rules.json`, replays each case through `LudoGame.fromState`
  + `rollDice` / `legalMoves` / `applyMove`, and asserts the expected
  legal moves and outcome. A vector that fails fails the build: no
  silent skips, no lenient matching. The runner also validates the
  vector file's shape — unknown fields or cases fail loudly.
- **Adding a case:** copy an existing case, give it a new `id`,
  state the full ruleset, and hand-compute every expectation from
  this document (especially the step→track arithmetic in §1). A new
  ruleset version requires new vectors before it can ship (BR-14).
- **CI:** the `vectors` job in `.github/workflows/ci.yml` runs
  `flutter test test/vectors/rules_vectors_test.dart`. The workflow
  file is staged locally and unpushed: pushing it needs the
  Workflows: Read and write permission on the GitHub App
  installation, which is still missing (the push 403s). Until that
  is fixed, `flutter test` (full suite, which includes the vector
  runner) is the gate, run locally via `tool/check.sh`.

## 7. References

- SDD v1.0 §6.2 (Table 6.2), §6.4, §6.5, §6.9; SRS v0.1 §7.1, §7.2,
  §7.4.
- Remediation plan §3.1 H-06, §3.2 M-17, §4 M3.6, §5 D-05/D-15/D-16/
  D-20, §6 verification (vectors row).
- Engine: `diceup_app/lib/domain/engine/ludo_game.dart`,
  `board.dart`, `token.dart`, `ruleset_config.dart`,
  `game_state.dart`, `move.dart`, `dice_roller.dart`.
