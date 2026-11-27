import { randomUUID } from 'node:crypto';
import {
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, IsNull, Repository } from 'typeorm';
import type { RequestUser } from '../common/guards/request-user';
import { ErrorCode } from '../common/errors/error-codes';
import { isUniqueViolationError } from '../common/errors/unique-violation';
import { Profile } from '../users/entities/profile.entity';
import { User } from '../users/entities/user.entity';
import {
  ACCESS_TOKEN_TTL_SECONDS,
  REFRESH_TOKEN_TTL_DAYS,
} from './auth.constants';
import type { AuthResponse, TokenPair } from './dto/auth-response';
import { toUserPublic } from './dto/auth-response';
import type { LoginDto, RefreshDto, RegisterDto } from './dto/auth.dto';
import { EmailVerificationService } from './email-verification.service';
import { AuthSession } from './entities/auth-session.entity';
import { LoginThrottleService } from './login-throttle.service';
import { PasswordHasherService } from './password-hasher.service';
import { TokenService, hashRefreshToken } from './token.service';

/** Discriminated outcome of the refresh transaction (see refresh()). */
type RefreshOutcome =
  | { kind: 'invalid' }
  | { kind: 'reuse'; familyId: string }
  | { kind: 'deleted' }
  | { kind: 'suspended' }
  | {
      kind: 'ok';
      user: User;
      newSessionId: string;
      refreshToken: string;
    };

/**
 * AuthService (FR-02/04/05/09, NFR-13/15/16, plan §7.2).
 *
 * - register: duplicate checks (409 EMAIL_TAKEN / USERNAME_TAKEN —
 *   specific by design, FR-02 carve-out), Argon2id hash, one
 *   transaction creating user + profile, then a session pair and a
 *   verification email. A mailer failure does not fail registration
 *   (the user can resend); it is logged.
 * - login: throttle check → load by email-or-username → Argon2id
 *   verify (dummy verify on unknown users, D-P4-20) → status checks
 *   only AFTER a correct password (§7.3: the 403 cannot enumerate
 *   accounts) → throttle reset → session pair.
 * - refresh: rotation inside a transaction with a row lock; reuse of
 *   a rotated token revokes the whole family (SDD §12.4).
 * - logout: revokes the current session row (sid from the JWT).
 */
@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
    @InjectRepository(Profile) private readonly profiles: Repository<Profile>,
    @InjectRepository(AuthSession)
    private readonly sessions: Repository<AuthSession>,
    private readonly dataSource: DataSource,
    private readonly hasher: PasswordHasherService,
    private readonly tokens: TokenService,
    private readonly throttle: LoginThrottleService,
    private readonly verification: EmailVerificationService,
  ) {}

  async register(dto: RegisterDto): Promise<AuthResponse> {
    const [byEmail, byUsername] = await Promise.all([
      this.users.findOne({ where: { email: dto.email } }),
      this.users.findOne({ where: { username: dto.username } }),
    ]);
    if (byEmail) {
      throw new ConflictException({
        code: ErrorCode.EmailTaken,
        message: 'That email is already registered.',
      });
    }
    if (byUsername) {
      throw new ConflictException({
        code: ErrorCode.UsernameTaken,
        message: 'That username is already taken.',
      });
    }
    const passwordHash = await this.hasher.hash(dto.password);
    const userId = randomUUID();
    // NOTE (Stage 4, H-02): the duplicate pre-checks above are a
    // TOCTOU race — two concurrent registers with the same email or
    // username can both pass them. The loser then hits the CITEXT
    // unique index inside the transaction; that must come back as the
    // same 409 the pre-check produces, never a 500. The re-check
    // inside the catch identifies which key lost the race.
    let created: { user: User; profile: Profile };
    try {
      created = await this.dataSource.transaction(async (manager) => {
        const user = manager.create(User, {
          id: userId,
          email: dto.email,
          username: dto.username,
          passwordHash,
          status: 'active',
        });
        await manager.save(user);
        const profile = manager.create(Profile, {
          userId: user.id,
          displayName: dto.displayName ?? dto.username,
          avatarKey: 'default',
          notificationPreferences: {},
        });
        await manager.save(profile);
        return { user, profile };
      });
    } catch (err) {
      if (isUniqueViolationError(err)) {
        const [byEmail, byUsername] = await Promise.all([
          this.users.findOne({ where: { email: dto.email } }),
          this.users.findOne({ where: { username: dto.username } }),
        ]);
        if (byEmail) {
          throw new ConflictException({
            code: ErrorCode.EmailTaken,
            message: 'That email is already registered.',
          });
        }
        if (byUsername) {
          throw new ConflictException({
            code: ErrorCode.UsernameTaken,
            message: 'That username is already taken.',
          });
        }
      }
      throw err;
    }
    const tokens = await this.createSession(created.user);
    try {
      await this.verification.sendVerificationEmail(created.user);
    } catch (err) {
      // Registration stands; the user can resend verification.
      this.logger.warn(
        `Registration succeeded but verification email failed for ${created.user.email}: ${(err as Error).message}`,
      );
    }
    return { user: toUserPublic(created.user, created.profile), tokens };
  }

  async login(dto: LoginDto, ip: string): Promise<AuthResponse> {
    const identifier = dto.identifier.trim();
    await this.throttle.assertNotThrottled(identifier, ip);
    const user = await this.findByIdentifierWithHash(identifier);
    if (!user) {
      await this.hasher.verifyDummy(dto.password);
      await this.throttle.recordFailure(identifier, ip);
      throw AuthService.invalidCredentials();
    }
    const ok = await this.hasher.verify(user.passwordHash, dto.password);
    if (!ok) {
      await this.throttle.recordFailure(identifier, ip);
      throw AuthService.invalidCredentials();
    }
    // Status is checked only after a correct password (§7.3).
    if (user.deletionRequestedAt) {
      throw new ForbiddenException({
        code: ErrorCode.Forbidden,
        message: 'This account has a pending deletion request.',
      });
    }
    if (user.status !== 'active') {
      throw new ForbiddenException({
        code: ErrorCode.AccountSuspended,
        message: 'This account is suspended.',
      });
    }
    await this.throttle.reset(identifier, ip);
    const profile = await this.profiles.findOne({
      where: { userId: user.id },
    });
    const tokens = await this.createSession(user);
    return { user: toUserPublic(user, profile), tokens };
  }

  async refresh(dto: RefreshDto): Promise<TokenPair> {
    const hash = hashRefreshToken(dto.refreshToken);
    const outcome: RefreshOutcome =
      await this.dataSource.transaction<RefreshOutcome>(
        async (manager): Promise<RefreshOutcome> => {
          const session = await manager.findOne(AuthSession, {
            where: { refreshTokenHash: hash },
            lock: { mode: 'pessimistic_write' },
          });
          // familyId is always set by this service; a null is a corrupt
          // row, treated as invalid rather than trusted.
          if (!session || !session.familyId) return { kind: 'invalid' };
          if (
            session.revokedAt !== null ||
            session.expiresAt.getTime() <= Date.now()
          ) {
            // Revoked/expired token presented again. If the family still
            // has a live session, this token was superseded by rotation —
            // that is reuse: revoke the whole family (SDD §12.4). A
            // logout-revoked token has no live sibling and is just invalid.
            const liveSibling = await manager.findOne(AuthSession, {
              where: { familyId: session.familyId, revokedAt: IsNull() },
            });
            const reuse =
              !!liveSibling && liveSibling.expiresAt.getTime() > Date.now();
            if (reuse) return { kind: 'reuse', familyId: session.familyId };
            return { kind: 'invalid' };
          }
          const user = await manager.findOne(User, {
            where: { id: session.userId },
          });
          if (!user) return { kind: 'invalid' };
          if (user.deletionRequestedAt) return { kind: 'deleted' };
          if (user.status !== 'active') return { kind: 'suspended' };
          // Rotate: revoke the presented session, create its successor in
          // the same family. The row lock serialises concurrent refreshes
          // with the same token — the second sees a revoked row (reuse).
          const { token, hash: newHash } = this.tokens.generateRefreshToken();
          const newSessionId = randomUUID();
          const expiresAt = new Date(
            Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 3600 * 1000,
          );
          await manager.update(
            AuthSession,
            { id: session.id },
            { revokedAt: new Date() },
          );
          await manager.save(AuthSession, {
            id: newSessionId,
            userId: session.userId,
            refreshTokenHash: newHash,
            familyId: session.familyId,
            deviceLabel: session.deviceLabel,
            expiresAt,
          });
          return {
            kind: 'ok',
            user,
            newSessionId,
            refreshToken: token,
          };
        },
      );

    if (outcome.kind === 'reuse') {
      // Family revocation happens outside the transaction above: a
      // throw inside it would have rolled the revocation back.
      await this.sessions.update(
        { familyId: outcome.familyId, revokedAt: IsNull() },
        { revokedAt: new Date() },
      );
      this.logger.warn(
        `Refresh-token reuse detected — revoked family ${outcome.familyId}`,
      );
      throw new UnauthorizedException('Invalid refresh token.');
    }
    if (outcome.kind === 'invalid') {
      throw new UnauthorizedException('Invalid refresh token.');
    }
    if (outcome.kind === 'deleted') {
      throw new ForbiddenException({
        code: ErrorCode.Forbidden,
        message: 'This account has a pending deletion request.',
      });
    }
    if (outcome.kind === 'suspended') {
      throw new ForbiddenException({
        code: ErrorCode.AccountSuspended,
        message: 'This account is suspended.',
      });
    }
    return {
      accessToken: this.tokens.signAccessToken(
        {
          id: outcome.user.id,
          emailVerified: outcome.user.emailVerifiedAt !== null,
        },
        outcome.newSessionId,
      ),
      refreshToken: outcome.refreshToken,
      expiresIn: ACCESS_TOKEN_TTL_SECONDS,
      tokenType: 'Bearer',
    };
  }

  async logout(user: RequestUser): Promise<void> {
    await this.sessions.update(
      { id: user.sessionId },
      { revokedAt: new Date() },
    );
  }

  /** Creates a session row (family_id = its own id) + a token pair. */
  private async createSession(user: User): Promise<TokenPair> {
    const { token: refreshToken, hash } = this.tokens.generateRefreshToken();
    const sessionId = randomUUID();
    const expiresAt = new Date(
      Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 3600 * 1000,
    );
    await this.sessions.save({
      id: sessionId,
      userId: user.id,
      refreshTokenHash: hash,
      familyId: sessionId,
      deviceLabel: null,
      expiresAt,
    });
    return {
      accessToken: this.tokens.signAccessToken(
        { id: user.id, emailVerified: user.emailVerifiedAt !== null },
        sessionId,
      ),
      refreshToken,
      expiresIn: ACCESS_TOKEN_TTL_SECONDS,
      tokenType: 'Bearer',
    };
  }

  /** Email-or-username lookup with the hash selected (NFR-13: the
   * hash is selected only on this dedicated auth path). */
  private async findByIdentifierWithHash(
    identifier: string,
  ): Promise<User | null> {
    const where = identifier.includes('@')
      ? { email: identifier }
      : { username: identifier };
    return this.users.findOne({
      where,
      select: [
        'id',
        'email',
        'username',
        'passwordHash',
        'status',
        'emailVerifiedAt',
        'deletionRequestedAt',
      ],
    });
  }

  private static invalidCredentials(): UnauthorizedException {
    return new UnauthorizedException({
      code: ErrorCode.InvalidCredentials,
      message: 'Email or password is incorrect.',
    });
  }
}
