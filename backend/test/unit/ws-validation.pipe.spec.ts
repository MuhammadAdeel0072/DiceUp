import { WsException } from '@nestjs/websockets';
import { ErrorCode } from '../../src/common/errors/error-codes';
import { PingDto } from '../../src/socket/dto/ping.dto';
import {
  flattenValidationErrors,
  WsValidationPipe,
} from '../../src/socket/ws-validation.pipe';

const REQUEST_ID = '3f7a2c10-9c4e-4b1a-8e2d-1a2b3c4d5e6f';

function envelopeOf(err: unknown): {
  success: boolean;
  error: { code: string; message: string; details?: Record<string, string[]> };
} {
  expect(err).toBeInstanceOf(WsException);
  return (err as WsException).getError() as ReturnType<typeof envelopeOf>;
}

describe('WsValidationPipe (socket event validation)', () => {
  const pipe = new WsValidationPipe();
  const meta = { type: 'body', metatype: PingDto, data: undefined } as never;

  it('accepts a valid ping payload and returns a PingDto', async () => {
    const out = await pipe.transform({ requestId: REQUEST_ID }, meta);
    expect(out).toBeInstanceOf(PingDto);
    expect((out as PingDto).requestId).toBe(REQUEST_ID);
  });

  it('strips unknown fields (whitelist, same rule as REST)', async () => {
    const out = await pipe.transform(
      { requestId: REQUEST_ID, injected: 'nope', roomId: 'x' },
      meta,
    );
    expect(out).toBeInstanceOf(PingDto);
    expect(out as Record<string, unknown>).not.toHaveProperty('injected');
    expect(out as Record<string, unknown>).not.toHaveProperty('roomId');
  });

  it('rejects a missing requestId with VALIDATION_FAILED + field details', async () => {
    const err = await pipe.transform({}, meta).catch((e: unknown) => e);
    const body = envelopeOf(err);
    expect(body.success).toBe(false);
    expect(body.error.code).toBe(ErrorCode.ValidationFailed);
    expect(body.error.details?.requestId).toBeDefined();
  });

  it('rejects a non-UUID requestId with VALIDATION_FAILED', async () => {
    const err = await pipe
      .transform({ requestId: 'not-a-uuid' }, meta)
      .catch((e: unknown) => e);
    const body = envelopeOf(err);
    expect(body.error.code).toBe(ErrorCode.ValidationFailed);
    expect(body.error.details?.requestId).toBeDefined();
  });

  it('rejects a malformed (non-object) payload instead of crashing', async () => {
    for (const bad of ['just-a-string', 42, null, ['x']]) {
      const err = await pipe
        .transform(bad as never, meta)
        .catch((e: unknown) => e);
      const body = envelopeOf(err);
      expect(body.error.code).toBe(ErrorCode.ValidationFailed);
    }
  });

  it('rejects an oversized payload with PAYLOAD_TOO_LARGE', async () => {
    const err = await pipe
      .transform({ requestId: REQUEST_ID, pad: 'x'.repeat(11 * 1024) }, meta)
      .catch((e: unknown) => e);
    const body = envelopeOf(err);
    expect(body.error.code).toBe(ErrorCode.PayloadTooLarge);
  });

  it('skips non-body params (e.g. the @ConnectedSocket() socket)', async () => {
    // The pipe runs for every handler param. A Socket is circular —
    // JSON.stringify on it throws — so the size check must only run
    // for body params; otherwise every valid event would fail with a
    // spurious VALIDATION_FAILED (found by the e2e ping test).
    const circular: Record<string, unknown> = {};
    circular.self = circular;
    const customMeta = {
      type: 'custom',
      metatype: Object,
      data: undefined,
    } as never;
    await expect(pipe.transform(circular, customMeta)).resolves.toBe(circular);
  });
});

describe('flattenValidationErrors', () => {
  it('flattens nested children with dotted paths', () => {
    const out = flattenValidationErrors([
      {
        property: 'outer',
        children: [
          {
            property: 'inner',
            constraints: { isString: 'inner must be a string' },
          },
        ],
      } as never,
      {
        property: 'requestId',
        constraints: { isUuid: 'requestId must be a UUID' },
      } as never,
    ]);
    expect(out).toEqual({
      'outer.inner': ['inner must be a string'],
      requestId: ['requestId must be a UUID'],
    });
  });
});
