/// Player colours in DiceUp.
///
/// SDD §6.2: four colours, one per player. The SRS does not name the
/// colours, so the SDD's proposed defaults (red, green, yellow, blue)
/// are used here.
enum PlayerColour { red, green, yellow, blue }

extension PlayerColourLabel on PlayerColour {
  /// Lower-case name used in JSON snapshots and logs.
  String get label => name;
}
