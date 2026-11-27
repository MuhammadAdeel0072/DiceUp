import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ScheduleModule } from '@nestjs/schedule';
import { TypeOrmModule } from '@nestjs/typeorm';
import type { AppConfig } from '../config/configuration';
import { AccountStatusGuard } from '../common/guards/account-status.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { RateLimitGuard } from '../common/rate-limit/rate-limit.guard';
import { RateLimitModule } from '../common/rate-limit/rate-limit.module';
import { MailerModule } from '../mailer/mailer.module';
import { Profile } from '../users/entities/profile.entity';
import { User } from '../users/entities/user.entity';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { AuthCleanupService } from './cleanup.service';
import { EmailTokenService } from './email-token.service';
import { EmailVerificationService } from './email-verification.service';
import { AuthSession } from './entities/auth-session.entity';
import { EmailToken } from './entities/email-token.entity';
import { buildJwtKeys, JWT_KEYS } from './jwt-keys';
import { LoginThrottleService } from './login-throttle.service';
import { PasswordHasherService } from './password-hasher.service';
import { PasswordResetService } from './password-reset.service';
import { JwtStrategy } from './strategies/jwt.strategy';
import { TokenService } from './token.service';

/**
 * AuthModule (plan §3.2/§7). Player identity end-to-end: register →
 * verify → login → refresh → logout, password recovery, session
 * revocation, purge job.
 *
 * Global guards are registered here in chain order (APP_GUARD):
 * JwtAuthGuard (token + sid session check) → AccountStatusGuard →
 * RolesGuard → RateLimitGuard (needs the user attached by the first).
 * They apply to every route in the app, including Users and Health —
 * public routes opt out explicitly with @Public().
 */
@Module({
  imports: [
    PassportModule.register({ defaultStrategy: 'jwt' }),
    JwtModule.register({}),
    TypeOrmModule.forFeature([User, Profile, AuthSession, EmailToken]),
    MailerModule,
    RateLimitModule,
    ScheduleModule.forRoot(),
  ],
  controllers: [AuthController],
  providers: [
    {
      provide: JWT_KEYS,
      inject: [ConfigService],
      useFactory: (config: ConfigService) =>
        buildJwtKeys(config.getOrThrow<AppConfig>('app')),
    },
    TokenService,
    PasswordHasherService,
    LoginThrottleService,
    EmailTokenService,
    EmailVerificationService,
    PasswordResetService,
    AuthService,
    AuthCleanupService,
    JwtStrategy,
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: AccountStatusGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
    { provide: APP_GUARD, useClass: RateLimitGuard },
  ],
  exports: [
    JWT_KEYS,
    TokenService,
    PasswordHasherService,
    AuthService,
    EmailVerificationService,
    PasswordResetService,
    // Exported for SocketModule: WsJwtGuard reuses the ONE auth path
    // (TokenService + JwtStrategy sid check) for socket auth.
    JwtStrategy,
  ],
})
export class AuthModule {}
