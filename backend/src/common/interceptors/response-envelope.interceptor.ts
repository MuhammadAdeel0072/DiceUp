import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import { Request, Response } from 'express';

/**
 * Response envelope interceptor (plan §6.3): wraps every successful
 * response as `{ success: true, data: <payload> }`. Also generates the
 * per-request `X-Request-Id` (returned to the client so it can quote it
 * to support, NFR-37).
 *
 * NOTE (Stage 4, M-04): the id is ALWAYS generated server-side. A
 * client-supplied `X-Request-Id` header is never adopted: it would let
 * a caller force log/correlation collisions, inject arbitrary text
 * into log lines, and correlate unrelated requests under one id.
 */
@Injectable()
export class ResponseEnvelopeInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const ctx = context.switchToHttp();
    const request = ctx.getRequest<Request>();
    const response = ctx.getResponse<Response>();
    const requestId = randomUUID();
    request.headers['x-request-id'] = requestId;
    response.setHeader('X-Request-Id', requestId);
    return next.handle().pipe(map((data) => ({ success: true, data })));
  }
}
