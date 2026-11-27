import {
  BadRequestException,
  INestApplication,
  ValidationPipe,
} from '@nestjs/common';
import helmet from 'helmet';
import { ErrorCode } from '../../src/common/errors/error-codes';
import { HttpExceptionFilter } from '../../src/common/filters/http-exception.filter';
import { LoggingInterceptor } from '../../src/common/interceptors/logging.interceptor';
import { ResponseEnvelopeInterceptor } from '../../src/common/interceptors/response-envelope.interceptor';
import { flattenValidationErrors } from '../../src/common/validation/flatten-validation-errors';
import { parseTrustProxy } from '../../src/config/configuration';
import { createRedisSocketAdapter } from '../../src/socket/socket-io.adapter';

/**
 * Test-app factory: mirrors main.ts bootstrap (global prefix /v1,
 * ValidationPipe whitelist, envelope + filter + logging, helmet,
 * Redis Socket.IO adapter with handshake auth) without binding a
 * port or loading Swagger. Any change here must be mirrored in
 * src/main.ts — the two are intentionally kept in sync.
 */
export function createApp(app: INestApplication): INestApplication {
  app.setGlobalPrefix('v1');
  app
    .getHttpAdapter()
    .getInstance()
    .set('trust proxy', parseTrustProxy(process.env.TRUST_PROXY));
  app.useWebSocketAdapter(createRedisSocketAdapter(app));
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: false,
      transform: true,
      // Mirror of src/main.ts (Stage 4, M-01): per-field details.
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
  app.enableShutdownHooks();
  return app;
}
