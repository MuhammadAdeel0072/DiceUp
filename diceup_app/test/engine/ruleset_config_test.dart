import 'package:diceup/domain/engine/ruleset_config.dart';
import 'package:test/test.dart';

void main() {
  group('defaults (SDD Table §6.2)', () {
    test('the stock ruleset has the SDD defaults', () {
      const config = RulesetConfig();
      expect(config.releaseOnSix, isTrue);
      expect(config.releaseOnOne, isFalse);
      expect(config.extraTurnOnSix, isTrue);
      expect(config.extraTurnOnCapture, isTrue);
      expect(config.extraTurnOnHome, isTrue);
      expect(config.maxConsecutiveSixes, 3);
      expect(config.exactFinish, isTrue);
      expect(config.version, '1.0.0');
    });

    test('releaseRolls follows the release flags', () {
      expect(const RulesetConfig().releaseRolls, {6});
      expect(const RulesetConfig(releaseOnOne: true).releaseRolls, {6, 1});
      expect(
        const RulesetConfig(
          releaseOnSix: false,
          releaseOnOne: true,
        ).releaseRolls,
        {1},
      );
      expect(
        const RulesetConfig(
          releaseOnSix: false,
          releaseOnOne: false,
        ).releaseRolls,
        isEmpty,
      );
    });
  });

  group('validate()', () {
    test('stock and variant configs validate', () {
      const RulesetConfig().validate();
      const RulesetConfig(releaseOnSix: false, releaseOnOne: true).validate();
      const RulesetConfig(maxConsecutiveSixes: 0).validate();
      const RulesetConfig(version: '2.0.0').validate();
    });

    test('no release roll throws with the exact message', () {
      expect(
        () => const RulesetConfig(
          releaseOnSix: false,
          releaseOnOne: false,
        ).validate(),
        throwsA(
          isA<InvalidRulesetConfig>().having(
            (e) => e.message,
            'message',
            'At least one release roll must be enabled.',
          ),
        ),
      );
    });

    test('a negative maxConsecutiveSixes throws with the exact message', () {
      expect(
        () => const RulesetConfig(maxConsecutiveSixes: -1).validate(),
        throwsA(
          isA<InvalidRulesetConfig>().having(
            (e) => e.message,
            'message',
            'maxConsecutiveSixes must be 0 (off) or positive.',
          ),
        ),
      );
    });

    test('an empty version throws with the exact message', () {
      expect(
        () => const RulesetConfig(version: '').validate(),
        throwsA(
          isA<InvalidRulesetConfig>().having(
            (e) => e.message,
            'message',
            'version must not be empty.',
          ),
        ),
      );
    });
  });

  group('serialization', () {
    test('toJson carries all eight fields', () {
      final json = const RulesetConfig().toJson();
      expect(json.keys, {
        'releaseOnSix',
        'releaseOnOne',
        'extraTurnOnSix',
        'extraTurnOnCapture',
        'extraTurnOnHome',
        'maxConsecutiveSixes',
        'exactFinish',
        'version',
      });
    });

    test('fromJson round-trips a non-default config', () {
      const config = RulesetConfig(
        releaseOnOne: true,
        extraTurnOnSix: false,
        maxConsecutiveSixes: 0,
        exactFinish: false,
        version: '1.2.0',
      );
      final json = Map<String, Object?>.of(config.toJson());
      final restored = RulesetConfig.fromJson(json);
      expect(restored, config);
      expect(restored.hashCode, config.hashCode);
      expect(restored.toJson(), config.toJson());
    });

    test('fromJson rejects a missing field', () {
      final json = Map<String, Object?>.of(const RulesetConfig().toJson())
        ..remove('version');
      expect(() => RulesetConfig.fromJson(json), throwsFormatException);
    });

    test('fromJson rejects a wrong-typed field', () {
      final json = Map<String, Object?>.of(const RulesetConfig().toJson())
        ..['maxConsecutiveSixes'] = '3';
      expect(() => RulesetConfig.fromJson(json), throwsFormatException);
    });

    test('fromJson wraps an invalid embedded ruleset in a FormatException', () {
      final json = Map<String, Object?>.of(const RulesetConfig().toJson())
        ..['releaseOnSix'] = false
        ..['releaseOnOne'] = false;
      expect(
        () => RulesetConfig.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('Invalid embedded ruleset:'),
          ),
        ),
      );
    });
  });

  group('equality', () {
    test('equal configs are == with equal hashCodes', () {
      final a = RulesetConfig(releaseOnOne: true, version: '1.1.0');
      final b = RulesetConfig(releaseOnOne: true, version: '1.1.0');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      // And equal configs collapse in a Set (hashCode + == agree).
      expect({a, b}.length, 1);
      expect({a}.contains(b), isTrue);
    });

    test('each field breaks equality', () {
      const base = RulesetConfig();
      final variants = [
        const RulesetConfig(releaseOnSix: false, releaseOnOne: true),
        const RulesetConfig(releaseOnOne: true),
        const RulesetConfig(extraTurnOnSix: false),
        const RulesetConfig(extraTurnOnCapture: false),
        const RulesetConfig(extraTurnOnHome: false),
        const RulesetConfig(maxConsecutiveSixes: 0),
        const RulesetConfig(exactFinish: false),
        const RulesetConfig(version: '2.0.0'),
      ];
      for (final variant in variants) {
        expect(variant, isNot(base));
        expect(base, isNot(variant));
      }
    });

    test('a config is not equal to a non-config', () {
      const config = RulesetConfig();
      expect(config == Object(), isFalse);
      expect(config, isNot('1.0.0'));
    });
  });

  group('InvalidRulesetConfig', () {
    test('toString names the type and the message', () {
      expect(
        const InvalidRulesetConfig('boom').toString(),
        'InvalidRulesetConfig: boom',
      );
    });
  });
}
