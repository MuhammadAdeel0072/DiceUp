import { AuthCleanupService } from '../../src/auth/cleanup.service';

function mockRepo(affected: number) {
  const execute = jest.fn().mockResolvedValue({ affected });
  const where = jest.fn().mockReturnThis();
  const del = jest.fn().mockReturnThis();
  const builder = { delete: del, where, execute };
  return { repo: { createQueryBuilder: () => builder } as never, execute };
}

describe('AuthCleanupService (plan §4.5 purge job)', () => {
  it('deletes expired sessions and used/expired email tokens, logging counts', async () => {
    const sessions = mockRepo(3);
    const tokens = mockRepo(5);
    const service = new AuthCleanupService(sessions.repo, tokens.repo);
    const logSpy = jest
      .spyOn(service['logger'] as { log: (...args: unknown[]) => void }, 'log')
      .mockImplementation(() => undefined);
    await expect(service.purgeExpired()).resolves.toEqual({
      sessionsDeleted: 3,
      tokensDeleted: 5,
    });
    expect(sessions.execute).toHaveBeenCalledTimes(1);
    expect(tokens.execute).toHaveBeenCalledTimes(1);
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        'Purged 3 expired auth sessions, 5 used/expired email tokens',
      ),
    );
  });
});
