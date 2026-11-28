import { randomUUID } from 'node:crypto';
import { HttpException } from '@nestjs/common';
import type { ConfigService } from '@nestjs/config';
import { DataSource } from 'typeorm';
import { buildDataSourceOptions } from '../../src/database/data-source';
import { RoomBroadcaster } from '../../src/rooms/room-broadcaster';
import { RoomsService } from '../../src/rooms/rooms.service';
import { Profile } from '../../src/users/entities/profile.entity';
import { User } from '../../src/users/entities/user.entity';
import {
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
} from '../integration/test-helpers';

jest.setTimeout(120000);

/**
 * RoomsService against a real PostgreSQL scratch DB (migrations run
 * as a release step would). Covers the service contract the REST and
 * socket layers share: create/join/leave/ready/start, host transfer,
 * the sweeper, and — the load-bearing case — concurrent joins on the
 * last seat (TOCTOU, same class as H-02): exactly one joiner wins.
 * Broadcasting is a no-op here (RoomBroadcaster with no gateway
 * attached drops emits); broadcast delivery is covered by the socket
 * e2e spec.
 */
describe('RoomsService (real PostgreSQL)', () => {
  let dbName: string;
  let databaseUrl: string;
  let ds: DataSource;
  let service: RoomsService;

  function codeOf(err: unknown): string | undefined {
    if (err instanceof HttpException) {
      const body = err.getResponse() as { code?: string };
      return typeof body === 'object' ? body.code : undefined;
    }
    return undefined;
  }

  function statusOf(err: unknown): number | undefined {
    return err instanceof HttpException ? err.getStatus() : undefined;
  }

  /** Expect the call to throw an HttpException with code + status. */
  async function expectCode(
    fn: () => Promise<unknown>,
    code: string,
    status: number,
  ): Promise<void> {
    try {
      await fn();
      throw new Error(`expected ${code} but the call succeeded`);
    } catch (err) {
      if ((err as Error).message.startsWith('expected ')) throw err;
      expect(codeOf(err)).toBe(code);
      expect(statusOf(err)).toBe(status);
    }
  }

  async function makeUser(): Promise<{ id: string }> {
    const tag = randomUUID().slice(0, 8);
    const user = await ds.getRepository(User).save(
      ds.getRepository(User).create({
        email: `room-${tag}@example.com`,
        username: `room_${tag}`,
        passwordHash: 'x',
        status: 'active',
        emailVerifiedAt: new Date(),
      }),
    );
    await ds.getRepository(Profile).save(
      ds.getRepository(Profile).create({
        userId: user.id,
        displayName: `Room ${tag}`,
      }),
    );
    return { id: user.id };
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
    service = new RoomsService(ds, config, new RoomBroadcaster());
  }, 120000);

  afterAll(async () => {
    if (ds) await ds.destroy();
    if (dbName) await dropScratchDb(dbName);
  });

  it('creates a room: host member, 6-char code, frozen ruleset', async () => {
    const host = await makeUser();
    const room = await service.createRoom(host.id, 4);
    expect(room.code).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
    expect(room.status).toBe('open');
    expect(room.hostId).toBe(host.id);
    expect(room.maxPlayers).toBe(4);
    expect(room.rulesetVersion).toBe('1.0.0');
    expect(room.source).toBe('manual');
    expect(room.members).toHaveLength(1);
    expect(room.members[0]).toMatchObject({
      userId: host.id,
      isHost: true,
      isReady: false,
    });
  });

  it('seeds the game_configurations row (30/60/3, max 4)', async () => {
    const config = await service.getGameConfiguration();
    expect(config).toMatchObject({
      version: '1.0.0',
      turnTimerSeconds: 30,
      gracePeriodSeconds: 60,
      missedTurnLimit: 3,
      maxRoomPlayers: 4,
    });
  });

  it('refuses a second room for a host already in an open room', async () => {
    const host = await makeUser();
    await service.createRoom(host.id, 2);
    await expectCode(
      () => service.createRoom(host.id, 2),
      'ALREADY_IN_ROOM',
      409,
    );
  });

  it('joins by code; unknown and closed codes are ROOM_NOT_FOUND', async () => {
    const host = await makeUser();
    const room = await service.createRoom(host.id, 4);
    const guest = await makeUser();
    const joined = await service.joinByCode(guest.id, room.code.toLowerCase());
    expect(joined.members).toHaveLength(2);
    // Idempotent re-join for a member.
    await expect(
      service.joinByCode(guest.id, room.code),
    ).resolves.toMatchObject({ id: room.id });
    const stranger0 = await makeUser();
    await expectCode(
      () => service.joinByCode(stranger0.id, 'ZZZZZZ'),
      'ROOM_NOT_FOUND',
      404,
    );
    // Closed room: the last member leaves, then the code is dead.
    await service.leaveRoom(host.id, room.id);
    await service.leaveRoom(guest.id, room.id);
    const stranger = await makeUser();
    await expectCode(
      () => service.joinByCode(stranger.id, room.code),
      'ROOM_NOT_FOUND',
      404,
    );
  });

  it('refuses a join on a full room (ROOM_FULL)', async () => {
    const host = await makeUser();
    const room = await service.createRoom(host.id, 2);
    await service.joinByCode((await makeUser()).id, room.code);
    const third = await makeUser();
    await expectCode(
      () => service.joinByCode(third.id, room.code),
      'ROOM_FULL',
      409,
    );
  });

  it('concurrent joins on the last seat: exactly one wins (TOCTOU)', async () => {
    const host = await makeUser();
    const room = await service.createRoom(host.id, 2);
    const contenders = await Promise.all(
      Array.from({ length: 10 }, () => makeUser()),
    );
    const results = await Promise.allSettled(
      contenders.map((u) => service.joinByCode(u.id, room.code)),
    );
    const won = results.filter((r) => r.status === 'fulfilled');
    const lost = results.filter((r) => r.status === 'rejected');
    expect(won).toHaveLength(1);
    expect(lost).toHaveLength(9);
    for (const l of lost) {
      expect(codeOf((l as PromiseRejectedResult).reason)).toBe('ROOM_FULL');
    }
    const view = await service.findRoomView(room.id);
    expect(view?.members).toHaveLength(2);
  });

  it('transfers host to the longest-present member; empty room closes', async () => {
    const host = await makeUser();
    const room = await service.createRoom(host.id, 4);
    const second = await makeUser();
    const third = await makeUser();
    await service.joinByCode(second.id, room.code);
    await service.joinByCode(third.id, room.code);
    const afterLeave = await service.leaveRoom(host.id, room.id);
    expect(afterLeave.hostId).toBe(second.id);
    expect(afterLeave.members.find((m) => m.userId === second.id)?.isHost).toBe(
      true,
    );
    expect(afterLeave.status).toBe('open');
    await service.leaveRoom(second.id, room.id);
    const closed = await service.leaveRoom(third.id, room.id);
    expect(closed.status).toBe('closed');
    expect(closed.members).toHaveLength(0);
    expect(closed.closedAt).not.toBeNull();
  });

  it('leave rejects non-members and playing rooms', async () => {
    const host = await makeUser();
    const room = await service.createRoom(host.id, 2);
    const stranger = await makeUser();
    await expectCode(
      () => service.leaveRoom(stranger.id, room.id),
      'NOT_ROOM_MEMBER',
      403,
    );
    const guest = await makeUser();
    await service.joinByCode(guest.id, room.code);
    await service.setReady(host.id, room.id, true);
    await service.setReady(guest.id, room.id, true);
    await service.startMatch(host.id, room.id);
    await expectCode(
      () => service.leaveRoom(host.id, room.id),
      'INVALID_STATE',
      409,
    );
  });

  it('startMatch enforces host, ≥2 players, all ready; seats in join order', async () => {
    const host = await makeUser();
    const room = await service.createRoom(host.id, 4);
    const guest = await makeUser();
    await service.joinByCode(guest.id, room.code);
    // Non-host cannot start.
    await expectCode(
      () => service.startMatch(guest.id, room.id),
      'NOT_ROOM_HOST',
      403,
    );
    // Not all ready.
    await service.setReady(host.id, room.id, true);
    await expectCode(
      () => service.startMatch(host.id, room.id),
      'INVALID_STATE',
      409,
    );
    await service.setReady(guest.id, room.id, true);
    const started = await service.startMatch(host.id, room.id);
    expect(started.seats).toEqual([
      { userId: host.id, seat: 0, colour: 'red' },
      { userId: guest.id, seat: 1, colour: 'green' },
    ]);
    expect(started.rulesetVersion).toBe('1.0.0');
    const view = await service.findRoomView(room.id);
    expect(view?.status).toBe('playing');
    expect(view?.matchId).toBe(started.matchId);
    // Match rows persisted: match + players + match_started event.
    const matchPlayers = await ds.query(
      `SELECT "user_id", "seat", "colour" FROM "match_players" WHERE "match_id" = $1 ORDER BY "seat"`,
      [started.matchId],
    );
    expect(matchPlayers).toHaveLength(2);
    expect(matchPlayers[0]).toMatchObject({
      user_id: host.id,
      seat: 0,
      colour: 'red',
    });
    const events = await ds.query(
      `SELECT "seq_no", "type" FROM "move_events" WHERE "match_id" = $1`,
      [started.matchId],
    );
    expect(events).toEqual([{ seq_no: 1, type: 'match_started' }]);
    // Second start is refused; joins on a playing room are ROOM_STARTED.
    await expectCode(
      () => service.startMatch(host.id, room.id),
      'INVALID_STATE',
      409,
    );
    const late = await makeUser();
    await expectCode(
      () => service.joinByCode(late.id, room.code),
      'ROOM_STARTED',
      409,
    );
  });

  it('startMatch needs at least 2 players', async () => {
    const host = await makeUser();
    const room = await service.createRoom(host.id, 4);
    await service.setReady(host.id, room.id, true);
    await expectCode(
      () => service.startMatch(host.id, room.id),
      'INVALID_STATE',
      409,
    );
  });

  it('startMatch is refused while Redis is down (Stage 5, risk 5)', async () => {
    const host = await makeUser();
    const guest = await makeUser();
    const room = await service.createRoom(host.id, 2);
    await service.joinByCode(guest.id, room.code);
    await service.setReady(host.id, room.id, true);
    await service.setReady(guest.id, room.id, true);
    const stubConfig = {
      getOrThrow: (key: string) =>
        key === 'app' ? { rulesetVersion: '1.0.0' } : undefined,
    } as unknown as ConfigService;
    const downService = new RoomsService(
      ds,
      stubConfig,
      new RoomBroadcaster(),
      {
        ping: async () => false,
      } as never,
    );
    await expectCode(
      () => downService.startMatch(host.id, room.id),
      'MATCH_UNAVAILABLE',
      503,
    );
    // Nothing was created: the room is still open, no match exists.
    expect((await service.findRoomView(room.id))?.status).toBe('open');
    const matches = await ds.query(
      `SELECT COUNT(*) AS "n" FROM "matches" WHERE "room_id" = $1`,
      [room.id],
    );
    expect(Number(matches[0].n)).toBe(0);
  });

  it('sweeper closes only empty rooms older than 10 minutes', async () => {
    const host = await makeUser();
    const empty = await service.createRoom(host.id, 4);
    const busyHost = await makeUser();
    const busy = await service.createRoom(busyHost.id, 4);
    await service.joinByCode((await makeUser()).id, busy.code);
    // Age both rooms 11 minutes.
    await ds.query(
      `UPDATE "rooms" SET "created_at" = now() - interval '11 minutes' WHERE "id" IN ($1, $2)`,
      [empty.id, busy.id],
    );
    // Empty the first room (leaves close it immediately — so instead
    // simulate an orphan by deleting the member row directly).
    await ds.query(`DELETE FROM "room_members" WHERE "room_id" = $1`, [
      empty.id,
    ]);
    expect(await service.sweepEmptyRooms()).toBe(1);
    expect((await service.findRoomView(empty.id))?.status).toBe('closed');
    expect((await service.findRoomView(busy.id))?.status).toBe('open');
    expect(await service.sweepEmptyRooms()).toBe(0);
  });
});
