import { randomUUID } from 'node:crypto';
import { HttpException } from '@nestjs/common';
import type { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import { DataSource } from 'typeorm';
import { buildDataSourceOptions } from '../../src/database/data-source';
import { FixedDiceRoller } from '../../src/game/dice-roller';
import { MatchService } from '../../src/match/match.service';
import { RedisService } from '../../src/redis/redis.service';
import { RoomBroadcaster } from '../../src/rooms/room-broadcaster';
import { RoomsService } from '../../src/rooms/rooms.service';
import { Profile } from '../../src/users/entities/profile.entity';
import { User } from '../../src/users/entities/user.entity';
import {
  captureSetup,
  insertRecordedEvents,
  nearWinSetup,
  snapshotTokenSteps,
} from '../integration/gameplay-helpers';
import {
  REDIS_URL,
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
} from '../integration/test-helpers';

jest.setTimeout(120000);

/**
 * MatchService against a real PostgreSQL scratch DB + real Redis 7.
 * Covers: state transitions + checkpointing + replay-from-events,
 * turn/token ownership and illegal-move validation, seq/requestId
 * dedup (a duplicate returns the original result, no second
 * transition), simultaneous requests (exactly one wins), winner
 * declaration, and the atomic match-end transaction. Broadcasting
 * is a no-op here (RoomBroadcaster with no gateway attached drops
 * emits); broadcast delivery is covered by the socket e2e spec.
 */
describe('MatchService (real PostgreSQL + real Redis)', () => {
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
        email: `gm-${tag}@example.com`,
        username: `gm_${tag}`,
        passwordHash: 'x',
        status: 'active',
        emailVerifiedAt: new Date(),
      }),
    );
    await ds.getRepository(Profile).save(
      ds.getRepository(Profile).create({
        userId: user.id,
        displayName: `GM ${tag}`,
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

  async function startMatch(): Promise<{
    matchId: string;
    host: { id: string; username: string };
    guest: { id: string; username: string };
  }> {
    const host = await makeUser();
    const guest = await makeUser();
    const room = await rooms.createRoom(host.id, 2);
    await rooms.joinByCode(guest.id, room.code);
    await rooms.setReady(host.id, room.id, true);
    await rooms.setReady(guest.id, room.id, true);
    const started = await rooms.startMatch(host.id, room.id);
    return { matchId: started.matchId, host, guest };
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
    const keys = await redis.keys('match:lock:*');
    if (keys.length > 0) await redis.del(...keys);
  });

  it('rolls with the server roller and checkpoints the event + snapshot', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6]);
    const result = await svc.rollDice(matchId, host.id, randomUUID());
    expect(result.duplicate).toBe(false);
    expect(result.events).toEqual([]);
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
    const state = (await svc.getMatchState(matchId, host.id)) as {
      seq: number;
      snapshot: Record<string, unknown>;
    };
    expect(state.seq).toBe(2);
    const snap = state.snapshot as {
      phase: string;
      lastRoll: number;
      currentPlayerIndex: number;
    };
    expect(snap.phase).toBe('awaitingMove');
    expect(snap.lastRoll).toBe(6);
    expect(snap.currentPlayerIndex).toBe(0);
  });

  it('rejects an out-of-turn roll and leaves the state unchanged', async () => {
    const { matchId, host, guest } = await startMatch();
    const svc = service([6]);
    await expectCode(
      () => svc.rollDice(matchId, guest.id, randomUUID()),
      'NOT_YOUR_TURN',
    );
    const state = (await svc.getMatchState(matchId, host.id)) as {
      seq: number;
    };
    expect(state.seq).toBe(1);
    expect(await countEvents(matchId)).toBe(1);
  });

  it('rejects a second roll while a move is pending', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6]);
    await svc.rollDice(matchId, host.id, randomUUID());
    await expectCode(
      () => svc.rollDice(matchId, host.id, randomUUID()),
      'INVALID_STATE',
    );
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
  });

  it('rejects a move before any roll', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6]);
    await expectCode(
      () => svc.moveToken(matchId, host.id, '0:0', randomUUID()),
      'INVALID_STATE',
    );
    expect(await countEvents(matchId)).toBe(1);
  });

  it('rejects another player’s token and an illegal move', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6, 5]);
    await svc.rollDice(matchId, host.id, randomUUID());
    // Seat 1's token while it is seat 0's turn.
    await expectCode(
      () => svc.moveToken(matchId, host.id, '1:0', randomUUID()),
      'ILLEGAL_MOVE',
    );
    // Release token 0, then a 5: only token 0 may move.
    await svc.moveToken(matchId, host.id, '0:0', randomUUID());
    await svc.rollDice(matchId, host.id, randomUUID());
    await expectCode(
      () => svc.moveToken(matchId, host.id, '0:1', randomUUID()),
      'ILLEGAL_MOVE',
    );
    expect(await countEvents(matchId, 'token_moved')).toBe(1);
  });

  it('rejects a non-player and an unknown match', async () => {
    const { matchId, host } = await startMatch();
    const outsider = await makeUser();
    const svc = service([6]);
    await expectCode(
      () => svc.rollDice(matchId, outsider.id, randomUUID()),
      'NOT_MATCH_PLAYER',
    );
    await expectCode(
      () => svc.rollDice(randomUUID(), host.id, randomUUID()),
      'MATCH_NOT_FOUND',
    );
    await expectCode(
      () => svc.getMatchView(matchId, outsider.id),
      'NOT_MATCH_PLAYER',
    );
  });

  it('ignores a client-supplied dice value and rolls its own', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([2]);
    await svc.rollDice(matchId, host.id, randomUUID(), 6);
    const state = (await svc.getMatchState(matchId, host.id)) as {
      snapshot: Record<string, unknown>;
    };
    // The server rolled 2 (no legal move, turn passed), not the
    // client-supplied 6.
    expect((state.snapshot as { lastRoll: number }).lastRoll).toBe(2);
    expect(
      (state.snapshot as { currentPlayerIndex: number }).currentPlayerIndex,
    ).toBe(1);
  });

  it('returns the original result for a duplicate requestId, with no second transition', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6]);
    const requestId = randomUUID();
    const first = await svc.rollDice(matchId, host.id, requestId);
    expect(first.duplicate).toBe(false);
    const second = await svc.rollDice(matchId, host.id, requestId);
    expect(second.duplicate).toBe(true);
    expect(second.events).toHaveLength(1);
    expect(second.events[0].event).toBe('dice:rolled');
    expect((second.events[0].payload as { value: number }).value).toBe(6);
    expect((second.events[0].payload as { seq: number }).seq).toBe(2);
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
  });

  it('serialises simultaneous duplicate rolls to exactly one transition', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6]);
    const requestId = randomUUID();
    const results = await Promise.allSettled([
      svc.rollDice(matchId, host.id, requestId),
      svc.rollDice(matchId, host.id, requestId),
    ]);
    const fulfilled = results.filter(
      (r) => r.status === 'fulfilled',
    ) as PromiseFulfilledResult<{ duplicate: boolean }>[];
    expect(fulfilled).toHaveLength(2);
    expect(fulfilled.map((r) => r.value.duplicate).sort()).toEqual([
      false,
      true,
    ]);
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
  });

  it('serialises simultaneous conflicting rolls: exactly one wins', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6]);
    const results = await Promise.allSettled([
      svc.rollDice(matchId, host.id, randomUUID()),
      svc.rollDice(matchId, host.id, randomUUID()),
    ]);
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    expect(results.filter((r) => r.status === 'rejected')).toHaveLength(1);
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
  });

  it('serialises simultaneous duplicate moves to exactly one transition', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6]);
    await svc.rollDice(matchId, host.id, randomUUID());
    const requestId = randomUUID();
    const results = await Promise.allSettled([
      svc.moveToken(matchId, host.id, '0:0', requestId),
      svc.moveToken(matchId, host.id, '0:0', requestId),
    ]);
    const fulfilled = results.filter(
      (r) => r.status === 'fulfilled',
    ) as PromiseFulfilledResult<{ duplicate: boolean }>[];
    expect(fulfilled).toHaveLength(2);
    expect(fulfilled.map((r) => r.value.duplicate).sort()).toEqual([
      false,
      true,
    ]);
    expect(await countEvents(matchId, 'token_moved')).toBe(1);
  });

  it('replays from the log: a fresh service instance sees the identical snapshot', async () => {
    const { matchId, host, guest } = await startMatch();
    const svc = service([6, 5, 2]);
    await svc.rollDice(matchId, host.id, randomUUID());
    await svc.moveToken(matchId, host.id, '0:0', randomUUID());
    await svc.rollDice(matchId, host.id, randomUUID());
    await svc.moveToken(matchId, host.id, '0:0', randomUUID());
    const before = await svc.getMatchState(matchId, host.id);
    const fresh = service([6]);
    const after = await fresh.getMatchState(matchId, guest.id);
    expect(after).toEqual(before);
    // And the in-memory cache agrees with a full replay too.
    const loaded = await fresh.loadGame(matchId);
    expect(loaded.seq).toBe((before as { seq: number }).seq);
  });

  it('captures: a scripted position replays, then the live move captures', async () => {
    const { matchId, host, guest } = await startMatch();
    const setup = captureSetup([
      { userId: host.id, seat: 0, colour: 'red', name: host.username },
      { userId: guest.id, seat: 1, colour: 'green', name: guest.username },
    ]);
    await insertRecordedEvents(ds, matchId, setup.events);
    const svc = service([6, 3]);
    const state = (await svc.getMatchState(matchId, host.id)) as {
      snapshot: Record<string, unknown>;
    };
    expect(snapshotTokenSteps(state.snapshot, 0, 0)).toBe(7);
    expect(snapshotTokenSteps(state.snapshot, 1, 0)).toBe(3);
    await svc.rollDice(matchId, host.id, randomUUID());
    await svc.moveToken(matchId, host.id, '0:0', randomUUID());
    await svc.rollDice(matchId, host.id, randomUUID());
    const moved = await svc.moveToken(matchId, host.id, '0:0', randomUUID());
    expect(moved.duplicate).toBe(false);
    const after = (await svc.getMatchState(matchId, host.id)) as {
      snapshot: Record<string, unknown>;
    };
    expect(snapshotTokenSteps(after.snapshot, 0, 0)).toBe(16);
    expect(snapshotTokenSteps(after.snapshot, 1, 0)).toBe(0);
    // Extra turn on capture: it is still red's turn.
    expect(
      (after.snapshot as { currentPlayerIndex: number }).currentPlayerIndex,
    ).toBe(0);
  });

  it('declares the winner atomically: result, ranks, log and refusal afterwards', async () => {
    const { matchId, host, guest } = await startMatch();
    const setup = nearWinSetup([
      { userId: host.id, seat: 0, colour: 'red', name: host.username },
      { userId: guest.id, seat: 1, colour: 'green', name: guest.username },
    ]);
    await insertRecordedEvents(ds, matchId, setup.events);
    const svc = service([1]);
    const state = (await svc.getMatchState(matchId, host.id)) as {
      snapshot: Record<string, unknown>;
    };
    const winningToken = (
      (
        state.snapshot as {
          players: Array<{ tokens: Array<{ stepsTaken: number }> }>;
        }
      ).players[0].tokens as Array<{ stepsTaken: number }>
    ).findIndex((t) => t.stepsTaken === 55);
    expect(winningToken).toBeGreaterThanOrEqual(0);
    await svc.rollDice(matchId, host.id, randomUUID());
    const moved = await svc.moveToken(
      matchId,
      host.id,
      `0:${winningToken}`,
      randomUUID(),
    );
    expect(moved.duplicate).toBe(false);
    const view = await svc.getMatchView(matchId, host.id);
    expect(view.status).toBe('completed');
    expect(view.winnerId).toBe(host.id);
    expect(view.currentPlayerId).toBeNull();
    const winner = view.players.find((p) => p.userId === host.id)!;
    const loser = view.players.find((p) => p.userId === guest.id)!;
    expect(winner).toMatchObject({ result: 'win', finishRank: 1 });
    expect(loser).toMatchObject({ result: 'loss', finishRank: 2 });
    const ended = await ds.query(
      `SELECT "payload" FROM "move_events" WHERE "match_id" = $1 AND "type" = 'match_ended'`,
      [matchId],
    );
    expect(ended).toHaveLength(1);
    expect((ended[0].payload as { winnerId: string }).winnerId).toBe(host.id);
    expect(
      (
        ended[0].payload as { standings: Array<{ rank: number }> }
      ).standings.map((s) => s.rank),
    ).toEqual([1, 2]);
    await expectCode(
      () => svc.rollDice(matchId, host.id, randomUUID()),
      'MATCH_FINISHED',
    );
    await expectCode(
      () => svc.moveToken(matchId, host.id, '0:0', randomUUID()),
      'MATCH_FINISHED',
    );
  });

  it('state:request rejects a lastSeq ahead of the server', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6]);
    await expectCode(
      () => svc.requestState(matchId, host.id, 99),
      'STALE_STATE',
    );
    const state = (await svc.requestState(matchId, host.id, 0)) as {
      seq: number;
    };
    expect(state.seq).toBe(1);
  });

  it('lists the ordered move log with a fromSeq filter', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6]);
    await svc.rollDice(matchId, host.id, randomUUID());
    const log = await svc.listEvents(matchId, host.id, 2, 100);
    expect(log.seq).toBe(2);
    expect(log.events.map((e) => e.seq)).toEqual([2]);
    expect(log.events[0].type).toBe('dice_rolled');
    const all = await svc.listEvents(matchId, host.id, 1, 100);
    expect(all.events.map((e) => e.type)).toEqual([
      'match_started',
      'dice_rolled',
    ]);
  });

  it('getActiveMatch finds the in-progress match and null otherwise', async () => {
    const { matchId, host } = await startMatch();
    const svc = service([6]);
    const active = await svc.getActiveMatch(host.id);
    expect(active?.id).toBe(matchId);
    const outsider = await makeUser();
    expect(await svc.getActiveMatch(outsider.id)).toBeNull();
  });

  it('continues on the local mutex when Redis is unreachable', async () => {
    const { matchId, host } = await startMatch();
    const throwingRedis = {
      acquireLock: jest.fn().mockRejectedValue(new Error('ECONNREFUSED')),
      releaseLock: jest.fn(),
    };
    const svc = new MatchService(
      ds,
      throwingRedis as never,
      new RoomBroadcaster(),
      new FixedDiceRoller([6], { cycle: true }),
    );
    const result = await svc.rollDice(matchId, host.id, randomUUID());
    expect(result.duplicate).toBe(false);
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
    // Two concurrent intents still serialise on the local mutex.
    const results = await Promise.allSettled([
      svc.moveToken(matchId, host.id, '0:0', randomUUID()),
      svc.moveToken(matchId, host.id, '0:1', randomUUID()),
    ]);
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    expect(await countEvents(matchId, 'token_moved')).toBe(1);
  });
});
