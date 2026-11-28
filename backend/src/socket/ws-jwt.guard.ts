import {
  CanActivate,
  ExecutionContext,
  Inject,
  Injectable,
  Logger,
  Optional,
  UnauthorizedException,
} from '@nestjs/common';
import { WsException } from '@nestjs/websockets';
import type { Socket } from 'socket.io';
import { ErrorCode } from '../common/errors/error-codes';
import type { RequestUser } from '../common/guards/request-user';
import { JwtStrategy } from '../auth/strategies/jwt.strategy';
import { TokenService } from '../auth/token.service';
import { MatchService } from '../match/match.service';
import { type SocketClientData } from './socket.constants';
import { SocketAuthError, socketWsException } from './socket-error';

/** A socket.io socket with the typed Phase 4 client data. */
export type GameSocket = Socket & { data: SocketClientData };

/**
 * WsJwtGuard (plan §9.2, CI-02, NFR-17) — the ONE auth path, shared
 * with REST. It reuses TokenService.verifyAccessToken (RS256 signature,
 * issuer, expiry) and JwtStrategy.validate — including the load-bearing
 * `sid` revocation check against auth_sessions — so a logged-out or
 * revoked session fails socket auth immediately, exactly as it fails
 * REST. The account-status and email-verified rules are the same ones
 * the HTTP AccountStatusGuard / EmailVerifiedGuard enforce, with the
 * same codes and messages, applied here because those guards are
 * HTTP-context only (`switchToHttp()` is undefined on a WS context)
 * and global APP_GUARDs do not apply to gateways.
 *
 * Two enforcement points, one `authenticate()`:
 * 1. Handshake — the Socket.IO adapter middleware calls
 *    `authenticate(socket.handshake.auth)` before the connection is
 *    accepted; a failure rejects the handshake (`connect_error`) and
 *    the socket never connects. This is the primary enforcement:
 *    Nest guards do NOT run on `handleConnection` (the controller
 *    subscribes the lifecycle hook directly), so a guard alone could
 *    not refuse a connection.
 * 2. Per message — `canActivate()` (wired explicitly on the gateway
 *    with @UseGuards, since APP_GUARDs do not cover gateways)
 *    re-validates the stored handshake token on every event, so a
 *    session revoked mid-connection fails the next event immediately
 *    instead of living until the socket drops. The refreshed
 *    principal replaces `client.data.user`.
 */
@Injectable()
export class WsJwtGuard implements CanActivate {
  private readonly logger = new Logger(WsJwtGuard.name);

  constructor(
    private readonly tokens: TokenService,
    private readonly strategy: JwtStrategy,
    /**
     * Stage 6 (FR-54 heartbeat): the per-message re-validation is
     * also the heartbeat — every authenticated message refreshes
     * the player's presence. Optional so unit tests can keep
     * constructing the guard with two arguments; without it no
     * presence is written (pre-Stage 6 behaviour).
     */
    @Optional() @Inject(MatchService) private readonly matches?: MatchService,
  ) {}

  /**
   * Authenticate one handshake (or one stored token) and return the
   * principal. Throws SocketAuthError with the §6.3 code on any auth
   * failure; unexpected errors (e.g. the database being unreachable
   * for the `sid` lookup) propagate so the caller can map them to a
   * 503 instead of misreporting them as bad credentials.
   */
  async authenticate(auth: unknown): Promise<RequestUser> {
    const token = extractHandshakeToken(auth);
    if (!token) {
      throw new SocketAuthError(
        ErrorCode.Unauthorized,
        'Authentication token is required.',
      );
    }
    let user: RequestUser;
    try {
      const payload = this.tokens.verifyAccessToken(token);
      user = await this.strategy.validate(payload);
    } catch (err) {
      if (err instanceof UnauthorizedException) {
        // Token invalid/expired, or the session row is gone/revoked/
        // expired — the message stays generic on purpose (no leak
        // about which of those it was).
        throw new SocketAuthError(
          ErrorCode.Unauthorized,
          'Invalid or expired access token.',
        );
      }
      throw err;
    }
    // Same rules, codes and messages as the HTTP guards (plan §7.3):
    // a deletion request, a suspension, or an unverified email refuses
    // online access — including socket access.
    if (user.deletionRequestedAt) {
      throw new SocketAuthError(
        ErrorCode.Forbidden,
        'This account has a pending deletion request.',
      );
    }
    if (user.status === 'suspended' || user.status === 'blocked') {
      throw new SocketAuthError(
        ErrorCode.AccountSuspended,
        'This account is suspended.',
      );
    }
    if (!user.emailVerified) {
      throw new SocketAuthError(
        ErrorCode.EmailNotVerified,
        'Verify your email to use online features.',
      );
    }
    return user;
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const client = context.switchToWs().getClient<GameSocket>();
    const token =
      client.data.authToken ?? extractHandshakeToken(client.handshake.auth);
    if (!token) {
      throw socketWsException(
        ErrorCode.Unauthorized,
        'Authentication token is required.',
      );
    }
    try {
      const user = await this.authenticate({ token });
      client.data.user = user;
      client.data.authToken = token;
      // Stage 6 heartbeat: an authenticated message proves the
      // player is live — refresh presence (best-effort, never a
      // failed message).
      if (this.matches) void this.matches.touchPresence(user.id);
      return true;
    } catch (err) {
      if (err instanceof SocketAuthError) {
        throw new WsException(err.toEnvelope());
      }
      this.logger.error(
        `Socket auth failed unexpectedly (socket=${client.id}): ${(err as Error).message}`,
      );
      throw socketWsException(
        ErrorCode.ServiceUnavailable,
        'Authentication is temporarily unavailable.',
      );
    }
  }
}

/** The handshake `auth` object is `{ token }` (plan §9.2). */
export function extractHandshakeToken(auth: unknown): string | undefined {
  if (!auth || typeof auth !== 'object') return undefined;
  const token = (auth as Record<string, unknown>).token;
  return typeof token === 'string' && token.length > 0 ? token : undefined;
}

/** The optional client app version from the handshake (logged, not enforced). */
export function extractHandshakeAppVersion(auth: unknown): string | undefined {
  if (!auth || typeof auth !== 'object') return undefined;
  const version = (auth as Record<string, unknown>).appVersion;
  return typeof version === 'string' && version.length > 0
    ? version
    : undefined;
}
