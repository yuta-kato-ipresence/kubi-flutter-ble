import 'dart:typed_data';
import 'types/pan_tilt_angles.dart';

/// BLE protocol constants and pure functions for Kubi devices.
///
/// All functions are side-effect free.
class KubiProtocol {
  KubiProtocol._();

  // ================================================================
  // Constants
  // ================================================================

  static const String kubiServiceUuid = '0000e001-0000-1000-8000-00805f9b34fb';
  static const String servoServiceUuid = '2a001800-2803-2801-2800-1d9ff2d5c442';
  static const String ledUuid = '0000e002-0000-1000-8000-00805f9b34fb';
  static const String panTiltConfigUuid =
      '00009142-0000-1000-8000-00805f9b34fb';
  static const String panUuid = '00009143-0000-1000-8000-00805f9b34fb';
  static const String tiltUuid = '00009144-0000-1000-8000-00805f9b34fb';
  static const String motorPositionUuid =
      '00009145-0000-1000-8000-00805f9b34fb';

  static const double panMin = -150.0;
  static const double panMax = 150.0;
  static const double tiltMin = -20.0;
  static const double tiltMax = 40.0;

  static const int defaultMoveSpeed = 100;
  static const double defaultSpeed = 52.3;
  static const double maxSpeed = 100.0;

  static const int servoFlagPan = 0x01;
  static const int servoFlagTilt = 0x02;
  static const int defaultServoFlag = 0x20;

  static const int connectionTimeoutMs = 3000;

  // ================================================================
  // Angle conversions
  // ================================================================

  /// Clamp pan to [panMin, panMax].
  static double clampPan(double deg) {
    return panMin > deg
        ? panMin
        : panMax < deg
        ? panMax
        : deg;
  }

  /// Clamp tilt to [tiltMin, tiltMax].
  static double clampTilt(double deg) {
    return tiltMin > deg
        ? tiltMin
        : tiltMax < deg
        ? tiltMax
        : deg;
  }

  /// Clamp both pan and tilt.
  static PanTiltAngles clampPanTilt(double pan, double tilt) {
    return PanTiltAngles(pan: clampPan(pan), tilt: clampTilt(tilt));
  }

  /// Convert angle (degrees) to servo value (0-1023).
  ///
  /// Formula: round((angle + 150) * 1023 / 300)
  /// 0° -> 512
  static int servoAngle(double deg) {
    final clamped = clampPan(deg);
    final shifted = clamped + 150.0;
    final val = (shifted * 1023.0 / 300.0).round();
    return val < 0
        ? 0
        : val > 1023
        ? 1023
        : val;
  }

  /// Convert servo value (0-1023) back to angle (degrees).
  static double valToAngle(int val) {
    return (val * 300.0) / 1023.0 - 150.0;
  }

  // ================================================================
  // Speed conversions
  // ================================================================

  /// Clamp speed to [1, 100].
  static int clampSpeed(double? speed) {
    if (speed == null) return defaultMoveSpeed;
    final rounded = speed.round();
    return rounded < 1
        ? 1
        : rounded > 100
        ? 100
        : rounded;
  }

  // ================================================================
  // Payload builders
  // ================================================================

  /// Build axis config payload: [axisFlag, servoFlag, speedLo, speedHi].
  static Uint8List buildAxisConfigPayload({
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

  /// Build axis goal payload (big-endian): [valueHi, valueLo].
  static Uint8List buildAxisPayload(int value) {
    return Uint8List.fromList([(value >> 8) & 0xff, value & 0xff]);
  }

  /// Parse position data from BLE notify.
  ///
  /// Returns null if data is invalid.
  static PanTiltAngles? parsePosition(List<int> data) {
    if (data.length < 4) return null;
    // Assuming big-endian 16-bit values for pan and tilt
    final panRaw = (data[0] << 8) | data[1];
    final tiltRaw = (data[2] << 8) | data[3];
    return PanTiltAngles(pan: valToAngle(panRaw), tilt: valToAngle(tiltRaw));
  }

  /// Encode register read command: [motorId, addr].
  static Uint8List encodeRegisterReadCmd(int motorId, int addr) {
    return Uint8List.fromList([motorId & 0xff, addr & 0xff]);
  }
}
