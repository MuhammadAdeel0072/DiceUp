/// A versioned, frozen set of Ludo rule options.
///
/// SDD §6.2 (Table §6.2) and SRS BR-04..BR-14. The config is chosen at
/// setup, validated once, and frozen for the whole match (BR-14): a
/// [LudoGame] never mutates its ruleset after construction.
///
/// Defaults below are the SDD Table §6.2 defaults. They are proposals
/// pending stakeholder approval (SRS OD-02); changing a default is a
/// configuration change (a new [version]), never a code change.
class RulesetConfig {
  const RulesetConfig({
    this.releaseOnSix = true,
    this.releaseOnOne = false,
    this.extraTurnOnSix = true,
    this.extraTurnOnCapture = true,
    this.extraTurnOnHome = true,
    this.maxConsecutiveSixes = 3,
    this.exactFinish = true,
    this.version = '1.0.0',
  });

  /// A token leaves the yard on a roll of 6 (BR-04, default).
  final bool releaseOnSix;

  /// Variant: a token also leaves the yard on a roll of 1 (BR-04).
  final bool releaseOnOne;

  /// Rolling a 6 grants another roll (BR-06).
  final bool extraTurnOnSix;

  /// Capturing an opponent token grants another roll (BR-06).
  final bool extraTurnOnCapture;

  /// Moving a token home grants another roll (BR-06).
  final bool extraTurnOnHome;

  /// Consecutive sixes in one turn sequence after which the roll is not
  /// played and the turn passes (BR-07). `0` disables the limit.
  final int maxConsecutiveSixes;

  /// A token reaches home only with an exact roll; an overshooting roll
  /// makes that token's move illegal (BR-10). When false, an overshoot
  /// still lands the token home (variant behaviour).
  final bool exactFinish;

  /// Ruleset version, stored with every match so a match can always be
  /// replayed under the rules it used (BR-14).
  final String version;

  /// Rolls that release a token from the yard.
  Set<int> get releaseRolls {
    final rolls = <int>{};
    if (releaseOnSix) rolls.add(6);
    if (releaseOnOne) rolls.add(1);
    return rolls;
  }

  /// Throws [InvalidRulesetConfig] if the configuration is incoherent.
  void validate() {
    if (!releaseOnSix && !releaseOnOne) {
      throw const InvalidRulesetConfig(
        'At least one release roll must be enabled.',
      );
    }
    if (maxConsecutiveSixes < 0) {
      throw const InvalidRulesetConfig(
        'maxConsecutiveSixes must be 0 (off) or positive.',
      );
    }
    if (version.isEmpty) {
      throw const InvalidRulesetConfig('version must not be empty.');
    }
  }

  Map<String, Object> toJson() => {
        'releaseOnSix': releaseOnSix,
        'releaseOnOne': releaseOnOne,
        'extraTurnOnSix': extraTurnOnSix,
        'extraTurnOnCapture': extraTurnOnCapture,
        'extraTurnOnHome': extraTurnOnHome,
        'maxConsecutiveSixes': maxConsecutiveSixes,
        'exactFinish': exactFinish,
        'version': version,
      };

  factory RulesetConfig.fromJson(Map<String, Object?> json) {
    return RulesetConfig(
      releaseOnSix: json['releaseOnSix'] as bool? ?? true,
      releaseOnOne: json['releaseOnOne'] as bool? ?? false,
      extraTurnOnSix: json['extraTurnOnSix'] as bool? ?? true,
      extraTurnOnCapture: json['extraTurnOnCapture'] as bool? ?? true,
      extraTurnOnHome: json['extraTurnOnHome'] as bool? ?? true,
      maxConsecutiveSixes: json['maxConsecutiveSixes'] as int? ?? 3,
      exactFinish: json['exactFinish'] as bool? ?? true,
      version: json['version'] as String? ?? '1.0.0',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RulesetConfig &&
      releaseOnSix == other.releaseOnSix &&
      releaseOnOne == other.releaseOnOne &&
      extraTurnOnSix == other.extraTurnOnSix &&
      extraTurnOnCapture == other.extraTurnOnCapture &&
      extraTurnOnHome == other.extraTurnOnHome &&
      maxConsecutiveSixes == other.maxConsecutiveSixes &&
      exactFinish == other.exactFinish &&
      version == other.version;

  @override
  int get hashCode => Object.hash(
        releaseOnSix,
        releaseOnOne,
        extraTurnOnSix,
        extraTurnOnCapture,
        extraTurnOnHome,
        maxConsecutiveSixes,
        exactFinish,
        version,
      );
}

/// Thrown when a [RulesetConfig] fails [RulesetConfig.validate].
class InvalidRulesetConfig implements Exception {
  const InvalidRulesetConfig(this.message);
  final String message;
  @override
  String toString() => 'InvalidRulesetConfig: $message';
}
