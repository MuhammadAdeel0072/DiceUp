import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import {
  ForgotPasswordDto,
  LoginDto,
  RefreshDto,
  RegisterDto,
  ResetPasswordDto,
  VerifyEmailDto,
} from '../../src/auth/dto/auth.dto';
import {
  ChangePasswordDto,
  UpdatePreferencesDto,
  UpdateProfileDto,
} from '../../src/users/dto/users.dto';

async function errorsOf<T extends object>(
  cls: new () => T,
  plain: Record<string, unknown>,
): Promise<string[]> {
  const instance = plainToInstance(cls, plain);
  const errors = await validate(instance);
  return errors.flatMap((e) => Object.values(e.constraints ?? {}));
}

async function errorPropsOf<T extends object>(
  cls: new () => T,
  plain: Record<string, unknown>,
): Promise<string[]> {
  const instance = plainToInstance(cls, plain);
  const errors = await validate(instance);
  return errors.map((e) => e.property).sort();
}

describe('DTO validation matrix (plan §10.2)', () => {
  describe('RegisterDto', () => {
    const valid = {
      email: 'ali@example.com',
      username: 'ali_plays',
      password: 'CorrectHorse!9',
    };

    it('accepts a valid registration', async () => {
      expect(await errorsOf(RegisterDto, valid)).toEqual([]);
    });

    it('lower-cases and trims the email', async () => {
      const dto = plainToInstance(RegisterDto, {
        ...valid,
        email: '  ALI@Example.COM ',
      });
      expect(dto.email).toBe('ali@example.com');
    });

    it('rejects a bad email, bad username, and weak password', async () => {
      expect(await errorsOf(RegisterDto, { ...valid, email: 'nope' })).toEqual(
        expect.arrayContaining([expect.stringMatching(/email/i)]),
      );
      expect(
        await errorsOf(RegisterDto, { ...valid, username: 'a!' }),
      ).toHaveLength(1);
      expect(
        await errorsOf(RegisterDto, { ...valid, username: 'ab' }),
      ).toHaveLength(1);
      expect(
        await errorsOf(RegisterDto, { ...valid, password: 'short' }),
      ).toHaveLength(1);
    });

    it('rejects missing required fields', async () => {
      expect(await errorPropsOf(RegisterDto, {})).toEqual([
        'email',
        'password',
        'username',
      ]);
    });

    it('rejects a display name over 50 chars', async () => {
      expect(
        await errorsOf(RegisterDto, {
          ...valid,
          displayName: 'x'.repeat(51),
        }),
      ).toHaveLength(1);
    });
  });

  describe('LoginDto', () => {
    it('accepts email or username identifiers', async () => {
      expect(
        await errorsOf(LoginDto, {
          identifier: 'ali@example.com',
          password: 'x',
        }),
      ).toEqual([]);
      expect(
        await errorsOf(LoginDto, { identifier: 'ali_plays', password: 'x' }),
      ).toEqual([]);
    });

    it('rejects empty identifier/password', async () => {
      expect(
        await errorsOf(LoginDto, { identifier: '', password: '' }),
      ).toHaveLength(2);
    });
  });

  describe('token DTOs', () => {
    it('requires a token for verify/reset/refresh', async () => {
      expect(await errorPropsOf(VerifyEmailDto, {})).toEqual(['token']);
      expect(await errorPropsOf(RefreshDto, {})).toEqual(['refreshToken']);
      expect(await errorPropsOf(ResetPasswordDto, { token: 't' })).toEqual([
        'newPassword',
      ]);
      expect(
        await errorsOf(ResetPasswordDto, {
          token: 't',
          newPassword: 'short',
        }),
      ).toHaveLength(1);
    });

    it('requires a valid email for forgot-password', async () => {
      expect(await errorsOf(ForgotPasswordDto, { email: 'nope' })).toHaveLength(
        1,
      );
    });
  });

  describe('Users DTOs', () => {
    it('UpdateProfileDto: valid patch, bad avatar, long display name', async () => {
      expect(
        await errorsOf(UpdateProfileDto, {
          displayName: 'Ali',
          avatarKey: 'gold',
        }),
      ).toEqual([]);
      expect(await errorsOf(UpdateProfileDto, {})).toEqual([]);
      expect(
        await errorsOf(UpdateProfileDto, { avatarKey: 'not-a-key' }),
      ).toHaveLength(1);
      expect(
        await errorsOf(UpdateProfileDto, { displayName: 'x'.repeat(51) }),
      ).toHaveLength(1);
    });

    it('ChangePasswordDto: weak new password rejected', async () => {
      expect(
        await errorsOf(ChangePasswordDto, {
          oldPassword: 'old-password',
          newPassword: 'short',
        }),
      ).toHaveLength(1);
      expect(
        await errorsOf(ChangePasswordDto, {
          oldPassword: 'old-password',
          newPassword: 'NewPassword1',
        }),
      ).toEqual([]);
    });

    it('UpdatePreferencesDto: booleans only', async () => {
      expect(
        await errorsOf(UpdatePreferencesDto, {
          emailNotifications: true,
          pushNotifications: false,
        }),
      ).toEqual([]);
      expect(
        await errorsOf(UpdatePreferencesDto, { emailNotifications: 'yes' }),
      ).toHaveLength(1);
    });
  });
});
