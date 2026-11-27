import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';

/**
 * Marks a route as public (no JWT required). Public routes are an
 * explicit allow-list (NFR-17, deny-by-default): /auth/* public
 * endpoints, /health, /health/ready. Everything else requires a
 * valid access token via the global JwtAuthGuard.
 */
export const Public = (): MethodDecorator & ClassDecorator =>
  SetMetadata(IS_PUBLIC_KEY, true);
