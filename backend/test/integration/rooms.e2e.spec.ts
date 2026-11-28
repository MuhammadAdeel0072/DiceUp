import { INestApplication } from '@nestjs/common';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { LogMailerService } from '../../src/mailer/log-mailer.service';
import { RoomsService } from '../../src/rooms/rooms.service';
import { User } from '../../src/users/entities/user.entity';
import {
  bootTestApp,
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
  RateLimitCleaner,
  uniqueUser,
} from './test-helpers';

/**
 * Rooms REST end-to-end (plan §10.3): real PostgreSQL 16 + real
 * Redis 7, fresh scratch database, migrations, real HTTP listen.
 * Covers: create/join/leave/get, validation, the specific room
 * errors (ROOM_NOT_FOUND / ROOM_FULL / ROOM_STARTED), unauthorised
 * access, host transfer, close-if-empty, and the empty-room sweeper.
 * Socket delivery of the same changes is covered by
 * rooms-socket.e2e.spec.ts.
 */
describe('rooms REST (real PostgreSQL + real Redis)', () => {
  let dbName: string;
  let databaseUrl: string;
  let app: INestApplication;
  let ds: DataSource;
  let mailer: LogMailerService;
  let cleaner: RateLimitCleaner;

  const api = () => request(app.getHttpServer());
  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  async function registerUser(): Promise<{
    email: string;
    password: string;
    userId: string;
  }> {
    const u = uniqueUser();
    const res = await api().post('/v1/auth/register').send(u);
    expect(res.status).toBe(201);
    return {
      email: u.email,
      password: u.password,
      userId: res.body.data.user.id as string,
    };
  }

  async function verifyUser(email: string): Promise<void> {
    const msg = mailer.findLatest(email, 'verification');
    expect(msg).toBeDefined();
    const res = await api()
      .post('/v1/auth/verify-email')
      .send({ token: msg!.token });
    expect(res.status).toBe(200);
  }

  async function login(email: string, password: string): Promise<string> {
    const res = await api()
      .post('/v1/auth/login')
      .send({ identifier: email, password });
    expect(res.status).toBe(200);
    return res.body.data.tokens.accessToken as string;
  }

  async function verifiedAccessToken(): Promise<{
    accessToken: string;
    userId: string;
  }> {
    const u = await registerUser();
    await verifyUser(u.email);
    const accessToken = await login(u.email, u.password);
    return { accessToken, userId: u.userId };
  }

  async function createRoom(
    token: string,
    maxPlayers = 4,
  ): Promise<{ id: string; code: string }> {
    const res = await api()
      .post('/v1/rooms')
      .set(auth(token))
      .send({ maxPlayers });
    expect(res.status).toBe(201);
    return {
      id: res.body.data.id as string,
      code: res.body.data.code as string,
    };
  }

  beforeAll(async () => {
    ({ name: dbName, url: databaseUrl } = await createScratchDb());
    await migrateScratchDb(databaseUrl);
    app = await bootTestApp(databaseUrl);
    await app.listen(0);
    ds = app.get(DataSource);
    mailer = app.get(LogMailerService);
    cleaner = new RateLimitCleaner();
  }, 120000);

  afterAll(async () => {
    if (cleaner) await cleaner.quit();
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await cleaner.clear();
    mailer.clear();
  });

  it('refuses unauthenticated room calls (401)', async () => {
    await expect(
      api().post('/v1/rooms').send({ maxPlayers: 4 }),
    ).resolves.toMatchObject({
      status: 401,
    });
    await expect(
      api().post('/v1/rooms/join').send({ code: 'AAAAAA' }),
    ).resolves.toMatchObject({ status: 401 });
    await expect(api().get('/v1/matchmaking/status')).resolves.toMatchObject({
      status: 401,
    });
  });

  it('creates a room (201) and validates maxPlayers (400)', async () => {
    const { accessToken, userId } = await verifiedAccessToken();
    const res = await api()
      .post('/v1/rooms')
      .set(auth(accessToken))
      .send({ maxPlayers: 2 });
    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({
      success: true,
      data: { hostId: userId, maxPlayers: 2, status: 'open' },
    });
    expect(res.body.data.code as string).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
    const bad = await api()
      .post('/v1/rooms')
      .set(auth(accessToken))
      .send({ maxPlayers: 5 });
    expect(bad.status).toBe(400);
    expect(bad.body.error.code).toBe('VALIDATION_FAILED');
  });

  it('join: unknown code 404 ROOM_NOT_FOUND, bad format 400', async () => {
    const { accessToken } = await verifiedAccessToken();
    const res = await api()
      .post('/v1/rooms/join')
      .set(auth(accessToken))
      .send({ code: 'ZZZZZZ' });
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('ROOM_NOT_FOUND');
    const bad = await api()
      .post('/v1/rooms/join')
      .set(auth(accessToken))
      .send({ code: 'BAD!' });
    expect(bad.status).toBe(400);
    expect(bad.body.error.code).toBe('VALIDATION_FAILED');
  });

  it('join: full room 409 ROOM_FULL; second room 409 ALREADY_IN_ROOM', async () => {
    const host = await verifiedAccessToken();
    const room = await createRoom(host.accessToken, 2);
    const guest = await verifiedAccessToken();
    const joined = await api()
      .post('/v1/rooms/join')
      .set(auth(guest.accessToken))
      .send({ code: room.code });
    expect(joined.status).toBe(200);
    expect(joined.body.data.members).toHaveLength(2);
    const third = await verifiedAccessToken();
    const full = await api()
      .post('/v1/rooms/join')
      .set(auth(third.accessToken))
      .send({ code: room.code });
    expect(full.status).toBe(409);
    expect(full.body.error.code).toBe('ROOM_FULL');
    const secondRoom = await api()
      .post('/v1/rooms')
      .set(auth(guest.accessToken))
      .send({ maxPlayers: 2 });
    expect(secondRoom.status).toBe(409);
    expect(secondRoom.body.error.code).toBe('ALREADY_IN_ROOM');
  });

  it('join: started room 409 ROOM_STARTED', async () => {
    const host = await verifiedAccessToken();
    const room = await createRoom(host.accessToken, 2);
    const guest = await verifiedAccessToken();
    await api()
      .post('/v1/rooms/join')
      .set(auth(guest.accessToken))
      .send({ code: room.code });
    const rooms = app.get(RoomsService);
    await rooms.setReady(host.userId, room.id, true);
    await rooms.setReady(guest.userId, room.id, true);
    await rooms.startMatch(host.userId, room.id);
    const late = await verifiedAccessToken();
    const res = await api()
      .post('/v1/rooms/join')
      .set(auth(late.accessToken))
      .send({ code: room.code });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('ROOM_STARTED');
  });

  it('get room: member 200, non-member 403, unknown 404', async () => {
    const host = await verifiedAccessToken();
    const room = await createRoom(host.accessToken, 4);
    const stranger = await verifiedAccessToken();
    const ok = await api()
      .get(`/v1/rooms/${room.id}`)
      .set(auth(host.accessToken));
    expect(ok.status).toBe(200);
    expect(ok.body.data.members).toHaveLength(1);
    const forbidden = await api()
      .get(`/v1/rooms/${room.id}`)
      .set(auth(stranger.accessToken));
    expect(forbidden.status).toBe(403);
    expect(forbidden.body.error.code).toBe('NOT_ROOM_MEMBER');
    const missing = await api()
      .get('/v1/rooms/3f7a2c10-9c4e-4b1a-8e2d-1a2b3c4d5e6f')
      .set(auth(host.accessToken));
    expect(missing.status).toBe(404);
    expect(missing.body.error.code).toBe('ROOM_NOT_FOUND');
  });

  it('leave: host transfers to longest-present; last leave closes', async () => {
    const host = await verifiedAccessToken();
    const room = await createRoom(host.accessToken, 4);
    const second = await verifiedAccessToken();
    const third = await verifiedAccessToken();
    for (const g of [second, third]) {
      const res = await api()
        .post('/v1/rooms/join')
        .set(auth(g.accessToken))
        .send({ code: room.code });
      expect(res.status).toBe(200);
    }
    const left = await api()
      .post(`/v1/rooms/${room.id}/leave`)
      .set(auth(host.accessToken));
    expect(left.status).toBe(200);
    expect(left.body.data.hostId).toBe(second.userId);
    expect(left.body.data.status).toBe('open');
    await api()
      .post(`/v1/rooms/${room.id}/leave`)
      .set(auth(second.accessToken));
    const closed = await api()
      .post(`/v1/rooms/${room.id}/leave`)
      .set(auth(third.accessToken));
    expect(closed.status).toBe(200);
    expect(closed.body.data.status).toBe('closed');
    expect(closed.body.data.members).toHaveLength(0);
    // The closed room is gone: a leave on it is ROOM_NOT_FOUND, and
    // the user row itself is untouched by any of this.
    const stranger = await verifiedAccessToken();
    const gone = await api()
      .post(`/v1/rooms/${room.id}/leave`)
      .set(auth(stranger.accessToken));
    expect(gone.status).toBe(404);
    expect(gone.body.error.code).toBe('ROOM_NOT_FOUND');
  });

  it('sweeper closes an orphaned empty room older than 10 minutes', async () => {
    const host = await verifiedAccessToken();
    const room = await createRoom(host.accessToken, 4);
    // Orphan the room: remove the member row directly (a create whose
    // client vanished, UC-06 E1) and age it past the threshold.
    await ds.query(`DELETE FROM "room_members" WHERE "room_id" = $1`, [
      room.id,
    ]);
    await ds.query(
      `UPDATE "rooms" SET "created_at" = now() - interval '11 minutes' WHERE "id" = $1`,
      [room.id],
    );
    const rooms = app.get(RoomsService);
    expect(await rooms.sweepEmptyRooms()).toBe(1);
    const rows = await ds.query(
      `SELECT "status" FROM "rooms" WHERE "id" = $1`,
      [room.id],
    );
    expect(rows[0].status).toBe('closed');
    // The user row itself is untouched.
    const user = await ds
      .getRepository(User)
      .findOne({ where: { id: host.userId } });
    expect(user).not.toBeNull();
  });
});
