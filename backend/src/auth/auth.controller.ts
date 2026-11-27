import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Ip,
  Post,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Public } from '../common/decorators/public.decorator';
import type { RequestUser } from '../common/guards/request-user';
import { RateLimit } from '../common/rate-limit/rate-limit.decorator';
import { RATE_LIMITS } from './auth.constants';
import { AuthService } from './auth.service';
import type { TokenPair } from './dto/auth-response';
import { AuthResponseDto, TokenPairDto } from './dto/auth-response';
import {
  ForgotPasswordDto,
  LoginDto,
  RefreshDto,
  RegisterDto,
  ResendVerificationDto,
  ResetPasswordDto,
  VerifyEmailDto,
} from './dto/auth.dto';
import { EmailVerificationService } from './email-verification.service';
import { PasswordResetService } from './password-reset.service';

/**
 * AuthController (plan §6.2). Public endpoints are an explicit
 * allow-list (@Public()); logout requires a valid access token.
 * Rate limits (§6.5) ride on @RateLimit() — login instead uses the
 * failure-based NFR-16 throttle inside AuthService.
 */
@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly verification: EmailVerificationService,
    private readonly passwordReset: PasswordResetService,
  ) {}

  @Public()
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  @RateLimit({ ...RATE_LIMITS.register, keyBy: 'ip' })
  @ApiOperation({ summary: 'Register a new player (FR-02)' })
  @ApiResponse({ status: 201, type: AuthResponseDto })
  @ApiResponse({ status: 409, description: 'EMAIL_TAKEN / USERNAME_TAKEN' })
  register(@Body() dto: RegisterDto) {
    return this.auth.register(dto);
  }

  @Public()
  @Post('login')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Log in with email or username (FR-04)' })
  @ApiResponse({ status: 200, type: AuthResponseDto })
  @ApiResponse({ status: 401, description: 'INVALID_CREDENTIALS (generic)' })
  @ApiResponse({ status: 429, description: 'RATE_LIMITED (NFR-16)' })
  login(@Body() dto: LoginDto, @Ip() ip: string) {
    return this.auth.login(dto, ip);
  }

  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @RateLimit({ ...RATE_LIMITS.refresh, keyBy: 'ip' })
  @ApiOperation({ summary: 'Rotate a refresh token (NFR-15)' })
  @ApiResponse({ status: 200, type: TokenPairDto })
  @ApiResponse({ status: 401, description: 'Invalid / reused refresh token' })
  refresh(@Body() dto: RefreshDto): Promise<TokenPair> {
    return this.auth.refresh(dto);
  }

  @Post('logout')
  @HttpCode(HttpStatus.OK)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Log out — revoke the current session (FR-05)' })
  @ApiResponse({ status: 200, description: 'Session revoked' })
  async logout(@CurrentUser() user: RequestUser) {
    await this.auth.logout(user);
    return { loggedOut: true };
  }

  @Public()
  @Post('verify-email')
  @HttpCode(HttpStatus.OK)
  @RateLimit({ ...RATE_LIMITS.tokenEndpoint, keyBy: 'ip' })
  @ApiOperation({ summary: 'Verify email with a single-use code (FR-03)' })
  @ApiResponse({ status: 200, description: 'Email verified' })
  @ApiResponse({ status: 409, description: 'TOKEN_ALREADY_USED' })
  @ApiResponse({ status: 410, description: 'TOKEN_EXPIRED' })
  verifyEmail(@Body() dto: VerifyEmailDto) {
    return this.verification.verify(dto.token);
  }

  @Public()
  @Post('verify-email/resend')
  @HttpCode(HttpStatus.OK)
  @RateLimit({ ...RATE_LIMITS.tokenEndpoint, keyBy: 'ip' })
  @ApiOperation({ summary: 'Resend the verification email (neutral response)' })
  @ApiResponse({ status: 200, description: 'Neutral — no leak' })
  async resendVerification(@Body() dto: ResendVerificationDto) {
    await this.verification.resend(dto.email);
    return {
      message:
        'If an unverified account exists for that email, a new verification email has been sent.',
    };
  }

  @Public()
  @Post('forgot-password')
  @HttpCode(HttpStatus.OK)
  @RateLimit({ ...RATE_LIMITS.forgotPassword, keyBy: 'email' })
  @ApiOperation({ summary: 'Request a password reset (FR-06, neutral 200)' })
  @ApiResponse({ status: 200, description: 'Neutral — no leak' })
  async forgotPassword(@Body() dto: ForgotPasswordDto) {
    await this.passwordReset.request(dto.email);
    return {
      message:
        'If an account exists for that email, a password-reset email has been sent.',
    };
  }

  @Public()
  @Post('reset-password')
  @HttpCode(HttpStatus.OK)
  @RateLimit({ ...RATE_LIMITS.tokenEndpoint, keyBy: 'ip' })
  @ApiOperation({ summary: 'Reset password with a single-use code (FR-06)' })
  @ApiResponse({ status: 200, description: 'Password reset' })
  @ApiResponse({ status: 409, description: 'TOKEN_ALREADY_USED' })
  @ApiResponse({ status: 410, description: 'TOKEN_EXPIRED' })
  async resetPassword(@Body() dto: ResetPasswordDto) {
    await this.passwordReset.reset(dto.token, dto.newPassword);
    return { message: 'Your password has been reset.' };
  }
}
