import {
  SOCKET_CONNECTION_WINDOW_SECONDS,
  SOCKET_CONNECTIONS_PER_MINUTE_PER_IP,
  SOCKET_CONNECTIONS_PER_MINUTE_PER_USER,
} from '../../src/socket/socket.constants';
import { SocketConnectionRateLimitService } from '../../src/socket/socket-connection-rate-limit.service';

/**
 * Socket connection rate limits (L-02): per IP before auth, per
 * user after auth, with an in-process fallback when Redis is down.
 */
describe('SocketConnectionRateLimitService', () => {
  function serviceWith(redis: unknown): SocketConnectionRateLimitService {
    return new SocketConnectionRateLimitService(redis as never);
  }

  it('allows connections within the per-IP budget and keys by IP + 1m window', async () => {
    const redis = { incrWithExpiry: jest.fn().mockResolvedValue(1) };
    const service = serviceWith(redis);
    await expect(service.checkIp('9.9.9.9')).resolves.toEqual({
      allowed: true,
    });
    expect(redis.incrWithExpiry).toHaveBeenCalledWith(
      'ratelimit:socket-conn-ip:9.9.9.9:1m',
      SOCKET_CONNECTION_WINDOW_SECONDS,
    );
  });

  it(`rejects the ${SOCKET_CONNECTIONS_PER_MINUTE_PER_IP + 1}th connection from one IP`, async () => {
    const redis = {
      incrWithExpiry: jest
        .fn()
        .mockResolvedValue(SOCKET_CONNECTIONS_PER_MINUTE_PER_IP + 1),
    };
    const service = serviceWith(redis);
    await expect(service.checkIp('9.9.9.9')).resolves.toEqual({
      allowed: false,
    });
  });

  it(`allows exactly ${SOCKET_CONNECTIONS_PER_MINUTE_PER_USER} connections per user`, async () => {
    const redis = {
      incrWithExpiry: jest
        .fn()
        .mockResolvedValue(SOCKET_CONNECTIONS_PER_MINUTE_PER_USER),
    };
    const service = serviceWith(redis);
    await expect(service.checkUser('user-1')).resolves.toEqual({
      allowed: true,
    });
    expect(redis.incrWithExpiry).toHaveBeenCalledWith(
      'ratelimit:socket-conn-user:user-1:1m',
      SOCKET_CONNECTION_WINDOW_SECONDS,
    );
  });

  it('falls back to a local bucket when Redis is down (same budgets)', async () => {
    const redis = {
      incrWithExpiry: jest.fn().mockRejectedValue(new Error('ECONNREFUSED')),
    };
    const service = serviceWith(redis);
    for (let i = 0; i < SOCKET_CONNECTIONS_PER_MINUTE_PER_USER; i += 1) {
      await expect(service.checkUser('user-1')).resolves.toEqual({
        allowed: true,
      });
    }
    await expect(service.checkUser('user-1')).resolves.toEqual({
      allowed: false,
    });
    // A different user still has a full budget.
    await expect(service.checkUser('user-2')).resolves.toEqual({
      allowed: true,
    });
  });
});
