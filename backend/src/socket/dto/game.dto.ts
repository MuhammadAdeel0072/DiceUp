import { ApiProperty } from '@nestjs/swagger';
import {
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Min,
} from 'class-validator';

/**
 * Gameplay socket DTOs (Phase 5, Stage 5; SDD §12.6). Client events
 * express intent only and every mutating intent carries a
 * client-generated UUID `requestId` (FR-53 idempotency): a retried
 * intent with the same `requestId` returns the original result,
 * never a second transition.
 *
 * `tokenId` identifies one token as `"{seat}:{tokenIndex}"`
 * (e.g. `"0:2"` — seat 0's third token). Seats are the join-order
 * seats from `match:started`; token indices are 0–3 within a seat.
 * The server never accepts a position, a dice value, or a winner
 * from a client — those are all computed by the engine.
 */

/** `dice:roll` payload (FR-49): no dice value is ever supplied. */
export class DiceRollDto {
  @ApiProperty({ description: 'Match id (UUID).' })
  @IsUUID()
  matchId!: string;

  @ApiProperty({
    description: 'Client-generated UUID for FR-53 idempotency.',
  })
  @IsUUID()
  requestId!: string;

  /**
   * A client-supplied dice value, if one arrives, is IGNORED (the
   * server rolls with CryptoDiceRoller) and LOGGED (SDD §8.8). The
   * field exists on the DTO only so the value can be observed and
   * logged — the whitelist would otherwise strip it silently.
   */
  @ApiProperty({
    description: 'Ignored when present: the server generates the roll. Logged.',
    required: false,
  })
  @IsOptional()
  @IsInt()
  value?: number;
}

/** `token:move` payload (FR-50). */
export class TokenMoveDto {
  @ApiProperty({ description: 'Match id (UUID).' })
  @IsUUID()
  matchId!: string;

  @ApiProperty({
    description: 'Token id as "{seat}:{tokenIndex}", e.g. "0:2".',
    example: '0:2',
  })
  @IsString()
  @Matches(/^[0-3]:[0-3]$/, {
    message: 'tokenId must be "{seat}:{tokenIndex}" with each in 0..3.',
  })
  tokenId!: string;

  @ApiProperty({
    description: 'Client-generated UUID for FR-53 idempotency.',
  })
  @IsUUID()
  requestId!: string;
}

/** `state:request` payload (FR-57). */
export class StateRequestDto {
  @ApiProperty({ description: 'Match id (UUID).' })
  @IsUUID()
  matchId!: string;

  @ApiProperty({
    description:
      'The last seq the client has applied. The server always answers ' +
      'with a full snapshot; a lastSeq ahead of the server state is ' +
      'rejected as STALE_STATE.',
    example: 4,
  })
  @IsInt()
  @Min(0)
  lastSeq!: number;
}
