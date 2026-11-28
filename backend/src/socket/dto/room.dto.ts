import { ApiProperty } from '@nestjs/swagger';
import {
  IsBoolean,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
} from 'class-validator';

/** `room:join` payload (FR-44): a 6-char code, case-insensitive. */
export class RoomJoinDto {
  @ApiProperty({ example: 'K7Q2XA' })
  @IsString()
  @MaxLength(6)
  @Matches(/^[A-HJ-NP-Z2-9]{6}$/i, {
    message:
      'Room code must be 6 characters: letters and digits, no I, O, 0 or 1.',
  })
  roomCode!: string;
}

/** `room:leave` payload (FR-59). */
export class RoomLeaveDto {
  @ApiProperty({ description: 'Room id (UUID).' })
  @IsUUID()
  roomId!: string;
}

/** `room:ready` payload (FR-46). */
export class RoomReadyDto {
  @ApiProperty({ description: 'Room id (UUID).' })
  @IsUUID()
  roomId!: string;

  @ApiProperty({ example: true })
  @IsBoolean()
  ready!: boolean;
}

/** `match:start` payload (FR-47, host only). */
export class MatchStartDto {
  @ApiProperty({ description: 'Room id (UUID).' })
  @IsUUID()
  roomId!: string;
}
