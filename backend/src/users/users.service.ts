import {
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';
import { AuthSession } from '../auth/entities/auth-session.entity';
import { PasswordHasherService } from '../auth/password-hasher.service';
import { ErrorCode } from '../common/errors/error-codes';
import type { NotificationPreferences } from './entities/profile.entity';
import { Profile } from './entities/profile.entity';
import { User } from './entities/user.entity';
import type {
  ChangePasswordDto,
  UpdatePreferencesDto,
  UpdateProfileDto,
} from './dto/users.dto';
import type { OwnProfile, PublicProfile } from './dto/profile-response';

/**
 * UsersService (FR-07/08/10/63).
 * Ownership is structural: every method takes the id from the JWT
 * (`me` routes take no id at all), never from a client-supplied
 * field — there is nothing to tamper with (NFR-17, SDD §13.2).
 * Password data is never in a response shape (DTO allow-list, NFR-21).
 */
@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
    @InjectRepository(Profile) private readonly profiles: Repository<Profile>,
    private readonly dataSource: DataSource,
    private readonly hasher: PasswordHasherService,
  ) {}

  async getMe(userId: string): Promise<OwnProfile> {
    const { user, profile } = await this.loadOwn(userId);
    return this.toOwnProfile(user, profile);
  }

  async updateMe(userId: string, dto: UpdateProfileDto): Promise<OwnProfile> {
    const { user, profile } = await this.loadOwn(userId);
    if (dto.displayName !== undefined) profile.displayName = dto.displayName;
    if (dto.avatarKey !== undefined) profile.avatarKey = dto.avatarKey;
    await this.profiles.save(profile);
    return this.toOwnProfile(user, profile);
  }

  /**
   * Change password: old password required + verified; on success the
   * new hash is stored and ALL sessions are revoked in one transaction
   * (FR-08) — every device must log in again with the new password.
   */
  async changePassword(
    userId: string,
    dto: ChangePasswordDto,
  ): Promise<{ message: string }> {
    const user = await this.users.findOne({
      where: { id: userId },
      select: ['id', 'passwordHash'],
    });
    if (!user) throw new NotFoundException('User not found.');
    const ok = await this.hasher.verify(user.passwordHash, dto.oldPassword);
    if (!ok) {
      throw new UnauthorizedException({
        code: ErrorCode.InvalidCredentials,
        message: 'Current password is incorrect.',
      });
    }
    const passwordHash = await this.hasher.hash(dto.newPassword);
    await this.dataSource.transaction(async (manager) => {
      await manager.update(User, { id: userId }, { passwordHash });
      await manager.update(AuthSession, { userId }, { revokedAt: new Date() });
    });
    return { message: 'Password changed. All sessions have been signed out.' };
  }

  async updatePreferences(
    userId: string,
    dto: UpdatePreferencesDto,
  ): Promise<{ notificationPreferences: NotificationPreferences }> {
    const { profile } = await this.loadOwn(userId);
    const merged: NotificationPreferences = {
      ...profile.notificationPreferences,
      ...(dto.emailNotifications !== undefined
        ? { emailNotifications: dto.emailNotifications }
        : {}),
      ...(dto.pushNotifications !== undefined
        ? { pushNotifications: dto.pushNotifications }
        : {}),
    };
    profile.notificationPreferences = merged;
    await this.profiles.save(profile);
    return { notificationPreferences: merged };
  }

  /** Public profile — only public fields; unknown id → 404 (FR-63). */
  async getPublicProfile(id: string): Promise<PublicProfile> {
    const profile = await this.profiles.findOne({ where: { userId: id } });
    if (!profile) throw new NotFoundException('Profile not found.');
    return {
      userId: profile.userId,
      displayName: profile.displayName,
      avatarKey: profile.avatarKey,
      matchesPlayed: profile.matchesPlayed,
      matchesWon: profile.matchesWon,
    };
  }

  /**
   * FR-10 (partial): records the deletion request and revokes all
   * sessions immediately. NO personal data is deleted or anonymised
   * by this path — full anonymisation awaits OPEN-5/OD-08.
   */
  async requestDeletion(
    userId: string,
  ): Promise<{ deletionRequestedAt: Date }> {
    const requestedAt = new Date();
    await this.dataSource.transaction(async (manager) => {
      await manager.update(
        User,
        { id: userId },
        { deletionRequestedAt: requestedAt },
      );
      await manager.update(AuthSession, { userId }, { revokedAt: new Date() });
    });
    return { deletionRequestedAt: requestedAt };
  }

  private async loadOwn(
    userId: string,
  ): Promise<{ user: User; profile: Profile }> {
    const user = await this.users.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found.');
    const profile = await this.profiles.findOne({ where: { userId } });
    if (!profile) throw new NotFoundException('Profile not found.');
    return { user, profile };
  }

  private toOwnProfile(user: User, profile: Profile): OwnProfile {
    return {
      id: user.id,
      email: user.email,
      username: user.username,
      displayName: profile.displayName,
      avatarKey: profile.avatarKey,
      emailVerified: user.emailVerifiedAt !== null,
      status: user.status,
      matchesPlayed: profile.matchesPlayed,
      matchesWon: profile.matchesWon,
      notificationPreferences: profile.notificationPreferences ?? {},
      createdAt: user.createdAt,
    };
  }
}
