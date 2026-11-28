import {
  MiddlewareConsumer,
  Module,
  NestModule,
  RequestMethod,
} from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { appConfig } from './config/configuration';
import { configValidationSchema } from './config/config.validation';
import { LoggerModule } from './common/logging/logger.module';
import { UnauthenticatedRateLimitMiddleware } from './common/rate-limit/unauthenticated-rate-limit.middleware';
import { DatabaseModule } from './database/database.module';
import { RedisModule } from './redis/redis.module';
import { HealthModule } from './health/health.module';
import { AuthModule } from './auth/auth.module';
import { MailerModule } from './mailer/mailer.module';
import { MatchmakingModule } from './matchmaking/matchmaking.module';
import { MatchModule } from './match/match.module';
import { RoomsModule } from './rooms/rooms.module';
import { SocketModule } from './socket/socket.module';
import { UsersModule } from './users/users.module';

/**
 * AppModule (plan §3.2). Stage 2b adds Auth, Users and Mailer; the
 * global guards (JwtAuthGuard, AccountStatusGuard, RolesGuard,
 * RateLimitGuard) are registered as APP_GUARDs in AuthModule and
 * apply to every route — public routes opt out with @Public().
 * Socket.IO gateway is Stage 2c (SocketModule): namespace /game,
 * handshake auth via WsJwtGuard, Redis adapter. Global APP_GUARDs do
 * NOT apply to gateways — the gateway wires WsJwtGuard explicitly,
 * and the adapter middleware authenticates the handshake.
 *
 * Stage 5 adds MatchModule (server-authoritative gameplay) and the
 * L-01 per-IP flood-bound middleware (registered in `configure`
 * below, so it also applies in the e2e test-app factory, which
 * boots this module).
 */
@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [appConfig],
      validationSchema: configValidationSchema,
      validationOptions: { abortEarly: false, allowUnknown: true },
    }),
    LoggerModule,
    DatabaseModule,
    RedisModule,
    HealthModule,
    MailerModule,
    AuthModule,
    UsersModule,
    RoomsModule,
    MatchmakingModule,
    MatchModule,
    SocketModule,
  ],
  providers: [UnauthenticatedRateLimitMiddleware],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    // L-01: the flood bound runs before the guard chain (a guard
    // cannot bound unauthenticated traffic — JwtAuthGuard 401s
    // first). The middleware itself skips non-/v1 paths and health,
    // so the route pattern here is intentionally broad.
    consumer
      .apply(UnauthenticatedRateLimitMiddleware)
      .forRoutes({ path: '*', method: RequestMethod.ALL });
  }
}
