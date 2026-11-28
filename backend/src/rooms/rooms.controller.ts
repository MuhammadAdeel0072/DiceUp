import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Body,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import type { RequestUser } from '../common/guards/request-user';
import { CreateRoomDto, JoinRoomDto } from './dto/rooms.dto';
import { RoomsService } from './rooms.service';

/**
 * RoomsController (Phase 5, Stage 3; FR-43/44/59).
 *
 * All routes sit behind the global JWT guard — no @Public() anywhere.
 * Validation errors are 400 VALIDATION_FAILED (global pipe); room
 * errors carry their §6.3 codes (ROOM_NOT_FOUND / ROOM_FULL /
 * ROOM_STARTED / ALREADY_IN_ROOM / ALREADY_IN_MATCH / NOT_ROOM_MEMBER).
 * Readiness and start are socket-only (`room:ready`, `match:start` on
 * /game) — there is no REST ready/start, so the lobby has one
 * authority for live state.
 */
@ApiTags('rooms')
@ApiBearerAuth()
@Controller('rooms')
export class RoomsController {
  constructor(private readonly rooms: RoomsService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a room (FR-43)' })
  @ApiResponse({ status: 201, description: 'Room created, caller is host' })
  @ApiResponse({
    status: 409,
    description: 'ALREADY_IN_ROOM / ALREADY_IN_MATCH',
  })
  createRoom(@CurrentUser() user: RequestUser, @Body() dto: CreateRoomDto) {
    return this.rooms.createRoom(user.id, dto.maxPlayers);
  }

  @Post('join')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Join an open room by code (FR-44)' })
  @ApiResponse({ status: 200, description: 'Joined (idempotent for members)' })
  @ApiResponse({ status: 404, description: 'ROOM_NOT_FOUND' })
  @ApiResponse({ status: 409, description: 'ROOM_FULL / ROOM_STARTED' })
  joinRoom(@CurrentUser() user: RequestUser, @Body() dto: JoinRoomDto) {
    return this.rooms.joinByCode(user.id, dto.code);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get a room (members only)' })
  @ApiResponse({ status: 200, description: 'Room with members' })
  @ApiResponse({ status: 403, description: 'NOT_ROOM_MEMBER' })
  @ApiResponse({ status: 404, description: 'ROOM_NOT_FOUND' })
  getRoom(
    @CurrentUser() user: RequestUser,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.rooms.getRoomViewForMember(id, user.id);
  }

  @Post(':id/leave')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Leave a room (FR-59)' })
  @ApiResponse({
    status: 200,
    description: 'Left; host transferred or room closed',
  })
  @ApiResponse({ status: 403, description: 'NOT_ROOM_MEMBER' })
  @ApiResponse({ status: 409, description: 'INVALID_STATE (match started)' })
  leaveRoom(
    @CurrentUser() user: RequestUser,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.rooms.leaveRoom(user.id, id);
  }
}
