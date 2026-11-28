import { Controller, Get, HttpCode, HttpStatus, Post } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import type { RequestUser } from '../common/guards/request-user';
import { MatchmakingService } from './matchmaking.service';

/**
 * MatchmakingController (Phase 5, Stage 3; FR-45).
 *
 * All routes sit behind the global JWT guard — no @Public() anywhere.
 * Group size is 4 (OD-05, C-13); arrival order only (G-2). Queue
 * entries never expire on their own (G-6) — cancel with POST /leave.
 * When a join completes a group of 4, the response carries the
 * created room (`matched: true`); the other three members learn via
 * `matchmaking:matched` on their sockets or `GET /status`.
 */
@ApiTags('matchmaking')
@ApiBearerAuth()
@Controller('matchmaking')
export class MatchmakingController {
  constructor(private readonly matchmaking: MatchmakingService) {}

  @Post('join')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Join the matchmaking queue (FR-45)' })
  @ApiResponse({ status: 200, description: 'Queued, or matched with a room' })
  @ApiResponse({
    status: 409,
    description: 'ALREADY_IN_MATCHMAKING / ALREADY_IN_ROOM / ALREADY_IN_MATCH',
  })
  @ApiResponse({
    status: 503,
    description: 'MATCHMAKING_UNAVAILABLE (Redis down)',
  })
  join(@CurrentUser() user: RequestUser) {
    return this.matchmaking.join(user.id);
  }

  @Post('leave')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Leave the matchmaking queue (cancel)' })
  @ApiResponse({
    status: 200,
    description: '{left: true} when an entry was removed',
  })
  leave(@CurrentUser() user: RequestUser) {
    return this.matchmaking.leave(user.id);
  }

  @Get('status')
  @ApiOperation({ summary: 'Queue position / matched room / idle' })
  @ApiResponse({ status: 200, description: 'queued | matched | idle' })
  status(@CurrentUser() user: RequestUser) {
    return this.matchmaking.status(user.id);
  }
}
