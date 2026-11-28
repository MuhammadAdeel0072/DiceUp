import type { NextFunction, Request, Response } from 'express';
import { RATE_LIMITS } from '../../src/auth/auth.constants';
import { UnauthenticatedRateLimitMiddleware } from '../../src/common/rate-limit/unauthenticated-rate-limit.middleware';

/**
 * L-01 middleware: a per-IP flood bound on /v1 (except health) that
 * runs before the guard chain, fails open when Redis is down, and
 * answers 429 with Retry-After over the limit.
 */
describe('UnauthenticatedRateLimitMiddleware', () => {
  function mocks(
    path: string,
    ip = '9.9.9.9',
  ): {
    req: Request;
    res: Response;
    next: NextFunction;
  } {
    const req = { path, ip } as unknown as Request;
    const res = {
      setHeader: jest.fn(),
      status: jest.fn().mockReturnThis(),
      json: jest.fn(),
    } as unknown as Response;
    const next = jest.fn() as unknown as NextFunction;
    return { req, res, next };
  }

  function middlewareWith(redis: unknown): UnauthenticatedRateLimitMiddleware {
    return new UnauthenticatedRateLimitMiddleware(redis as never);
  }

  it('passes non-/v1 and health requests without touching Redis', async () => {
    const redis = { incrWithExpiry: jest.fn(), ttl: jest.fn() };
    const middleware = middlewareWith(redis);
    for (const path of ['/', '/v1/health', '/v1/health/ready']) {
      const { req, res, next } = mocks(path);
      await middleware.use(req, res, next);
      expect(next).toHaveBeenCalled();
    }
    expect(redis.incrWithExpiry).not.toHaveBeenCalled();
    // /v1/docs IS a /v1 path, so it is counted like any other.
    const { req, res, next } = mocks('/v1/docs');
    await middleware.use(req, res, next);
    expect(next).toHaveBeenCalled();
    expect(redis.incrWithExpiry).toHaveBeenCalledTimes(1);
  });

  it('counts /v1 requests per IP and passes within the budget', async () => {
    const redis = {
      incrWithExpiry: jest.fn().mockResolvedValue(1),
      ttl: jest.fn(),
    };
    const middleware = middlewareWith(redis);
    const { req, res, next } = mocks('/v1/rooms');
    await middleware.use(req, res, next);
    expect(next).toHaveBeenCalled();
    expect(redis.incrWithExpiry).toHaveBeenCalledWith(
      'ratelimit:ip:9.9.9.9:unauth-1m',
      RATE_LIMITS.ipFlood.windowSeconds,
    );
    expect(res.status).not.toHaveBeenCalled();
  });

  it('answers 429 with Retry-After over the limit', async () => {
    const redis = {
      incrWithExpiry: jest
        .fn()
        .mockResolvedValue(RATE_LIMITS.ipFlood.limit + 1),
      ttl: jest.fn().mockResolvedValue(42),
    };
    const middleware = middlewareWith(redis);
    const { req, res, next } = mocks('/v1/auth/login');
    await middleware.use(req, res, next);
    expect(next).not.toHaveBeenCalled();
    expect(res.setHeader).toHaveBeenCalledWith('Retry-After', '42');
    expect(res.status).toHaveBeenCalledWith(429);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: {
        code: 'RATE_LIMITED',
        message: 'Too many requests from this address. Slow down.',
      },
    });
  });

  it('fails OPEN when Redis is down (reads keep working)', async () => {
    const redis = {
      incrWithExpiry: jest.fn().mockRejectedValue(new Error('ECONNREFUSED')),
      ttl: jest.fn(),
    };
    const middleware = middlewareWith(redis);
    const { req, res, next } = mocks('/v1/rooms/abc');
    await middleware.use(req, res, next);
    expect(next).toHaveBeenCalled();
    expect(res.status).not.toHaveBeenCalled();
  });
});
