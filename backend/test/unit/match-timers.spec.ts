import { randomUUID } from 'node:crypto';
import { HttpException } from '@nestjs/common';
import type { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import { DataSource } from 'typeorm';
import { buildDataSourceOptions } from '../../src/database/data-source';
import { FixedDiceRoller } from '../../src/game/dice-roller';
import {
  DEFAULT_GAME_TIMING,
  MatchService,
} from '../../src/match/match.service';
import {
  applyForfeitToState,
  computeForfeitStandings,
  skipForfeitedPlayers,
  toMatchStatePayload,
  toTurnChangedSocketPayload,
} from '../../src/match/match-payloads';
import { LudoGame } from '../../src/game';
import { RedisService } from '../../src/redis/redis.service';
import { RoomBroadcaster } from '../../src/rooms/room-broadcaster';
import { RoomsService } from '../../src/rooms/rooms.service';
import { Profile } from '../../src/users/entities/profile.entity';
import { User } from '../../src/users/entities/user.entity';
import {
  REDIS_URL,
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
} from '../integration/test-helpers';

jest.setTimeout(120000);

/**
 * Stage 6 timer / grace / forfeit / recovery tests (real
 * PostgreSQL scratch DB + real Redis 7, service-level — no
 * sockets; the socket delivery is covered by the recovery-timers
 * e2e spec). The service is constructed directly, so no sweepers
 * run: every timer/grace step is driven explicitly (past
 * deadlines written to the DB + a direct sweep/process call), and
 * a fresh service instance stands in for a restarted process
 * (empty in-memory cache → replay from the log).
 */
describe('MatchService timers / grace / forfeit / recovery (Stage 6)', () => {
  let dbName: string;
  let databaseUrl: string;
  let ds: DataSource;
  let rooms: RoomsService;
  let redis: Redis;
  let redisService: RedisService;

  function codeOf(err: unknown): string | undefined {
    if (err instanceof HttpException) {
      const body = err.getResponse() as { code?: string };
      return typeof body === 'object' ? body.code : undefined;
    }
    return undefined;
  }

  async function expectCode(
    fn: () => Promise<unknown>,
    code: string,
  ): Promise<void> {
    try {
      await fn();
      throw new Error(`expected ${code} but the call succeeded`);
    } catch (err) {
      if ((err as Error).message.startsWith('expected ')) throw err;
      expect(codeOf(err)).toBe(code);
    }
  }

  async function makeUser(): Promise<{ id: string; username: string }> {
    const tag = randomUUID().slice(0, 8);
    const user = await ds.getRepository(User).save(
      ds.getRepository(User).create({
        email: `tm-${tag}@example.com`,
        username: `tm_${tag}`,
        passwordHash: 'x',
        status: 'active',
        emailVerifiedAt: new Date(),
      }),
    );
    await ds.getRepository(Profile).save(
      ds.getRepository(Profile).create({
        userId: user.id,
        displayName: `TM ${tag}`,
      }),
    );
    return { id: user.id, username: user.username };
  }

  function service(rolls: number[]): MatchService {
    return new MatchService(
      ds,
      redisService,
      new RoomBroadcaster(),
      new FixedDiceRoller(rolls, { cycle: true }),
    );
  }

  async function startMatch(playerCount = 2): Promise<{
    matchId: string;
    users: Array<{ id: string; username: string }>;
  }> {
    const users: Array<{ id: string; username: string }> = [];
    for (let i = 0; i < playerCount; i += 1) users.push(await makeUser());
    const room = await rooms.createRoom(users[0].id, playerCount);
    for (const u of users.slice(1)) await rooms.joinByCode(u.id, room.code);
    for (const u of users) await rooms.setReady(u.id, room.id, true);
    const started = await rooms.startMatch(users[0].id, room.id);
    return { matchId: started.matchId, users };
  }

  async function setConfig(
    turn: number,
    grace: number,
    missed: number,
  ): Promise<void> {
    await ds.query(
      `UPDATE "game_configurations"
          SET "turn_timer_seconds" = $1, "grace_period_seconds" = $2,
              "missed_turn_limit" = $3
        WHERE "version" = '1.0.0'`,
      [turn, grace, missed],
    );
  }

  async function setTurnPast(matchId: string): Promise<void> {
    await ds.query(
      `UPDATE "matches" SET "turn_ends_at" = now() - interval '1 second' WHERE "id" = $1`,
      [matchId],
    );
  }

  async function setGracePast(matchId: string, userId: string): Promise<void> {
    await ds.query(
      `UPDATE "match_players" SET "grace_ends_at" = now() - interval '1 second'
        WHERE "match_id" = $1 AND "user_id" = $2`,
      [matchId, userId],
    );
  }

  async function matchRow(matchId: string): Promise<{
    status: string;
    winnerId: string | null;
    turnEndsAt: Date | null;
    turnEpoch: number;
  }> {
    const rows = await ds.query(
      `SELECT "status", "winner_id" AS "winnerId",
              "turn_ends_at" AS "turnEndsAt", "turn_epoch" AS "turnEpoch"
         FROM "matches" WHERE "id" = $1`,
      [matchId],
    );
    return rows[0];
  }

  async function playerRow(
    matchId: string,
    userId: string,
  ): Promise<{
    result: string | null;
    missedTurns: number;
    disconnectedAt: Date | null;
    graceEndsAt: Date | null;
  }> {
    const rows = await ds.query(
      `SELECT "result", "missed_turns" AS "missedTurns",
              "disconnected_at" AS "disconnectedAt",
              "grace_ends_at" AS "graceEndsAt"
         FROM "match_players" WHERE "match_id" = $1 AND "user_id" = $2`,
      [matchId, userId],
    );
    return rows[0];
  }

  async function countEvents(matchId: string, type?: string): Promise<number> {
    const rows = await ds.query(
      `SELECT COUNT(*) AS "n" FROM "move_events" WHERE "match_id" = $1` +
        (type ? ` AND "type" = $2` : ''),
      type ? [matchId, type] : [matchId],
    );
    return Number(rows[0].n);
  }

  beforeAll(async () => {
    ({ name: dbName, url: databaseUrl } = await createScratchDb());
    await migrateScratchDb(databaseUrl);
    ds = new DataSource(buildDataSourceOptions(databaseUrl));
    await ds.initialize();
    const config = {
      getOrThrow: (key: string) =>
        key === 'app' ? { rulesetVersion: '1.0.0' } : undefined,
    } as unknown as ConfigService;
    rooms = new RoomsService(ds, config, new RoomBroadcaster());
    redis = new Redis(REDIS_URL, {
      lazyConnect: true,
      maxRetriesPerRequest: 3,
    });
    redisService = new RedisService(redis as never);
  }, 120000);

  afterAll(async () => {
    if (redis) redis.disconnect();
    if (ds) await ds.destroy();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await setConfig(30, 60, 3);
    const keys = await redis.keys('match:lock:*');
    if (keys.length > 0) await redis.del(...keys);
    const presence = await redis.keys('presence:user:*');
    if (presence.length > 0) await redis.del(...presence);
  });

  // -- Pure helpers ---------------------------------------------------------

  it('skipForfeitedPlayers advances past a forfeited current player', () => {
    const game = LudoGame.newMatch({
      seats: [
        { name: 'a', colour: 'red', type: 'human' },
        { name: 'b', colour: 'green', type: 'human' },
        { name: 'c', colour: 'yellow', type: 'human' },
      ],
    });
    // Engine starts with seat 0; pretend the turn passed to seat 1.
    const atSeat1 = game.state.copyWith({ currentPlayerIndex: 1 });
    const skipped = skipForfeitedPlayers(atSeat1, new Set([1]));
    expect(skipped.currentPlayerIndex).toBe(2);
    expect(skipped.phase).toBe('awaitingRoll');
    expect(skipForfeitedPlayers(atSeat1, new Set([0]))).toBe(atSeat1);
  });

  it('applyForfeitToState yards the tokens and passes the turn', () => {
    const game = LudoGame.newMatch({
      seats: [
        { name: 'a', colour: 'red', type: 'human' },
        { name: 'b', colour: 'green', type: 'human' },
      ],
      diceRoller: new FixedDiceRoller([6]),
    });
    game.rollDice(); // 6: a release is pending.
    expect(game.state.phase).toBe('awaitingMove');
    const forfeited = applyForfeitToState(game.state, 0, new Set([0]));
    expect(forfeited.players[0].tokens.every((t) => t.stepsTaken === 0)).toBe(
      true,
    );
    expect(forfeited.currentPlayerIndex).toBe(1);
  });

  it('computeForfeitStandings names the sole survivor winner', () => {
    const game = LudoGame.newMatch({
      seats: [
        { name: 'a', colour: 'red', type: 'human' },
        { name: 'b', colour: 'green', type: 'human' },
      ],
    });
    const seats = [
      { userId: 'u0', seat: 0, colour: 'red' },
      { userId: 'u1', seat: 1, colour: 'green' },
    ];
    const { winnerId, standings } = computeForfeitStandings(
      game.state,
      seats,
      1,
      new Set([0]),
    );
    expect(winnerId).toBe('u1');
    expect(standings).toEqual([
      {
        userId: 'u1',
        seat: 1,
        colour: 'green',
        rank: 1,
        result: 'win',
        tokensHome: 0,
      },
      {
        userId: 'u0',
        seat: 0,
        colour: 'red',
        rank: 2,
        result: 'forfeit',
        tokensHome: 0,
      },
    ]);
  });

  it('turn payloads carry a real turnEndsAt; match:state carries turn + players', () => {
    expect(
      toTurnChangedSocketPayload('m', 2, 'u', '2026-11-28T00:00:30.000Z'),
    ).toEqual({
      matchId: 'm',
      playerId: 'u',
      turnEndsAt: '2026-11-28T00:00:30.000Z',
      seq: 2,
    });
    const game = LudoGame.newMatch({
      seats: [
        { name: 'a', colour: 'red', type: 'human' },
        { name: 'b', colour: 'green', type: 'human' },
      ],
    });
    const state = toMatchStatePayload(
      'm',
      game.snapshot(),
      1,
      [
        { userId: 'u0', seat: 0, colour: 'red' },
        { userId: 'u1', seat: 1, colour: 'green' },
      ],
      {
        turnPlayerId: 'u0',
        turnEndsAt: '2026-11-28T00:00:30.000Z',
        players: [
          {
            userId: 'u0',
            seat: 0,
            colour: 'red',
            disconnected: false,
            graceEndsAt: null,
            missedTurns: 0,
            result: null,
          },
        ],
      },
    );
    expect(
      (state.turn as { playerId: string; turnEndsAt: string }).playerId,
    ).toBe('u0');
    expect(
      (state.turn as { playerId: string; turnEndsAt: string }).turnEndsAt,
    ).toBe('2026-11-28T00:00:30.000Z');
  });

  it('getGameConfig reads the seeded row and falls back to 30/60/3', async () => {
    const svc = service([6]);
    expect(await svc.getGameConfig()).toEqual({
      turnTimerSeconds: 30,
      gracePeriodSeconds: 60,
      missedTurnLimit: 3,
    });
    await setConfig(5, 9, 2);
    expect(await svc.getGameConfig()).toEqual({
      turnTimerSeconds: 5,
      gracePeriodSeconds: 9,
      missedTurnLimit: 2,
    });
    await ds.query(`DELETE FROM "game_configurations"`);
    expect(await svc.getGameConfig()).toEqual({ ...DEFAULT_GAME_TIMING });
    // Restore the seeded row for the tests that follow.
    await ds.query(
      `INSERT INTO "game_configurations"
         ("version", "turn_timer_seconds", "grace_period_seconds",
          "missed_turn_limit", "max_room_players")
       VALUES ('1.0.0', 30, 60, 3, 4)`,
    );
  });

  // -- Timer arming ---------------------------------------------------------

  it('startMatch arms the first turn timer (deadline ~30 s, epoch 1)', async () => {
    const { matchId, users } = await startMatch();
    const row = await matchRow(matchId);
    expect(row.status).toBe('in_progress');
    expect(row.turnEpoch).toBe(1);
    expect(row.turnEndsAt).not.toBeNull();
    const ms = row.turnEndsAt!.getTime() - Date.now();
    expect(ms).toBeGreaterThan(20_000);
    expect(ms).toBeLessThanOrEqual(30_000);
    const svc = service([6]);
    const state = (await svc.getMatchState(matchId, users[0].id)) as {
      turn: { playerId: string; turnEndsAt: string };
      players: Array<{ disconnected: boolean; missedTurns: number }>;
    };
    expect(state.turn.playerId).toBe(users[0].id);
    expect(Date.parse(state.turn.turnEndsAt)).toBeGreaterThan(Date.now());
    expect(state.players).toHaveLength(2);
    expect(state.players[0].disconnected).toBe(false);
  });

  it('a manual roll re-arms only when the turn passes', async () => {
    const { matchId, users } = await startMatch();
    const svc = service([6, 2]);
    // Roll 6: awaitingMove, same turn — deadline + epoch unchanged.
    await svc.rollDice(matchId, users[0].id, randomUUID());
    let row = await matchRow(matchId);
    expect(row.turnEpoch).toBe(1);
    const firstDeadline = row.turnEndsAt!.getTime();
    // Move token 0:0 (release, extra turn) — fresh window, epoch 2.
    await svc.moveToken(matchId, users[0].id, '0:0', randomUUID());
    row = await matchRow(matchId);
    expect(row.turnEpoch).toBe(2);
    expect(row.turnEndsAt!.getTime()).toBeGreaterThanOrEqual(firstDeadline);
    // Roll 2 and move 0:0 (1 -> 3): no extra turn, so the turn
    // passes to the guest — epoch 3.
    await svc.rollDice(matchId, users[0].id, randomUUID());
    await svc.moveToken(matchId, users[0].id, '0:0', randomUUID());
    row = await matchRow(matchId);
    expect(row.turnEpoch).toBe(3);
  });

  // -- Timeout auto-play ----------------------------------------------------

  it('timeout auto-rolls and auto-moves the FIRST legal move', async () => {
    const { matchId, users } = await startMatch();
    await setTurnPast(matchId);
    const fresh = service([6]);
    const outcome = await fresh.processTurnTimeout(matchId);
    expect(outcome).toBe('applied');
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
    expect(await countEvents(matchId, 'token_moved')).toBe(1);
    const rows = await ds.query(
      `SELECT "payload" FROM "move_events" WHERE "match_id" = $1 AND "type" = 'token_moved'`,
      [matchId],
    );
    const payload = rows[0].payload as { tokenId: string; value?: number };
    expect(payload.tokenId).toBe('0:0'); // engine order: token 0 first
    const dice = await ds.query(
      `SELECT "payload" FROM "move_events" WHERE "match_id" = $1 AND "type" = 'dice_rolled'`,
      [matchId],
    );
    expect((dice[0].payload as { value: number }).value).toBe(6);
    expect((await playerRow(matchId, users[0].id)).missedTurns).toBe(1);
    const row = await matchRow(matchId);
    expect(row.turnEpoch).toBe(2);
    expect(row.turnEndsAt!.getTime()).toBeGreaterThan(Date.now());
    // The auto-move was a release (extra turn): still host's turn.
    const state = (await fresh.getMatchState(matchId, users[0].id)) as {
      snapshot: { currentPlayerIndex: number };
    };
    expect(state.snapshot.currentPlayerIndex).toBe(0);
  });

  it('timeout with no legal move skips the turn and counts a miss', async () => {
    const { matchId, users } = await startMatch();
    await setTurnPast(matchId);
    const fresh = service([2]);
    expect(await fresh.processTurnTimeout(matchId)).toBe('applied');
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
    expect(await countEvents(matchId, 'token_moved')).toBe(0);
    const state = (await fresh.getMatchState(matchId, users[0].id)) as {
      snapshot: { currentPlayerIndex: number };
    };
    expect(state.snapshot.currentPlayerIndex).toBe(1);
    expect((await playerRow(matchId, users[0].id)).missedTurns).toBe(1);
  });

  it('a stale epoch and a future deadline are both ignored', async () => {
    const { matchId } = await startMatch();
    const svc = service([6]);
    expect(await svc.processTurnTimeout(matchId, 999)).toBe('stale');
    expect(await svc.processTurnTimeout(matchId, 1)).toBe('not-due');
    expect(await countEvents(matchId)).toBe(1);
    await setTurnPast(matchId);
    expect(await svc.processTurnTimeout(matchId, 999)).toBe('stale');
    // A fresh instance (empty cache) sees the past deadline.
    expect(await service([6]).processTurnTimeout(matchId, 1)).toBe('applied');
  });

  it('exactly one timeout transition under concurrent firings', async () => {
    const { matchId } = await startMatch();
    await setTurnPast(matchId);
    const [a, b] = await Promise.all([
      service([6]).processTurnTimeout(matchId),
      service([6]).processTurnTimeout(matchId),
    ]);
    expect([a, b].sort()).toEqual(['applied', 'not-due']);
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
    expect(await countEvents(matchId, 'token_moved')).toBe(1);
  });

  it('a manual roll resets the consecutive missed-turn count', async () => {
    const { matchId, users } = await startMatch();
    await setTurnPast(matchId);
    await service([2]).processTurnTimeout(matchId); // host misses (1)
    expect((await playerRow(matchId, users[0].id)).missedTurns).toBe(1);
    // Guest's turn now: guest rolls 2 manually (no legal move,
    // turn passes back to host) — guest's own count stays 0.
    const svc = service([2]);
    await svc.rollDice(matchId, users[1].id, randomUUID());
    // Host rolls manually: the miss is forgiven.
    await svc.rollDice(matchId, users[0].id, randomUUID());
    expect((await playerRow(matchId, users[0].id)).missedTurns).toBe(0);
  });

  it('3 consecutive missed turns forfeit the player (alternating)', async () => {
    const { matchId, users } = await startMatch();
    // Every roll is 2 (no legal moves while all tokens are in the
    // yard): each expiry passes the turn, so host and guest miss
    // alternately — host reaches 3 first and forfeits; guest wins.
    for (let i = 0; i < 5; i += 1) {
      await setTurnPast(matchId);
      expect(await service([2]).processTurnTimeout(matchId)).toBe('applied');
    }
    const host = await playerRow(matchId, users[0].id);
    const guest = await playerRow(matchId, users[1].id);
    expect(host.missedTurns).toBe(3);
    expect(host.result).toBe('forfeit');
    expect(guest.missedTurns).toBe(2);
    expect(guest.result).toBe('win');
    const row = await matchRow(matchId);
    expect(row.status).toBe('completed');
    expect(row.winnerId).toBe(users[1].id);
    expect(row.turnEndsAt).toBeNull();
    expect(await countEvents(matchId, 'player_forfeited')).toBe(1);
    expect(await countEvents(matchId, 'match_ended')).toBe(1);
    const ended = await ds.query(
      `SELECT "payload" FROM "move_events" WHERE "match_id" = $1 AND "type" = 'match_ended'`,
      [matchId],
    );
    const standings = (
      ended[0].payload as {
        standings: Array<{ userId: string; result: string; rank: number }>;
      }
    ).standings;
    expect(standings).toEqual([
      expect.objectContaining({
        userId: users[1].id,
        result: 'win',
        rank: 1,
      }),
      expect.objectContaining({
        userId: users[0].id,
        result: 'forfeit',
        rank: 2,
      }),
    ]);
  });

  // -- Grace / forfeit / presence ------------------------------------------

  it('disconnect marks grace; reconnect clears it (idempotent)', async () => {
    const { matchId, users } = await startMatch();
    const svc = service([6]);
    expect(await svc.handlePlayerDisconnected(users[0].id)).toBe(true);
    expect(await svc.handlePlayerDisconnected(users[0].id)).toBe(false);
    const marked = await playerRow(matchId, users[0].id);
    expect(marked.disconnectedAt).not.toBeNull();
    expect(marked.graceEndsAt!.getTime() - Date.now()).toBeGreaterThan(50_000);
    const state = (await svc.getMatchState(matchId, users[0].id)) as {
      players: Array<{ disconnected: boolean; graceEndsAt: string | null }>;
    };
    expect(state.players[0].disconnected).toBe(true);
    expect(state.players[0].graceEndsAt).not.toBeNull();
    expect(await svc.handlePlayerConnected(users[0].id)).toBe(true);
    expect(await svc.handlePlayerConnected(users[0].id)).toBe(false);
    const cleared = await playerRow(matchId, users[0].id);
    expect(cleared.disconnectedAt).toBeNull();
    expect(cleared.graceEndsAt).toBeNull();
  });

  it('grace expiry forfeits and the sole remaining player wins', async () => {
    const { matchId, users } = await startMatch();
    const svc = service([6]);
    expect(await svc.handlePlayerDisconnected(users[1].id)).toBe(true);
    await setGracePast(matchId, users[1].id);
    await svc.sweepExpiredGraces();
    const guest = await playerRow(matchId, users[1].id);
    expect(guest.result).toBe('forfeit');
    const row = await matchRow(matchId);
    expect(row.status).toBe('completed');
    expect(row.winnerId).toBe(users[0].id);
    expect(await countEvents(matchId, 'player_forfeited')).toBe(1);
  });

  it('voluntary leave forfeits; a forfeited player cannot act', async () => {
    // 3 players, so the match continues after the leave and the
    // forfeited player is still rejectable (in a 2-player match
    // the leave ends the match instead).
    const { matchId, users } = await startMatch(3);
    const svc = service([6]);
    const left = await svc.leaveMatch(users[0].id);
    expect(left).toEqual({ matchId, forfeited: true });
    expect((await playerRow(matchId, users[0].id)).result).toBe('forfeit');
    expect((await matchRow(matchId)).status).toBe('in_progress');
    await expectCode(
      () => svc.rollDice(matchId, users[0].id, randomUUID()),
      'INVALID_STATE',
    );
    // And a 2-player leave ends the match with the other winner.
    const two = await startMatch(2);
    await svc.leaveMatch(two.users[0].id);
    expect((await matchRow(two.matchId)).winnerId).toBe(two.users[1].id);
    expect(await svc.leaveMatch(users[0].id)).toEqual({
      matchId,
      forfeited: false,
    });
  });

  it('presence: mark/touch/clear + the 10 s sweep marks a lapsed player', async () => {
    const { matchId, users } = await startMatch();
    const svc = service([6]);
    expect(await svc.isPresent(users[0].id)).toBe(false);
    await svc.markPresence(users[0].id);
    expect(await svc.isPresent(users[0].id)).toBe(true);
    await svc.clearPresence(users[0].id);
    expect(await svc.isPresent(users[0].id)).toBe(false);
    // Nobody has heartbeated: the sweep marks both players.
    await svc.sweepPresence();
    expect(
      (await playerRow(matchId, users[0].id)).disconnectedAt,
    ).not.toBeNull();
    expect(
      (await playerRow(matchId, users[1].id)).disconnectedAt,
    ).not.toBeNull();
    // A heartbeat protects the player from the sweep.
    await svc.handlePlayerConnected(users[0].id);
    await svc.markPresence(users[0].id);
    await svc.sweepPresence();
    expect((await playerRow(matchId, users[0].id)).disconnectedAt).toBeNull();
  });

  // -- Forfeit turn-skipping + replay ---------------------------------------

  it('a forfeit passes the turn past the forfeited seat (3 players)', async () => {
    const { matchId, users } = await startMatch(3);
    const svc = service([2]);
    await svc.leaveMatch(users[1].id); // seat 1 forfeits
    expect((await playerRow(matchId, users[1].id)).result).toBe('forfeit');
    // Seat 0 rolls 2 (no legal move): the turn must skip seat 1.
    await svc.rollDice(matchId, users[0].id, randomUUID());
    const state = (await svc.getMatchState(matchId, users[0].id)) as {
      snapshot: { currentPlayerIndex: number };
    };
    expect(state.snapshot.currentPlayerIndex).toBe(2);
    // A fresh instance replays the log (incl. the forfeit) and
    // lands on the same turn — replay reproduces the skip.
    const replayed = (await service([2]).getMatchState(
      matchId,
      users[0].id,
    )) as { snapshot: { currentPlayerIndex: number } };
    expect(replayed.snapshot.currentPlayerIndex).toBe(2);
  });

  it('replay restores a forfeited match incl. timer state', async () => {
    const { matchId, users } = await startMatch(3);
    const svc = service([2]);
    await svc.leaveMatch(users[1].id);
    await svc.rollDice(matchId, users[0].id, randomUUID()); // turn -> seat 2
    // Fresh process, past deadline: the restored timer still fires,
    // and the timeout skips the forfeited seat (2 -> 0).
    await setTurnPast(matchId);
    const fresh = service([2]);
    expect(await fresh.processTurnTimeout(matchId)).toBe('applied');
    const state = (await fresh.getMatchState(matchId, users[0].id)) as {
      snapshot: { currentPlayerIndex: number };
      turn: { playerId: string };
    };
    expect(state.snapshot.currentPlayerIndex).toBe(0);
    expect(state.turn.playerId).toBe(users[0].id);
  });

  // -- Restart recovery ------------------------------------------------------

  it('recovery restores a healthy match and cancels a corrupt one', async () => {
    // Earlier tests leave their matches in progress; count them so
    // the recovery counts below are relative, not absolute.
    const before = await ds.query(
      `SELECT COUNT(*) AS "n" FROM "matches" WHERE "status" = 'in_progress'`,
    );
    const liveBefore = Number(before[0].n);
    const { matchId: goodId } = await startMatch();
    const { matchId: badId } = await startMatch();
    // Corrupt the second match's log: a dice value outside 1..6.
    await ds.query(
      `INSERT INTO "move_events"
         ("match_id", "seq_no", "actor_id", "type", "payload", "request_id")
       VALUES ($1, 2, NULL, 'dice_rolled', '{"value": 99}'::jsonb, NULL)`,
      [badId],
    );
    const svc = service([6]);
    const result = await svc.recoverInProgressMatches();
    expect(result.restored).toBe(liveBefore + 1);
    expect(result.cancelled).toBe(1);
    expect((await matchRow(goodId)).status).toBe('in_progress');
    expect((await matchRow(badId)).status).toBe('cancelled');
    // The healthy match still plays after recovery.
    const { users } = await (async () => {
      const rows = await ds.query(
        `SELECT "user_id" AS "userId" FROM "match_players" WHERE "match_id" = $1 ORDER BY "seat"`,
        [goodId],
      );
      return { users: rows as Array<{ userId: string }> };
    })();
    await svc.rollDice(goodId, users[0].userId, randomUUID());
    expect(await countEvents(goodId, 'dice_rolled')).toBe(1);
  });

  it('recovery re-arms a match whose turn deadline is missing', async () => {
    const { matchId } = await startMatch();
    await ds.query(
      `UPDATE "matches" SET "turn_ends_at" = NULL WHERE "id" = $1`,
      [matchId],
    );
    const svc = service([6]);
    const result = await svc.recoverInProgressMatches();
    expect(result.rearmed).toBe(1);
    const row = await matchRow(matchId);
    expect(row.turnEndsAt).not.toBeNull();
    expect(row.turnEndsAt!.getTime()).toBeGreaterThan(Date.now());
  });
});
