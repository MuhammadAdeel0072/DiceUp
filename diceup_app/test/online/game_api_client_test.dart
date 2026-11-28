import 'dart:convert';

import 'package:diceup/data/online/auth_config.dart';
import 'package:diceup/data/online/auth_models.dart';
import 'package:diceup/data/online/game_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const baseUrl = 'http://127.0.0.1:3000/v1';
  const token = 'access-token';

  GameApiClient clientWith(MockClient mock) => GameApiClient(
    config: const AuthConfig(baseUrl: baseUrl),
    httpClient: mock,
  );

  Map<String, Object?> roomData({String code = 'K7Q2XA'}) => <String, Object?>{
    'id': '00000000-0000-0000-0000-000000000099',
    'code': code,
    'hostId': '00000000-0000-0000-0000-000000000001',
    'maxPlayers': 4,
    'status': 'open',
    'rulesetVersion': '1.0.0',
    'source': 'manual',
    'createdAt': '2026-11-28T00:00:00.000Z',
    'closedAt': null,
    'members': [
      <String, Object?>{
        'userId': '00000000-0000-0000-0000-000000000001',
        'username': 'ada',
        'displayName': 'Ada',
        'isReady': false,
        'isHost': true,
        'joinedAt': '2026-11-28T00:00:00.000Z',
      },
    ],
    'matchId': null,
  };

  http.Response ok(Object? data, [int status = 200]) => http.Response(
    jsonEncode(<String, Object?>{'success': true, 'data': data}),
    status,
    headers: {'content-type': 'application/json'},
  );

  http.Response err(String code, int status) => http.Response(
    jsonEncode(<String, Object?>{
      'success': false,
      'error': <String, Object?>{'code': code, 'message': 'Failed.'},
    }),
    status,
    headers: {'content-type': 'application/json'},
  );

  group('GameApiClient rooms', () {
    test('createRoom posts the limit and parses the room', () async {
      final client = clientWith(
        MockClient((request) async {
          expect(request.url.toString(), '$baseUrl/rooms');
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer $token');
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['maxPlayers'], 2);
          return ok(roomData(), 201);
        }),
      );
      final room = await client.createRoom(accessToken: token, maxPlayers: 2);
      expect(room.code, 'K7Q2XA');
      expect(room.hostId, '00000000-0000-0000-0000-000000000001');
      expect(room.members, hasLength(1));
    });

    test('joinRoom maps ROOM_NOT_FOUND to ApiException', () async {
      final client = clientWith(
        MockClient((_) async => err('ROOM_NOT_FOUND', 404)),
      );
      await expectLater(
        client.joinRoom(accessToken: token, code: 'ZZZZZZ'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'ROOM_NOT_FOUND'),
        ),
      );
    });

    test('joinRoom maps ROOM_FULL to ApiException', () async {
      final client = clientWith(MockClient((_) async => err('ROOM_FULL', 409)));
      await expectLater(
        client.joinRoom(accessToken: token, code: 'K7Q2XA'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ROOM_FULL')),
      );
    });

    test('leaveRoom posts to the room id', () async {
      final client = clientWith(
        MockClient((request) async {
          expect(
            request.url.toString(),
            '$baseUrl/rooms/00000000-0000-0000-0000-000000000099/leave',
          );
          return ok(roomData());
        }),
      );
      final room = await client.leaveRoom(
        accessToken: token,
        roomId: '00000000-0000-0000-0000-000000000099',
      );
      expect(room.code, 'K7Q2XA');
    });
  });

  group('GameApiClient matchmaking', () {
    test('joinMatchmaking returns the queued payload', () async {
      final client = clientWith(
        MockClient((request) async {
          expect(request.url.toString(), '$baseUrl/matchmaking/join');
          return ok(<String, Object?>{
            'matched': false,
            'position': 2,
            'queueSize': 2,
            'groupSize': 4,
          });
        }),
      );
      final result = await client.joinMatchmaking(accessToken: token);
      expect(result['matched'], isFalse);
      expect(result['position'], 2);
    });

    test(
      'joinMatchmaking returns the matched room when a group forms',
      () async {
        final client = clientWith(
          MockClient(
            (_) async =>
                ok(<String, Object?>{'matched': true, 'room': roomData()}),
          ),
        );
        final result = await client.joinMatchmaking(accessToken: token);
        expect(result['matched'], isTrue);
        expect((result['room'] as Map<String, Object?>)['code'], 'K7Q2XA');
      },
    );

    test('matchmakingStatus parses queued / matched / idle', () async {
      final client = clientWith(
        MockClient(
          (_) async => ok(<String, Object?>{
            'status': 'queued',
            'position': 1,
            'queueSize': 3,
            'groupSize': 4,
          }),
        ),
      );
      final status = await client.matchmakingStatus(accessToken: token);
      expect(status.isQueued, isTrue);
      expect(status.position, 1);
      expect(status.queueSize, 3);
    });

    test(
      'leaveMatchmaking maps ALREADY_IN_MATCHMAKING errors through',
      () async {
        final client = clientWith(
          MockClient((_) async => err('MATCHMAKING_UNAVAILABLE', 503)),
        );
        await expectLater(
          client.joinMatchmaking(accessToken: token),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'MATCHMAKING_UNAVAILABLE',
            ),
          ),
        );
      },
    );
  });
}
