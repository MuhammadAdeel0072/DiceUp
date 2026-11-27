import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import {
  IsEmail,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import { USERNAME_PATTERN } from '../auth.constants';

export class RegisterDto {
  @ApiProperty({ example: 'ali@example.com' })
  @IsEmail()
  @MaxLength(254)
  @Transform(({ value }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  email!: string;

  @ApiProperty({
    example: 'ali_plays',
    description: '3–30 chars: letters, digits, dot, underscore, hyphen.',
  })
  @IsString()
  @Matches(USERNAME_PATTERN, {
    message:
      'Username must be 3–30 characters: letters, digits, dot, underscore or hyphen.',
  })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  username!: string;

  @ApiProperty({ minLength: 8, maxLength: 128 })
  @IsString()
  @MinLength(8, { message: 'Password must be at least 8 characters.' })
  @MaxLength(128)
  password!: string;

  @ApiProperty({ required: false, maxLength: 50 })
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(50)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  displayName?: string;
}

export class LoginDto {
  @ApiProperty({
    example: 'ali@example.com',
    description: 'Email or username.',
  })
  @IsString()
  @MinLength(1)
  @MaxLength(254)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  identifier!: string;

  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(128)
  password!: string;
}

export class RefreshDto {
  @ApiProperty({ description: 'Opaque refresh token from login/register.' })
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  refreshToken!: string;
}

export class VerifyEmailDto {
  @ApiProperty({ description: 'Verification code from the email.' })
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  token!: string;
}

export class ResendVerificationDto {
  @ApiProperty({ example: 'ali@example.com' })
  @IsEmail()
  @MaxLength(254)
  @Transform(({ value }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  email!: string;
}

export class ForgotPasswordDto {
  @ApiProperty({ example: 'ali@example.com' })
  @IsEmail()
  @MaxLength(254)
  @Transform(({ value }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  email!: string;
}

export class ResetPasswordDto {
  @ApiProperty({ description: 'Reset code from the email.' })
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  token!: string;

  @ApiProperty({ minLength: 8, maxLength: 128 })
  @IsString()
  @MinLength(8, { message: 'Password must be at least 8 characters.' })
  @MaxLength(128)
  newPassword!: string;
}
