import type { ExecutionContext } from '@nestjs/common';
import { AccountStatusGuard } from '../../src/common/guards/account-status.guard';
import { EmailVerifiedGuard } from '../../src/common/guards/email-verified.guard';
import type { RequestUser } from '../../src/common/guards/request-user';
import { RolesGuard } from '../../src/common/guards/roles.guard';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY } from '../../src/common/decorators/roles.decorator';

function makeUser(overrides: Partial<RequestUser> = {}): RequestUser {
  return {
    id: 'user-1',
    email: 'ali@example.com',
    username: 'ali_plays',
    role: 'player',
    emailVerified: true,
    status: 'active',
    sessionId: 'session-1',
    deletionRequestedAt: null,
    ...overrides,
  };
}

function makeContext(user?: RequestUser): ExecutionContext {
  return {
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
    getHandler: () => ({}) as never,
    getClass: () => ({}) as never,
  } as unknown as ExecutionContext;
}

describe('AccountStatusGuard (BR-19)', () => {
  const guard = new AccountStatusGuard();

  it('allows active accounts', () => {
    expect(guard.canActivate(makeContext(makeUser()))).toBe(true);
  });

  it('passes through when there is no principal (JwtAuthGuard decides)', () => {
    expect(guard.canActivate(makeContext(undefined))).toBe(true);
  });

  it.each(['suspended', 'blocked'] as const)(
    'denies %s accounts with 403 ACCOUNT_SUSPENDED',
    (status) => {
      try {
        guard.canActivate(makeContext(makeUser({ status })));
        fail('should have thrown');
      } catch (err) {
        const e = err as { status: number; response: { code: string } };
        expect(e.status).toBe(403);
        expect(e.response.code).toBe('ACCOUNT_SUSPENDED');
      }
    },
  );

  it('denies accounts with a pending deletion request', () => {
    try {
      guard.canActivate(
        makeContext(makeUser({ deletionRequestedAt: new Date() })),
      );
      fail('should have thrown');
    } catch (err) {
      const e = err as { status: number; response: { code: string } };
      expect(e.status).toBe(403);
      expect(e.response.code).toBe('FORBIDDEN');
    }
  });
});

describe('EmailVerifiedGuard (FR-03)', () => {
  const guard = new EmailVerifiedGuard();

  it('allows verified users', () => {
    expect(guard.canActivate(makeContext(makeUser()))).toBe(true);
  });

  it('passes through when there is no principal', () => {
    expect(guard.canActivate(makeContext(undefined))).toBe(true);
  });

  it('denies unverified users with 403 EMAIL_NOT_VERIFIED', () => {
    try {
      guard.canActivate(makeContext(makeUser({ emailVerified: false })));
      fail('should have thrown');
    } catch (err) {
      const e = err as { status: number; response: { code: string } };
      expect(e.status).toBe(403);
      expect(e.response.code).toBe('EMAIL_NOT_VERIFIED');
    }
  });
});

describe('RolesGuard (role foundations)', () => {
  function guardWithRoles(roles?: string[]): RolesGuard {
    const reflector = new Reflector();
    jest.spyOn(reflector, 'getAllAndOverride').mockImplementation((key) => {
      if (key === ROLES_KEY) return roles as never;
      return undefined as never;
    });
    return new RolesGuard(reflector);
  }

  it('allows routes with no @Roles metadata', () => {
    expect(guardWithRoles(undefined).canActivate(makeContext(makeUser()))).toBe(
      true,
    );
  });

  it('allows a matching role', () => {
    expect(
      guardWithRoles(['player']).canActivate(makeContext(makeUser())),
    ).toBe(true);
  });

  it('denies a non-matching role with 403 FORBIDDEN', () => {
    try {
      guardWithRoles(['admin']).canActivate(makeContext(makeUser()));
      fail('should have thrown');
    } catch (err) {
      const e = err as { status: number; response: { code: string } };
      expect(e.status).toBe(403);
      expect(e.response.code).toBe('FORBIDDEN');
    }
  });

  it('passes through when there is no principal', () => {
    expect(guardWithRoles(['admin']).canActivate(makeContext(undefined))).toBe(
      true,
    );
  });
});
