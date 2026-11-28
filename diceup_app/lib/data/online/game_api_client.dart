import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_config.dart';
import 'auth_models.dart';
import 'game_models.dart';

/// REST client for the Phase 5 backend rooms + matchmaking API
/// (Stage 3). Thin and honest, mirroring [AuthApiClient]: it maps
/// the response envelope to models or [ApiException], and nothing else.
///
/// * Base URL comes from [AuthConfig] — never a hard-coded host.
/// * Every request times out after [requestTimeout] (15 s). GETs
///   retry once on a transient transport failure; POSTs are never
///   retried automatically (they are not idempotent).
/// * Error mapping: the envelope `error.code` is the contract
///   (`ROOM_NOT_FOUND`, `ROOM_FULL`, `ROOM_STARTED`,
///   `ALREADY_IN_ROOM`, `ALREADY_IN_MATCH`, `ALREADY_IN_MATCHMAKING`,
///   `NOT_ROOM_MEMBER`, `NOT_ROOM_HOST`, `MATCHMAKING_UNAVAILABLE`).
/// * Methods take the access token as a parameter; [GameRoomService]
///   supplies a fresh one (silent refresh + 401-retry) via
///   [AuthService]. This client never holds a session itself.
/// * No tokens or secrets are ever logged, and request bodies are
///   never logged.
class GameApiClient {
  GameApiClient({AuthConfig? config, http.Client? httpClient})
    : _config = config ?? AuthConfig.fromEnvironment(),
      _http = httpClient ?? http.Client();

  final AuthConfig _config;
  final http.Client _http;

  static const Duration requestTimeout = Duration(seconds: 15);

  String get baseUrl => _config.baseUrl;

  void close() => _http.close();

  // -- Rooms (FR-43/44/59) ------------------------------------------------

  /// `POST /rooms` → 201 + room. 409 `ALREADY_IN_ROOM` /
  /// `ALREADY_IN_MATCH`; 400 `VALIDATION_FAILED` (limit outside 2–4).
  Future<RoomView> createRoom({
    required String accessToken,
    required int maxPlayers,
  }) async {
    final data = await _postJson('/rooms', <String, Object?>{
      'maxPlayers': maxPlayers,
    }, token: accessToken);
    return RoomView.fromJson(data);
  }

  /// `POST /rooms/join` → 200 + room. 404 `ROOM_NOT_FOUND`;
  /// 409 `ROOM_FULL` / `ROOM_STARTED` / `ALREADY_IN_ROOM`.
  Future<RoomView> joinRoom({
    required String accessToken,
    required String code,
  }) async {
    final data = await _postJson('/rooms/join', <String, Object?>{
      'code': code,
    }, token: accessToken);
    return RoomView.fromJson(data);
  }

  /// `GET /rooms/:id` → 200 + room. 403 `NOT_ROOM_MEMBER`;
  /// 404 `ROOM_NOT_FOUND`.
  Future<RoomView> getRoom({
    required String accessToken,
    required String roomId,
  }) async {
    final data = await _getJson('/rooms/$roomId', token: accessToken);
    return RoomView.fromJson(data);
  }

  /// `POST /rooms/:id/leave` → 200 + room (host transferred, or the
  /// room closed when empty). 409 `INVALID_STATE` once the match
  /// has started (mid-match leave is a Stage 6 forfeit).
  Future<RoomView> leaveRoom({
    required String accessToken,
    required String roomId,
  }) async {
    final data = await _postJson(
      '/rooms/$roomId/leave',
      const <String, Object?>{},
      token: accessToken,
    );
    return RoomView.fromJson(data);
  }

  // -- Matchmaking (FR-45) --------------------------------------------------

  /// `POST /matchmaking/join` → 200 `{matched, position, queueSize,
  /// groupSize}` or `{matched: true, room}` when the group of 4
  /// formed. 409 `ALREADY_IN_MATCHMAKING` / `ALREADY_IN_ROOM` /
  /// `ALREADY_IN_MATCH`; 503 `MATCHMAKING_UNAVAILABLE` (Redis down).
  Future<Map<String, Object?>> joinMatchmaking({
    required String accessToken,
  }) async {
    return _postJson(
      '/matchmaking/join',
      const <String, Object?>{},
      token: accessToken,
    );
  }

  /// `POST /matchmaking/leave` → 200 `{left: true|false}`.
  Future<Map<String, Object?>> leaveMatchmaking({
    required String accessToken,
  }) async {
    return _postJson(
      '/matchmaking/leave',
      const <String, Object?>{},
      token: accessToken,
    );
  }

  /// `GET /matchmaking/status` → 200 `{status: queued|matched|idle,
  /// position?, queueSize, groupSize, roomId?, roomCode?}`.
  Future<MatchmakingStatus> matchmakingStatus({
    required String accessToken,
  }) async {
    final data = await _getJson('/matchmaking/status', token: accessToken);
    return MatchmakingStatus.fromJson(data);
  }

  // -- Envelope + transport (mirrors AuthApiClient) -------------------------

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

  Map<String, String> _headers({String? token}) => <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

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
