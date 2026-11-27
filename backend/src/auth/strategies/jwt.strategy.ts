import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { InjectRepository } from '@nestjs/typeorm';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { Repository } from 'typeorm';
import type { RequestUser } from '../../common/guards/request-user';
import type { AccessTokenPayload } from '../token.service';
import { AuthSession } from '../entities/auth-session.entity';
import { User } from '../../users/entities/user.entity';
import type { JwtKeys } from '../jwt-keys';
import { JWT_KEYS } from '../jwt-keys';

/**
 * JWT strategy (passport-jwt, [P4 choice] D-P4-06). RS256, issuer
 * checked, Bearer token from the Authorization header.
 *
 * validate() is where the load-bearing `sid` revocation check lives
 * (plan §7.1): the JWT's `sid` must match a live auth_sessions row
 * (not revoked, not expired) on EVERY authenticated request. The
 * 15-min access token alone cannot be recalled — this lookup is what
 * makes logout / password-change / suspension take effect before
 * expiry. It costs one indexed lookup per request, accepted
 * deliberately; it must not be optimised away (plan §12 item 7).
 * The returned object becomes `request.user` — the only principal
 * guards and controllers may trust.
 */
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy, 'jwt') {
  constructor(
    @Inject(JWT_KEYS) keys: JwtKeys,
    @InjectRepository(AuthSession)
    private readonly sessions: Repository<AuthSession>,
    @InjectRepository(User)
    private readonly users: Repository<User>,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: keys.publicKey,
      algorithms: ['RS256'],
      issuer: keys.issuer,
    });
  }

  async validate(payload: AccessTokenPayload): Promise<RequestUser> {
    if (
      !payload ||
      typeof payload.sub !== 'string' ||
      typeof payload.sid !== 'string' ||
      payload.role !== 'player'
    ) {
      throw new UnauthorizedException('Invalid access token.');
    }
    const session = await this.sessions.findOne({
      where: { id: payload.sid },
    });
    if (
      !session ||
      session.userId !== payload.sub ||
      session.revokedAt !== null ||
      session.expiresAt.getTime() <= Date.now()
    ) {
      throw new UnauthorizedException('Session is no longer valid.');
    }
    const user = await this.users.findOne({ where: { id: payload.sub } });
    if (!user) {
      throw new UnauthorizedException('Invalid access token.');
    }
    return {
      id: user.id,
      email: user.email,
      username: user.username,
      role: 'player',
      emailVerified: user.emailVerifiedAt !== null,
      status: user.status,
      sessionId: session.id,
      deletionRequestedAt: user.deletionRequestedAt,
    };
  }
}
