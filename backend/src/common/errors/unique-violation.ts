/**
 * PostgreSQL unique-violation detection (Stage 4, H-02).
 *
 * A `findOne` duplicate pre-check followed by an insert is a TOCTOU
 * race: two concurrent requests can both pass the check and the loser
 * hits the unique index. TypeORM surfaces that as a QueryFailedError
 * wrapping the pg error (code `23505` on `driverError`). Without this
 * check the loser got a misleading 500 INTERNAL_ERROR; callers map
 * it to the correct 409 (register) or retry once (email-token issue).
 */
export function isUniqueViolationError(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false;
  const direct = (err as { code?: unknown }).code;
  if (direct === '23505') return true;
  const driver = (err as { driverError?: { code?: unknown } }).driverError;
  return driver?.code === '23505';
}
