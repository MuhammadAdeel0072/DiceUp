import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsInt, IsString, Matches, Max, MaxLength, Min } from 'class-validator';
import { normalizeRoomCode } from '../room-code';

/** POST /rooms body (FR-43): the host chooses the limit, 2–4. */
export class CreateRoomDto {
  @ApiProperty({
    example: 4,
    description: 'Player limit for the room (2–4).',
  })
  @IsInt()
  @Min(2)
  @Max(4)
  maxPlayers!: number;
}

/** POST /rooms/join body (FR-44): a 6-char code, case-insensitive. */
export class JoinRoomDto {
  @ApiProperty({ example: 'K7Q2XA' })
  @IsString()
  @MaxLength(6)
  @Matches(/^[A-HJ-NP-Z2-9]{6}$/i, {
    message:
      'Room code must be 6 characters: letters and digits, no I, O, 0 or 1.',
  })
  @Transform(({ value }) =>
    typeof value === 'string' ? normalizeRoomCode(value) : value,
  )
  code!: string;
}
