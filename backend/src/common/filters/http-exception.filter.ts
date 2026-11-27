import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { randomUUID } from 'node:crypto';
import { ErrorCode } from '../errors/error-codes';
import { RateLimitedException } from '../errors/rate-limited.exception';

/**
 * Global exception filter (plan §8.4): the single place that maps every
 * error to the §6.3 envelope. Known HttpExceptions keep status/code;
 * validation failures become 400 VALIDATION_FAILED with per-field details;
 * unknown errors become 500 INTERNAL_ERROR with a correlationId that is
 * logged server-side. No stack trace or secret ever reaches the client.
 */
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();
    // Stage 4, M-04: the correlation id is ALWAYS generated server-side.
    // A client-supplied X-Request-Id must never become the correlation
    // id (log injection / forced collisions). Guards reject before the
    // envelope interceptor runs, so the filter cannot rely on the
    // header having been (re)written by then — generate fresh here.
    const correlationId = randomUUID();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let code = ErrorCode.InternalError;
    let message = 'An unexpected error occurred.';
    let details: Record<string, string[]> | undefined;
    let data: unknown;

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse();
      if (typeof body === 'object' && body !== null) {
        const b = body as Record<string, unknown>;
        // Validation failures carry per-field `details` from the
        // global pipe's exceptionFactory (Stage 4, M-01) — pass them
        // through verbatim. The `_global` fallback covers any 400
        // whose body only has a flat message list.
        if (
          status === HttpStatus.BAD_REQUEST &&
          b.details !== undefined &&
          typeof b.details === 'object' &&
          b.details !== null
        ) {
          code = ErrorCode.ValidationFailed;
          message =
            typeof b.message === 'string' ? b.message : 'Validation failed.';
          details = b.details as Record<string, string[]>;
        } else if (
          status === HttpStatus.BAD_REQUEST &&
          Array.isArray(b.message)
        ) {
          code = ErrorCode.ValidationFailed;
          message = 'Validation failed.';
          details = { _global: (b.message as unknown[]).map(String) };
        } else {
          message =
            typeof b.message === 'string' ? b.message : exception.message;
          if (typeof b.code === 'string') code = b.code as ErrorCode;
          // Plain Nest HttpExceptions carry no `code`; map the status
          // to the §6.3 code instead of defaulting to INTERNAL_ERROR.
          else {
            const statusCodeMap: Record<number, ErrorCode> = {
              [HttpStatus.BAD_REQUEST]: ErrorCode.ValidationFailed,
              [HttpStatus.UNAUTHORIZED]: ErrorCode.Unauthorized,
              [HttpStatus.FORBIDDEN]: ErrorCode.Forbidden,
              [HttpStatus.NOT_FOUND]: ErrorCode.NotFound,
              [HttpStatus.CONFLICT]: ErrorCode.InvalidState,
              [HttpStatus.TOO_MANY_REQUESTS]: ErrorCode.RateLimited,
              [HttpStatus.SERVICE_UNAVAILABLE]: ErrorCode.ServiceUnavailable,
            };
            code = statusCodeMap[status] ?? ErrorCode.InternalError;
          }
          if (b.data !== undefined) data = b.data;
        }
      } else {
        message = exception.message;
      }
      if (status >= 500) {
        // Only a bare 500 is an unexpected internal error. A deliberate
        // 5xx with an explicit code (e.g. 503 SERVICE_UNAVAILABLE from
        // readiness) keeps its code and message.
        if (status === HttpStatus.INTERNAL_SERVER_ERROR) {
          code = ErrorCode.InternalError;
          message = 'An unexpected error occurred.';
        }
      }
    } else {
      // Express body-parser errors (NFR-20): these are not
      // HttpExceptions — they surface here as plain Errors with a
      // `status` and a `type`. Without this branch an oversized body
      // (100 KB limit) came back as a misleading 500.
      const err = exception as { status?: unknown; type?: unknown };
      if (err?.status === HttpStatus.PAYLOAD_TOO_LARGE) {
        status = HttpStatus.PAYLOAD_TOO_LARGE;
        code = ErrorCode.PayloadTooLarge;
        message = 'Request body is too large.';
      } else if (err?.type === 'entity.parse.failed') {
        status = HttpStatus.BAD_REQUEST;
        code = ErrorCode.ValidationFailed;
        message = 'Request body is not valid JSON.';
      }
    }

    this.logger.error(
      `[${correlationId}] ${request.method} ${request.url} -> ${status} ${code}`,
      exception instanceof Error ? exception.stack : String(exception),
    );

    // 429s carry a Retry-After header (plan §6.5). The value comes
    // from RateLimitedException; a plain 429 without one gets no header.
    if (exception instanceof RateLimitedException) {
      response.setHeader('Retry-After', String(exception.retryAfterSeconds));
    }

    response.status(status).json({
      success: false,
      error: {
        code,
        message,
        ...(details ? { details } : {}),
        ...(data !== undefined ? { data } : {}),
        ...(status === HttpStatus.INTERNAL_SERVER_ERROR
          ? { correlationId }
          : {}),
      },
    });
  }
}
