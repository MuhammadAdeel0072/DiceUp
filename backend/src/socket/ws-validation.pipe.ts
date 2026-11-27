import {
  ArgumentMetadata,
  ValidationPipe,
  type ValidationError,
} from '@nestjs/common';
import { WsException } from '@nestjs/websockets';
import { ErrorCode } from '../common/errors/error-codes';
import { flattenValidationErrors } from '../common/validation/flatten-validation-errors';
import { SOCKET_MAX_EVENT_BYTES } from './socket.constants';
import { socketErrorEnvelope } from './socket-error';

/** Re-exported for existing import sites (ws-validation.pipe.spec). */
export { flattenValidationErrors } from '../common/validation/flatten-validation-errors';

/**
 * WsValidationPipe — the ValidationPipe equivalent for socket payloads
 * (plan §9.2). Same rules as the REST global pipe (whitelist: strip
 * unknown fields, transform to the DTO), but a failure throws a
 * WsException carrying the §6.3 envelope instead of an HTTP 400, so
 * the client receives a `VALIDATION_FAILED` `exception` event with
 * per-field `details` — and the gateway never crashes on a malformed
 * payload. Applied at the gateway class level with @UsePipes.
 *
 * The 10 KB per-event limit (SDD §13.4) is enforced here, on the RAW
 * payload, before the whitelist strips unknown fields — a check after
 * stripping could never trigger, because stripping shrinks the
 * payload. `maxHttpBufferSize` on the server only bounds HTTP
 * (polling handshake) traffic, not WebSocket frames, so this is the
 * real enforcement point for WS traffic.
 */
export class WsValidationPipe extends ValidationPipe {
  constructor() {
    super({
      whitelist: true,
      forbidNonWhitelisted: false,
      transform: true,
      exceptionFactory: (errors: ValidationError[]) =>
        new WsException(
          socketErrorEnvelope(
            ErrorCode.ValidationFailed,
            'Validation failed.',
            flattenValidationErrors(errors),
          ),
        ),
    });
  }

  override async transform(
    value: unknown,
    metadata: ArgumentMetadata,
  ): Promise<unknown> {
    // Only the message BODY is a client payload. The pipe is also
    // invoked for the other handler params — notably
    // @ConnectedSocket(), whose value is the server-side Socket.
    // JSON.stringify on a Socket throws (circular references), which
    // used to surface as a spurious VALIDATION_FAILED on every valid
    // event; and a socket must never be validated as a DTO. So the
    // size check runs for body params only, and a value that cannot
    // be stringified is not a client payload at all (nothing arriving
    // over the wire can be cyclic — socket.io could not have encoded
    // it), so it is left for `super.transform` to skip as usual.
    if (metadata.type === 'body') {
      let size: number;
      try {
        size = JSON.stringify(value)?.length ?? 0;
      } catch {
        return super.transform(value, metadata);
      }
      if (size > SOCKET_MAX_EVENT_BYTES) {
        throw new WsException(
          socketErrorEnvelope(
            ErrorCode.PayloadTooLarge,
            'Socket event payload is too large.',
          ),
        );
      }
    }
    return super.transform(value, metadata);
  }
}
