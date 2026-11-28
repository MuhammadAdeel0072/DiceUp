import 'auth_api_client.dart';
import 'auth_models.dart';
import 'token_storage.dart';

/// Authentication service (Phase 5, Stage 2): the single place that
/// owns the session — API calls, secure storage, and silent refresh.
///
/// * The in-memory [_session] is the source of truth for API calls;
///   secure storage is the durable copy, restored on [restoreSession].
/// * [restoreSession] (app restart): a stored session with a live
///   access token restores as-is; an expired access token triggers
///   one silent refresh; a failed refresh clears the stored session
///   (the refresh token is invalid / reused / revoked — there is
///   nothing left to restore) and returns null.
/// * Authenticated calls go through [_withFreshToken]: an expired
///   access token is refreshed first, and a 401 retries once after
///   a refresh — so a token expiring mid-call does not surface as a
///   spurious "not logged in". A second 401 clears the session.
/// * [logout] calls the backend first (revoking the session server
///   side, so the access token dies immediately) and clears local
///   state even if that call fails — a logout must never leave
///   tokens behind because the network was down.
/// * [changePassword] revokes ALL sessions server-side, so the
///   local session is cleared too and the user signs in again.
/// * Mid-match expiry re-handshake is a note for later stages (no
///   match logic exists yet); the refresh machinery it will reuse
///   is this service.
///
/// Throws [ApiException] on failure; never throws a raw transport
/// error, and never logs a token.
class AuthService {
  AuthService({required this._client, required this._storage});

  final AuthApiClient _client;
  final TokenStorage _storage;

  AuthSession? _session;

  /// The current in-memory session, null when signed out.
  AuthSession? get session => _session;

  /// True when a session is held in memory.
  bool get isAuthenticated => _session != null;

  /// Restores the persisted session, silently refreshing an expired
  /// access token. Returns the session, or null when there is none
  /// (or it could not be refreshed). A storage failure also yields
  /// null — a broken secure store must not crash startup.
  Future<AuthSession?> restoreSession() async {
    AuthSession? stored;
    try {
      stored = await _storage.readSession();
    } catch (_) {
      return null;
    }
    if (stored == null) return null;
    if (!stored.accessTokenExpired) {
      _session = stored;
      return stored;
    }
    try {
      final refreshed = await _refresh(stored);
      _session = refreshed;
      return refreshed;
    } on ApiException {
      await _clearLocal();
      return null;
    }
  }

  /// Logs in (FR-04) and persists the session.
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    final result = await _client.login(
      identifier: identifier,
      password: password,
    );
    return _adopt(
      AuthSession.received(user: result.user, tokens: result.tokens),
    );
  }

  /// Registers (FR-02) and persists the session. The account starts
  /// unverified — the caller routes to the verification screen.
  Future<AuthSession> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    final result = await _client.register(
      email: email,
      username: username,
      password: password,
      displayName: displayName,
    );
    return _adopt(
      AuthSession.received(user: result.user, tokens: result.tokens),
    );
  }

  /// Verifies the email with the code from the verification email
  /// (FR-03). Marks the local user verified on success.
  Future<void> verifyEmail({required String token}) async {
    await _client.verifyEmail(token: token);
    final session = _session;
    if (session != null) {
      final verified = session.copyWith(
        user: session.user.copyWith(emailVerified: true),
      );
      _session = verified;
      await _storage.saveSession(verified);
    }
  }

  /// Resends the verification email (neutral 200).
  Future<void> resendVerification({required String email}) =>
      _client.resendVerification(email: email);

  /// Requests a password-reset email (FR-06, neutral 200).
  Future<void> forgotPassword({required String email}) =>
      _client.forgotPassword(email: email);

  /// Resets the password with the code from the reset email (FR-06).
  /// Revokes all sessions server-side; any local session is cleared.
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _client.resetPassword(token: token, newPassword: newPassword);
    await _clearLocal();
  }

  /// Logs out (FR-05): revokes the session on the backend, then
  /// clears local tokens even if the backend call fails.
  Future<void> logout() async {
    final session = _session;
    if (session != null) {
      try {
        await _client.logout(accessToken: session.tokens.accessToken);
      } on ApiException {
        // The server-side revocation may already have happened, or
        // the network may be down — either way the local tokens go.
      }
    }
    await _clearLocal();
  }

  /// Own profile (FR-07) with silent refresh / 401-retry.
  Future<OwnProfile> fetchProfile() async {
    final profile = await _withFreshToken(
      (accessToken) => _client.getProfile(accessToken: accessToken),
    );
    return profile;
  }

  /// Runs [call] with a live access token (Stage 3: the game layer's
  /// authenticated calls). Refreshes first when expired, retries once
  /// after a refresh on 401 — the same guarantees as [fetchProfile],
  /// for callers that are not auth-profile shaped. Throws
  /// [ApiException] on failure; a second 401 clears the session.
  Future<T> callAuthenticated<T>(Future<T> Function(String accessToken) call) =>
      _withFreshToken(call);

  /// A live access token for the socket handshake (Stage 3): refreshes
  /// first when expired. Returns null when there is no session or the
  /// refresh failed (session cleared). The socket layer re-handshakes
  /// with the result; it never reads [_session] directly.
  Future<String?> freshAccessToken() async {
    final session = _session;
    if (session == null) return null;
    try {
      final live = session.accessTokenExpired
          ? await _refresh(session)
          : session;
      _session = live;
      return live.tokens.accessToken;
    } on ApiException {
      await _clearLocal();
      return null;
    }
  }

  /// Changes the password (FR-08). The backend revokes all
  /// sessions, so the local session is cleared and the user must
  /// sign in again with the new password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _withFreshToken(
      (accessToken) => _client.changePassword(
        accessToken: accessToken,
        currentPassword: currentPassword,
        newPassword: newPassword,
      ),
    );
    await _clearLocal();
  }

  /// Forces a refresh of the current session (used by the socket
  /// layer in later stages to re-handshake with a fresh token).
  /// Returns the new session, or null when there is no session or
  /// the refresh failed (session cleared).
  Future<AuthSession?> refreshSession() async {
    final session = _session;
    if (session == null) return null;
    try {
      final refreshed = await _refresh(session);
      _session = refreshed;
      return refreshed;
    } on ApiException {
      await _clearLocal();
      return null;
    }
  }

  /// Runs [call] with a live access token: refreshes first when
  /// expired, retries once after a refresh when the call answers
  /// 401. A second 401 clears the session and rethrows.
  Future<T> _withFreshToken<T>(
    Future<T> Function(String accessToken) call,
  ) async {
    var session = _session;
    if (session == null) {
      throw const ApiException(code: 'UNAUTHORIZED', message: 'Not signed in.');
    }
    if (session.accessTokenExpired) {
      session = await _refreshOrClear(session);
    }
    try {
      return await call(session.tokens.accessToken);
    } on ApiException catch (e) {
      if (e.httpStatus == 401 || e.code == 'UNAUTHORIZED') {
        session = await _refreshOrClear(session);
        try {
          return await call(session.tokens.accessToken);
        } on ApiException catch (retryError) {
          if (retryError.httpStatus == 401 ||
              retryError.code == 'UNAUTHORIZED') {
            await _clearLocal();
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<AuthSession> _refreshOrClear(AuthSession session) async {
    try {
      final refreshed = await _refresh(session);
      _session = refreshed;
      return refreshed;
    } on ApiException {
      await _clearLocal();
      rethrow;
    }
  }

  /// One refresh rotation: presents the stored refresh token and
  /// persists the new pair. A 401 here means the refresh token is
  /// invalid or was reused (family revoked) — the caller clears.
  Future<AuthSession> _refresh(AuthSession session) async {
    final tokens = await _client.refresh(
      refreshToken: session.tokens.refreshToken,
    );
    final refreshed = AuthSession.received(user: session.user, tokens: tokens);
    await _storage.saveSession(refreshed);
    return refreshed;
  }

  Future<AuthSession> _adopt(AuthSession session) async {
    _session = session;
    await _storage.saveSession(session);
    return session;
  }

  Future<void> _clearLocal() async {
    _session = null;
    try {
      await _storage.clearSession();
    } catch (_) {
      // Clearing is best-effort once the in-memory session is gone.
    }
  }
}
