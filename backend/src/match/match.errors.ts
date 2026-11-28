import { HttpException, HttpStatus } from '@nestjs/common';
import { ErrorCode } from '../common/errors/error-codes';

/**
 * A rejected game intent (Phase 5, Stage 5; FR-50/53).
 *
 * Thrown by MatchService when an intent cannot be applied: the
 * match does not exist, the actor is not a player, it is not their
 * turn, the move is illegal, the match has ended, or the request is
 * stale. State is unchanged in every case.
 *
 * It extends HttpException so the two transports share one error:
 * REST renders the §6.3 envelope with the HTTP status through the
 * global filter, while the gateway catches it and emits
 * `action:rejected { matchId, requestId?, code, message }` to the
 * requesting socket only.
 */
export class GameRejectedError extends HttpException {
  constructor(
    readonly code: ErrorCode,
    message: string,
    status: HttpStatus = HttpStatus.CONFLICT,
  ) {
    super({ code, message }, status);
    this.name = 'GameRejectedError';
    // HttpException stores the object response; the human message
    // must also be on `.message` for the gateway's action:rejected.
    this.message = message;
  }

  static matchNotFound(matchId: string): GameRejectedError {
    return new GameRejectedError(
      ErrorCode.MatchNotFound,
      `Match ${matchId} was not found.`,
      HttpStatus.NOT_FOUND,
    );
  }

  static notMatchPlayer(): GameRejectedError {
    return new GameRejectedError(
      ErrorCode.NotMatchPlayer,
      'You are not a player in this match.',
      HttpStatus.FORBIDDEN,
    );
  }

  static notYourTurn(): GameRejectedError {
    return new GameRejectedError(ErrorCode.NotYourTurn, 'It is not your turn.');
  }

  static illegalMove(message: string): GameRejectedError {
    return new GameRejectedError(ErrorCode.IllegalMove, message);
  }

  static invalidState(message: string): GameRejectedError {
    return new GameRejectedError(ErrorCode.InvalidState, message);
  }

  static matchFinished(): GameRejectedError {
    return new GameRejectedError(
      ErrorCode.MatchFinished,
      'This match has ended.',
    );
  }

  static staleState(): GameRejectedError {
    return new GameRejectedError(
      ErrorCode.StaleState,
      'Your lastSeq is ahead of the server state. Request a fresh snapshot.',
    );
  }

  static matchUnavailable(message: string): GameRejectedError {
    return new GameRejectedError(
      ErrorCode.MatchUnavailable,
      message,
      HttpStatus.SERVICE_UNAVAILABLE,
    );
  }
}
