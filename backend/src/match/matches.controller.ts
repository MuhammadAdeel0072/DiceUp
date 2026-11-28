import {
  Controller,
  DefaultValuePipe,
  Get,
  HttpCode,
  HttpStatus,
  NotFoundException,
  Param,
  ParseIntPipe,
  ParseUUIDPipe,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ErrorCode } from '../common/errors/error-codes';
import type { RequestUser } from '../common/guards/request-user';
import { MatchService } from './match.service';

/**
 * MatchesController (Phase 5, Stage 5; FR-57/58).
 *
 * Read-only lifecycle API for players of a match: the match view,
 * the authoritative snapshot, and the ordered move log. Every route
 * is player-only — a non-player gets 403 NOT_MATCH_PLAYER (the
 * rooms precedent), an unknown match 404 MATCH_NOT_FOUND. There is
 * deliberately no write endpoint here: results are written only by
 * the socket game flow in one atomic transaction (FR-58, BR-17),
 * never by a client or an admin.
 *
 * All routes sit behind the global JWT guard — no @Public() anywhere.
 */
@ApiTags('matches')
@ApiBearerAuth()
@Controller('matches')
export class MatchesController {
  constructor(private readonly matches: MatchService) {}

  @Get('active')
  @ApiOperation({ summary: 'The caller’s in-progress match, if any' })
  getActiveMatch(@CurrentUser() user: RequestUser) {
    return this.matches.getActiveMatch(user.id).then((match) => {
      if (!match) {
        throw new NotFoundException({
          code: ErrorCode.MatchNotFound,
          message: 'You have no match in progress.',
        });
      }
      return match;
    });
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get a match (players only)' })
  getMatch(
    @CurrentUser() user: RequestUser,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.matches.getMatchView(id, user.id);
  }

  @Get(':id/state')
  @ApiOperation({ summary: 'Full authoritative snapshot (FR-57)' })
  getMatchState(
    @CurrentUser() user: RequestUser,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.matches.getMatchState(id, user.id);
  }

  @Get(':id/events')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Ordered move log from a seq (FR-58)' })
  listEvents(
    @CurrentUser() user: RequestUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Query('fromSeq', new DefaultValuePipe(1), ParseIntPipe) fromSeq: number,
    @Query('limit', new DefaultValuePipe(200), ParseIntPipe) limit: number,
  ) {
    const safeLimit = Math.min(Math.max(limit, 1), 500);
    const safeFrom = Math.max(fromSeq, 1);
    return this.matches.listEvents(id, user.id, safeFrom, safeLimit);
  }
}
