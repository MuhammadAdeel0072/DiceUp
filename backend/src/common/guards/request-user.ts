import type { UserStatus } from '../../users/entities/user.entity';

/**
 * The authenticated principal attached to the request by JwtStrategy
 * (via JwtAuthGuard). This is the ONLY user shape guards and
 * controllers may trust — never a client-supplied id or role.
 * `role` is always 'player' in Phase 4 (no roles table; the single
 * admin role lives in Phase 7's admin_accounts, plan §4.1).
 */
export interface RequestUser {
  id: string;
  email: string;
  username: string;
  role: 'player';
  emailVerified: boolean;
  status: UserStatus;
  /** The auth_sessions row id (JWT `sid` claim). */
  sessionId: string;
  deletionRequestedAt: Date | null;
}
