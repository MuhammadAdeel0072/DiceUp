/**
 * Player colours in DiceUp (mirrors Dart `player_colour.dart`).
 *
 * SDD §6.2: four colours, one per player. The SRS does not name the
 * colours, so the SDD's proposed defaults (red, green, yellow, blue)
 * are used here.
 */
export const PLAYER_COLOURS = ['red', 'green', 'yellow', 'blue'] as const;

export type PlayerColour = (typeof PLAYER_COLOURS)[number];

export function isPlayerColour(value: unknown): value is PlayerColour {
  return (
    typeof value === 'string' &&
    (PLAYER_COLOURS as readonly string[]).includes(value)
  );
}
