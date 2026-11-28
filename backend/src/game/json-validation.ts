/**
 * Strict JSON field readers for snapshot deserialization (mirrors
 * Dart `json_validation.dart`, M1.1 / D-22).
 *
 * Every reader throws {@link FormatException} on a missing field, a
 * wrong type, or an out-of-range value. Nothing is coerced and
 * nothing silently defaults: a corrupt snapshot must fail loudly.
 * Unknown keys are ignored by the readers; the caller decides
 * whether a field is required.
 */
import { FormatException } from './errors';

/** The field must be an integer (a float or string is never coerced). */
export function requireInt(value: unknown, field: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw new FormatException(`Snapshot field "${field}" must be an integer.`);
  }
  return value;
}

/** The field must be an integer within min..max inclusive. */
export function requireIntInRange(
  value: unknown,
  field: string,
  min: number,
  max: number,
): number {
  const result = requireInt(value, field);
  if (result < min || result > max) {
    throw new FormatException(
      `Snapshot field "${field}" must be between ${min} and ${max} ` +
        `(got ${result}).`,
    );
  }
  return result;
}

/** The field must be a string. */
export function requireString(value: unknown, field: string): string {
  if (typeof value !== 'string') {
    throw new FormatException(`Snapshot field "${field}" must be a string.`);
  }
  return value;
}

/** The field must be a boolean. */
export function requireBool(value: unknown, field: string): boolean {
  if (typeof value !== 'boolean') {
    throw new FormatException(`Snapshot field "${field}" must be a boolean.`);
  }
  return value;
}

/** The field must be a JSON object (a map with string keys). */
export function requireMap(
  value: unknown,
  field: string,
): Record<string, unknown> {
  if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  throw new FormatException(`Snapshot field "${field}" must be a JSON object.`);
}

/** The field must be a JSON list. */
export function requireList(value: unknown, field: string): unknown[] {
  if (Array.isArray(value)) {
    return value;
  }
  throw new FormatException(`Snapshot field "${field}" must be a JSON list.`);
}

/**
 * The field must be a string naming one of `values`. Throws
 * {@link FormatException} on a missing, non-string, or unknown value.
 */
export function requireEnum<T extends string>(
  value: unknown,
  field: string,
  values: readonly T[],
): T {
  const raw = requireString(value, field);
  if ((values as readonly string[]).includes(raw)) {
    return raw as T;
  }
  throw new FormatException(
    `Snapshot field "${field}" has unknown value "${raw}".`,
  );
}

const ISO_8601_DATE_TIME =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z|([+-])(\d{2}):(\d{2}))?$/;

/**
 * The field must be a string holding a complete ISO-8601 date-time:
 * `YYYY-MM-DDTHH:MM:SS` with optional fractional seconds and an
 * optional zone (`Z` or `±HH:MM`). Returns the parsed {@link Date}.
 *
 * The shape and every component are checked against the raw input,
 * because `new Date` alone normalises out-of-range components (month
 * 13 rolls into the next year) and accepts date-only strings. A naive
 * date-time (no zone) is accepted — legacy stored snapshots and Dart
 * offline snapshots still carry one — and is parsed as local time,
 * matching Dart `DateTime.parse`. The backend snapshot writer emits
 * a Z-suffixed UTC instant instead (see `GameState.toJson`), so a
 * device in another zone never reads `startedAt` as the future.
 * A leap second (60) is rejected; the writer never emits one.
 */
export function requireIso8601DateTime(value: unknown, field: string): Date {
  const raw = requireString(value, field);
  const match = ISO_8601_DATE_TIME.exec(raw);
  if (match === null) {
    throw new FormatException(
      `Snapshot field "${field}" must be a complete ISO-8601 date-time ` +
        `(YYYY-MM-DDTHH:MM:SS with optional fractional seconds and ` +
        `optional Z or ±HH:MM zone) (got "${raw}").`,
    );
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  if (month < 1 || month > 12) {
    throw new FormatException(
      `Snapshot field "${field}" has an invalid month (got ${month}).`,
    );
  }
  // Day 0 of the next month is the last day of this month, so this is
  // leap-year aware: Feb 29 is valid only in a leap year.
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  if (day < 1 || day > daysInMonth) {
    throw new FormatException(
      `Snapshot field "${field}" has an invalid day (got ${day}).`,
    );
  }
  if (hour > 23) {
    throw new FormatException(
      `Snapshot field "${field}" has an invalid hour (got ${hour}).`,
    );
  }
  if (minute > 59) {
    throw new FormatException(
      `Snapshot field "${field}" has an invalid minute (got ${minute}).`,
    );
  }
  if (second > 59) {
    throw new FormatException(
      `Snapshot field "${field}" has an invalid second (got ${second}).`,
    );
  }
  const offsetHour = match[10];
  if (offsetHour !== undefined) {
    if (Number(offsetHour) > 23) {
      throw new FormatException(
        `Snapshot field "${field}" has an invalid zone offset hour ` +
          `(got ${offsetHour}).`,
      );
    }
    if (Number(match[11]) > 59) {
      throw new FormatException(
        `Snapshot field "${field}" has an invalid zone offset minute ` +
          `(got ${match[11]}).`,
      );
    }
  }
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    throw new FormatException(
      `Snapshot field "${field}" is not a valid date-time (got "${raw}").`,
    );
  }
  return parsed;
}
