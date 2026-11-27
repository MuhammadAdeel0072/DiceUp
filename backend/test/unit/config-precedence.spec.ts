import * as fs from 'node:fs';
import * as path from 'node:path';

/**
 * Config-precedence regression guard (Stage 4 — D-01 must never recur).
 *
 * Stage 3 proved the failure mode: `ConfigService.get()` checks the
 * Joi-validated env store (frozen at ConfigModule.forRoot() time from
 * backend/.env) before process.env, so a top-level read such as
 * `config.get('DATABASE_URL')` silently ignores a later process.env
 * assignment — and every e2e suite ran against diceup_dev instead of
 * its scratch database. The fix reads the namespaced keys
 * (`app.databaseUrl` / `app.redisUrl`) whose registerAs factory reads
 * live process.env.
 *
 * This test scans the source tree so a new module copying the old
 * pattern fails loudly here instead of silently pointing at the wrong
 * database/Redis (in production: the wrong DB).
 */
function srcFiles(): string[] {
  const root = path.join(process.cwd(), 'src');
  const out: string[] = [];
  const walk = (dir: string): void => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile() && entry.name.endsWith('.ts')) out.push(full);
    }
  };
  walk(root);
  return out;
}

/** Top-level env keys: only src/config/configuration.ts may read these. */
const TOP_LEVEL_ENV_KEYS = [
  'DATABASE_URL',
  'REDIS_URL',
  'JWT_PRIVATE_KEY',
  'JWT_PUBLIC_KEY',
  'JWT_PRIVATE_KEY_FILE',
  'JWT_PUBLIC_KEY_FILE',
  'JWT_ISSUER',
  'MAILER_PROVIDER',
  'MAILER_SMTP_HOST',
  'MAILER_SMTP_USER',
  'MAILER_SMTP_PASS',
  'CORS_ORIGINS',
  'RULESET_VERSION',
  'TRUST_PROXY',
  'NODE_ENV',
  'PORT',
  'LOG_LEVEL',
  'MAILER_FROM',
  'MAILER_SMTP_PORT',
] as const;

/**
 * Files allowed to touch process.env directly, and which keys each may
 * touch. configuration.ts IS the factory (the single place top-level
 * env is read). data-source.ts may read DATABASE_URL only for the
 * TypeORM CLI data source (never used by the running app) and NODE_ENV
 * only for the query-logging flag.
 */
const PROCESS_ENV_ALLOWLIST: Record<string, readonly string[]> = {
  'src/config/configuration.ts': TOP_LEVEL_ENV_KEYS,
  'src/database/data-source.ts': ['DATABASE_URL', 'NODE_ENV'],
};

describe('config precedence (D-01 regression guard)', () => {
  /** Source text with comments stripped (comments may name keys). */
  function codeOf(file: string): string {
    const text = fs.readFileSync(file, 'utf8');
    return text
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/^[ \t]*\/\/.*$/gm, '');
  }

  it('no ConfigService read of a top-level env key exists anywhere in src/', () => {
    const violations: string[] = [];
    for (const file of srcFiles()) {
      const rel = path.relative(process.cwd(), file);
      const text = codeOf(file);
      // Matches config.get('X') / config.getOrThrow("X") for any X
      // that is not a namespaced 'app.*' key.
      const re = /(?:\.get|\.getOrThrow)\(\s*['"]([^'"]+)['"]/g;
      for (const match of text.matchAll(re)) {
        if (!match[1].startsWith('app')) {
          violations.push(`${rel}: ConfigService reads '${match[1]}'`);
        }
      }
    }
    expect(violations).toEqual([]);
  });

  it('process.env is read only in the allow-listed files/keys', () => {
    const violations: string[] = [];
    for (const file of srcFiles()) {
      const rel = path.relative(process.cwd(), file);
      const text = codeOf(file);
      const allowed = PROCESS_ENV_ALLOWLIST[rel];
      const re =
        /process\.env(?:\.([A-Za-z_][A-Za-z0-9_]*)|\[['"]([^'"]+)['"]\])/g;
      for (const match of text.matchAll(re)) {
        const key = match[1] ?? match[2];
        if (!allowed || !allowed.includes(key)) {
          violations.push(`${rel}: process.env.${key} is not allow-listed`);
        }
      }
    }
    expect(violations).toEqual([]);
  });

  it('the namespaced reads the fix depends on still exist', () => {
    const read = (rel: string): string =>
      fs.readFileSync(path.join(process.cwd(), rel), 'utf8');
    expect(read('src/database/database.module.ts')).toContain(
      'app.databaseUrl',
    );
    expect(read('src/redis/redis.module.ts')).toContain('app.redisUrl');
    expect(read('src/socket/socket-redis-clients.service.ts')).toContain(
      'app.redisUrl',
    );
  });
});
