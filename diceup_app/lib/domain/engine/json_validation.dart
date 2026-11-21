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
