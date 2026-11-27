import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { appConfig } from './config/configuration';
import { configValidationSchema } from './config/config.validation';
import { LoggerModule } from './common/logging/logger.module';
import { DatabaseModule } from './database/database.module';
import { RedisModule } from './redis/redis.module';
import { HealthModule } from './health/health.module';
import { AuthModule } from './auth/auth.module';
import { MailerModule } from './mailer/mailer.module';
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
 * and the adapter middleware authenticates the handshake. No game,
 * matchmaking, friends, leaderboard, notification or admin code
 * exists in this stage.
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
    SocketModule,
  ],
})
export class AppModule {}
