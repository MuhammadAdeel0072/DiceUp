import { ApiProperty } from '@nestjs/swagger';
import type { NotificationPreferences } from '../entities/profile.entity';

/** Own profile (FR-07/08) — the owner's full view, never a password hash. */
export interface OwnProfile {
  id: string;
  email: string;
  username: string;
  displayName: string;
  avatarKey: string;
  emailVerified: boolean;
  status: string;
  matchesPlayed: number;
  matchesWon: number;
  notificationPreferences: NotificationPreferences;
  createdAt: Date;
}

/** Public profile (FR-63) — only public fields, never email/hash. */
export interface PublicProfile {
  userId: string;
  displayName: string;
  avatarKey: string;
  matchesPlayed: number;
  matchesWon: number;
}

export class OwnProfileDto implements OwnProfile {
  @ApiProperty() id!: string;
  @ApiProperty() email!: string;
  @ApiProperty() username!: string;
  @ApiProperty() displayName!: string;
  @ApiProperty() avatarKey!: string;
  @ApiProperty() emailVerified!: boolean;
  @ApiProperty() status!: string;
  @ApiProperty() matchesPlayed!: number;
  @ApiProperty() matchesWon!: number;
  @ApiProperty() notificationPreferences!: NotificationPreferences;
  @ApiProperty() createdAt!: Date;
}

export class PublicProfileDto implements PublicProfile {
  @ApiProperty() userId!: string;
  @ApiProperty() displayName!: string;
  @ApiProperty() avatarKey!: string;
  @ApiProperty() matchesPlayed!: number;
  @ApiProperty() matchesWon!: number;
}
