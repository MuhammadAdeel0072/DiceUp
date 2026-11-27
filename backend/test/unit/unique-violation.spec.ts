import { QueryFailedError } from 'typeorm';
import { isUniqueViolationError } from '../../src/common/errors/unique-violation';

describe('isUniqueViolationError (Stage 4, H-02)', () => {
  it('detects a pg 23505 on driverError (TypeORM QueryFailedError shape)', () => {
    const pgError = Object.assign(new Error('duplicate key value'), {
      code: '23505',
      constraint: 'UQ_users_email',
    });
    const err = new QueryFailedError('INSERT INTO ...', [], pgError);
    expect(isUniqueViolationError(err)).toBe(true);
  });

  it('detects a bare 23505 code', () => {
    expect(isUniqueViolationError({ code: '23505' })).toBe(true);
  });

  it('rejects other pg codes and non-errors', () => {
    expect(isUniqueViolationError({ code: '23503' })).toBe(false);
    expect(isUniqueViolationError(new Error('boom'))).toBe(false);
    expect(isUniqueViolationError(null)).toBe(false);
    expect(isUniqueViolationError(undefined)).toBe(false);
  });
});
