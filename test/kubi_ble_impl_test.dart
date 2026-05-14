import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubi_flutter_ble/kubi_flutter_ble.dart';
import 'package:kubi_flutter_ble/src/kubi_protocol.dart' as proto;
import 'package:universal_ble/universal_ble.dart' hide BleConnectionState;

import 'fake_universal_ble_platform.dart';

void main() {
  late FakeUniversalBlePlatform fake;
  late KubiBleImpl impl;

  setUp(() {
    fake = FakeUniversalBlePlatform();
    UniversalBle.setInstance(fake);
    impl = KubiBleImpl();
  });

  tearDown(() async {
    await impl.dispose();
  });

  group('scan', () {
    test('scan stream emits Kubi devices and dedupes by id', () async {
      final got = <KubiDevice>[];
      final stream = impl.scan();
      final sub = stream.listen(got.add);
      await Future<void>.delayed(Duration.zero);
      fake.emitScan(BleDevice(deviceId: 'A', name: 'kubi-1'));
      fake.emitScan(BleDevice(deviceId: 'A', name: 'kubi-1')); // dup
      fake.emitScan(BleDevice(deviceId: 'B', name: 'kubi-2'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(got.map((d) => d.id).toList(), <String>['A', 'B']);
    });
  });

  group('connect', () {
    test('connect transitions disconnected -> connecting -> connected', () async {
      final states = <BleConnectionState>[];
      final sub = impl.connectionStateStream.listen((e) => states.add(e.state));
      await impl.connect(const KubiDevice(id: 'X', name: 'kubi-x'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(states, containsAllInOrder(<BleConnectionState>[
        BleConnectionState.connecting,
        BleConnectionState.connected,
      ]));
      // motorPositionUuid に subscribe された
      expect(
        fake.subscribed.any((s) =>
            s.char.toLowerCase() == proto.motorPositionUuid.toLowerCase()),
        isTrue,
      );
    });

    test('connect failure surfaces BleConnectionError + disconnected', () async {
      fake.connectThrow = Exception('boom');
      await expectLater(
        impl.connect(const KubiDevice(id: 'X', name: 'kubi-x')),
        throwsA(isA<BleConnectionError>()),
      );
    });
  });

  group('register read', () {
    test('matching notify resolves; mismatched header is ignored', () async {
      await impl.connect(const KubiDevice(id: 'X', name: 'kubi-x'));

      // _readRegister(motorId=1, addr=regGoalPosition, byteWidth=2) を pan/tilt 1 回ずつ
      // getCommandedPosition が 2 回 _readRegister を呼ぶ。pan, tilt の順 (motorId=1, then 2)。
      final fut = impl.getCommandedPosition();
      // write が出るのを待つ
      await Future<void>.delayed(Duration.zero);
      // 1) mismatched header (motorId=2) → 無視
      fake.pushRegisterNotify(
        deviceId: 'X',
        motorPositionUuid: proto.motorPositionUuid,
        motorId: 2,
        addr: proto.regGoalPosition,
        payload: <int>[0xff, 0x01],
      );
      // 2) matching pan (motorId=1, addr=regGoalPosition)、val=512 → ~0deg
      fake.pushRegisterNotify(
        deviceId: 'X',
        motorPositionUuid: proto.motorPositionUuid,
        motorId: 1,
        addr: proto.regGoalPosition,
        payload: <int>[0x00, 0x02], // 512 little-endian
      );
      await Future<void>.delayed(Duration.zero);
      // tilt notify (motorId=2) — pan が解決した後に発射される
      fake.pushRegisterNotify(
        deviceId: 'X',
        motorPositionUuid: proto.motorPositionUuid,
        motorId: 2,
        addr: proto.regGoalPosition,
        payload: <int>[0x00, 0x02],
      );
      final ang = await fut;
      expect(ang.pan, closeTo(proto.valToAngle(512), 0.01));
      expect(ang.tilt, closeTo(proto.valToAngle(512), 0.01));
    });

    test('register read times out -> BleRegisterReadTimeoutError', () async {
      await impl.connect(const KubiDevice(id: 'X', name: 'kubi-x'));
      // notify を一切返さない
      await expectLater(
        impl.getCommandedPosition(),
        throwsA(isA<BleRegisterReadTimeoutError>()),
      );
    }, timeout: const Timeout(Duration(seconds: 5)));
  });

  group('moveTo write order', () {
    test('write sequence: tilt-config, pan-config, pan-target, tilt-target', () async {
      await impl.connect(const KubiDevice(id: 'X', name: 'kubi-x'));
      fake.writes.clear();

      // settle が getActualPosition を呼ぶたびに matching notify を返す。
      // pan=10 -> servoAngle, tilt=5 -> servoAngle。target に十分近い値を返せば
      // 1 回の poll で settle 完了 → write 4 本だけ確認。
      final tPan = proto.servoAngle(10);
      final tTilt = proto.servoAngle(5);
      late StreamSubscription<dynamic> sub;
      sub = impl.onDebugEvent.listen((_) {});
      // ハンドラ: register read write が出るたびに即 notify を返す。
      // _readRegister は regRead2ByteUuid に write してから notify を待つ。
      // writes に register read が積まれた瞬間に notify を push する単純 poller。
      var writeIdx = 0;
      Timer.periodic(const Duration(milliseconds: 1), (t) {
        while (writeIdx < fake.writes.length) {
          final w = fake.writes[writeIdx++];
          if (w.char == proto.regRead2ByteUuid.toLowerCase()) {
            // cmd payload[0] = motorId, payload[1] = addr
            final motorId = w.value[0];
            final addr = w.value[1];
            final val = (motorId == 1) ? tPan : tTilt;
            fake.pushRegisterNotify(
              deviceId: 'X',
              motorPositionUuid: proto.motorPositionUuid,
              motorId: motorId,
              addr: addr,
              payload: <int>[val & 0xff, (val >> 8) & 0xff],
            );
          }
        }
        if (t.tick > 2000) t.cancel();
      });

      await impl.moveTo(
        target: const PanTiltAngles(pan: 10, tilt: 5),
        settle: const SettleOptions(toleranceLsb: 5),
      );
      await sub.cancel();

      // 最初の 4 件は move sequence (config tilt, config pan, pan target, tilt target)
      final moveWrites = fake.writes
          .where((w) =>
              w.char == proto.panTiltConfigUuid.toLowerCase() ||
              w.char == proto.panUuid.toLowerCase() ||
              w.char == proto.tiltUuid.toLowerCase())
          .toList();
      expect(moveWrites.length, 4);
      expect(moveWrites[0].char, proto.panTiltConfigUuid.toLowerCase());
      expect(moveWrites[0].value[0], 2); // tilt config first
      expect(moveWrites[1].char, proto.panTiltConfigUuid.toLowerCase());
      expect(moveWrites[1].value[0], 1); // pan config second
      expect(moveWrites[2].char, proto.panUuid.toLowerCase());
      expect(moveWrites[3].char, proto.tiltUuid.toLowerCase());
    });
  });

  group('availability lost', () {
    test('poweredOff while connected -> deviceLost emit', () async {
      await impl.connect(const KubiDevice(id: 'X', name: 'kubi-x'));
      final events = <ConnectionStateEvent>[];
      final sub = impl.connectionStateStream.listen(events.add);
      fake.emitAvailability(AvailabilityState.poweredOff);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(
        events.any((e) =>
            e.state == BleConnectionState.disconnected &&
            e.reason == DisconnectReason.deviceLost),
        isTrue,
      );
    });
  });
}
