import 'package:diceup/data/online/game_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoomView.fromJson', () {
    test('parses a room with members', () {
      final room = RoomView.fromJson(<String, Object?>{
        'id': 'room-1',
        'code': 'K7Q2XA',
        'hostId': 'host-1',
        'maxPlayers': 4,
        'status': 'open',
        'rulesetVersion': '1.0.0',
        'source': 'manual',
        'members': [
          <String, Object?>{
            'userId': 'host-1',
            'username': 'ada',
            'displayName': 'Ada',
            'isReady': true,
            'isHost': true,
            'joinedAt': '2026-11-28T00:00:00.000Z',
          },
          <String, Object?>{
            'userId': 'guest-1',
            'username': 'ben',
            'displayName': 'Ben',
            'isReady': true,
            'isHost': false,
            'joinedAt': '2026-11-28T00:00:01.000Z',
          },
        ],
        'matchId': null,
      });
      expect(room.code, 'K7Q2XA');
      expect(room.members, hasLength(2));
      expect(room.members[0].displayName, 'Ada');
      expect(room.isOpen, isTrue);
      expect(room.matchId, isNull);
    });

    test('tolerates a missing members list', () {
      final room = RoomView.fromJson(<String, Object?>{
        'id': 'room-1',
        'code': 'K7Q2XA',
        'hostId': 'host-1',
        'maxPlayers': 2,
        'status': 'closed',
        'rulesetVersion': '1.0.0',
        'source': 'manual',
        'matchId': null,
      });
      expect(room.members, isEmpty);
      expect(room.isOpen, isFalse);
    });
  });

  group('RoomView.canStart / startBlocker (FR-47)', () {
    RoomView roomWith(List<RoomMember> members, {String hostId = 'host-1'}) =>
        RoomView(
          id: 'room-1',
          code: 'K7Q2XA',
          hostId: hostId,
          maxPlayers: 4,
          status: 'open',
          rulesetVersion: '1.0.0',
          source: 'manual',
          members: members,
          matchId: null,
        );

    const host = RoomMember(
      userId: 'host-1',
      username: 'ada',
      displayName: 'Ada',
      isReady: true,
      isHost: true,
      joinedAt: '',
    );
    const guest = RoomMember(
      userId: 'guest-1',
      username: 'ben',
      displayName: 'Ben',
      isReady: true,
      isHost: false,
      joinedAt: '',
    );

    test('startable when host + 2 present + all ready', () {
      final room = roomWith([host, guest]);
      expect(room.canStart('host-1'), isTrue);
      expect(room.startBlocker('host-1'), isNull);
    });

    test('blocked for a non-host', () {
      final room = roomWith([host, guest]);
      expect(room.canStart('guest-1'), isFalse);
      expect(room.startBlocker('guest-1'), 'notHost');
    });

    test('blocked with fewer than 2 players', () {
      final room = roomWith([host]);
      expect(room.canStart('host-1'), isFalse);
      expect(room.startBlocker('host-1'), 'needPlayers');
    });

    test('blocked when anyone is not ready', () {
      final room = roomWith([
        host,
        const RoomMember(
          userId: 'guest-1',
          username: 'ben',
          displayName: 'Ben',
          isReady: false,
          isHost: false,
          joinedAt: '',
        ),
      ]);
      expect(room.canStart('host-1'), isFalse);
      expect(room.startBlocker('host-1'), 'needReady');
    });

    test('blocked once the room has started', () {
      final room = RoomView(
        id: 'room-1',
        code: 'K7Q2XA',
        hostId: 'host-1',
        maxPlayers: 4,
        status: 'playing',
        rulesetVersion: '1.0.0',
        source: 'manual',
        members: [host, guest],
        matchId: 'match-1',
      );
      expect(room.canStart('host-1'), isFalse);
      expect(room.startBlocker('host-1'), 'started');
    });
  });

  group('MatchStarted / MatchmakingStatus parsing', () {
    test('parses seats in order', () {
      final started = MatchStarted.fromJson(<String, Object?>{
        'matchId': 'match-1',
        'roomId': 'room-1',
        'seats': [
          <String, Object?>{'userId': 'a', 'seat': 0, 'colour': 'red'},
          <String, Object?>{'userId': 'b', 'seat': 1, 'colour': 'green'},
        ],
        'rulesetVersion': '1.0.0',
      });
      expect(started.seats.map((s) => s.colour), ['red', 'green']);
    });

    test('parses queued / matched / idle status', () {
      const queued = MatchmakingStatus(
        status: 'queued',
        position: 2,
        queueSize: 3,
        groupSize: 4,
        roomId: null,
        roomCode: null,
      );
      expect(queued.isQueued, isTrue);
      expect(queued.isMatched, isFalse);
      final matched = MatchmakingStatus.fromJson(<String, Object?>{
        'status': 'matched',
        'queueSize': 0,
        'groupSize': 4,
        'roomId': 'room-1',
        'roomCode': 'K7Q2XA',
      });
      expect(matched.isMatched, isTrue);
      expect(matched.roomCode, 'K7Q2XA');
    });
  });
}
