import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';

/**
 * Required roles for a route, checked by RolesGuard. Phase 4 has one
 * role: 'player' (carried in the JWT; no roles table, plan §4.1).
 * The guard allows routes with no @Roles() metadata — it is the
 * foundation Phase 7's admin roles will plug into.
 */
export const Roles = (...roles: string[]): MethodDecorator & ClassDecorator =>
  SetMetadata(ROLES_KEY, roles);
