import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_models.dart';

/// Secure token storage (Phase 5, Stage 2; FR-09).
///
/// Access + refresh tokens live ONLY in platform secure storage
/// (iOS Keychain / Android EncryptedSharedPreferences via
/// `flutter_secure_storage`). They are never written to SQLite —
/// the local DB layer explicitly holds no tokens — never logged,
/// and never stored alongside anything but the owning user's public
/// profile JSON (no secrets in it).
///
/// Storage failures (e.g. no secure enclave on a desktop run) are
/// surfaced as exceptions; [AuthService] treats a failed restore
/// read as "no session" instead of crashing the app.
abstract class TokenStorage {
  Future<void> saveSession(AuthSession session);
  Future<AuthSession?> readSession();
  Future<void> clearSession();
}

/// Platform secure storage implementation.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  // Default options: AES-GCM storage with RSA-OAEP key wrapping on
  // Android (v11 default — no separate encrypted-preferences flag),
  // Keychain on iOS.

  static const String _accessTokenKey = 'diceup_access_token';
  static const String _refreshTokenKey = 'diceup_refresh_token';
  static const String _expiresAtKey = 'diceup_token_expires_at_ms';
  static const String _userKey = 'diceup_user_json';

  final FlutterSecureStorage _storage;

  @override
  Future<void> saveSession(AuthSession session) async {
    await _storage.write(
      key: _accessTokenKey,
      value: session.tokens.accessToken,
    );
    await _storage.write(
      key: _refreshTokenKey,
      value: session.tokens.refreshToken,
    );
    await _storage.write(
      key: _expiresAtKey,
      value: session.accessTokenExpiresAt.millisecondsSinceEpoch.toString(),
    );
    await _storage.write(
      key: _userKey,
      value: jsonEncode(session.user.toJson()),
    );
  }

  @override
  Future<AuthSession?> readSession() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    final expiresAtMs = await _storage.read(key: _expiresAtKey);
    final userJson = await _storage.read(key: _userKey);
    if (accessToken == null ||
        refreshToken == null ||
        expiresAtMs == null ||
        userJson == null) {
      return null;
    }
    final expiresAt = int.tryParse(expiresAtMs);
    if (expiresAt == null) return null;
    AuthUser user;
    try {
      final decoded = jsonDecode(userJson);
      if (decoded is! Map<String, Object?>) return null;
      user = AuthUser.fromJson(decoded);
    } catch (_) {
      return null;
    }
    return AuthSession(
      user: user,
      tokens: TokenPair(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresIn: 900,
      ),
      accessTokenExpiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
    );
  }

  @override
  Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiresAtKey);
    await _storage.delete(key: _userKey);
  }
}
