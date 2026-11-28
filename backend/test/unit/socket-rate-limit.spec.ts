import { ServiceUnavailableException } from '@nestjs/common';
import type { ExecutionContext } from '@nestjs/common';
import { ErrorCode } from '../../src/common/errors/error-codes';
import {
  SOCKET_EVENTS_PER_SECOND,
  SOCKET_EVENT_WINDOW_SECONDS,
} from '../../src/socket/socket.constants';
import { SocketRateLimitService } from '../../src/socket/socket-rate-limit.service';
import { WsRateLimitGuard } from '../../src/socket/ws-rate-limit.guard';
import type { GameSocket } from '../../src/socket/ws-jwt.guard';

function makeClient(): GameSocket {
  return {
    id: 'socket-1',
    data: {},
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

function envelopeOf(err: unknown): { error: { code: string } } {
  return (err as { getError: () => { error: { code: string } } }).getError();
}

describe('SocketRateLimitService (20 events/s per connection)', () => {
  const redis = { incrWithExpiry: jest.fn() };
  const service = new SocketRateLimitService(redis as never);

  beforeEach(() => jest.clearAllMocks());

  it('allows events within the budget and keys by socket id + 1s window', async () => {
    redis.incrWithExpiry.mockResolvedValue(1);
    await expect(service.check('socket-1')).resolves.toEqual({
      allowed: true,
    });
    expect(redis.incrWithExpiry).toHaveBeenCalledWith(
      'ratelimit:socket:socket-1:1s',
      SOCKET_EVENT_WINDOW_SECONDS,
    );
  });

  it(`allows exactly ${SOCKET_EVENTS_PER_SECOND} events`, async () => {
    redis.incrWithExpiry.mockResolvedValue(SOCKET_EVENTS_PER_SECOND);
    await expect(service.check('socket-1')).resolves.toEqual({
      allowed: true,
    });
  });

  it('rejects the 21st event in the window', async () => {
    redis.incrWithExpiry.mockResolvedValue(SOCKET_EVENTS_PER_SECOND + 1);
    await expect(service.check('socket-1')).resolves.toEqual({
      allowed: false,
    });
  });

  it('falls back to a local per-socket bucket when Redis is unavailable (still throttled, never unthrottled)', async () => {
    // Stage 5 (assessment risk 5): in-progress matches must keep
    // working while Redis is down, so the 20/s event limit falls back
    // to an in-process bucket instead of failing closed. The limit
    // still holds per socket on this node; only the multi-node
    // aggregation is lost until Redis returns.
    redis.incrWithExpiry.mockRejectedValue(new Error('Redis is down'));
    for (let i = 0; i < SOCKET_EVENTS_PER_SECOND; i++) {
      await expect(service.check('socket-1')).resolves.toEqual({
        allowed: true,
      });
    }
    await expect(service.check('socket-1')).resolves.toEqual({
      allowed: false,
    });
  });
});

describe('WsRateLimitGuard', () => {
  const limiter = { check: jest.fn() };
  const guard = new WsRateLimitGuard(limiter as never);

  beforeEach(() => jest.clearAllMocks());

  it('allows an event within budget', async () => {
    limiter.check.mockResolvedValue({ allowed: true });
    const client = makeClient();
    expect(await guard.canActivate(makeContext(client))).toBe(true);
    expect(limiter.check).toHaveBeenCalledWith('socket-1');
  });

  it('drops an over-limit event with a RATE_LIMITED WsException', async () => {
    limiter.check.mockResolvedValue({ allowed: false });
    const client = makeClient();
    const err = await guard
      .canActivate(makeContext(client))
      .catch((e: unknown) => e);
    expect(envelopeOf(err).error.code).toBe(ErrorCode.RateLimited);
    expect(client.data.rateLimitViolations).toBe(1);
    expect(client.disconnect).not.toHaveBeenCalled();
  });

  it('disconnects the socket on sustained abuse (5th violation)', async () => {
    limiter.check.mockResolvedValue({ allowed: false });
    const client = makeClient();
    for (let i = 0; i < 5; i++) {
      await guard.canActivate(makeContext(client)).catch(() => undefined);
    }
    expect(client.data.rateLimitViolations).toBe(5);
    expect(client.disconnect).toHaveBeenCalledTimes(1);
    expect(client.disconnect).toHaveBeenCalledWith(true);
  });

  it('maps a Redis outage to SERVICE_UNAVAILABLE, not RATE_LIMITED', async () => {
    limiter.check.mockRejectedValue(
      new ServiceUnavailableException('unavailable'),
    );
    const client = makeClient();
    const err = await guard
      .canActivate(makeContext(client))
      .catch((e: unknown) => e);
    expect(envelopeOf(err).error.code).toBe(ErrorCode.ServiceUnavailable);
    expect(client.disconnect).not.toHaveBeenCalled();
  });
});
