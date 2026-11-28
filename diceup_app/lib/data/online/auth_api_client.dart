import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_config.dart';
import 'auth_models.dart';

/// REST client for the Phase 4 backend auth + users API (Phase 5,
/// Stage 2). Thin and honest: it maps the response envelope to
/// models or [ApiException], and nothing else.
///
/// * Base URL comes from [AuthConfig] (dart-define override,
///   loopback dev default) — never a hard-coded production host.
/// * Timeout / retry policy: every request times out after
///   [requestTimeout] (15 s). GETs retry once on a transient
///   transport failure; POSTs / PATCHes are never retried
///   automatically (they are not idempotent — a retried register
///   could surface a spurious `EMAIL_TAKEN`).
/// * Error mapping: the envelope `error.code` is the contract.
///   `details` of a `VALIDATION_FAILED` response become
///   [ApiException.fieldErrors]; a `429` carries `Retry-After`.
/// * No tokens or secrets are ever logged, and request bodies are
///   never logged (they carry passwords and codes).
class AuthApiClient {
  AuthApiClient({AuthConfig? config, http.Client? httpClient})
    : _config = config ?? AuthConfig.fromEnvironment(),
      _http = httpClient ?? http.Client();

  final AuthConfig _config;
  final http.Client _http;

  /// Per-request timeout (NFR-05/06 latency bars are server-side;
  /// this is the client giving up, not a service guarantee).
  static const Duration requestTimeout = Duration(seconds: 15);

  String get baseUrl => _config.baseUrl;

  void close() => _http.close();

  // -- Auth (FR-02/03/04/05/06) ---------------------------------------

  /// `POST /auth/register` → 201 + user + tokens.
  /// 409 `EMAIL_TAKEN` / `USERNAME_TAKEN`; 400 `VALIDATION_FAILED`.
  Future<({AuthUser user, TokenPair tokens})> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    final data = await _postJson('/auth/register', <String, Object?>{
      'email': email,
      'username': username,
      'password': password,
      if (displayName != null && displayName.trim().isNotEmpty)
        'displayName': displayName.trim(),
    });
    return _authResponse(data);
  }

  /// `POST /auth/login` → 200 + user + tokens.
  /// Wrong credentials / unknown account → 401 `INVALID_CREDENTIALS`
  /// (generic by design — no enumeration).
  Future<({AuthUser user, TokenPair tokens})> login({
    required String identifier,
    required String password,
  }) async {
    final data = await _postJson('/auth/login', <String, Object?>{
      'identifier': identifier,
      'password': password,
    });
    return _authResponse(data);
  }

  /// `POST /auth/refresh` → 200 + rotated token pair.
  /// Invalid / reused refresh token → 401.
  Future<TokenPair> refresh({required String refreshToken}) async {
    final data = await _postJson('/auth/refresh', <String, Object?>{
      'refreshToken': refreshToken,
    });
    return TokenPair.fromJson(data);
  }

  /// `POST /auth/logout` → 200 `{loggedOut: true}`. Revokes the
  /// current session; the access token then fails immediately.
  Future<void> logout({required String accessToken}) async {
    await _postJson(
      '/auth/logout',
      const <String, Object?>{},
      token: accessToken,
    );
  }

  /// `POST /auth/verify-email` → 200. Reuse → 409
  /// `TOKEN_ALREADY_USED`; expired → 410 `TOKEN_EXPIRED`; unknown
  /// code → 401 (generic, no leak).
  Future<void> verifyEmail({required String token}) async {
    await _postJson('/auth/verify-email', <String, Object?>{'token': token});
  }

  /// `POST /auth/verify-email/resend` → 200, neutral (no leak
  /// whether the account exists).
  Future<void> resendVerification({required String email}) async {
    await _postJson('/auth/verify-email/resend', <String, Object?>{
      'email': email,
    });
  }

  /// `POST /auth/forgot-password` → 200, neutral even for unknown
  /// emails.
  Future<void> forgotPassword({required String email}) async {
    await _postJson('/auth/forgot-password', <String, Object?>{'email': email});
  }

  /// `POST /auth/reset-password` → 200. A successful reset revokes
  /// all sessions. Reuse → 409; expired → 410.
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _postJson('/auth/reset-password', <String, Object?>{
      'token': token,
      'newPassword': newPassword,
    });
  }

  // -- Users (FR-07/08, authenticated) ---------------------------------

  /// `GET /users/me` → 200 own profile. Unverified users get 403
  /// `EMAIL_NOT_VERIFIED` (the `EmailVerifiedGuard` on users routes).
  Future<OwnProfile> getProfile({required String accessToken}) async {
    final data = await _getJson('/users/me', token: accessToken);
    return OwnProfile.fromJson(data);
  }

  /// `PATCH /users/me/password` → 200. Wrong current password →
  /// 401; success revokes all sessions (the caller must log out
  /// locally — see [AuthService.changePassword]).
  Future<void> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _patchJson('/users/me/password', <String, Object?>{
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    }, token: accessToken);
  }

  // -- Envelope + transport ---------------------------------------------

  ({AuthUser user, TokenPair tokens}) _authResponse(
    Map<String, Object?> data,
  ) => (
    user: AuthUser.fromJson(data['user'] as Map<String, Object?>),
    tokens: TokenPair.fromJson(data['tokens'] as Map<String, Object?>),
  );

  Future<Map<String, Object?>> _getJson(String path, {String? token}) async {
    final response = await _sendWithRetry(
      () => _http.get(
        Uri.parse('${_config.baseUrl}$path'),
        headers: _headers(token: token),
      ),
    );
    return _decode(response);
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body, {
    String? token,
  }) async {
    final response = await _send(
      () => _http.post(
        Uri.parse('${_config.baseUrl}$path'),
        headers: _headers(token: token),
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Future<Map<String, Object?>> _patchJson(
    String path,
    Map<String, Object?> body, {
    String? token,
  }) async {
    final response = await _send(
      () => _http.patch(
        Uri.parse('${_config.baseUrl}$path'),
        headers: _headers(token: token),
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Map<String, String> _headers({String? token}) => <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// One attempt with a timeout. Transport failures surface as
  /// [ApiException] with a client-side code — never a raw
  /// [SocketException] / [TimeoutException] leaking to the UI.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(requestTimeout);
    } on TimeoutException {
      throw ApiException.timeout();
    } on SocketException {
      throw ApiException.network();
    } on HttpException {
      throw ApiException.network();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException.network();
    }
  }

  /// GETs retry once on a transient transport failure, then give
  /// up with the same client-side code. POSTs/PATCHes never retry.
  Future<http.Response> _sendWithRetry(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await _send(request);
    } on ApiException catch (e) {
      if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
        return _send(request);
      }
      rethrow;
    }
  }

  /// Decodes the envelope. Success → `data` (or `{}` when the
  /// endpoint returns no payload). Failure → [ApiException] from
  /// the envelope `error.code`, with per-field `details` and
  /// `Retry-After` preserved. A non-JSON or wrong-shape body is
  /// [ApiException] `UNEXPECTED_RESPONSE`, never a crash.
  Map<String, Object?> _decode(http.Response response) {
    Map<String, Object?> body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw ApiException.unexpectedResponse();
      }
      body = decoded;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException.unexpectedResponse();
    }

    final error = body['error'];
    if (error is Map<String, Object?>) {
      final details = error['details'];
      final fieldErrors = <String, String>{};
      if (details is Map<String, Object?>) {
        for (final entry in details.entries) {
          final messages = entry.value;
          if (messages is List && messages.isNotEmpty) {
            fieldErrors[entry.key] = messages.first.toString();
          } else if (messages is String) {
            fieldErrors[entry.key] = messages;
          }
        }
      }
      final retryAfter = response.headers['retry-after'];
      throw ApiException(
        code: error['code'] as String? ?? 'INTERNAL_ERROR',
        message: error['message'] as String? ?? 'The request failed.',
        httpStatus: response.statusCode,
        fieldErrors: fieldErrors,
        retryAfterSeconds: retryAfter == null ? null : int.tryParse(retryAfter),
      );
    }

    if (response.statusCode >= 400) {
      throw ApiException(
        code: 'INTERNAL_ERROR',
        message: 'The request failed.',
        httpStatus: response.statusCode,
      );
    }

    final data = body['data'];
    if (data == null) return const <String, Object?>{};
    if (data is Map<String, Object?>) return data;
    throw ApiException.unexpectedResponse();
  }
}
