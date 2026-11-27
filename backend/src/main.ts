import { BadRequestException, Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { Logger as PinoLogger } from 'nestjs-pino';
import { AppModule } from './app.module';
import { ErrorCode } from './common/errors/error-codes';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { LoggingInterceptor } from './common/interceptors/logging.interceptor';
import { ResponseEnvelopeInterceptor } from './common/interceptors/response-envelope.interceptor';
import { flattenValidationErrors } from './common/validation/flatten-validation-errors';
import { validateProductionConfig } from './config/config.validation';
import { createRedisSocketAdapter } from './socket/socket-io.adapter';
import type { AppConfig } from './config/configuration';

/**
 * Bootstrap (plan §8.1/§8.2/§6.7/§6.8).
 * - Fail-fast in production when mandatory config is missing (§8.1).
 * - Global prefix /v1; global ValidationPipe (whitelist: strip unknown
 *   fields, plan §8.2 D-P4-14); global envelope + exception filter +
 *   logging interceptor; helmet (HSTS + nosniff, D-P4-17); CORS from
 *   config allow-list only, never a wildcard; JSON body limit 100 KB
 *   (NFR-20). Swagger at /v1/docs in non-production only (D-P4-03).
 * - TLS is a deployment property (NFR-14): the app binds plain HTTP
 *   only on localhost/dev and refuses production without TLS/proxy
 *   config — production requires CORS_ORIGINS + JWT keys (fail-fast)
 *   and is expected to run behind TLS termination.
 * - Socket.IO (plan §9.2): the Redis adapter + handshake-auth
 *   middleware are installed via createRedisSocketAdapter (same
 *   function the e2e test-app factory uses — the two must stay in
 *   sync). Socket.IO runs over the same HTTP(S) server as REST; no
 *   separate port, no plain-WS listener.
 */
async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  app.useLogger(app.get(PinoLogger));
  app.useWebSocketAdapter(createRedisSocketAdapter(app));
  const config = app.get(ConfigService);
  const appConfig = config.get<AppConfig>('app');
  if (!appConfig) throw new Error('Application configuration failed to load');
  validateProductionConfig(appConfig);

  const logger = new Logger('Bootstrap');
  app.setGlobalPrefix('v1');
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: false,
      transform: true,
      // Stage 4, M-01: per-field `details` in the §6.3 envelope. The
      // default factory only carries a flat message list, which the
      // filter used to collapse into a single `_global` entry — the
      // client could not tell which field failed. Keep in sync with
      // test/integration/test-app.factory.ts.
      exceptionFactory: (errors) =>
        new BadRequestException({
          code: ErrorCode.ValidationFailed,
          message: 'Validation failed.',
          details: flattenValidationErrors(errors),
        }),
    }),
  );
  app.useGlobalFilters(new HttpExceptionFilter());
  app.useGlobalInterceptors(
    new ResponseEnvelopeInterceptor(),
    new LoggingInterceptor(),
  );
  app.use(helmet());
  app.enableCors({
    origin: appConfig.corsOrigins.length > 0 ? appConfig.corsOrigins : false,
    credentials: false,
  });
  // Trust proxy (Stage 4, H-03): without this, req.ip is the reverse
  // proxy's address for every client and the per-IP rate limits /
  // login throttle collapse into one shared bucket. The value comes
  // from validated config (TRUST_PROXY, default: trust nobody).
  app.getHttpAdapter().getInstance().set('trust proxy', appConfig.trustProxy);
  // JSON body limit 100 KB (NFR-20 / SDD §13.4) is the platform-express
  // default; no second parser is added (a duplicate would double-parse).

  if (appConfig.nodeEnv !== 'production') {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('DiceUp API')
      .setDescription(
        'DiceUp online backend — Phase 4 foundation (SDD Stage 2 subset)',
      )
      .setVersion('0.1.0')
      .addBearerAuth()
      .build();
    const document = SwaggerModule.createDocument(app, swaggerConfig);
    // Global prefix does NOT apply to the Swagger path in Nest 11, so
    // the versioned path is spelled out here to land at /v1/docs.
    SwaggerModule.setup('v1/docs', app, document);
  }

  app.enableShutdownHooks();
  await app.listen(appConfig.port, '127.0.0.1');
  logger.log(
    `DiceUp backend listening on 127.0.0.1:${appConfig.port} (env=${appConfig.nodeEnv}, ruleset=${appConfig.rulesetVersion})`,
  );
}

bootstrap().catch((err: unknown) => {
  // Named error, no stack trace to a client (there is no client yet —
  // this is process stderr at boot). Exit non-zero: fail-fast (§8.1).
  console.error(`Fatal: backend failed to start: ${(err as Error).message}`);
  process.exit(1);
});
