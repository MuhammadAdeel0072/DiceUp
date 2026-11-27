import { LogMailerService } from '../../src/mailer/log-mailer.service';
import { SmtpMailerService } from '../../src/mailer/smtp-mailer.service';

describe('LogMailerService (dev/test transport)', () => {
  it('stores messages in memory for test inspection, never sending', async () => {
    const mailer = new LogMailerService();
    await mailer.sendVerification('ali@example.com', 'token-123');
    await mailer.sendPasswordReset('ali@example.com', 'token-456');
    expect(mailer.getSentMessages()).toHaveLength(2);
    expect(mailer.findLatest('ali@example.com', 'verification')?.token).toBe(
      'token-123',
    );
    expect(mailer.findLatest('ali@example.com', 'password-reset')?.token).toBe(
      'token-456',
    );
    expect(
      mailer.findLatest('bob@example.com', 'verification'),
    ).toBeUndefined();
    mailer.clear();
    expect(mailer.getSentMessages()).toEqual([]);
  });

  it('never writes the token to a log line', async () => {
    const mailer = new LogMailerService();
    const logged: string[] = [];
    jest
      .spyOn(mailer['logger'] as { log: (...args: unknown[]) => void }, 'log')
      .mockImplementation((message: unknown) => {
        logged.push(String(message));
      });
    await mailer.sendVerification('ali@example.com', 'super-secret-token');
    expect(logged.join(' ')).toContain('ali@example.com');
    expect(logged.join(' ')).not.toContain('super-secret-token');
  });
});

describe('SmtpMailerService', () => {
  it('sends verification + reset via the injected transport', async () => {
    const sent: Record<string, unknown>[] = [];
    const transport = {
      sendMail: jest.fn(async (opts: Record<string, unknown>) => {
        sent.push(opts);
        return { messageId: '1' };
      }),
    };
    const mailer = new SmtpMailerService(
      transport as never,
      'noreply@diceup.example',
    );
    await mailer.sendVerification('ali@example.com', 'verify-token');
    await mailer.sendPasswordReset('ali@example.com', 'reset-token');
    expect(transport.sendMail).toHaveBeenCalledTimes(2);
    expect(sent[0].to).toBe('ali@example.com');
    expect(sent[0].from).toBe('noreply@diceup.example');
    expect(sent[0].text as string).toContain('verify-token');
    expect(sent[0].text as string).toContain('24 hours');
    expect(sent[1].text as string).toContain('reset-token');
    expect(sent[1].text as string).toContain('1 hour');
  });
});
