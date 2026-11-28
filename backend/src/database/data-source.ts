import * as dotenv from 'dotenv';
import * as path from 'node:path';
import { DataSource, DataSourceOptions } from 'typeorm';
import { AuthSession } from '../auth/entities/auth-session.entity';
import { EmailToken } from '../auth/entities/email-token.entity';
import { GameConfiguration } from '../rooms/entities/game-configuration.entity';
import { Match } from '../rooms/entities/match.entity';
import { MatchPlayer } from '../rooms/entities/match-player.entity';
import { MoveEvent } from '../rooms/entities/move-event.entity';
import { Room } from '../rooms/entities/room.entity';
import { RoomMember } from '../rooms/entities/room-member.entity';
import { Profile } from '../users/entities/profile.entity';
import { User } from '../users/entities/user.entity';
import { InitAuth1764240000000 } from './migrations/0001_init-auth';
import { SnakeNamingStrategy } from './naming.strategy';
import { AddProfilePreferences1764249000000 } from './migrations/0002_add-profile-preferences';
import { RoomsMatchmaking1795822100000 } from './migrations/0003_rooms-matchmaking';
import { Stage6TimersPresence1796000000000 } from './migrations/0004_stage6_timers_presence';

// The TypeORM CLI runs this file outside Nest, so ConfigModule never
// loads .env for it. Load backend/.env here (CLI only in practice;
// harmless when imported by the app, which loads .env itself).
dotenv.config({ path: path.resolve(__dirname, '..', '..', '.env') });

/** The Phase 4 entities + the Phase 5 Stage 3 room/match entities. */
export const PHASE4_ENTITIES = [
  User,
  Profile,
  AuthSession,
  EmailToken,
  Room,
  RoomMember,
  Match,
  MatchPlayer,
  MoveEvent,
  GameConfiguration,
];

export const PHASE4_MIGRATIONS = [
  InitAuth1764240000000,
  AddProfilePreferences1764249000000,
  RoomsMatchmaking1795822100000,
  Stage6TimersPresence1796000000000,
];

/**
 * DataSource options builder — the single place the options are defined,
 * so the `synchronize: false` invariant (plan §4.4) is unit-testable
 * without booting the app. `synchronize` is NEVER true, in any env.
 *
 * Fail-fast bounds (Stage 4, M-02): the Stage 3 probe found boot
 * against a nonexistent database did not fail fast within ~6 min.
 * Measured in Stage 4, the cause is two unbounded defaults — the
 * Nest TypeORM module retries initial connect 10× with a 3 s delay
 * (see database.module.ts, now 3× / 1 s) and pg has NO connect
 * timeout by default (`connectionTimeoutMillis: 0`), so an
 * unreachable DB host hangs each attempt on the TCP SYN timeout
 * instead of failing. Both are bounded here: an initial connect
 * fails after 5 s, pool checkout after 5 s, so worst-case boot
 * against a dead/unreachable DB is ~17 s (3 attempts × 5 s + delays)
 * and then the process exits non-zero. A legitimately slow DB that
 * comes up later is handled the standard way — the orchestrator
 * restarts the crashed process (crash-loop with backoff), rather
 * than the app hanging with no /health and no readiness signal.
 */
export const DATABASE_RETRY_ATTEMPTS = 3;
export const DATABASE_RETRY_DELAY_MS = 1000;
export const DATABASE_CONNECT_TIMEOUT_MS = 5000;

export function buildDataSourceOptions(databaseUrl: string): DataSourceOptions {
  return {
    type: 'postgres',
    url: databaseUrl,
    entities: PHASE4_ENTITIES,
    migrations: PHASE4_MIGRATIONS,
    // Snake-case mapping (see naming.strategy.ts): entity properties
    // are camelCase, migration columns are snake_case.
    namingStrategy: new SnakeNamingStrategy(),
    // NEVER true — schema changes only via migrations (plan §4.4, SDD §15.2).
    synchronize: false,
    logging: process.env.NODE_ENV === 'development' ? ['error'] : false,
    // Bound the initial connect (TypeORM pg option; 0/undefined = hang
    // forever on an unreachable host) and pool checkout (pg Pool
    // option — bounds readiness `SELECT 1` when the pool is exhausted).
    connectTimeoutMS: DATABASE_CONNECT_TIMEOUT_MS,
    extra: { connectionTimeoutMillis: DATABASE_CONNECT_TIMEOUT_MS },
  };
}

/**
 * CLI data source for `npm run migration:*` (TypeORM CLI, plan §3.2).
 * Reads DATABASE_URL from the environment; never embeds a credential.
 * The CLI runs against the database named in DATABASE_URL — point it at
 * a scratch/dev database, never production, before running a migration.
 */
export const AppDataSource = new DataSource(
  buildDataSourceOptions(process.env.DATABASE_URL ?? ''),
);
