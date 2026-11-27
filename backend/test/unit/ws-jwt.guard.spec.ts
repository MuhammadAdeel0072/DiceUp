import { UnauthorizedException } from '@nestjs/common';
import type { ExecutionContext } from '@nestjs/common';
import type { RequestUser } from '../../src/common/guards/request-user';
import { ErrorCode } from '../../src/common/errors/error-codes';
import { SocketAuthError } from '../../src/socket/socket-error';
import {
  extractHandshakeToken,
  WsJwtGuard,
  type GameSocket,
} from '../../src/socket/ws-jwt.guard';

function makeUser(overrides: Partial<RequestUser> = {}): RequestUser {
  return {
    id: 'user-1',
    email: 'ali@example.com',
    username: 'ali_plays',
    role: 'player',
    emailVerified: true,
    status: 'active',
    sessionId: 'session-1',
    deletionRequestedAt: null,
    ...overrides,
  };
}

function makeClient(authToken?: string): GameSocket {
  return {
    id: 'socket-1',
    data: authToken ? { authToken } : {},
    handshake: { auth: authToken ? { token: authToken } : {} },
    disconnect: jest.fn(),
  } as unknown as GameSocket;
}

function makeContext(client: GameSocket): ExecutionContext {
  return {
    switchToWs: () => ({ getClient: () => client }),
    getHandler: () => ({}) as never,
    getClass: () => ({}) as never,
  } as unknown as ExecutionContext;
}

describe('extractHandshakeToken', () => {
  it.each([
    ['missing auth', undefined, undefined],
    ['null auth', null, undefined],
    ['empty object', {}, undefined],
    ['non-string token', { token: 42 }, undefined],
    ['empty token', { token: '' }, undefined],
    ['valid token', { token: 'tok-1' }, 'tok-1'],
  ])('%s → %s', (_label, auth, expected) => {
    expect(extractHandshakeToken(auth)).toBe(expected);
  });
});

describe('WsJwtGuard.authenticate (the ONE auth path)', () => {
  const payload = {
    sub: 'user-1',
    role: 'player' as const,
    email_verified: true,
    sid: 'session-1',
  };
  const tokens = { verifyAccessToken: jest.fn() };
  const strategy = { validate: jest.fn() };
  const guard = new WsJwtGuard(tokens as never, strategy as never);

  beforeEach(() => {
    jest.clearAllMocks();
    tokens.verifyAccessToken.mockReturnValue(payload);
    strategy.validate.mockResolvedValue(makeUser());
  });

  it('returns the principal for a valid token + live session', async () => {
    const user = await guard.authenticate({ token: 'good-token' });
    expect(user.id).toBe('user-1');
    expect(tokens.verifyAccessToken).toHaveBeenCalledWith('good-token');
    expect(strategy.validate).toHaveBeenCalledWith(payload);
  });

  it('rejects a missing token with UNAUTHORIZED', async () => {
    await expect(guard.authenticate({})).rejects.toMatchObject({
      code: ErrorCode.Unauthorized,
    } as unknown as SocketAuthError);
    await expect(guard.authenticate(undefined)).rejects.toBeInstanceOf(
      SocketAuthError,
    );
  });

  it('rejects a token that fails verification with UNAUTHORIZED', async () => {
    tokens.verifyAccessToken.mockImplementation(() => {
      throw new UnauthorizedException('bad');
    });
    const err = await guard
      .authenticate({ token: 'bad-token' })
      .catch((e: unknown) => e);
    expect(err).toBeInstanceOf(SocketAuthError);
    expect((err as SocketAuthError).code).toBe(ErrorCode.Unauthorized);
  });

  it('rejects a revoked session (sid check fails) with UNAUTHORIZED', async () => {
    strategy.validate.mockRejectedValue(
      new UnauthorizedException('Session is no longer valid.'),
    );
    const err = await guard
      .authenticate({ token: 'revoked-token' })
      .catch((e: unknown) => e);
    expect(err).toBeInstanceOf(SocketAuthError);
    expect((err as SocketAuthError).code).toBe(ErrorCode.Unauthorized);
    // The message stays generic — it must not say which check failed.
    expect((err as SocketAuthError).message).toBe(
      'Invalid or expired access token.',
    );
  });

  it.each(['suspended', 'blocked'] as const)(
    'rejects %s accounts with ACCOUNT_SUSPENDED',
    async (status) => {
      strategy.validate.mockResolvedValue(makeUser({ status }));
      const err = await guard
        .authenticate({ token: 'tok' })
        .catch((e: unknown) => e);
      expect((err as SocketAuthError).code).toBe(ErrorCode.AccountSuspended);
    },
  );

  it('rejects accounts with a pending deletion request with FORBIDDEN', async () => {
    strategy.validate.mockResolvedValue(
      makeUser({ deletionRequestedAt: new Date() }),
    );
    const err = await guard
      .authenticate({ token: 'tok' })
      .catch((e: unknown) => e);
    expect((err as SocketAuthError).code).toBe(ErrorCode.Forbidden);
  });

  it('rejects unverified users with EMAIL_NOT_VERIFIED', async () => {
    strategy.validate.mockResolvedValue(makeUser({ emailVerified: false }));
    const err = await guard
      .authenticate({ token: 'tok' })
      .catch((e: unknown) => e);
    expect((err as SocketAuthError).code).toBe(ErrorCode.EmailNotVerified);
  });

  it('lets unexpected errors propagate (not misreported as bad credentials)', async () => {
    strategy.validate.mockRejectedValue(new Error('database is down'));
    await expect(guard.authenticate({ token: 'tok' })).rejects.toThrow(
      'database is down',
    );
  });
});

describe('WsJwtGuard.canActivate (per-message re-validation)', () => {
  const tokens = { verifyAccessToken: jest.fn() };
  const strategy = { validate: jest.fn() };
  const guard = new WsJwtGuard(tokens as never, strategy as never);

  beforeEach(() => {
    jest.clearAllMocks();
    tokens.verifyAccessToken.mockReturnValue({ sub: 'user-1', sid: 's1' });
    strategy.validate.mockResolvedValue(makeUser());
  });

  it('re-validates the stored token and refreshes the principal', async () => {
    const client = makeClient('tok-1');
    expect(await guard.canActivate(makeContext(client))).toBe(true);
    expect(client.data.user?.id).toBe('user-1');
    expect(client.data.authToken).toBe('tok-1');
  });

  it('throws a WsException with the UNAUTHORIZED envelope when no token is present', async () => {
    const client = makeClient();
    const err = await guard
      .canActivate(makeContext(client))
      .catch((e: unknown) => e);
    const body = (
      err as { getError: () => { error: { code: string } } }
    ).getError();
    expect(body.error.code).toBe(ErrorCode.Unauthorized);
  });

  it('fails a message when the session was revoked mid-connection', async () => {
    strategy.validate.mockRejectedValue(
      new UnauthorizedException('Session is no longer valid.'),
    );
    const client = makeClient('tok-1');
    const err = await guard
      .canActivate(makeContext(client))
      .catch((e: unknown) => e);
    const body = (
      err as { getError: () => { error: { code: string } } }
    ).getError();
    expect(body.error.code).toBe(ErrorCode.Unauthorized);
  });

  it('maps unexpected failures to SERVICE_UNAVAILABLE, not UNAUTHORIZED', async () => {
    strategy.validate.mockRejectedValue(new Error('database is down'));
    const client = makeClient('tok-1');
    const err = await guard
      .canActivate(makeContext(client))
      .catch((e: unknown) => e);
    const body = (
      err as { getError: () => { error: { code: string } } }
    ).getError();
    expect(body.error.code).toBe(ErrorCode.ServiceUnavailable);
  });
});

describe('SocketAuthError.toHandshakeError (connect_error shape)', () => {
  it('puts the envelope on err.data so the client receives err.data', () => {
    const err = new SocketAuthError(
      ErrorCode.Unauthorized,
      'Invalid or expired access token.',
    ).toHandshakeError();
    // socket.io (namespace.js, protocol 4) sends the CONNECT_ERROR
    // packet as { message: err.message, data: err.data }, and the
    // client builds `new Error(packet.data.message)` with
    // `err.data = packet.data.data` — so err.data IS the envelope,
    // not a double-wrapped { message, data } object. (An earlier
    // version of this test asserted the double-wrapped shape; the
    // e2e connect_error assertions prove the envelope-direct shape
    // is what a real client receives.)
    const data = (err as Error & { data: unknown }).data as {
      success: boolean;
      error: { code: string; message: string };
    };
    expect(err.message).toBe('Invalid or expired access token.');
    expect(data.success).toBe(false);
    expect(data.error.code).toBe(ErrorCode.Unauthorized);
    expect(data.error.message).toBe('Invalid or expired access token.');
  });
});
