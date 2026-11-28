/**
 * A versioned, frozen set of Ludo rule options (mirrors Dart
 * `ruleset_config.dart`).
 *
 * SDD §6.2 (Table §6.2) and SRS BR-04..BR-14. The config is chosen at
 * setup, validated once, and frozen for the whole match (BR-14): a
 * {@link LudoGame} never mutates its ruleset after construction.
 *
 * Defaults below are the SDD Table §6.2 defaults. They are proposals
 * pending stakeholder approval (SRS OD-02); changing a default is a
 * configuration change (a new `version`), never a code change.
 */
import { FormatException, InvalidRulesetConfig } from './errors';
import { requireBool, requireInt, requireString } from './json-validation';

export interface RulesetConfigOptions {
  releaseOnSix: boolean;
  releaseOnOne: boolean;
  extraTurnOnSix: boolean;
  extraTurnOnCapture: boolean;
  extraTurnOnHome: boolean;
  maxConsecutiveSixes: number;
  exactFinish: boolean;
  version: string;
}

/** Dart `RulesetConfig` defaults (SDD §6.2). */
export const RULESET_DEFAULTS: RulesetConfigOptions = {
  releaseOnSix: true,
  releaseOnOne: false,
  extraTurnOnSix: true,
  extraTurnOnCapture: true,
  extraTurnOnHome: true,
  maxConsecutiveSixes: 3,
  exactFinish: true,
  version: '1.0.0',
};

export class RulesetConfig implements RulesetConfigOptions {
  constructor(opts: Partial<RulesetConfigOptions> = {}) {
    this.releaseOnSix = opts.releaseOnSix ?? RULESET_DEFAULTS.releaseOnSix;
    this.releaseOnOne = opts.releaseOnOne ?? RULESET_DEFAULTS.releaseOnOne;
    this.extraTurnOnSix =
      opts.extraTurnOnSix ?? RULESET_DEFAULTS.extraTurnOnSix;
    this.extraTurnOnCapture =
      opts.extraTurnOnCapture ?? RULESET_DEFAULTS.extraTurnOnCapture;
    this.extraTurnOnHome =
      opts.extraTurnOnHome ?? RULESET_DEFAULTS.extraTurnOnHome;
    this.maxConsecutiveSixes =
      opts.maxConsecutiveSixes ?? RULESET_DEFAULTS.maxConsecutiveSixes;
    this.exactFinish = opts.exactFinish ?? RULESET_DEFAULTS.exactFinish;
    this.version = opts.version ?? RULESET_DEFAULTS.version;
  }

  /** A token leaves the yard on a roll of 6 (BR-04, default). */
  readonly releaseOnSix: boolean;

  /** Variant: a token also leaves the yard on a roll of 1 (BR-04). */
  readonly releaseOnOne: boolean;

  /** Rolling a 6 grants another roll (BR-06). */
  readonly extraTurnOnSix: boolean;

  /** Capturing an opponent token grants another roll (BR-06). */
  readonly extraTurnOnCapture: boolean;

  /** Moving a token home grants another roll (BR-06). */
  readonly extraTurnOnHome: boolean;

  /**
   * Consecutive sixes in one turn sequence after which the roll is
   * not played and the turn passes (BR-07). `0` disables the limit.
   */
  readonly maxConsecutiveSixes: number;

  /**
   * A token reaches home only with an exact roll; an overshooting
   * roll makes that token's move illegal (BR-10). When false, an
   * overshoot still lands the token home (variant behaviour).
   */
  readonly exactFinish: boolean;

  /**
   * Ruleset version, stored with every match so a match can always
   * be replayed under the rules it used (BR-14).
   */
  readonly version: string;

  /** Rolls that release a token from the yard. */
  get releaseRolls(): Set<number> {
    const rolls = new Set<number>();
    if (this.releaseOnSix) rolls.add(6);
    if (this.releaseOnOne) rolls.add(1);
    return rolls;
  }

  /** Throws {@link InvalidRulesetConfig} if the config is incoherent. */
  validate(): void {
    if (!this.releaseOnSix && !this.releaseOnOne) {
      throw new InvalidRulesetConfig(
        'At least one release roll must be enabled.',
      );
    }
    if (this.maxConsecutiveSixes < 0) {
      throw new InvalidRulesetConfig(
        'maxConsecutiveSixes must be 0 (off) or positive.',
      );
    }
    if (this.version === '') {
      throw new InvalidRulesetConfig('version must not be empty.');
    }
  }

  toJson(): RulesetConfigOptions {
    return {
      releaseOnSix: this.releaseOnSix,
      releaseOnOne: this.releaseOnOne,
      extraTurnOnSix: this.extraTurnOnSix,
      extraTurnOnCapture: this.extraTurnOnCapture,
      extraTurnOnHome: this.extraTurnOnHome,
      maxConsecutiveSixes: this.maxConsecutiveSixes,
      exactFinish: this.exactFinish,
      version: this.version,
    };
  }

  /**
   * Strict deserialization (M1.1, D-22): all eight fields must be
   * present with the correct types, and {@link validate} must pass.
   * An {@link InvalidRulesetConfig} from the JSON path is reported
   * as a {@link FormatException} (the setup path still throws
   * {@link InvalidRulesetConfig} directly).
   */
  static fromJson(json: Record<string, unknown>): RulesetConfig {
    const config = new RulesetConfig({
      releaseOnSix: requireBool(json.releaseOnSix, 'releaseOnSix'),
      releaseOnOne: requireBool(json.releaseOnOne, 'releaseOnOne'),
      extraTurnOnSix: requireBool(json.extraTurnOnSix, 'extraTurnOnSix'),
      extraTurnOnCapture: requireBool(
        json.extraTurnOnCapture,
        'extraTurnOnCapture',
      ),
      extraTurnOnHome: requireBool(json.extraTurnOnHome, 'extraTurnOnHome'),
      maxConsecutiveSixes: requireInt(
        json.maxConsecutiveSixes,
        'maxConsecutiveSixes',
      ),
      exactFinish: requireBool(json.exactFinish, 'exactFinish'),
      version: requireString(json.version, 'version'),
    });
    try {
      config.validate();
    } catch (e) {
      if (e instanceof InvalidRulesetConfig) {
        throw new FormatException(`Invalid embedded ruleset: ${e.message}`);
      }
      throw e;
    }
    return config;
  }

  equals(other: RulesetConfig): boolean {
    return (
      other instanceof RulesetConfig &&
      this.releaseOnSix === other.releaseOnSix &&
      this.releaseOnOne === other.releaseOnOne &&
      this.extraTurnOnSix === other.extraTurnOnSix &&
      this.extraTurnOnCapture === other.extraTurnOnCapture &&
      this.extraTurnOnHome === other.extraTurnOnHome &&
      this.maxConsecutiveSixes === other.maxConsecutiveSixes &&
      this.exactFinish === other.exactFinish &&
      this.version === other.version
    );
  }
}
