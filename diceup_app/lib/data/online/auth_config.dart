/// Online API configuration (Phase 5, Stage 2).
///
/// The backend runs locally for development; the base URL is
/// configurable so no production host is ever hard-coded here.
///
/// Override with a dart-define, e.g.:
/// `flutter run --dart-define=DICEUP_API_BASE_URL=http://10.0.2.2:3000/v1`
/// (Android emulator reaching a host-side backend).
/// Default: the local dev backend on loopback.
class AuthConfig {
  const AuthConfig({required this.baseUrl, this.rulesetVersion = '1.0.0'});

  /// Default base URL: local dev backend, `/v1` global prefix.
  static const String defaultBaseUrl = 'http://127.0.0.1:3000/v1';

  /// Base URL from `--dart-define=DICEUP_API_BASE_URL`, or the
  /// loopback dev default when unset.
  factory AuthConfig.fromEnvironment() => AuthConfig(
    baseUrl: const String.fromEnvironment(
      'DICEUP_API_BASE_URL',
      defaultValue: defaultBaseUrl,
    ),
    rulesetVersion: const String.fromEnvironment(
      'DICEUP_RULESET_VERSION',
      defaultValue: '1.0.0',
    ),
  );

  /// Base URL of the backend REST API, including the `/v1` prefix.
  /// Never a production host unless the build passes one explicitly.
  final String baseUrl;

  /// The frozen ruleset version (Stage 3, OD-11): every Phase 5
  /// match uses this version; the backend pins the same value
  /// (RULESET_VERSION, default 1.0.0). A room's own
  /// `rulesetVersion` is authoritative once the room exists — this
  /// is only the pre-room summary shown on the create form (G-16).
  final String rulesetVersion;
}
