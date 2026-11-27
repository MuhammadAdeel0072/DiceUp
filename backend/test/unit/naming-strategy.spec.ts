import { SnakeNamingStrategy } from '../../src/database/naming.strategy';

/**
 * Naming strategy regression test: every entity property must map to
 * the exact snake_case column the migrations create. Without the
 * strategy, TypeORM queries `emailVerifiedAt` (property name) and
 * PostgreSQL answers "column does not exist" — the latent Stage 2a
 * defect found by Stage 2b.
 */
describe('SnakeNamingStrategy', () => {
  const strategy = new SnakeNamingStrategy();

  it.each([
    ['emailVerifiedAt', 'email_verified_at'],
    ['passwordHash', 'password_hash'],
    ['deletionRequestedAt', 'deletion_requested_at'],
    ['createdAt', 'created_at'],
    ['updatedAt', 'updated_at'],
    ['userId', 'user_id'],
    ['refreshTokenHash', 'refresh_token_hash'],
    ['familyId', 'family_id'],
    ['deviceLabel', 'device_label'],
    ['expiresAt', 'expires_at'],
    ['revokedAt', 'revoked_at'],
    ['tokenHash', 'token_hash'],
    ['usedAt', 'used_at'],
    ['displayName', 'display_name'],
    ['avatarKey', 'avatar_key'],
    ['matchesPlayed', 'matches_played'],
    ['matchesWon', 'matches_won'],
    ['notificationPreferences', 'notification_preferences'],
    ['email', 'email'],
    ['username', 'username'],
    ['status', 'status'],
    ['purpose', 'purpose'],
    ['id', 'id'],
  ])('maps %s → %s', (property, column) => {
    expect(strategy.columnName(property, undefined, [])).toBe(column);
  });

  it('an explicit custom name wins over the conversion', () => {
    expect(strategy.columnName('foo', 'custom_name', [])).toBe('custom_name');
  });
});
