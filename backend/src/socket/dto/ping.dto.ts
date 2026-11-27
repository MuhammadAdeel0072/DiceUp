import { ApiProperty } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';

/**
 * `ping` payload (foundation-only connectivity probe — NOT a game
 * event). The client-generated UUID `requestId` follows the FR-53
 * idempotency convention (plan §9.3): every client mutating intent
 * carries one, and the server echoes it in `pong` so the client can
 * match the reply. Unknown fields are stripped by WsValidationPipe.
 */
export class PingDto {
  @ApiProperty({
    description: 'Client-generated UUID, echoed back in pong.',
    example: '3f7a2c10-9c4e-4b1a-8e2d-1a2b3c4d5e6f',
  })
  @IsUUID()
  requestId!: string;
}

/** `pong` reply shape (server → client). */
export interface PongPayload {
  requestId: string;
  serverTime: string;
}

/** `connected` lifecycle event shape (server → client, on connect). */
export interface ConnectedPayload {
  userId: string;
  socketId: string;
  connectedAt: string;
}
