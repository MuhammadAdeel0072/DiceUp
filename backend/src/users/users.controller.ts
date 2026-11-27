import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { EmailVerifiedGuard } from '../common/guards/email-verified.guard';
import type { RequestUser } from '../common/guards/request-user';
import { OwnProfileDto, PublicProfileDto } from './dto/profile-response';
import {
  ChangePasswordDto,
  UpdatePreferencesDto,
  UpdateProfileDto,
} from './dto/users.dto';
import { UsersService } from './users.service';

/**
 * UsersController (plan §6.2, FR-07/08/10/63).
 * All routes require an authenticated, email-verified player
 * (global JwtAuthGuard + AccountStatusGuard + this controller's
 * EmailVerifiedGuard + @Roles('player')). No route takes a user id
 * from the client except GET /users/{id}/profile, which returns
 * public fields only.
 */
@ApiTags('users')
@ApiBearerAuth()
@UseGuards(EmailVerifiedGuard)
@Roles('player')
@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get('me')
  @ApiOperation({ summary: 'Own profile (FR-07)' })
  @ApiResponse({ status: 200, type: OwnProfileDto })
  getMe(@CurrentUser() user: RequestUser) {
    return this.users.getMe(user.id);
  }

  @Patch('me')
  @ApiOperation({ summary: 'Update own display name / avatar (FR-07)' })
  @ApiResponse({ status: 200, type: OwnProfileDto })
  updateMe(@CurrentUser() user: RequestUser, @Body() dto: UpdateProfileDto) {
    return this.users.updateMe(user.id, dto);
  }

  @Patch('me/password')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Change password; revokes all sessions (FR-08)' })
  @ApiResponse({ status: 200, description: 'Password changed' })
  @ApiResponse({ status: 401, description: 'Current password is incorrect' })
  changePassword(
    @CurrentUser() user: RequestUser,
    @Body() dto: ChangePasswordDto,
  ) {
    return this.users.changePassword(user.id, dto);
  }

  @Patch('me/preferences')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Update notification preferences (FR-08)' })
  @ApiResponse({ status: 200, description: 'Preferences saved' })
  updatePreferences(
    @CurrentUser() user: RequestUser,
    @Body() dto: UpdatePreferencesDto,
  ) {
    return this.users.updatePreferences(user.id, dto);
  }

  @Get(':id/profile')
  @ApiOperation({ summary: 'Public profile of another player (FR-63)' })
  @ApiResponse({ status: 200, type: PublicProfileDto })
  @ApiResponse({ status: 404, description: 'Profile not found' })
  getPublicProfile(@Param('id', ParseUUIDPipe) id: string) {
    return this.users.getPublicProfile(id);
  }

  @Delete('me')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary:
      'Request account deletion — marker + revoke sessions (FR-10, partial)',
  })
  @ApiResponse({ status: 200, description: 'Deletion requested' })
  requestDeletion(@CurrentUser() user: RequestUser) {
    return this.users.requestDeletion(user.id);
  }
}
