import { createHash, randomBytes } from 'node:crypto';
import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ACCESS_TOKEN_TTL_SECONDS } from './auth.constants';
import type { JwtKeys } from './jwt-keys';
import { JWT_KEYS } from './jwt-keys';

/** Claims carried by the access JWT (SDD §12.4). */
export interface AccessTokenPayload {
  sub: string;
  role: 'player';
  email_verified: boolean;
  sid: string;
  iat?: number;
  exp?: number;
  iss?: string;
}

/**
 * TokenService (plan §7.1, NFR-15).
 * - Access tokens: RS256 JWT, 15-min expiry, claims sub / role /
 *   email_verified / sid. Signed with the private key, verified with
 *   the public key (asymmetric — verifiers never hold the signing key).
 * - Refresh tokens: opaque 256-bit random values, stored SHA-256
 *   hashed in auth_sessions, never in plaintext, never logged.
 */
@Injectable()
export class TokenService {
  constructor(
    private readonly jwt: JwtService,
    @Inject(JWT_KEYS) private readonly keys: JwtKeys,
  ) {}

  signAccessToken(
    user: { id: string; emailVerified: boolean },
    sessionId: string,
  ): string {
    return this.jwt.sign(
      {
        sub: user.id,
        role: 'player',
        email_verified: user.emailVerified,
        sid: sessionId,
      },
      {
        privateKey: this.keys.privateKey,
        algorithm: 'RS256',
        expiresIn: ACCESS_TOKEN_TTL_SECONDS,
        issuer: this.keys.issuer,
      },
    );
  }

  /** Verifies signature, algorithm, issuer and expiry. Throws 401. */
  verifyAccessToken(token: string): AccessTokenPayload {
    try {
      return this.jwt.verify<AccessTokenPayload>(token, {
        publicKey: this.keys.publicKey,
        algorithms: ['RS256'],
        issuer: this.keys.issuer,
      });
    } catch {
      throw new UnauthorizedException('Invalid or expired access token.');
    }
  }

  /** A fresh opaque refresh token + its SHA-256 hash for storage. */
  generateRefreshToken(): { token: string; hash: string } {
    const token = randomBytes(32).toString('base64url');
    return { token, hash: hashRefreshToken(token) };
  }
}

/** SHA-256 hash of a refresh token, as stored in auth_sessions. */
export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}
