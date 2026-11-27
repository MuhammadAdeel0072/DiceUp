import 'dart:math';

/// Dice source. Injectable so tests can feed a fixed sequence while
/// production uses a uniform random source (SRS FR-15, SDD §6.4).
/// The AI and the UI never roll dice themselves — only the engine,
/// through a [DiceRoller], does.
abstract class DiceRoller {
  /// Returns a uniform integer in 1..6 (BR-02).
  int roll();
}

/// Production dice: uniform 1..6 from [Random].
/// Offline results are unranked, so no fairness proof is required
/// (SRS §7.3); the server uses a cryptographically secure RNG online.
class RandomDiceRoller implements DiceRoller {
  RandomDiceRoller([Random? random]) : _random = random ?? Random();

  final Random _random;

  /// Seeded roller: a fixed seed replays the same dice sequence,
  /// which is how AI regressions are bisected (SDD §7.4).
  factory RandomDiceRoller.seeded(int seed) => RandomDiceRoller(Random(seed));

  @override
  int roll() => _random.nextInt(6) + 1;
}

/// Test dice: returns a predetermined sequence of values.
class FixedDiceRoller implements DiceRoller {
  FixedDiceRoller(List<int> values, {this.cycle = false})
    : _values = List.unmodifiable(values) {
    if (_values.isEmpty) {
      throw ArgumentError('FixedDiceRoller needs at least one value.');
    }
    for (final value in _values) {
      if (value < 1 || value > 6) {
        throw ArgumentError('Dice values must be in 1..6, got $value.');
      }
    }
  }

  final List<int> _values;

  /// When true, the sequence repeats from the start instead of
  /// throwing once exhausted (handy for long AI simulations).
  final bool cycle;

  int _position = 0;

  @override
  int roll() {
    if (_position >= _values.length) {
      if (!cycle) {
        throw StateError('FixedDiceRoller sequence exhausted.');
      }
      _position = 0;
    }
    return _values[_position++];
  }
}
