import {
  Inject,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
  Optional,
} from '@nestjs/common';
import type { ConfigService } from '@nestjs/config';
import { DataSource, EntityManager, In, MoreThanOrEqual } from 'typeorm';
import { LudoGame, Move, type DiceRoller, type MoveResult } from '../game';
import type { GameState } from '../game/game-state';
import { isUniqueViolationError } from '../common/errors/unique-violation';
import type { AppConfig } from '../config/configuration';
import { REDIS_KEYS } from '../redis/redis-keys';
import { RedisService } from '../redis/redis.service';
import { RoomBroadcaster } from '../rooms/room-broadcaster';
import { GameConfiguration } from '../rooms/entities/game-configuration.entity';
import { Match } from '../rooms/entities/match.entity';
import { MatchPlayer } from '../rooms/entities/match-player.entity';
import {
  MoveEvent,
  type MoveEventType,
} from '../rooms/entities/move-event.entity';
import { User } from '../users/entities/user.entity';
import { GameRejectedError } from './match.errors';
import {
  applyForfeitToState,
  computeForfeitStandings,
  describeMoveTransition,
  describeRollTransition,
  parseTokenId,
  skipForfeitedPlayers,
  socketEventsForStoredIntent,
  toDiceRolledSocketPayload,
  toMatchEndedSocketPayload,
  toMatchStatePayload,
  toPlayerDisconnectedSocketPayload,
  toPlayerForfeitedSocketPayload,
  toPlayerReconnectedSocketPayload,
  toTokenMovedSocketPayload,
  toTurnChangedSocketPayload,
  type DiceRolledPayload,
  type MatchEndedPayload,
  type MatchStateExtras,
  type SeatView,
  type Standing,
  type TokenMovedPayload,
  type TurnChangedPayload,
} from './match-payloads';
import { replayMatchEvents } from './match-replay';

/**
 * Injection token for the dice source MatchService rolls with.
 * Production binds CryptoDiceRoller; tests override it with a
 * FixedDiceRoller (see gameplay.e2e.spec.ts). Replay never uses it
 * — replay re-rolls the recorded values instead.
 */
export const MATCH_DICE_ROLLER = 'MATCH_DICE_ROLLER';

/** One socket event to deliver (used for duplicate replays). */
export interface GameSocketEvent {
  event: string;
  payload: Record<string, unknown>;
}

/** Result of a game intent: fresh, or the original on a duplicate. */
export interface GameIntentResult {
  duplicate: boolean;
  /** Original socket events — non-empty only for duplicates. */
  events: GameSocketEvent[];
}

/** A match as REST clients see it (FR-58 lifecycle reads). */
export interface MatchView {
  id: string;
  roomId: string;
  rulesetVersion: string;
  status: string;
  winnerId: string | null;
  startedAt: string;
  endedAt: string | null;
  seq: number;
  currentPlayerId: string | null;
  phase: string;
  players: Array<{
    userId: string;
    seat: number;
    colour: string;
    result: string | null;
    finishRank: number | null;
    missedTurns: number;
    disconnected: boolean;
    graceEndsAt: string | null;
  }>;
}

/** One row of the ordered move log (FR-58). */
export interface MatchEventView {
  seq: number;
  type: string;
  actorId: string | null;
  payload: Record<string, unknown>;
  createdAt: string;
}

/** A match loaded from PostgreSQL, with its live engine state. */
export interface LoadedGame {
  match: Match;
  roomId: string;
  seats: SeatView[];
  game: LudoGame;
  /** Highest `seq_no` in the log (1 = just `match_started`). */
  seq: number;
  /** The `match_players` rows (missed turns, grace, results). */
  playerRows: MatchPlayer[];
}

/** Timer/grace/missed-turn values (seeded game_configurations row). */
export interface GameTimingConfig {
  turnTimerSeconds: number;
  gracePeriodSeconds: number;
  missedTurnLimit: number;
}

/** Fallback when no game_configurations row exists (G-4/C-11). */
export const DEFAULT_GAME_TIMING: GameTimingConfig = {
  turnTimerSeconds: 30,
  gracePeriodSeconds: 60,
  missedTurnLimit: 3,
};

/** How a player left the match (BR-15 forfeit reasons). */
export type ForfeitReason = 'grace' | 'missed-turns' | 'leave';

/** How long to spin for the per-match Redis lock before refusing. */
const LOCK_WAIT_MS = 5000;
/** Spin interval while waiting for the per-match Redis lock. */
const LOCK_POLL_MS = 20;
/** TTL of the per-match Redis lock (SDD §9.4). */
const LOCK_TTL_SECONDS = 10;
/** Presence key TTL (SDD §9.4 `presence:user:{userId}`). */
const PRESENCE_TTL_SECONDS = 30;
/** Turn/grace sweep cadence — the timer fires within one tick. */
const TURN_SWEEP_MS = 1000;
/** Heartbeat detection sweep cadence (SDD-proposed Q-09, G-13). */
const PRESENCE_SWEEP_MS = 10000;

/** One event row to insert inside a game transaction. */
interface EventRow {
  matchId: string;
  seqNo: number;
  actorId: string | null;
  type: MoveEventType;
  payload: Record<string, unknown>;
  requestId: string | null;
}

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

/**
 * MatchService (Phase 5, Stages 5–6; FR-49–FR-58, SDD §8.6/§8.8).
 *
 * The match aggregate: an in-memory LudoGame under the per-match
 * Redis lock, checkpointed to PostgreSQL after every accepted
 * transition — the `move_events` row *is* the checkpoint (seq_no,
 * actor, type, payload JSONB, request_id). Replay from the log
 * reproduces the state; the in-memory copy is only a cache, keyed
 * by the highest persisted seq, so any node can rebuild the truth
 * from PostgreSQL at any time (CI-05: no result lives only in
 * memory or Redis).
 *
 * Authority: the engine takes intents only. Turn/token ownership
 * and legality are checked here, server-side, on every intent; a
 * client-supplied dice value is ignored + logged; only the server
 * declares the winner and advances turns. A rejected intent changes
 * no state and is reported as `action:rejected` with a code.
 *
 * Idempotency (FR-53): `requestId` dedup via `UNIQUE (match_id,
 * request_id)` — a duplicate returns the ORIGINAL result (same
 * seq), never a second transition. Simultaneous intents serialise
 * under the per-match Redis lock; exactly one transition wins.
 *
 * Stage 6 (FR-52/54/55/56, NFR-32/33) — timers, grace, forfeit,
 * recovery:
 * - Turn timer (30 s, seeded config): the deadline + epoch live
 *   on the `matches` row, written in the same transaction as the
 *   turn's events. A 1 s sweeper fires due timers; exactly one
 *   timeout transition per turn is enforced by the per-match lock
 *   plus the epoch guard (a stale timer whose epoch no longer
 *   matches is ignored). On expiry the server auto-rolls (if
 *   needed) and auto-moves the FIRST legal move in engine order
 *   (DA-04), or skips when no legal move exists; each expiry is
 *   one missed turn for that player.
 * - Disconnect / grace (60 s): a disconnect marks the player
 *   DISCONNECTED, broadcasts `player:disconnected` with
 *   `graceEndsAt`, and starts the grace. A reconnect (same
 *   account, any socket) clears the flags, broadcasts
 *   `player:reconnected`, and serves the persisted state via
 *   `match:state` — a client never restores its own local state.
 *   Grace expiry, 3 consecutive missed turns, or a voluntary
 *   mid-match leave forfeits the player per BR-15 (tokens removed,
 *   recorded as a loss; the match continues while ≥ 2 players
 *   remain, else the sole remaining player wins).
 * - Presence (`presence:user:{userId}`, TTL 30 s) is refreshed on
 *   every authenticated socket message (the heartbeat); a 10 s
 *   sweeper marks players whose presence has lapsed DISCONNECTED,
 *   which covers dead sockets the transport never reported.
 * - Restart recovery (NFR-33): on boot every in-progress match is
 *   replayed from its log — healthy matches are re-armed from the
 *   persisted turn state, a match whose log cannot be replayed is
 *   cleanly cancelled (status `cancelled`, reason logged) instead
 *   of resuming corrupted. C-12: there is no flagged status; a
 *   match that fails validation is cancelled, never flagged.
 *
 * Redis-down: when the lock cannot be reached, mutations fall back
 * to a process-local per-match mutex, so in-progress matches
 * continue on the node holding them (state still checkpointed in
 * PostgreSQL after every transition). New matches are refused
 * while Redis is down — that check lives in RoomsService.startMatch.
 */
@Injectable()
export class MatchService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MatchService.name);

  /** Live games by match id (cache; PostgreSQL is the truth). */
  private readonly games = new Map<string, LoadedGame>();

  /** Process-local per-match mutex chains (Redis-down fallback). */
  private readonly localMutexes = new Map<string, Promise<unknown>>();

  /** Sweeper timers (started in onModuleInit, cleared on destroy). */
  private turnSweepTimer: NodeJS.Timeout | null = null;
  private presenceSweepTimer: NodeJS.Timeout | null = null;

  constructor(
    private readonly dataSource: DataSource,
    private readonly redis: RedisService,
    private readonly broadcaster: RoomBroadcaster,
    @Inject(MATCH_DICE_ROLLER) private readonly diceRoller: DiceRoller,
    /**
     * Optional so unit tests can keep constructing the service with
     * four arguments; without it the seeded config row is looked up
     * by the default ruleset version (1.0.0). In the app
     * ConfigService is global, so it is always injected there.
     */
    @Optional() private readonly config?: ConfigService,
  ) {}

  // -- Lifecycle: recovery + sweepers (Stage 6, NFR-33) -----------------

  /**
   * On boot: recover every in-progress match from its persisted
   * log, then start the turn/grace (1 s) and presence (10 s)
   * sweepers. Recovery never throws — a match that cannot be
   * replayed is cancelled with its reason logged.
   */
  async onModuleInit(): Promise<void> {
    await this.recoverInProgressMatches();
    this.turnSweepTimer = setInterval(() => {
      void this.sweepDueTurnsAndGraces().catch((err: unknown) => {
        this.logger.error(`Turn/grace sweep failed: ${(err as Error).message}`);
      });
    }, TURN_SWEEP_MS);
    this.presenceSweepTimer = setInterval(() => {
      void this.sweepPresence().catch((err: unknown) => {
        this.logger.error(`Presence sweep failed: ${(err as Error).message}`);
      });
    }, PRESENCE_SWEEP_MS);
  }

  onModuleDestroy(): void {
    if (this.turnSweepTimer) clearInterval(this.turnSweepTimer);
    if (this.presenceSweepTimer) clearInterval(this.presenceSweepTimer);
    this.turnSweepTimer = null;
    this.presenceSweepTimer = null;
  }

  /**
   * Restart recovery (NFR-33): replay every in-progress match
   * from its `move_events` log. A healthy match keeps its state
   * and is re-armed from the persisted turn deadline (or armed
   * now when it has none — e.g. it started before Stage 6); a
   * match whose log cannot be replayed is cleanly cancelled
   * (status `cancelled`, reason logged) — it never resumes in a
   * corrupted or half-applied state, and no result is invented
   * for it. Returns the counts, for tests and the boot log.
   */
  async recoverInProgressMatches(): Promise<{
    restored: number;
    rearmed: number;
    cancelled: number;
  }> {
    const rows = await this.dataSource.query(
      `SELECT "id" FROM "matches" WHERE "status" = 'in_progress'`,
    );
    let restored = 0;
    let rearmed = 0;
    let cancelled = 0;
    for (const row of rows as Array<{ id: string }>) {
      const matchId = row.id;
      this.games.delete(matchId);
      try {
        const loaded = await this.loadGame(matchId);
        restored += 1;
        if (!loaded.match.turnEndsAt && !loaded.game.isFinished) {
          const cfg = await this.getGameConfig();
          const deadline = new Date(Date.now() + cfg.turnTimerSeconds * 1000);
          await this.dataSource
            .getRepository(Match)
            .update(
              { id: matchId },
              { turnEndsAt: deadline, turnEpoch: loaded.match.turnEpoch + 1 },
            );
          loaded.match.turnEndsAt = deadline;
          loaded.match.turnEpoch += 1;
          rearmed += 1;
        }
      } catch (err) {
        const reason = (err as Error).message;
        this.logger.error(
          `Restart recovery: cancelling match ${matchId} — ` +
            `its move log cannot be replayed (${reason})`,
        );
        await this.dataSource
          .getRepository(Match)
          .update(
            { id: matchId },
            { status: 'cancelled', endedAt: new Date(), turnEndsAt: null },
          );
        cancelled += 1;
      }
    }
    if (rows.length > 0) {
      this.logger.log(
        `Restart recovery: ${restored} match(es) restored ` +
          `(${rearmed} re-armed), ${cancelled} cancelled`,
      );
    }
    return { restored, rearmed, cancelled };
  }

  /** One turn/grace sweep tick: due turn timers, then due graces. */
  async sweepDueTurnsAndGraces(): Promise<void> {
    await this.sweepDueTurns();
    await this.sweepExpiredGraces();
  }

  /** Fire every due turn timer (deadline passed, still in progress). */
  async sweepDueTurns(): Promise<void> {
    const rows = await this.dataSource.query(
      `SELECT "id" AS "id" FROM "matches"
        WHERE "status" = 'in_progress'
          AND "turn_ends_at" IS NOT NULL
          AND "turn_ends_at" <= now()`,
    );
    for (const row of rows as Array<{ id: string }>) {
      try {
        await this.processTurnTimeout(row.id);
      } catch (err) {
        this.logger.error(
          `Turn timeout for match ${row.id} failed: ${(err as Error).message}`,
        );
      }
    }
  }

  /** Forfeit every player whose grace expired (BR-15). */
  async sweepExpiredGraces(): Promise<void> {
    const rows = await this.dataSource.query(
      `SELECT p."match_id" AS "matchId", p."user_id" AS "userId"
         FROM "match_players" p
         JOIN "matches" m ON m."id" = p."match_id"
        WHERE m."status" = 'in_progress'
          AND p."result" IS NULL
          AND p."grace_ends_at" IS NOT NULL
          AND p."grace_ends_at" <= now()`,
    );
    for (const row of rows as Array<{ matchId: string; userId: string }>) {
      try {
        await this.forfeitPlayer(row.matchId, row.userId, 'grace');
      } catch (err) {
        this.logger.error(
          `Grace forfeit for match ${row.matchId} user ${row.userId} ` +
            `failed: ${(err as Error).message}`,
        );
      }
    }
  }

  /**
   * Heartbeat detection (10 s sweep, G-13): any player of an
   * in-progress match who is not marked disconnected, not
   * forfeited, and whose presence key has lapsed (no heartbeat
   * within its 30 s TTL) is marked DISCONNECTED with a fresh
   * grace. A connected client heartbeats every 10 s (its `ping`),
   * so a live player is never marked by this sweep; a dead
   * socket is caught at most ~30 s after its last heartbeat.
   */
  async sweepPresence(): Promise<void> {
    const rows = await this.dataSource.query(
      `SELECT p."match_id" AS "matchId", p."user_id" AS "userId"
         FROM "match_players" p
         JOIN "matches" m ON m."id" = p."match_id"
        WHERE m."status" = 'in_progress'
          AND p."result" IS NULL
          AND p."disconnected_at" IS NULL`,
    );
    for (const row of rows as Array<{ matchId: string; userId: string }>) {
      try {
        if (!(await this.isPresent(row.userId))) {
          await this.handlePlayerDisconnected(row.userId);
        }
      } catch (err) {
        this.logger.error(
          `Presence sweep for user ${row.userId} failed: ` +
            `${(err as Error).message}`,
        );
      }
    }
  }

  // -- Presence (Stage 6, FR-54; SDD §9.4) ------------------------------

  /** The frozen ruleset version (config, or the 1.0.0 default). */
  private get rulesetVersion(): string {
    try {
      return this.config?.get<AppConfig>('app')?.rulesetVersion ?? '1.0.0';
    } catch {
      return '1.0.0';
    }
  }

  /** Timer/grace/missed-turn values from the seeded config row. */
  async getGameConfig(): Promise<GameTimingConfig> {
    const repo = this.dataSource.getRepository(GameConfiguration);
    const row =
      (await repo.findOne({ where: { version: this.rulesetVersion } })) ??
      (
        await repo.find({
          order: { createdAt: 'ASC' },
          take: 1,
        })
      )[0];
    if (!row) return { ...DEFAULT_GAME_TIMING };
    const sane = (value: unknown, fallback: number): number =>
      typeof value === 'number' && Number.isInteger(value) && value > 0
        ? value
        : fallback;
    return {
      turnTimerSeconds: sane(
        row.turnTimerSeconds,
        DEFAULT_GAME_TIMING.turnTimerSeconds,
      ),
      gracePeriodSeconds: sane(
        row.gracePeriodSeconds,
        DEFAULT_GAME_TIMING.gracePeriodSeconds,
      ),
      missedTurnLimit: sane(
        row.missedTurnLimit,
        DEFAULT_GAME_TIMING.missedTurnLimit,
      ),
    };
  }

  /**
   * Record a heartbeat: `presence:user:{userId}` = now, TTL 30 s.
   * Best-effort — a Redis failure is logged, never thrown, so a
   * presence write can never break a connect or a game intent.
   */
  async markPresence(userId: string): Promise<void> {
    try {
      await this.redis.set(
        REDIS_KEYS.presenceUser(userId),
        new Date().toISOString(),
        PRESENCE_TTL_SECONDS,
      );
    } catch (err) {
      this.logger.warn(
        `Presence write failed for user ${userId}: ${(err as Error).message}`,
      );
    }
  }

  /** Alias for markPresence — every authenticated message heartbeats. */
  async touchPresence(userId: string): Promise<void> {
    await this.markPresence(userId);
  }

  /** Drop the presence key (clean disconnect). Best-effort. */
  async clearPresence(userId: string): Promise<void> {
    try {
      await this.redis.del(REDIS_KEYS.presenceUser(userId));
    } catch (err) {
      this.logger.warn(
        `Presence clear failed for user ${userId}: ${(err as Error).message}`,
      );
    }
  }

  /**
   * True when a recent heartbeat exists. Fail-open: when Redis is
   * unreachable the answer is "present" — a Redis outage must
   * never mass-mark players disconnected.
   */
  async isPresent(userId: string): Promise<boolean> {
    try {
      return (await this.redis.get(REDIS_KEYS.presenceUser(userId))) !== null;
    } catch {
      return true;
    }
  }

  // -- Reads ---------------------------------------------------------------

  /** Room + seats for a match, after a membership check (gateway join). */
  async getMatchRoom(
    matchId: string,
    userId: string,
  ): Promise<{ roomId: string; seats: SeatView[] }> {
    const loaded = await this.loadGame(matchId);
    this.requireSeat(loaded, userId);
    return { roomId: loaded.roomId, seats: loaded.seats };
  }

  /** The match view for a player (403 NOT_MATCH_PLAYER otherwise). */
  async getMatchView(matchId: string, userId: string): Promise<MatchView> {
    const loaded = await this.loadGame(matchId);
    this.requireSeat(loaded, userId);
    return this.toMatchView(loaded);
  }

  /** The caller's in-progress match, or null. */
  async getActiveMatch(userId: string): Promise<MatchView | null> {
    const rows = await this.dataSource.query(
      `SELECT p."match_id" AS "matchId" FROM "match_players" p
        JOIN "matches" m ON m."id" = p."match_id"
       WHERE p."user_id" = $1 AND m."status" = 'in_progress' LIMIT 1`,
      [userId],
    );
    if (rows.length === 0) return null;
    return this.getMatchView(rows[0].matchId as string, userId);
  }

  /** Full snapshot for a player (REST; the socket path is requestState). */
  async getMatchState(
    matchId: string,
    userId: string,
  ): Promise<Record<string, unknown>> {
    const loaded = await this.loadGame(matchId);
    this.requireSeat(loaded, userId);
    return toMatchStatePayload(
      matchId,
      loaded.game.snapshot(),
      loaded.seq,
      loaded.seats,
      this.stateExtras(loaded),
    );
  }

  /**
   * Snapshot for a socket `state:request` (FR-57). A `lastSeq`
   * ahead of the server state is rejected as STALE_STATE — the
   * client is ahead of the truth, which must never happen. Works
   * for a finished match too: a reconnect to a finished match
   * returns the final state, not a live seat (Stage 6).
   */
  async requestState(
    matchId: string,
    userId: string,
    lastSeq: number,
  ): Promise<Record<string, unknown>> {
    const loaded = await this.loadGame(matchId);
    this.requireSeat(loaded, userId);
    if (lastSeq > loaded.seq) throw GameRejectedError.staleState();
    return toMatchStatePayload(
      matchId,
      loaded.game.snapshot(),
      loaded.seq,
      loaded.seats,
      this.stateExtras(loaded),
    );
  }

  /** The ordered move log from `fromSeq` (FR-58 read path). */
  async listEvents(
    matchId: string,
    userId: string,
    fromSeq: number,
    limit: number,
  ): Promise<{
    matchId: string;
    seq: number;
    events: MatchEventView[];
  }> {
    const loaded = await this.loadGame(matchId);
    this.requireSeat(loaded, userId);
    const rows = await this.dataSource.getRepository(MoveEvent).find({
      where: { matchId, seqNo: MoreThanOrEqual(fromSeq) },
      order: { seqNo: 'ASC' },
      take: limit,
    });
    return {
      matchId,
      seq: loaded.seq,
      events: rows.map((r) => ({
        seq: r.seqNo,
        type: r.type,
        actorId: r.actorId,
        payload: r.payload,
        createdAt: r.createdAt.toISOString(),
      })),
    };
  }

  /**
   * Load (or reload) a match's live state from PostgreSQL. The
   * cache is trusted only when its seq equals the highest persisted
   * seq — any node can rebuild the truth by replaying the log.
   */
  async loadGame(matchId: string): Promise<LoadedGame> {
    const match = await this.dataSource
      .getRepository(Match)
      .findOne({ where: { id: matchId } });
    if (!match) throw GameRejectedError.matchNotFound(matchId);
    const maxSeqRows = await this.dataSource.query(
      `SELECT COALESCE(MAX("seq_no"), 0) AS "maxSeq" FROM "move_events" WHERE "match_id" = $1`,
      [matchId],
    );
    const maxSeq = Number(maxSeqRows[0]?.maxSeq ?? 0);
    const cached = this.games.get(matchId);
    if (cached && cached.seq === maxSeq) return cached;
    const players = await this.dataSource
      .getRepository(MatchPlayer)
      .find({ where: { matchId }, order: { seat: 'ASC' } });
    const users =
      players.length > 0
        ? await this.dataSource
            .getRepository(User)
            .find({ where: { id: In(players.map((p) => p.userId)) } })
        : [];
    const nameById = new Map(users.map((u) => [u.id, u.username]));
    const events = await this.dataSource
      .getRepository(MoveEvent)
      .find({ where: { matchId }, order: { seqNo: 'ASC' } });
    const game = replayMatchEvents({
      seats: players.map((p) => ({
        seat: p.seat,
        colour: p.colour,
        name: nameById.get(p.userId) ?? 'unknown',
      })),
      rulesetVersion: match.rulesetVersion,
      startedAt: match.startedAt,
      events: events.map((e) => ({
        seqNo: e.seqNo,
        type: e.type,
        payload: e.payload,
      })),
      liveDiceRoller: this.diceRoller,
    });
    const loaded: LoadedGame = {
      match,
      roomId: match.roomId,
      seats: players.map((p) => ({
        userId: p.userId,
        seat: p.seat,
        colour: p.colour,
      })),
      game,
      seq: events.length > 0 ? events[events.length - 1].seqNo : 0,
      playerRows: players,
    };
    this.games.set(matchId, loaded);
    return loaded;
  }

  // -- Disconnect / reconnect (Stage 6, FR-54/55/56) ----------------------

  /**
   * Mark a player DISCONNECTED (FR-54): sets the disconnect +
   * grace timestamps and broadcasts `player:disconnected
   * {matchId, playerId, graceEndsAt}`. Idempotent — a player
   * already marked, forfeited, or in no in-progress match is a
   * no-op (repeated disconnects / stale sockets). Returns true
   * when the player was newly marked.
   */
  async handlePlayerDisconnected(userId: string): Promise<boolean> {
    const active = await this.findActiveMatchId(userId);
    if (!active) return false;
    return this.withMatchLock(active, async () => {
      const loaded = await this.loadGame(active);
      const row = this.playerRow(loaded, userId);
      if (!row || row.result) return false;
      if (row.disconnectedAt) return false;
      const cfg = await this.getGameConfig();
      const now = new Date();
      const graceEndsAt = new Date(
        now.getTime() + cfg.gracePeriodSeconds * 1000,
      );
      await this.dataSource
        .getRepository(MatchPlayer)
        .update(
          { matchId: active, userId },
          { disconnectedAt: now, graceEndsAt },
        );
      this.syncPlayerRow(loaded, userId, {
        disconnectedAt: now,
        graceEndsAt,
      });
      await this.broadcaster.emitGameEvent(
        loaded.roomId,
        loaded.seats.map((s) => s.userId),
        'player:disconnected',
        toPlayerDisconnectedSocketPayload(
          active,
          loaded.seq,
          userId,
          graceEndsAt.toISOString(),
        ),
      );
      return true;
    });
  }

  /**
   * Reconnect (FR-55): same account, any socket. Clears the
   * disconnect/grace flags and broadcasts `player:reconnected`.
   * The caller serves the persisted state via `match:state` — a
   * reconnecting client must never restore its own locally stored
   * state. Idempotent; returns true when flags were cleared.
   */
  async handlePlayerConnected(userId: string): Promise<boolean> {
    const active = await this.findActiveMatchId(userId);
    if (!active) return false;
    return this.withMatchLock(active, async () => {
      const loaded = await this.loadGame(active);
      const row = this.playerRow(loaded, userId);
      if (!row || row.result) return false;
      if (!row.disconnectedAt) return false;
      await this.dataSource
        .getRepository(MatchPlayer)
        .update(
          { matchId: active, userId },
          { disconnectedAt: null, graceEndsAt: null },
        );
      this.syncPlayerRow(loaded, userId, {
        disconnectedAt: null,
        graceEndsAt: null,
      });
      await this.broadcaster.emitGameEvent(
        loaded.roomId,
        loaded.seats.map((s) => s.userId),
        'player:reconnected',
        toPlayerReconnectedSocketPayload(active, loaded.seq, userId),
      );
      return true;
    });
  }

  /**
   * Voluntary mid-match leave (FR-56, G-15): forfeits the player
   * (BR-15). The UX copy/confirmation is Stage 7; this is the
   * backend trigger. Returns the match id, or null when the user
   * is in no in-progress match.
   */
  async leaveMatch(
    userId: string,
  ): Promise<{ matchId: string; forfeited: boolean } | null> {
    const active = await this.findActiveMatchId(userId);
    if (!active) return null;
    const result = await this.forfeitPlayer(active, userId, 'leave');
    return { matchId: active, forfeited: result.forfeited };
  }

  /**
   * Forfeit a player (BR-15): grace expiry, 3 consecutive missed
   * turns, or voluntary leave. Tokens leave the board, the result
   * is recorded as a loss (`forfeit`), a `player_forfeited`
   * `move_events` row is written, and `player:forfeited` is
   * broadcast. The match continues while ≥ 2 players remain;
   * otherwise the sole remaining player wins and the match ends
   * (`match:ended` with standings). Idempotent.
   */
  async forfeitPlayer(
    matchId: string,
    userId: string,
    reason: ForfeitReason,
  ): Promise<{ forfeited: boolean; ended: boolean; winnerId: string | null }> {
    return this.withMatchLock(matchId, async () => {
      const loaded = await this.loadGame(matchId);
      return this.forfeitPlayerLocked(loaded, userId, reason);
    });
  }

  /**
   * The forfeit itself, with the per-match lock already held (so
   * the turn-timeout path can forfeit after its auto-play without
   * re-entering the lock). Operates on the passed-in loaded game
   * and updates it in place.
   */
  private async forfeitPlayerLocked(
    loaded: LoadedGame,
    userId: string,
    reason: ForfeitReason,
  ): Promise<{ forfeited: boolean; ended: boolean; winnerId: string | null }> {
    const matchId = loaded.match.id;
    if (loaded.match.status !== 'in_progress' || loaded.game.isFinished) {
      return { forfeited: false, ended: false, winnerId: null };
    }
    const seat = this.requireSeat(loaded, userId).seat;
    const row = this.playerRow(loaded, userId);
    if (!row || row.result) {
      return { forfeited: false, ended: false, winnerId: null };
    }
    const cfg = await this.getGameConfig();
    const forfeitedSeats = new Set(
      loaded.playerRows
        .filter((p) => p.result === 'forfeit')
        .map((p) => p.seat),
    );
    forfeitedSeats.add(seat);
    const before = loaded.game.state;
    const newState = applyForfeitToState(before, seat, forfeitedSeats);
    const activeAfter = loaded.playerRows.filter(
      (p) => p.userId !== userId && !p.result,
    );
    const matchEnds = activeAfter.length < 2;
    const winnerSeat =
      matchEnds && activeAfter.length === 1 ? activeAfter[0].seat : null;
    const winnerId =
      winnerSeat === null ? null : loaded.seats[winnerSeat].userId;
    const turnPassed =
      !matchEnds && newState.currentPlayerIndex !== before.currentPlayerIndex;
    const standings =
      winnerSeat === null
        ? null
        : computeForfeitStandings(
            newState,
            loaded.seats,
            winnerSeat,
            forfeitedSeats,
          ).standings;
    const seq = loaded.seq + 1;
    const followUpSeq = seq + 1;
    // A match that ends with nobody left cannot name a winner —
    // unreachable (the match ends as soon as < 2 remain), but if
    // it ever happened, cancel rather than invent a result (C-12).
    const cancelMatch = matchEnds && winnerSeat === null;
    const newDeadline = new Date(Date.now() + cfg.turnTimerSeconds * 1000);
    const outcome = await this.runGameTransaction(matchId, async (m) => {
      await this.insertEvent(m, {
        matchId,
        seqNo: seq,
        actorId: userId,
        type: 'player_forfeited',
        payload: {
          playerId: userId,
          seat,
          reason,
          snapshot: newState.toJson(),
        },
        requestId: null,
      });
      if (turnPassed) {
        await this.insertEvent(m, {
          matchId,
          seqNo: followUpSeq,
          actorId: null,
          type: 'turn_changed',
          payload: {
            playerId: loaded.seats[newState.currentPlayerIndex].userId,
            snapshot: newState.toJson(),
          },
          requestId: null,
        });
      }
      if (matchEnds && !cancelMatch) {
        await this.insertEvent(m, {
          matchId,
          seqNo: followUpSeq,
          actorId: userId,
          type: 'match_ended',
          payload: {
            winnerId: winnerId!,
            standings: standings!,
            snapshot: newState.toJson(),
          } satisfies MatchEndedPayload as unknown as Record<string, unknown>,
          requestId: null,
        });
        await m.getRepository(Match).update(
          { id: matchId },
          {
            status: 'completed',
            winnerId,
            endedAt: new Date(),
            turnEndsAt: null,
          },
        );
        for (const standing of standings!) {
          await m
            .getRepository(MatchPlayer)
            .update(
              { matchId, userId: standing.userId },
              { result: standing.result, finishRank: standing.rank },
            );
        }
      } else if (cancelMatch) {
        await m
          .getRepository(Match)
          .update(
            { id: matchId },
            { status: 'cancelled', endedAt: new Date(), turnEndsAt: null },
          );
      } else {
        await m
          .getRepository(MatchPlayer)
          .update({ matchId, userId }, { result: 'forfeit' });
        await m
          .getRepository(Match)
          .update(
            { id: matchId },
            { turnEndsAt: newDeadline, turnEpoch: loaded.match.turnEpoch + 1 },
          );
      }
    });
    if (outcome === 'duplicate') {
      // A seq collision means another writer committed first; the
      // cache is already dropped — re-check from the truth.
      const fresh = await this.loadGame(matchId);
      const freshRow = this.playerRow(fresh, userId);
      return {
        forfeited: freshRow?.result === 'forfeit',
        ended: fresh.match.status !== 'in_progress',
        winnerId: fresh.match.winnerId,
      };
    }
    loaded.game = LudoGame.fromState(newState, {
      ruleset: loaded.game.ruleset,
      diceRoller: this.diceRoller,
    });
    loaded.seq = seq + (turnPassed || (matchEnds && !cancelMatch) ? 1 : 0);
    if (matchEnds && !cancelMatch) {
      loaded.match.status = 'completed';
      loaded.match.winnerId = winnerId;
      loaded.match.endedAt = new Date();
      loaded.match.turnEndsAt = null;
      for (const standing of standings!) {
        this.syncPlayerRow(loaded, standing.userId, {
          result: standing.result,
          finishRank: standing.rank,
        });
      }
    } else if (cancelMatch) {
      loaded.match.status = 'cancelled';
      loaded.match.endedAt = new Date();
      loaded.match.turnEndsAt = null;
      this.logger.error(
        `Forfeit of ${userId} left match ${matchId} with no players ` +
          `— match cancelled instead of naming a winner.`,
      );
    } else {
      loaded.match.turnEndsAt = newDeadline;
      loaded.match.turnEpoch += 1;
      this.syncPlayerRow(loaded, userId, { result: 'forfeit' });
    }
    this.games.set(matchId, loaded);
    const memberIds = loaded.seats.map((s) => s.userId);
    await this.broadcaster.emitGameEvent(
      loaded.roomId,
      memberIds,
      'player:forfeited',
      toPlayerForfeitedSocketPayload(matchId, seq, userId),
    );
    if (turnPassed) {
      await this.broadcaster.emitGameEvent(
        loaded.roomId,
        memberIds,
        'turn:changed',
        toTurnChangedSocketPayload(
          matchId,
          followUpSeq,
          loaded.seats[newState.currentPlayerIndex].userId,
          newDeadline.toISOString(),
        ),
      );
    }
    if (matchEnds && !cancelMatch) {
      await this.broadcaster.emitGameEvent(
        loaded.roomId,
        memberIds,
        'match:ended',
        toMatchEndedSocketPayload(matchId, followUpSeq, {
          winnerId: winnerId!,
          standings: standings!,
          snapshot: newState.toJson(),
        }),
      );
    }
    return {
      forfeited: true,
      ended: matchEnds && !cancelMatch,
      winnerId,
    };
  }

  // -- Turn timers (Stage 6, FR-52) ----------------------------------------

  /**
   * Fire one due turn timer (FR-52, G-9): the timer spans the
   * whole turn (roll + move). On expiry the server auto-rolls if
   * the player has not rolled, then auto-moves the FIRST legal
   * move in engine order (DA-04), or skips when no legal move
   * exists. Each expiry is one missed turn for that player; at
   * the seeded limit (3 consecutive) the player forfeits (BR-15).
   *
   * Exactly once per turn: the caller passes the epoch it armed
   * for (the sweeper passes none and relies on the deadline), and
   * the stored epoch must still match — a stale timer whose turn
   * already advanced is ignored. Returns what happened, for
   * tests: `applied` (an auto-play ran), `ignored` (no live
   * match/turn), `stale` (epoch moved on), `not-due` (deadline
   * still in the future).
   */
  async processTurnTimeout(
    matchId: string,
    expectedEpoch?: number,
  ): Promise<'applied' | 'ignored' | 'stale' | 'not-due'> {
    return this.withMatchLock(matchId, async () => {
      const loaded = await this.loadGame(matchId);
      if (loaded.match.status !== 'in_progress' || loaded.game.isFinished) {
        return 'ignored';
      }
      if (
        expectedEpoch !== undefined &&
        expectedEpoch !== loaded.match.turnEpoch
      ) {
        return 'stale';
      }
      const endsAt = loaded.match.turnEndsAt;
      if (!endsAt || endsAt.getTime() > Date.now()) return 'not-due';
      const cfg = await this.getGameConfig();
      const seat = loaded.game.currentPlayerIndex;
      const playerId = loaded.seats[seat].userId;
      const playerRow = this.playerRow(loaded, playerId);
      if (!playerRow || playerRow.result) return 'ignored';
      const forfeitedSeats = new Set(
        loaded.playerRows
          .filter((p) => p.result === 'forfeit')
          .map((p) => p.seat),
      );
      const missed = (playerRow.missedTurns ?? 0) + 1;

      // Auto-play: roll if needed, then the first legal move.
      const beforeRoll = loaded.game.state;
      let rolledValue: number | null = null;
      let rollSnapshot: Record<string, unknown> | null = null;
      let rollTurnChangedPlayerId: string | null = null;
      if (loaded.game.state.phase === 'awaitingRoll') {
        try {
          rolledValue = loaded.game.rollDice();
        } catch (err) {
          throw GameRejectedError.invalidState((err as Error).message);
        }
        const afterRoll = this.skipForfeited(loaded, forfeitedSeats);
        rollSnapshot = afterRoll.toJson();
        rollTurnChangedPlayerId =
          afterRoll.currentPlayerIndex !== beforeRoll.currentPlayerIndex
            ? loaded.seats[afterRoll.currentPlayerIndex].userId
            : null;
      }
      let moved: {
        tokenId: string;
        payload: TokenMovedPayload;
        turnChangedPlayerId: string | null;
      } | null = null;
      if (loaded.game.state.phase === 'awaitingMove') {
        const legal = loaded.game.legalMoves();
        if (legal.length > 0) {
          const first = legal[0];
          const beforeMove = loaded.game.state;
          let result: MoveResult;
          try {
            result = loaded.game.applyMove(first);
          } catch (err) {
            throw GameRejectedError.invalidState((err as Error).message);
          }
          const afterMove = this.skipForfeited(loaded, forfeitedSeats);
          const desc = describeMoveTransition({
            before: beforeMove,
            after: afterMove,
            result,
            seats: loaded.seats,
          });
          moved = {
            tokenId: `${first.playerIndex}:${first.tokenIndex}`,
            payload: {
              playerId,
              tokenId: `${first.playerIndex}:${first.tokenIndex}`,
              fromSteps: result.fromSteps,
              toSteps: result.toSteps,
              landing: desc.landing,
              captured: desc.captured,
              extraTurn: desc.extraTurn,
              winnerId: desc.winnerId,
              currentPlayerId: desc.currentPlayerId,
              turnChangedPlayerId: desc.turnChangedPlayerId,
              matchEnded:
                desc.winnerId === null
                  ? null
                  : { winnerId: desc.winnerId, standings: desc.standings! },
              snapshot: afterMove.toJson(),
            },
            turnChangedPlayerId: desc.turnChangedPlayerId,
          };
        }
        // No legal move in awaitingMove cannot happen (rollDice only
        // leaves awaitingMove when a legal move exists) — but if it
        // ever did, the turn simply ends below with no move row.
      }
      const after = loaded.game.state;
      const winnerId = moved?.payload.winnerId ?? null;
      const turnChangedPlayerId =
        moved?.turnChangedPlayerId ?? rollTurnChangedPlayerId;
      const matchEnded = winnerId !== null;
      const newDeadline = new Date(Date.now() + cfg.turnTimerSeconds * 1000);
      const newEpoch = loaded.match.turnEpoch + 1;
      // Seq layout mirrors rollDice/moveToken: the primary rows
      // first (dice, then move), one follow-up row (turn change or
      // match end) at last primary seq + 1.
      let seq = loaded.seq + 1;
      const diceSeq = rolledValue !== null ? seq : null;
      if (moved) seq += 1;
      const moveSeq = moved ? (diceSeq !== null ? diceSeq + 1 : seq) : null;
      const followUpSeq =
        turnChangedPlayerId || matchEnded
          ? (moveSeq ?? diceSeq ?? seq) + 1
          : null;
      const standings = moved?.payload.matchEnded?.standings ?? null;
      const outcome = await this.runGameTransaction(matchId, async (m) => {
        if (rolledValue !== null) {
          await this.insertEvent(m, {
            matchId,
            seqNo: diceSeq!,
            actorId: playerId,
            type: 'dice_rolled',
            payload: {
              playerId,
              value: rolledValue,
              turnChangedPlayerId: rollTurnChangedPlayerId,
              snapshot: rollSnapshot!,
            } satisfies DiceRolledPayload as unknown as Record<string, unknown>,
            requestId: null,
          });
        }
        if (moved) {
          await this.insertEvent(m, {
            matchId,
            seqNo: moveSeq!,
            actorId: playerId,
            type: 'token_moved',
            payload: moved.payload as unknown as Record<string, unknown>,
            requestId: null,
          });
        }
        if (turnChangedPlayerId && followUpSeq !== null) {
          await this.insertEvent(m, {
            matchId,
            seqNo: followUpSeq,
            actorId: null,
            type: 'turn_changed',
            payload: {
              playerId: turnChangedPlayerId,
              snapshot: after.toJson(),
            },
            requestId: null,
          });
        }
        if (matchEnded && followUpSeq !== null) {
          await this.insertEvent(m, {
            matchId,
            seqNo: followUpSeq,
            actorId: playerId,
            type: 'match_ended',
            payload: {
              winnerId: winnerId!,
              standings: standings!,
              snapshot: after.toJson(),
            } satisfies MatchEndedPayload as unknown as Record<string, unknown>,
            requestId: null,
          });
          await m.getRepository(Match).update(
            { id: matchId },
            {
              status: 'completed',
              winnerId,
              endedAt: new Date(),
              turnEndsAt: null,
            },
          );
          for (const standing of standings!) {
            await m
              .getRepository(MatchPlayer)
              .update(
                { matchId, userId: standing.userId },
                { result: standing.result, finishRank: standing.rank },
              );
          }
        } else {
          await m
            .getRepository(Match)
            .update(
              { id: matchId },
              { turnEndsAt: newDeadline, turnEpoch: newEpoch },
            );
        }
        await m
          .getRepository(MatchPlayer)
          .update({ matchId, userId: playerId }, { missedTurns: missed });
      });
      if (outcome === 'duplicate') {
        // A seq collision means another writer committed first.
        return 'ignored';
      }
      const finalSeq = followUpSeq ?? moveSeq ?? diceSeq ?? loaded.seq;
      loaded.seq = finalSeq;
      if (matchEnded) {
        loaded.match.status = 'completed';
        loaded.match.winnerId = winnerId;
        loaded.match.endedAt = new Date();
        loaded.match.turnEndsAt = null;
        for (const standing of standings!) {
          this.syncPlayerRow(loaded, standing.userId, {
            result: standing.result,
            finishRank: standing.rank,
          });
        }
      } else {
        loaded.match.turnEndsAt = newDeadline;
        loaded.match.turnEpoch = newEpoch;
      }
      this.syncPlayerRow(loaded, playerId, { missedTurns: missed });
      this.games.set(matchId, loaded);
      const memberIds = loaded.seats.map((s) => s.userId);
      const deadlineIso = matchEnded ? null : newDeadline.toISOString();
      if (rolledValue !== null) {
        await this.broadcaster.emitGameEvent(
          loaded.roomId,
          memberIds,
          'dice:rolled',
          toDiceRolledSocketPayload(matchId, diceSeq!, {
            playerId,
            value: rolledValue,
            turnChangedPlayerId: rollTurnChangedPlayerId,
            snapshot: rollSnapshot!,
          }),
        );
      }
      if (moved) {
        await this.broadcaster.emitGameEvent(
          loaded.roomId,
          memberIds,
          'token:moved',
          toTokenMovedSocketPayload(
            matchId,
            moveSeq!,
            moved.payload,
            deadlineIso,
          ),
        );
      }
      if (turnChangedPlayerId && followUpSeq !== null) {
        await this.broadcaster.emitGameEvent(
          loaded.roomId,
          memberIds,
          'turn:changed',
          toTurnChangedSocketPayload(
            matchId,
            followUpSeq,
            turnChangedPlayerId,
            deadlineIso,
          ),
        );
      }
      if (matchEnded && followUpSeq !== null) {
        await this.broadcaster.emitGameEvent(
          loaded.roomId,
          memberIds,
          'match:ended',
          toMatchEndedSocketPayload(matchId, followUpSeq, {
            winnerId: winnerId!,
            standings: standings!,
            snapshot: after.toJson(),
          }),
        );
        return 'applied';
      }
      // 3 consecutive missed turns forfeits the player (BR-15).
      // The forfeit runs after the auto-play, under the same lock.
      if (missed >= cfg.missedTurnLimit) {
        const fresh = await this.loadGame(matchId);
        await this.forfeitPlayerLocked(fresh, playerId, 'missed-turns');
      }
      return 'applied';
    });
  }

  // -- Intents ---------------------------------------------------------------

  /**
   * `dice:roll` (FR-49). The server generates the roll; a
   * client-supplied `value` is ignored and logged (SDD §8.8).
   * Returns the original result on a duplicate `requestId`.
   * A manual roll resets the player's consecutive missed-turn
   * count (G-5); acting also clears a stale DISCONNECTED mark
   * left by the presence sweep (the player is plainly live).
   */
  async rollDice(
    matchId: string,
    userId: string,
    requestId: string,
    clientValue?: number,
  ): Promise<GameIntentResult> {
    if (clientValue !== undefined) {
      this.logger.warn(
        `Ignoring client-supplied dice value ${clientValue} ` +
          `(match=${matchId} user=${userId})`,
      );
    }
    return this.withMatchLock(matchId, async () => {
      const loaded = await this.loadGame(matchId);
      const seat = this.requireSeat(loaded, userId);
      const duplicate = await this.duplicateResult(matchId, requestId, userId);
      if (duplicate) return duplicate;
      this.requireInProgress(loaded);
      this.requireActivePlayer(loaded, userId);
      if (loaded.game.currentPlayerIndex !== seat.seat) {
        throw GameRejectedError.notYourTurn();
      }
      if (loaded.game.state.phase !== 'awaitingRoll') {
        throw GameRejectedError.invalidState(
          'A roll is already outstanding. Move a token first.',
        );
      }
      const cfg = await this.getGameConfig();
      const wasDisconnected = !!this.playerRow(loaded, userId)?.disconnectedAt;
      const before = loaded.game.state;
      let value: number;
      try {
        value = loaded.game.rollDice();
      } catch (err) {
        throw GameRejectedError.invalidState((err as Error).message);
      }
      const after = this.skipForfeited(loaded, this.forfeitedSeats(loaded));
      const { turnChangedPlayerId } = describeRollTransition({
        before,
        after,
        seats: loaded.seats,
      });
      const seq = loaded.seq + 1;
      // The timer spans the whole turn: it re-arms only when the
      // turn passes (or when no deadline was persisted yet). The
      // deadline is computed BEFORE the payload so the stored row
      // carries it — a duplicate `requestId` must re-emit the exact
      // original result, deadline included (FR-53).
      const newDeadline =
        turnChangedPlayerId || !loaded.match.turnEndsAt
          ? new Date(Date.now() + cfg.turnTimerSeconds * 1000)
          : loaded.match.turnEndsAt;
      const newEpoch =
        turnChangedPlayerId || !loaded.match.turnEndsAt
          ? loaded.match.turnEpoch + 1
          : loaded.match.turnEpoch;
      const dicePayload: DiceRolledPayload = {
        playerId: userId,
        value,
        turnChangedPlayerId,
        turnEndsAt: newDeadline.toISOString(),
        snapshot: after.toJson(),
      };
      const turnPayload: TurnChangedPayload | null =
        turnChangedPlayerId === null
          ? null
          : { playerId: turnChangedPlayerId, snapshot: after.toJson() };
      const outcome = await this.runGameTransaction(matchId, async (m) => {
        await this.insertEvent(m, {
          matchId,
          seqNo: seq,
          actorId: userId,
          type: 'dice_rolled',
          payload: dicePayload as unknown as Record<string, unknown>,
          requestId,
        });
        if (turnPayload) {
          await this.insertEvent(m, {
            matchId,
            seqNo: seq + 1,
            actorId: null,
            type: 'turn_changed',
            payload: turnPayload as unknown as Record<string, unknown>,
            requestId: null,
          });
        }
        await m
          .getRepository(Match)
          .update(
            { id: matchId },
            { turnEndsAt: newDeadline, turnEpoch: newEpoch },
          );
        await m
          .getRepository(MatchPlayer)
          .update({ matchId, userId }, { missedTurns: 0 });
        if (wasDisconnected) {
          await m
            .getRepository(MatchPlayer)
            .update(
              { matchId, userId },
              { disconnectedAt: null, graceEndsAt: null },
            );
        }
      });
      const retried = await this.handleTransactionOutcome(
        matchId,
        requestId,
        userId,
        outcome,
      );
      if (retried) return retried;
      loaded.seq = seq + (turnPayload ? 1 : 0);
      loaded.match.turnEndsAt = newDeadline;
      loaded.match.turnEpoch = newEpoch;
      this.syncPlayerRow(loaded, userId, { missedTurns: 0 });
      if (wasDisconnected) {
        this.syncPlayerRow(loaded, userId, {
          disconnectedAt: null,
          graceEndsAt: null,
        });
      }
      this.games.set(matchId, loaded);
      const memberIds = loaded.seats.map((s) => s.userId);
      await this.broadcaster.emitGameEvent(
        loaded.roomId,
        memberIds,
        'dice:rolled',
        toDiceRolledSocketPayload(matchId, seq, dicePayload),
      );
      if (turnChangedPlayerId) {
        await this.broadcaster.emitGameEvent(
          loaded.roomId,
          memberIds,
          'turn:changed',
          toTurnChangedSocketPayload(
            matchId,
            seq + 1,
            turnChangedPlayerId,
            newDeadline.toISOString(),
          ),
        );
      }
      if (wasDisconnected) {
        await this.broadcaster.emitGameEvent(
          loaded.roomId,
          memberIds,
          'player:reconnected',
          toPlayerReconnectedSocketPayload(matchId, loaded.seq, userId),
        );
      }
      return { duplicate: false, events: [] };
    });
  }

  /**
   * `token:move` (FR-50). Legality is decided by the engine; the
   * intent only names the token. Returns the original result on a
   * duplicate `requestId`. A move that grants an extra turn
   * re-arms the timer for the continuation (a fresh 30 s window
   * for the extra roll); a move that passes the turn re-arms it
   * for the next player.
   */
  async moveToken(
    matchId: string,
    userId: string,
    tokenId: string,
    requestId: string,
  ): Promise<GameIntentResult> {
    return this.withMatchLock(matchId, async () => {
      const loaded = await this.loadGame(matchId);
      const seat = this.requireSeat(loaded, userId);
      const duplicate = await this.duplicateResult(matchId, requestId, userId);
      if (duplicate) return duplicate;
      this.requireInProgress(loaded);
      this.requireActivePlayer(loaded, userId);
      if (loaded.game.currentPlayerIndex !== seat.seat) {
        throw GameRejectedError.notYourTurn();
      }
      const parsed = parseTokenId(tokenId);
      if (!parsed) {
        throw GameRejectedError.illegalMove(`Malformed tokenId "${tokenId}".`);
      }
      if (parsed.seat !== seat.seat) {
        throw GameRejectedError.illegalMove(
          'That token belongs to another player.',
        );
      }
      if (loaded.game.state.phase !== 'awaitingMove') {
        throw GameRejectedError.invalidState('Roll the dice first.');
      }
      const legal = loaded.game.legalMoves();
      if (
        !legal.some(
          (m) =>
            m.playerIndex === parsed.seat && m.tokenIndex === parsed.tokenIndex,
        )
      ) {
        throw GameRejectedError.illegalMove(
          `Token ${tokenId} cannot move on this roll.`,
        );
      }
      const cfg = await this.getGameConfig();
      const wasDisconnected = !!this.playerRow(loaded, userId)?.disconnectedAt;
      const before = loaded.game.state;
      let result: MoveResult;
      try {
        result = loaded.game.applyMove(
          new Move(parsed.seat, parsed.tokenIndex),
        );
      } catch (err) {
        throw GameRejectedError.illegalMove((err as Error).message);
      }
      const after = this.skipForfeited(loaded, this.forfeitedSeats(loaded));
      const desc = describeMoveTransition({
        before,
        after,
        result,
        seats: loaded.seats,
      });
      const seq = loaded.seq + 1;
      const standings: Standing[] | null = desc.standings;
      const matchEnded = desc.winnerId !== null;
      const rearm =
        !matchEnded &&
        (desc.turnChangedPlayerId !== null ||
          desc.extraTurn ||
          !loaded.match.turnEndsAt);
      const newDeadline = matchEnded
        ? null
        : rearm
          ? new Date(Date.now() + cfg.turnTimerSeconds * 1000)
          : loaded.match.turnEndsAt;
      const newEpoch = matchEnded
        ? loaded.match.turnEpoch
        : rearm
          ? loaded.match.turnEpoch + 1
          : loaded.match.turnEpoch;
      // The deadline is computed BEFORE the payload so the stored
      // row carries it — a duplicate `requestId` must re-emit the
      // exact original result, deadline included (FR-53).
      const movePayload: TokenMovedPayload = {
        playerId: userId,
        tokenId,
        fromSteps: result.fromSteps,
        toSteps: result.toSteps,
        landing: desc.landing,
        captured: desc.captured,
        extraTurn: desc.extraTurn,
        winnerId: desc.winnerId,
        currentPlayerId: desc.currentPlayerId,
        turnChangedPlayerId: desc.turnChangedPlayerId,
        matchEnded:
          desc.winnerId === null
            ? null
            : { winnerId: desc.winnerId, standings: desc.standings! },
        turnEndsAt: newDeadline ? newDeadline.toISOString() : null,
        snapshot: after.toJson(),
      };
      const outcome = await this.runGameTransaction(matchId, async (m) => {
        await this.insertEvent(m, {
          matchId,
          seqNo: seq,
          actorId: userId,
          type: 'token_moved',
          payload: movePayload as unknown as Record<string, unknown>,
          requestId,
        });
        if (desc.turnChangedPlayerId) {
          await this.insertEvent(m, {
            matchId,
            seqNo: seq + 1,
            actorId: null,
            type: 'turn_changed',
            payload: {
              playerId: desc.turnChangedPlayerId,
              snapshot: after.toJson(),
            },
            requestId: null,
          });
        }
        if (desc.winnerId !== null) {
          // FR-58: result + participants + ruleset version (already
          // on the match row) + ordered move log in ONE transaction.
          // No client or admin may edit a result afterwards (BR-17):
          // there is no update path for a completed match.
          await this.insertEvent(m, {
            matchId,
            seqNo: seq + 1,
            actorId: userId,
            type: 'match_ended',
            payload: {
              winnerId: desc.winnerId,
              standings: desc.standings!,
              snapshot: after.toJson(),
            } satisfies MatchEndedPayload as unknown as Record<string, unknown>,
            requestId: null,
          });
          await m.getRepository(Match).update(
            { id: matchId },
            {
              status: 'completed',
              winnerId: desc.winnerId,
              endedAt: new Date(),
              turnEndsAt: null,
            },
          );
          for (const standing of standings!) {
            await m
              .getRepository(MatchPlayer)
              .update(
                { matchId, userId: standing.userId },
                { result: standing.result, finishRank: standing.rank },
              );
          }
        } else {
          await m
            .getRepository(Match)
            .update(
              { id: matchId },
              { turnEndsAt: newDeadline, turnEpoch: newEpoch },
            );
        }
        if (wasDisconnected) {
          await m
            .getRepository(MatchPlayer)
            .update(
              { matchId, userId },
              { disconnectedAt: null, graceEndsAt: null },
            );
        }
      });
      const retried = await this.handleTransactionOutcome(
        matchId,
        requestId,
        userId,
        outcome,
      );
      if (retried) return retried;
      loaded.seq = seq + (desc.turnChangedPlayerId || desc.winnerId ? 1 : 0);
      if (desc.winnerId !== null) {
        loaded.match.status = 'completed';
        loaded.match.winnerId = desc.winnerId;
        loaded.match.endedAt = new Date();
        loaded.match.turnEndsAt = null;
      } else {
        loaded.match.turnEndsAt = newDeadline;
        loaded.match.turnEpoch = newEpoch;
      }
      if (wasDisconnected) {
        this.syncPlayerRow(loaded, userId, {
          disconnectedAt: null,
          graceEndsAt: null,
        });
      }
      this.games.set(matchId, loaded);
      const memberIds = loaded.seats.map((s) => s.userId);
      await this.broadcaster.emitGameEvent(
        loaded.roomId,
        memberIds,
        'token:moved',
        toTokenMovedSocketPayload(
          matchId,
          seq,
          movePayload,
          newDeadline ? newDeadline.toISOString() : null,
        ),
      );
      if (desc.turnChangedPlayerId) {
        await this.broadcaster.emitGameEvent(
          loaded.roomId,
          memberIds,
          'turn:changed',
          toTurnChangedSocketPayload(
            matchId,
            seq + 1,
            desc.turnChangedPlayerId,
            newDeadline ? newDeadline.toISOString() : null,
          ),
        );
      }
      if (desc.winnerId !== null) {
        await this.broadcaster.emitGameEvent(
          loaded.roomId,
          memberIds,
          'match:ended',
          toMatchEndedSocketPayload(matchId, seq + 1, {
            winnerId: desc.winnerId,
            standings: standings!,
            snapshot: after.toJson(),
          }),
        );
      }
      if (wasDisconnected) {
        await this.broadcaster.emitGameEvent(
          loaded.roomId,
          memberIds,
          'player:reconnected',
          toPlayerReconnectedSocketPayload(matchId, loaded.seq, userId),
        );
      }
      return { duplicate: false, events: [] };
    });
  }

  // -- Helpers ---------------------------------------------------------------

  private requireSeat(loaded: LoadedGame, userId: string): SeatView {
    const seat = loaded.seats.find((s) => s.userId === userId);
    if (!seat) throw GameRejectedError.notMatchPlayer();
    return seat;
  }

  private requireInProgress(loaded: LoadedGame): void {
    if (loaded.match.status !== 'in_progress' || loaded.game.isFinished) {
      throw GameRejectedError.matchFinished();
    }
  }

  /** A forfeited player may read the match but may no longer act. */
  private requireActivePlayer(loaded: LoadedGame, userId: string): void {
    if (this.playerRow(loaded, userId)?.result) {
      throw GameRejectedError.invalidState('You have forfeited this match.');
    }
  }

  /** The `match_players` row for a user (null when not a player). */
  private playerRow(loaded: LoadedGame, userId: string): MatchPlayer | null {
    return loaded.playerRows.find((p) => p.userId === userId) ?? null;
  }

  /** Seats holding a `forfeit` result (the engine must skip them). */
  private forfeitedSeats(loaded: LoadedGame): Set<number> {
    return new Set(
      loaded.playerRows
        .filter((p) => p.result === 'forfeit')
        .map((p) => p.seat),
    );
  }

  /**
   * Apply the forfeit-skip to the loaded game (rebuilding it when
   * the engine landed the turn on a forfeited player) and return
   * the resulting state.
   */
  private skipForfeited(
    loaded: LoadedGame,
    forfeitedSeats: ReadonlySet<number>,
  ): GameState {
    const skipped = skipForfeitedPlayers(loaded.game.state, forfeitedSeats);
    if (skipped !== loaded.game.state) {
      loaded.game = LudoGame.fromState(skipped, {
        ruleset: loaded.game.ruleset,
        diceRoller: this.diceRoller,
      });
    }
    return skipped;
  }

  /** Patch the cached `match_players` row after a DB write. */
  private syncPlayerRow(
    loaded: LoadedGame,
    userId: string,
    patch: Partial<MatchPlayer>,
  ): void {
    const row = loaded.playerRows.find((p) => p.userId === userId);
    if (row) Object.assign(row, patch);
  }

  /** The in-progress match id for a user, or null. */
  private async findActiveMatchId(userId: string): Promise<string | null> {
    const rows = await this.dataSource.query(
      `SELECT p."match_id" AS "matchId" FROM "match_players" p
        JOIN "matches" m ON m."id" = p."match_id"
       WHERE p."user_id" = $1 AND m."status" = 'in_progress' LIMIT 1`,
      [userId],
    );
    return rows.length > 0 ? (rows[0].matchId as string) : null;
  }

  /** Stage 6 extras for a `match:state` payload (turn + presence). */
  private stateExtras(loaded: LoadedGame): MatchStateExtras {
    const live =
      loaded.match.status === 'in_progress' && !loaded.game.isFinished;
    return {
      turnPlayerId: live
        ? loaded.seats[loaded.game.currentPlayerIndex].userId
        : null,
      turnEndsAt: live
        ? (loaded.match.turnEndsAt?.toISOString() ?? null)
        : null,
      players: loaded.seats.map((seat) => {
        const row = this.playerRow(loaded, seat.userId);
        return {
          userId: seat.userId,
          seat: seat.seat,
          colour: seat.colour,
          disconnected: !!row?.disconnectedAt,
          graceEndsAt: row?.graceEndsAt?.toISOString() ?? null,
          missedTurns: row?.missedTurns ?? 0,
          result: (row?.result ?? null) as 'win' | 'loss' | 'forfeit' | null,
        };
      }),
    };
  }

  /**
   * The original result for a retried `requestId` (FR-53), or null
   * when this is a first attempt. A `requestId` already used by a
   * different player is rejected — ids are per-client UUIDs, so a
   * cross-player collision is a client bug, not a retry.
   */
  private async duplicateResult(
    matchId: string,
    requestId: string,
    userId: string,
  ): Promise<GameIntentResult | null> {
    const existing = await this.dataSource
      .getRepository(MoveEvent)
      .findOne({ where: { matchId, requestId } });
    if (!existing) return null;
    if (existing.actorId !== userId) {
      throw GameRejectedError.invalidState(
        'This requestId was already used by another player.',
      );
    }
    return {
      duplicate: true,
      events: socketEventsForStoredIntent(matchId, {
        type: existing.type,
        seqNo: existing.seqNo,
        payload: existing.payload,
      }),
    };
  }

  private async insertEvent(
    manager: EntityManager,
    row: EventRow,
  ): Promise<void> {
    await manager
      .getRepository(MoveEvent)
      .save(manager.getRepository(MoveEvent).create(row));
  }

  /**
   * Runs a game transaction. On a unique violation the in-memory
   * transition is discarded (the cache entry is dropped, so the
   * next load replays the truth) and the caller re-checks the
   * `requestId` row — the lock should have prevented this, so a
   * hit means another writer committed this exact intent first.
   */
  private async runGameTransaction(
    matchId: string,
    write: (manager: EntityManager) => Promise<void>,
  ): Promise<'committed' | 'duplicate'> {
    try {
      await this.dataSource.transaction(write);
      return 'committed';
    } catch (err) {
      this.games.delete(matchId);
      if (isUniqueViolationError(err)) return 'duplicate';
      throw err;
    }
  }

  /**
   * After a transaction reports a possible duplicate, resolve it:
   * the original result when the `requestId` row exists, otherwise
   * a retryable refusal (the client retries with the same
   * `requestId`, which then dedups or applies cleanly).
   */
  private async handleTransactionOutcome(
    matchId: string,
    requestId: string,
    userId: string,
    outcome: 'committed' | 'duplicate',
  ): Promise<GameIntentResult | null> {
    if (outcome === 'committed') return null;
    const retried = await this.duplicateResult(matchId, requestId, userId);
    if (retried) return retried;
    throw GameRejectedError.matchUnavailable(
      'The match changed while applying this action. ' +
        'Retry with the same requestId.',
    );
  }

  private async toMatchView(loaded: LoadedGame): Promise<MatchView> {
    const players = await this.dataSource
      .getRepository(MatchPlayer)
      .find({ where: { matchId: loaded.match.id }, order: { seat: 'ASC' } });
    const live =
      loaded.match.status === 'in_progress' && !loaded.game.isFinished;
    return {
      id: loaded.match.id,
      roomId: loaded.match.roomId,
      rulesetVersion: loaded.match.rulesetVersion,
      status: loaded.match.status,
      winnerId: loaded.match.winnerId,
      startedAt: loaded.match.startedAt.toISOString(),
      endedAt: loaded.match.endedAt ? loaded.match.endedAt.toISOString() : null,
      seq: loaded.seq,
      currentPlayerId: live
        ? loaded.seats[loaded.game.currentPlayerIndex].userId
        : null,
      phase: loaded.game.state.phase,
      players: players.map((p) => ({
        userId: p.userId,
        seat: p.seat,
        colour: p.colour,
        result: p.result,
        finishRank: p.finishRank,
        missedTurns: p.missedTurns ?? 0,
        disconnected: !!p.disconnectedAt,
        graceEndsAt: p.graceEndsAt ? p.graceEndsAt.toISOString() : null,
      })),
    };
  }

  /**
   * Serialise one transition under the per-match Redis lock
   * (FR-50/53). Spins briefly for a contended lock, then refuses
   * with a retryable error — the client retries with the same
   * `requestId`. When Redis itself is unreachable, falls back to
   * a process-local per-match mutex so in-progress matches
   * continue on the node holding them (assessment risk 5).
   */
  private async withMatchLock<T>(
    matchId: string,
    fn: () => Promise<T>,
  ): Promise<T> {
    const key = REDIS_KEYS.matchLock(matchId);
    const deadline = Date.now() + LOCK_WAIT_MS;
    let token: string | null = null;
    let redisDown = false;
    while (Date.now() < deadline) {
      try {
        token = await this.redis.acquireLock(key, LOCK_TTL_SECONDS);
      } catch {
        redisDown = true;
        break;
      }
      if (token) break;
      await sleep(LOCK_POLL_MS);
    }
    if (redisDown || !token) {
      if (!redisDown) {
        throw GameRejectedError.matchUnavailable(
          'The match is busy. Retry with the same requestId.',
        );
      }
      this.logger.warn(
        `Redis unreachable for match ${matchId} — using the local per-match mutex`,
      );
      return this.withLocalMutex(matchId, fn);
    }
    try {
      return await fn();
    } finally {
      await this.redis.releaseLock(key, token).catch(() => {
        // Redis may have died mid-transition; the TTL expires it.
      });
    }
  }

  /**
   * Process-local per-match mutex (promise chain). Only used when
   * Redis is unreachable — the node holding the match is then the
   * only writer by construction.
   */
  private async withLocalMutex<T>(
    matchId: string,
    fn: () => Promise<T>,
  ): Promise<T> {
    const previous = this.localMutexes.get(matchId) ?? Promise.resolve();
    const run = previous.catch(() => {}).then(fn);
    this.localMutexes.set(matchId, run);
    try {
      return await run;
    } finally {
      if (this.localMutexes.get(matchId) === run) {
        this.localMutexes.delete(matchId);
      }
    }
  }
}
