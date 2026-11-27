import type { ValidationError } from '@nestjs/common';

/**
 * class-validator errors → `{ field: [messages] }` (nested flattened).
 * Shared by the REST global ValidationPipe (via main.ts /
 * test-app.factory.ts exceptionFactory) and WsValidationPipe so both
 * transports report per-field `details` in the §6.3 envelope (Stage 4,
 * M-01: the HTTP filter used to collapse every validation failure
 * into a single `_global` list, losing which field failed).
 */
export function flattenValidationErrors(
  errors: ValidationError[],
  prefix = '',
): Record<string, string[]> {
  const details: Record<string, string[]> = {};
  for (const error of errors) {
    const field = prefix ? `${prefix}.${error.property}` : error.property;
    if (error.constraints) {
      details[field] = Object.values(error.constraints);
    }
    if (error.children && error.children.length > 0) {
      Object.assign(details, flattenValidationErrors(error.children, field));
    }
  }
  return details;
}
