import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { CreateRoomDto, JoinRoomDto } from '../../src/rooms/dto/rooms.dto';
import {
  MatchStartDto,
  RoomJoinDto,
  RoomLeaveDto,
  RoomReadyDto,
} from '../../src/socket/dto/room.dto';

async function errorsOf<T extends object>(
  cls: new () => T,
  plain: Record<string, unknown>,
): Promise<string[]> {
  const instance = plainToInstance(cls, plain);
  const errors = await validate(instance);
  return errors.flatMap((e) => Object.values(e.constraints ?? {}));
}

async function propsOf<T extends object>(
  cls: new () => T,
  plain: Record<string, unknown>,
): Promise<string[]> {
  const instance = plainToInstance(cls, plain);
  const errors = await validate(instance);
  return errors.map((e) => e.property).sort();
}

/**
 * Room + socket DTO validation (plan §10.2 pattern): the global
 * ValidationPipe enforces these at the boundary; the matrix pins
 * the accepted/rejected shapes so a later edit cannot silently
 * widen them (e.g. a 5-player room, or a lowercase code slipping
 * through unnormalised).
 */
describe('rooms DTO validation', () => {
  describe('CreateRoomDto', () => {
    it('accepts limits 2–4', async () => {
      for (const maxPlayers of [2, 3, 4]) {
        expect(await errorsOf(CreateRoomDto, { maxPlayers })).toEqual([]);
      }
    });

    it('rejects limits outside 2–4 and non-integers', async () => {
      expect(await propsOf(CreateRoomDto, { maxPlayers: 1 })).toEqual([
        'maxPlayers',
      ]);
      expect(await propsOf(CreateRoomDto, { maxPlayers: 5 })).toEqual([
        'maxPlayers',
      ]);
      expect(await propsOf(CreateRoomDto, { maxPlayers: 2.5 })).toEqual([
        'maxPlayers',
      ]);
      expect(await propsOf(CreateRoomDto, {})).toEqual(['maxPlayers']);
    });
  });

  describe('JoinRoomDto', () => {
    it('accepts a well-formed code and normalises it to upper-case', async () => {
      expect(await errorsOf(JoinRoomDto, { code: 'K7Q2XA' })).toEqual([]);
      const dto = plainToInstance(JoinRoomDto, { code: '  k7q2xa ' });
      await validate(dto);
      expect(dto.code).toBe('K7Q2XA');
    });

    it('rejects confusable / short / long / missing codes', async () => {
      for (const code of ['K7Q2XI', 'K7Q2X0', 'K7Q2X1', 'K7Q2X', 'K7Q2XAA']) {
        expect(await propsOf(JoinRoomDto, { code })).toEqual(['code']);
      }
      expect(await propsOf(JoinRoomDto, {})).toEqual(['code']);
    });
  });

  describe('socket room DTOs', () => {
    it('RoomJoinDto accepts a code', async () => {
      expect(await errorsOf(RoomJoinDto, { roomCode: 'K7Q2XA' })).toEqual([]);
      expect(await propsOf(RoomJoinDto, { roomCode: 'BAD!' })).toEqual([
        'roomCode',
      ]);
    });

    it('RoomLeaveDto / RoomReadyDto / MatchStartDto require a UUID roomId', async () => {
      const id = '3f7a2c10-9c4e-4b1a-8e2d-1a2b3c4d5e6f';
      expect(await errorsOf(RoomLeaveDto, { roomId: id })).toEqual([]);
      expect(await errorsOf(RoomReadyDto, { roomId: id, ready: true })).toEqual(
        [],
      );
      expect(await errorsOf(MatchStartDto, { roomId: id })).toEqual([]);
      expect(await propsOf(RoomLeaveDto, { roomId: 'not-a-uuid' })).toEqual([
        'roomId',
      ]);
      expect(await propsOf(RoomReadyDto, { roomId: id, ready: 'yes' })).toEqual(
        ['ready'],
      );
    });
  });
});
