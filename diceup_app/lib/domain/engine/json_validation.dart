/// Strict JSON field readers for snapshot deserialization (M1.1, D-22).
///
/// Every reader throws [FormatException] on a missing field, a wrong
/// type, or an out-of-range value. Nothing is coerced (`as` casts on
/// untrusted data would throw [TypeError], not [FormatException]) and
/// nothing silently defaults: a corrupt snapshot must fail loudly so
/// the caller can delete it and show the recovery notice instead of
/// silently changing the match (wrong colour, an AI seat becoming
/// human). Unknown keys are ignored by the readers; the caller decides
/// whether a field is required.
library;

/// The field [value] must be an [int] (a [double] or [String] is never
/// coerced). Throws [FormatException] otherwise.
int requireInt(Object? value, String field) {
  if (value is! int) {
    throw FormatException('Snapshot field "$field" must be an integer.');
  }
  return value;
}

/// The field [value] must be an [int] within [min]..[max] inclusive.
/// Throws [FormatException] otherwise.
int requireIntInRange(Object? value, String field, int min, int max) {
  final result = requireInt(value, field);
  if (result < min || result > max) {
    throw FormatException(
      'Snapshot field "$field" must be between $min and $max '
      '(got $result).',
    );
  }
  return result;
}

/// The field [value] must be a [String]. Throws [FormatException]
/// otherwise.
String requireString(Object? value, String field) {
  if (value is! String) {
    throw FormatException('Snapshot field "$field" must be a string.');
  }
  return value;
}

/// The field [value] must be a [bool]. Throws [FormatException]
/// otherwise.
bool requireBool(Object? value, String field) {
  if (value is! bool) {
    throw FormatException('Snapshot field "$field" must be a boolean.');
  }
  return value;
}

/// The field [value] must be a JSON object (a map with string keys).
/// Throws [FormatException] otherwise.
Map<String, Object?> requireMap(Object? value, String field) {
  if (value is Map && value.keys.every((key) => key is String)) {
    return value.cast<String, Object?>();
  }
  throw FormatException('Snapshot field "$field" must be a JSON object.');
}

/// The field [value] must be a JSON list. Throws [FormatException]
/// otherwise.
List<Object?> requireList(Object? value, String field) {
  if (value is List) {
    return value.cast<Object?>();
  }
  throw FormatException('Snapshot field "$field" must be a JSON list.');
}

/// The field [value] must be a string naming one of [values] (matched
/// on [Enum.name]). Throws [FormatException] on a missing, non-string,
/// or unknown value.
T requireEnum<T extends Enum>(
  Object? value,
  String field,
  List<T> values,
) {
  final raw = requireString(value, field);
  for (final candidate in values) {
    if (candidate.name == raw) return candidate;
  }
  throw FormatException('Snapshot field "$field" has unknown value "$raw".');
}

/// The field [value] must be a string holding a complete ISO-8601
/// date-time: `YYYY-MM-DDTHH:MM:SS` with optional fractional seconds
/// (`.\d+`) and an optional zone (`Z` or `±HH:MM`). Returns the parsed
/// [DateTime]. Throws [FormatException] otherwise.
///
/// The shape and every component are checked against the RAW input,
/// because [DateTime.tryParse] alone is not enough: it normalises
/// out-of-range components (month 13 rolls into the next year, hour 99
/// rolls into later days) instead of rejecting them, and it accepts
/// date-only strings. A naive date-time (no zone) is accepted — the
/// snapshot writer emits `DateTime.now().toIso8601String()`, which
/// has no zone suffix. The literal `T` separator and seconds are
/// required. A leap second (60) is rejected; the writer never emits
/// one. Once the components check out, the value is parsed with
/// [DateTime.tryParse], which preserves the instant for offsets.
DateTime requireIso8601DateTime(Object? value, String field) {
  final raw = requireString(value, field);
  final match = _iso8601DateTime.firstMatch(raw);
  if (match == null) {
    throw FormatException(
      'Snapshot field "$field" must be a complete ISO-8601 date-time '
      '(YYYY-MM-DDTHH:MM:SS with optional fractional seconds and '
      'optional Z or ±HH:MM zone) (got "$raw").',
    );
  }
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6]!);
  if (month < 1 || month > 12) {
    throw FormatException(
      'Snapshot field "$field" has an invalid month (got $month).',
    );
  }
  // Day 0 of the next month is the last day of this month, so this is
  // leap-year aware: Feb 29 is valid only in a leap year.
  final daysInMonth = DateTime.utc(year, month + 1, 0).day;
  if (day < 1 || day > daysInMonth) {
    throw FormatException(
      'Snapshot field "$field" has an invalid day (got $day).',
    );
  }
  if (hour > 23) {
    throw FormatException(
      'Snapshot field "$field" has an invalid hour (got $hour).',
    );
  }
  if (minute > 59) {
    throw FormatException(
      'Snapshot field "$field" has an invalid minute (got $minute).',
    );
  }
  if (second > 59) {
    throw FormatException(
      'Snapshot field "$field" has an invalid second (got $second).',
    );
  }
  final offsetHour = match[10];
  if (offsetHour != null) {
    if (int.parse(offsetHour) > 23) {
      throw FormatException(
        'Snapshot field "$field" has an invalid zone offset hour '
        '(got $offsetHour).',
      );
    }
    if (int.parse(match[11]!) > 59) {
      throw FormatException(
        'Snapshot field "$field" has an invalid zone offset minute '
        '(got ${match[11]}).',
      );
    }
  }
  // Belt and braces: the shape and components already checked out, so
  // tryParse must succeed; a null result is still a FormatException.
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException(
      'Snapshot field "$field" is not a valid date-time (got "$raw").',
    );
  }
  return parsed;
}

/// Complete ISO-8601 date-time with a literal `T` separator and
/// mandatory seconds: `YYYY-MM-DDTHH:MM:SS`, optional fractional
/// seconds, optional `Z` or `±HH:MM` zone. Groups: 1 year, 2 month,
/// 3 day, 4 hour, 5 minute, 6 second, 7 fractional seconds,
/// 8 zone, 9 zone sign, 10 zone offset hour, 11 zone offset minute.
final _iso8601DateTime = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d+)?'
  r'(Z|([+-])(\d{2}):(\d{2}))?$',
);
