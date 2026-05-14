/// Kubi BLE protocol constants and pure functions.
///
/// 全シンボルは top-level (class でラップしない、設計書 §3.8)。
/// `lib/kubi_flutter_ble.dart` から export しないことで **package-private** を実現する。
/// 利用者がプロトコル直叩きすべきユースケースは想定しない。
///
/// 一次ソース:
/// - kubi-ble (TS) `src/constants.ts` / `src/web-kubi-ble.ts:28-86`
/// - kubi-ble/docs/servo-spec.md §2.2 / §3.3 / §6 / §8.2
library;

import 'dart:typed_data';

import 'types/pan_tilt_angles.dart';
import 'types/position_source.dart';

// =====================================================================
// GATT UUIDs (servo-spec.md §2.2 / kubi-ble constants.ts と完全一致)
// =====================================================================

/// Kubi servo service (唯一の primary service)。
const String servoServiceUuid = '2a001800-2803-2801-2800-1d9ff2d5c442';

/// PAN/TILT 共用 register write 2 byte (軸設定 / 速度書き込み)。
/// byte[0] で軸を指定: 0x01 = pan, 0x02 = tilt。
const String panTiltConfigUuid = '00009142-0000-1000-8000-00805f9b34fb';

/// register read 1 byte コマンド入口。
const String regRead1ByteUuid = '00009143-0000-1000-8000-00805f9b34fb';

/// register read 2 byte コマンド入口。
const String regRead2ByteUuid = '00009144-0000-1000-8000-00805f9b34fb';

/// Pan 目標角度 (Big Endian 2 byte、サーボ値 0〜1023)。
const String panUuid = '00009145-0000-1000-8000-00805f9b34fb';

/// Tilt 目標角度 (Big Endian 2 byte、サーボ値 0〜1023)。
const String tiltUuid = '00009146-0000-1000-8000-00805f9b34fb';

/// モーター現在位置通知 (Subscribe 必須)。
/// register read の応答 notify もこの characteristic 経由 (servo-spec.md §4)。
const String motorPositionUuid = '00009147-0000-1000-8000-00805f9b34fb';

// =====================================================================
// Dynamixel AX-12 互換 register アドレス (servo-spec.md §4.2)
// =====================================================================

/// Goal Position register アドレス (コマンドされた目標値、書いた writtenVal がそのままエコー)。
const int regGoalPosition = 0x1e;

/// Present Position register アドレス (物理的な現在位置、servo encoder の実測値)。
const int regPresentPosition = 0x24;

// =====================================================================
// 軸範囲 (servo-spec.md §3.3、実機検証済 ±150° / -20°〜+40°)
// =====================================================================

const double panMin = -150.0;
const double panMax = 150.0;
const double tiltMin = -20.0;
const double tiltMax = 40.0;

// =====================================================================
// 速度範囲 (B4/A6、TS clampSpeed と等価)
//
// servo-spec.md §8.2 で `0` は「無限速」の特殊値として予約されているため、
// ユーザー API では `1` を下限とする。
// =====================================================================

const int defaultMoveSpeed = 100;
const int minMoveSpeed = 1;
const int maxMoveSpeed = 100;

// =====================================================================
// 軸フラグ
// =====================================================================

const int servoFlagPan = 0x01;
const int servoFlagTilt = 0x02;
const int defaultServoFlag = 0x20;

// =====================================================================
// timing 既定値 (B16、TS KUBI_CONSTANTS.SETTLE_DEFAULTS / SUBSCRIBE_DEFAULTS と完全一致)
// =====================================================================

/// `waitUntilSettled` / `SettleOptions` の polling 間隔既定 (ms)。
const int settleDefaultPollIntervalMs = 80;

/// `waitUntilSettled` / `SettleOptions` の許容差既定 (servo LSB 単位)。
///
/// HW デッドバンド ±2-6 LSB に backlash 観測値のマージンを加えた値。
/// kubi-ble v0.7.1 で 7 → 10 に更新 (C2 hysteresis 実機計測由来)。
const int settleDefaultToleranceLsb = 10;

/// `waitUntilSettled` / `SettleOptions` のタイムアウト既定 (ms)。
const int settleDefaultTimeoutMs = 4000;

/// `subscribePosition` の polling 間隔既定 (ms)。
/// 50 未満は内部で 50 にクランプ (kubi-ble 互換)。
const int subscribeDefaultIntervalMs = 250;

/// `subscribePosition` polling 間隔の最小値 (ms)。
const int subscribeMinIntervalMs = 50;

/// `subscribePosition` の観測対象既定。
///
/// kubi-ble v0.8 と整合 (commanded position を既定で配信)。
const PositionSource subscribeDefaultSource = PositionSource.commanded;

/// `_readRegister` のタイムアウト既定 (ms)。
const int readRegisterDefaultTimeoutMs = 500;

/// GATT 接続のタイムアウト既定 (ms)。
const int connectionTimeoutMs = 3000;

/// Web Bluetooth `requestDevice` の name prefix filter。
/// 大文字小文字区別あり (実機例: `kubi000012AB01`)。
const String deviceNamePrefix = 'kubi';

// =====================================================================
// 速度補正テーブル (B6、kubi-ble issue #12 実機測定由来)
//
// `MoveSpec.synced` 時の `_resolveSpeeds` で必須。
// **更新時は kubi-ble `web-kubi-ble.ts:28-86` と同期すること**。
// =====================================================================

/// Pan 軸: speed 値 (1〜100) → 実測角速度 (°/s) のマッピング (線形近似)。
const Map<int, double> panVelocityTable = {
  100: 30.98,
  80: 26.00,
  50: 18.83,
  30: 12.99,
  20: 10.43,
  10: 5.68,
};

/// Tilt 軸: speed 値 (1〜100) → 実測角速度 (°/s) のマッピング (線形近似)。
const Map<int, double> tiltVelocityTable = {
  100: 12.80,
  80: 12.80,
  50: 8.88,
  30: 7.63,
  20: 8.01,
  10: 4.92,
};

// =====================================================================
// 角度・サーボ値変換 (servo-spec.md §3.3、kubi-ble servoAngle と完全一致)
// =====================================================================

/// `pan` を [panMin], [panMax] にクランプ。
double clampPan(double deg) =>
    deg < panMin ? panMin : (deg > panMax ? panMax : deg);

/// `tilt` を [tiltMin], [tiltMax] にクランプ。
double clampTilt(double deg) =>
    deg < tiltMin ? tiltMin : (deg > tiltMax ? tiltMax : deg);

/// `pan`/`tilt` を同時にクランプ。
PanTiltAngles clampPanTilt(double pan, double tilt) =>
    PanTiltAngles(pan: clampPan(pan), tilt: clampTilt(tilt));

/// 角度 (degrees) → サーボ値 (0-1023)。
///
/// 数式: `round((angle + 150) * 1023 / 300)`、0° → 512。
/// 軸非依存に [-150, 150] でクランプする (kubi-ble v0.8 と完全一致)。
/// 軸範囲外のクランプは呼び出し側 ([clampPan] / [clampTilt]) で先に行うこと。
int servoAngle(double deg) {
  final clamped = deg < -150.0 ? -150.0 : (deg > 150.0 ? 150.0 : deg);
  final val = ((clamped + 150.0) * 1023.0 / 300.0).round();
  return val < 0 ? 0 : (val > 1023 ? 1023 : val);
}

/// サーボ値 (0-1023) → 角度 (degrees)。
double valToAngle(int val) => (val * 300.0) / 1023.0 - 150.0;

// =====================================================================
// 速度変換
// =====================================================================

/// `speed` を [minMoveSpeed], [maxMoveSpeed] にクランプ。
/// `null` の場合は [defaultMoveSpeed] を返す。
int clampSpeed(int? speed) {
  if (speed == null) return defaultMoveSpeed;
  if (speed < minMoveSpeed) return minMoveSpeed;
  if (speed > maxMoveSpeed) return maxMoveSpeed;
  return speed;
}

// =====================================================================
// 速度補正テーブル変換 (B6、kubi-ble getVelocity / panVelocity / tiltSpeedFromVelocity と完全一致)
// =====================================================================

/// テーブル参照 + 端点クランプ + 線形補間で角速度 (°/s) を求める。
double getVelocity(Map<int, double> table, int speed) {
  final speeds = table.keys.toList()..sort();
  if (speed <= speeds.first) return table[speeds.first]!;
  if (speed >= speeds.last) return table[speeds.last]!;
  for (var i = 0; i < speeds.length - 1; i++) {
    final s1 = speeds[i];
    final s2 = speeds[i + 1];
    if (speed >= s1 && speed <= s2) {
      final t = (speed - s1) / (s2 - s1);
      return table[s1]! + t * (table[s2]! - table[s1]!);
    }
  }
  return table[speeds.first]!;
}

/// Pan 軸: speed (1〜100) → 角速度 (°/s)。
double panVelocity(int speed) => getVelocity(panVelocityTable, speed);

/// Tilt 軸: 角速度 (°/s) → 速度 (1〜100、線形補間の逆関数)。
int tiltSpeedFromVelocity(double targetVel) {
  final speeds = tiltVelocityTable.keys.toList()..sort();
  if (targetVel <= tiltVelocityTable[speeds.first]!) return speeds.first;
  if (targetVel >= tiltVelocityTable[speeds.last]!) return speeds.last;
  for (var i = 0; i < speeds.length - 1; i++) {
    final s1 = speeds[i];
    final s2 = speeds[i + 1];
    final v1 = tiltVelocityTable[s1]!;
    final v2 = tiltVelocityTable[s2]!;
    if (targetVel >= v1 && targetVel <= v2) {
      final t = (targetVel - v1) / (v2 - v1);
      return (s1 + t * (s2 - s1)).round();
    }
  }
  return speeds.first;
}

// =====================================================================
// payload builders
// =====================================================================

/// 軸 config payload を組み立てる: `[axisFlag, servoFlag, speedLo, speedHi]`。
Uint8List buildAxisConfigPayload({
  required int axisFlag,
  required int servoFlag,
  required int axisSpeed,
}) {
  return Uint8List.fromList([
    axisFlag & 0xff,
    servoFlag & 0xff,
    axisSpeed & 0xff,
    (axisSpeed >> 8) & 0xff,
  ]);
}

/// 軸目標 payload を組み立てる (Big Endian): `[valueHi, valueLo]`。
Uint8List buildAxisPayload(int value) =>
    Uint8List.fromList([(value >> 8) & 0xff, value & 0xff]);

/// register read コマンドを組み立てる: `[motorId, addr]`。
Uint8List encodeRegisterReadCmd(int motorId, int addr) =>
    Uint8List.fromList([motorId & 0xff, addr & 0xff]);

/// register read 応答 notify の bytes を整数値として復号する。
///
/// `byteWidth == 1`: bytes[0] をそのまま返す。
/// `byteWidth == 2`: little-endian 2 byte (`bytes[1] << 8 | bytes[0]`) を返す。
///
/// 不正長の場合は `null` を返す (Phase 3 で `_readRegister` 側がこの戻り値を
/// `BleCommandError` に変換する想定)。
int? parseRegisterReadResponse(List<int> bytes, int byteWidth) {
  if (byteWidth == 1) {
    if (bytes.isEmpty) return null;
    return bytes[0] & 0xff;
  }
  if (byteWidth == 2) {
    if (bytes.length < 2) return null;
    return (bytes[0] & 0xff) | ((bytes[1] & 0xff) << 8);
  }
  return null;
}

// NOTE: 旧 `parsePosition(List<int>)` は誤実装 (motorPositionUuid notify は
// register read 応答 frame であり、生の pan/tilt 値ではない) のため削除。
// position 取得は Phase 3 で `_readRegister(motorId, regGoalPosition or regPresentPosition, 2)`
// + `parseRegisterReadResponse` で実装する。
