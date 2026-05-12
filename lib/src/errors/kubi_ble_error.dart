import '../types/pan_tilt_angles.dart';

/// Base exception for all Kubi BLE errors.
sealed class KubiBleError implements Exception {
  final String message;

  const KubiBleError(this.message);

  @override
  String toString() => 'KubiBleError: $message';
}

/// BLE is unavailable or unsupported on this platform/browser.
class BleUnavailableError extends KubiBleError {
  const BleUnavailableError(super.message);
}

/// User cancelled the device selection dialog.
class BleUserCancelledError extends KubiBleError {
  const BleUserCancelledError() : super('User cancelled device selection');
}

/// Connection failed or timed out.
class BleConnectionError extends KubiBleError {
  const BleConnectionError(super.message);
}

/// Device is not connected.
class BleNotConnectedError extends KubiBleError {
  const BleNotConnectedError() : super('Device is not connected');
}

/// Command failed (write/read error).
class BleCommandError extends KubiBleError {
  const BleCommandError(super.message);
}

/// Physical arrival (settle) timed out.
class BleSettleTimeoutError extends KubiBleError {
  final PanTiltAngles? lastObserved;

  const BleSettleTimeoutError({this.lastObserved}) : super('Settle timed out');
}

/// Register read timed out.
class BleRegisterReadTimeoutError extends KubiBleError {
  const BleRegisterReadTimeoutError() : super('Register read timed out');
}
