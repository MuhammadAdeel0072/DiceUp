/**
 * Socket.IO error shape (plan §9.3 / §6.3). Socket errors mirror the
 * REST envelope exactly — `{ success: false, error: { code, message,
 * details? } }` — so clients switch on `code`, never on message text,
 * on both transports. The envelope is what a client receives:
 * - for a rejected handshake, as `connect_error`'s `err.data`
 *   (see SocketAuthError.toHandshakeError);
 * - for a failed message handler, as the `exception` event payload
 *   (Nest's WsExceptionsHandler emits a WsException's object error
 *   verbatim — see BaseWsExceptionFilter in @nestjs/websockets).
 */
import { WsException } from '@nestjs/websockets';
import { ErrorCode, type ErrorEnvelope } from '../common/errors/error-codes';

/** Build the §6.3 error envelope for a socket error. */
export function socketErrorEnvelope(
  code: ErrorCode,
  message: string,
  details?: Record<string, string[]>,
): ErrorEnvelope {
  return {
    success: false,
    error: {
      code,
      message,
      ...(details ? { details } : {}),
    },
  };
}

/** A WsException carrying the §6.3 envelope (delivered as `exception`). */
export function socketWsException(
  code: ErrorCode,
  message: string,
  details?: Record<string, string[]>,
): WsException {
  return new WsException(socketErrorEnvelope(code, message, details));
}

/**
 * Handshake authentication failure (plan §9.2). Thrown by
 * WsJwtGuard.authenticate(); the Socket.IO adapter middleware converts
 * it into the error passed to `next(err)`.
 *
 * How the client sees it: socket.io's middleware error path
 * (namespace.js, protocol 4 — the path socket.io 4.x clients use)
 * sends the CONNECT_ERROR packet as
 * `{ message: err.message, data: err.data }`, and the client builds
 * `new Error(packet.data.message)` with `err.data = packet.data.data`.
 * So `toHandshakeError()` puts the envelope itself on `error.data`,
 * and an engine.io-v4 client receives `connect_error` with
 * `err.message` (human-readable) and `err.data` (the full envelope,
 * with the machine-readable `code`).
 */
export class SocketAuthError extends Error {
  constructor(
    readonly code: ErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'SocketAuthError';
  }

  toEnvelope(): ErrorEnvelope {
    return socketErrorEnvelope(this.code, this.message);
  }

  toHandshakeError(): Error {
    const error = new Error(this.message);
    // The envelope rides on `error.data`: socket.io sends it as the
    // CONNECT_ERROR packet data, and the client receives it as
    // `err.data` (engine.io v4 clients — socket.io 4.x, including the
    // Flutter socket_io_client — read the code from `err.data`;
    // `err.message` carries the same human-readable message).
    (error as Error & { data: unknown }).data = this.toEnvelope();
    return error;
  }
}
