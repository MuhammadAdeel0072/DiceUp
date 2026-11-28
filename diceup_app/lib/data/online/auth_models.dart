/// Auth models (Phase 5, Stage 2): request/response shapes for the
/// Phase 4 backend auth API (`backend/docs/06-rest-api.md`,
/// `07-authentication.md`). Plain data only — no I/O, no Flutter.
///
/// The backend envelope is `{success: true, data}` on success and
/// `{success: false, error: {code, message, details?}}` on failure.
/// [ApiException.code] is the machine-readable contract — callers
/// switch on the code, never on message text.
///
/// Tokens are never logged: no `toString` here prints a token, and
/// the client never logs request bodies or `Authorization` headers.
library;

/// The public user shape returned by the backend — never contains
/// a password hash (NFR-13/21).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.avatarKey,
    required this.emailVerified,
  });

  factory AuthUser.fromJson(Map<String, Object?> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String? ?? json['username'] as String,
    avatarKey: json['avatarKey'] as String? ?? 'default',
    emailVerified: json['emailVerified'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'email': email,
    'username': username,
    'displayName': displayName,
    'avatarKey': avatarKey,
    'emailVerified': emailVerified,
  };

  AuthUser copyWith({bool? emailVerified, String? displayName}) => AuthUser(
    id: id,
    email: email,
    username: username,
    displayName: displayName ?? this.displayName,
    avatarKey: avatarKey,
    emailVerified: emailVerified ?? this.emailVerified,
  );

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String avatarKey;
  final bool emailVerified;
}

/// The token pair returned by register / login / refresh.
///
/// Access token: RS256 JWT, 15 min (`expiresIn` seconds).
/// Refresh token: opaque 256-bit token, 30 days, rotated on use.
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory TokenPair.fromJson(Map<String, Object?> json) => TokenPair(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 900,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresIn': expiresIn,
  };

  final String accessToken;
  final String refreshToken;

  /// Access-token lifetime in seconds (900).
  final int expiresIn;
}

/// The authenticated session: user + tokens + the wall-clock time
/// the access token expires (computed from `expiresIn` at receipt,
/// so restore can decide on refresh without decoding the JWT).
class AuthSession {
  const AuthSession({
    required this.user,
    required this.tokens,
    required this.accessTokenExpiresAt,
  });

  factory AuthSession.fromJson(Map<String, Object?> json) => AuthSession(
    user: AuthUser.fromJson(json['user'] as Map<String, Object?>),
    tokens: TokenPair.fromJson(json['tokens'] as Map<String, Object?>),
    accessTokenExpiresAt: DateTime.fromMillisecondsSinceEpoch(
      (json['accessTokenExpiresAtMs'] as num).toInt(),
    ),
  );

  /// Builds a session from a fresh [AuthResponse] body.
  factory AuthSession.received({
    required AuthUser user,
    required TokenPair tokens,
  }) => AuthSession(
    user: user,
    tokens: tokens,
    accessTokenExpiresAt: DateTime.now().add(
      Duration(seconds: tokens.expiresIn),
    ),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'user': user.toJson(),
    'tokens': tokens.toJson(),
    'accessTokenExpiresAtMs': accessTokenExpiresAt.millisecondsSinceEpoch,
  };

  final AuthUser user;
  final TokenPair tokens;
  final DateTime accessTokenExpiresAt;

  /// True when the access token is expired or expires within the
  /// refresh skew window (30 s) — the point at which the service
  /// silently refreshes instead of using it.
  bool get accessTokenExpired => DateTime.now().isAfter(
    accessTokenExpiresAt.subtract(const Duration(seconds: 30)),
  );

  AuthSession copyWith({AuthUser? user, TokenPair? tokens}) {
    final nextTokens = tokens ?? this.tokens;
    return AuthSession(
      user: user ?? this.user,
      tokens: nextTokens,
      accessTokenExpiresAt: tokens == null
          ? accessTokenExpiresAt
          : DateTime.now().add(Duration(seconds: nextTokens.expiresIn)),
    );
  }
}

/// The own-profile shape from `GET /users/me` (FR-07).
class OwnProfile {
  const OwnProfile({
    required this.user,
    required this.status,
    required this.matchesPlayed,
    required this.matchesWon,
    required this.createdAt,
  });

  factory OwnProfile.fromJson(Map<String, Object?> json) => OwnProfile(
    user: AuthUser.fromJson(json),
    status: json['status'] as String? ?? 'active',
    matchesPlayed: (json['matchesPlayed'] as num?)?.toInt() ?? 0,
    matchesWon: (json['matchesWon'] as num?)?.toInt() ?? 0,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final AuthUser user;
  final String status;
  final int matchesPlayed;
  final int matchesWon;
  final DateTime createdAt;
}

/// An error from the backend API (or from the transport).
///
/// [code] is the backend envelope `error.code` when the backend
/// answered (e.g. `INVALID_CREDENTIALS`, `EMAIL_TAKEN`,
/// `TOKEN_EXPIRED`, `RATE_LIMITED`, `VALIDATION_FAILED`), or one of
/// the client-side codes below when it did not:
/// * `NETWORK_ERROR` — no connection / DNS / socket failure.
/// * `TIMEOUT` — the request exceeded [AuthApiClient.requestTimeout].
/// * `UNEXPECTED_RESPONSE` — non-JSON or wrong-shape response.
///
/// [fieldErrors] carries the per-field `details` of a
/// `VALIDATION_FAILED` response (field → first message), so screens
/// can show the error under the field it belongs to. [retryAfter]
/// carries the `Retry-After` seconds of a `RATE_LIMITED` response.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.httpStatus,
    this.fieldErrors = const <String, String>{},
    this.retryAfterSeconds,
  });

  /// Client-side: the request never reached the backend.
  factory ApiException.network([String? message]) => ApiException(
    code: 'NETWORK_ERROR',
    message: message ?? 'Could not reach the server.',
  );

  /// Client-side: the request timed out.
  factory ApiException.timeout() =>
      const ApiException(code: 'TIMEOUT', message: 'The request timed out.');

  /// Client-side: the backend answered with something unparseable.
  factory ApiException.unexpectedResponse([String? message]) => ApiException(
    code: 'UNEXPECTED_RESPONSE',
    message: message ?? 'The server gave an unexpected response.',
  );

  /// The backend envelope `error.code`, or a client-side code.
  final String code;

  /// Human-readable message from the backend (or the client).
  /// UI copy comes from localised mappings of [code], never from
  /// this string verbatim — it is developer-facing only.
  final String message;

  /// HTTP status when the backend answered, null when it did not.
  final int? httpStatus;

  /// Per-field validation messages (`VALIDATION_FAILED` only).
  final Map<String, String> fieldErrors;

  /// `Retry-After` seconds (`RATE_LIMITED` only).
  final int? retryAfterSeconds;

  @override
  String toString() => 'ApiException($code, HTTP $httpStatus)';
}
