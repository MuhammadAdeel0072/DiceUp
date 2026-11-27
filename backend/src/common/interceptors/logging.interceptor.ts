import {
  CallHandler,
  ExecutionContext,
  Injectable,
  Logger,
  NestInterceptor,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { Request } from 'express';

/**
 * Logging interceptor (plan §6.8 / NFR-37): logs every request once —
 * method, path, status, latency ms, requestId. Bodies and Authorization
 * headers are never logged. Secrets are additionally stripped by the
 * pino redaction list in logger.module.ts.
 */
@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger(LoggingInterceptor.name);

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const ctx = context.switchToHttp();
    const request = ctx.getRequest<Request>();
    const started = Date.now();
    const requestId = request.headers['x-request-id'] as string | undefined;
    return next.handle().pipe(
      tap({
        next: () => {
          const response = ctx.getResponse<{ statusCode: number }>();
          this.logger.log(
            `[${requestId ?? '-'}] ${request.method} ${request.url} ${response.statusCode} ${Date.now() - started}ms`,
          );
        },
        error: (err: unknown) => {
          this.logger.error(
            `[${requestId ?? '-'}] ${request.method} ${request.url} error ${Date.now() - started}ms`,
            err instanceof Error ? err.stack : String(err),
          );
        },
      }),
    );
  }
}
