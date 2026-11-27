import { ApiProperty } from '@nestjs/swagger';
import type { Profile } from '../../users/entities/profile.entity';
import type { User } from '../../users/entities/user.entity';

/** Public user shape — never contains password_hash (NFR-13/21). */
export interface UserPublic {
  id: string;
  email: string;
  username: string;
  displayName: string;
  avatarKey: string;
  emailVerified: boolean;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  /** Access-token lifetime in seconds (900). */
  expiresIn: number;
  tokenType: 'Bearer';
}

export interface AuthResponse {
  user: UserPublic;
  tokens: TokenPair;
}

/** Maps a user + profile row to the public shape. */
export function toUserPublic(user: User, profile: Profile | null): UserPublic {
  return {
    id: user.id,
    email: user.email,
    username: user.username,
    displayName: profile?.displayName ?? user.username,
    avatarKey: profile?.avatarKey ?? 'default',
    emailVerified: user.emailVerifiedAt !== null,
  };
}

/** Swagger response shapes (generated spec, plan §6.7). */
export class UserPublicDto implements UserPublic {
  @ApiProperty()
  id!: string;
  @ApiProperty()
  email!: string;
  @ApiProperty()
  username!: string;
  @ApiProperty()
  displayName!: string;
  @ApiProperty()
  avatarKey!: string;
  @ApiProperty()
  emailVerified!: boolean;
}

export class TokenPairDto implements TokenPair {
  @ApiProperty()
  accessToken!: string;
  @ApiProperty()
  refreshToken!: string;
  @ApiProperty({ example: 900 })
  expiresIn!: number;
  @ApiProperty({ example: 'Bearer' })
  tokenType!: 'Bearer';
}

export class AuthResponseDto implements AuthResponse {
  @ApiProperty({ type: UserPublicDto })
  user!: UserPublicDto;
  @ApiProperty({ type: TokenPairDto })
  tokens!: TokenPairDto;
}
