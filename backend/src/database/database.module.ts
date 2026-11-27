import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  DATABASE_RETRY_ATTEMPTS,
  DATABASE_RETRY_DELAY_MS,
  PHASE4_ENTITIES,
  buildDataSourceOptions,
} from './data-source';

/**
 * DatabaseModule — TypeORM + pg, PostgreSQL 16 only (SDD §3.5/§9.2,
 * CI-04: only the backend connects). Async factory from validated
 * config; `synchronize` is false (see data-source.ts). Repositories are
 * injected into services; services never import DataSource directly
 * except for explicit transactions (plan §4.2).
 */
@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        // NOTE (Stage 3): read the namespaced `app.databaseUrl`, NOT the
        // top-level `DATABASE_URL`. ConfigService.get() checks the Joi
        // VALIDATED env store before process.env, and that store is
        // frozen at ConfigModule.forRoot() time (import time) from
        // backend/.env — so a later process.env assignment (exactly what
        // the e2e helpers do to point at a scratch DB) is silently
        // ignored and the app keeps using diceup_dev. The `app.*`
        // factory reads live process.env when ConfigService is created,
        // so it honours the assignment. (Auth/Mailer already use `app`.)
        ...buildDataSourceOptions(config.getOrThrow<string>('app.databaseUrl')),
        // Bounded initial-connect retries (Stage 4, M-02): the Nest
        // TypeORM defaults (10 attempts × 3 s delay, plus pg's
        // no-timeout connect) let boot against a dead DB hang for
        // minutes. 3 × 1 s + the 5 s connect timeout in
        // buildDataSourceOptions bounds worst-case boot failure to
        // ~17 s, then the process exits non-zero.
        retryAttempts: DATABASE_RETRY_ATTEMPTS,
        retryDelay: DATABASE_RETRY_DELAY_MS,
      }),
    }),
    TypeOrmModule.forFeature(PHASE4_ENTITIES),
  ],
  exports: [TypeOrmModule],
})
export class DatabaseModule {}
