import {
  Controller,
  Get,
  HttpCode,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../common/decorators/public.decorator';
import { HealthService } from './health.service';
import { ErrorCode } from '../common/errors/error-codes';

/**
 * Health endpoints (plan §6.6, [P4 choice] Terminus-style, hand-rolled).
 *
 * GET /v1/health — liveness only. 200 `{ status: "ok" }` if the Node
 * process can answer. No dependency checks, no version strings, no secrets.
 * GET /v1/health/ready — readiness. 200 only if BOTH PostgreSQL and
 * Redis are up; 503 otherwise, naming which dependency is down plus
 * per-check latency. No credentials, connection strings, stack traces,
 * or internal hostnames in either response.
 */
@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(private readonly health: HealthService) {}

  @Public()
  @Get()
  @HttpCode(HttpStatus.OK)
  liveness(): { status: string } {
    return { status: 'ok' };
  }

  @Public()
  @Get('ready')
  async readiness() {
    const result = await this.health.checkReadiness();
    if (result.status !== 'ok') {
      // Error envelope (§6.3) via the global filter; the per-dependency
      // detail travels in error.data (see HttpExceptionFilter).
      throw new HttpException(
        {
          code: ErrorCode.ServiceUnavailable,
          message: 'A required dependency is unavailable.',
          data: result,
        },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    return result;
  }
}
