import { DefaultNamingStrategy, type NamingStrategyInterface } from 'typeorm';

/**
 * SnakeNamingStrategy — maps camelCase entity properties to the
 * snake_case columns the migrations create (SDD §9.2).
 *
 * This is a latent Stage 2a defect found by Stage 2b's first
 * repository query: TypeORM's default strategy uses the property
 * name verbatim (`emailVerifiedAt`), while migration 0001 creates
 * `email_verified_at` — so every repository query failed with
 * `column User.emailVerifiedAt does not exist`. No repository query
 * ran in Stage 2a (health uses raw `SELECT 1`), so it stayed hidden.
 *
 * The strategy converts every property name (e.g. `passwordHash` →
 * `password_hash`, `deletionRequestedAt` →
 * `deletion_requested_at`); explicit @Entity table names are
 * untouched. Verified by test/unit/naming-strategy.spec.ts against
 * every column in migrations 0001/0002.
 */
export class SnakeNamingStrategy
  extends DefaultNamingStrategy
  implements NamingStrategyInterface
{
  override columnName(
    propertyName: string,
    customName?: string,
    embeddedPrefixes: string[] = [],
  ): string {
    if (customName) return customName;
    const full = [...embeddedPrefixes, propertyName].join('_');
    return full.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
  }
}
