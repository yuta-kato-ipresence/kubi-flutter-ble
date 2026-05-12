import 'types/kubi_device.dart';
import 'types/pan_tilt_angles.dart';
import 'types/move_result.dart';
import 'types/move_event.dart';

/// Abstract interface for Kubi BLE operations.
///
/// Design pillars (from TS v1.3 §1.2):
/// - **Write (command)**: [moveTo] / [setTarget]
/// - **Read (observe)**: [getCommandedPosition] / [getActualPosition] / [waitUntilSettled] / [subscribePosition]
/// - **Events**: [onMove] (4 phases) / [onConnectionStateChange] / [onDebugEvent]
abstract interface class KubiBle {
  // ================================================================
  // Connection layer
  // ================================================================

  /// Request a BLE device from the browser/system picker.
  ///
  /// Throws [BleUnavailableError] if BLE is not supported.
  /// Throws [BleUserCancelledError] if user cancels the dialog.
  Future<KubiDevice> requestDevice();

  /// Connect to the given [device].
  ///
  /// Throws [BleConnectionError] on timeout or failure.
  Future<void> connect(KubiDevice device);

  /// Disconnect from the current device.
  Future<void> disconnect();

  /// Subscribe to connection state changes.
  ///
  /// Returns an unsubscribe function.
  void Function() onConnectionStateChange(
    void Function(BleConnectionState) listener,
  );

  /// Current connection state.
  BleConnectionState get currentConnectionState;

  // ================================================================
  // Movement layer
  // ================================================================

  /// Move to the specified angles, awaiting physical arrival.
  ///
  /// If a newer [moveTo] or [setTarget] is called while pending,
  /// the previous future resolves to [MoveResultCancelled].
  Future<MoveResult> moveTo({
    required double pan,
    required double tilt,
    double? speed,
  });

  /// Fire-and-forget movement (for joystick-like rapid updates).
  ///
  /// Latest value buffer: if called while a GATT write is in progress,
  /// the latest target is deferred and written after the current one.
  Future<void> setTarget({
    required double pan,
    required double tilt,
    double? speed,
  });

  /// Get the last commanded position (from internal buffer).
  PanTiltAngles? getCommandedPosition();

  /// Get the actual physical position (from register read).
  Future<PanTiltAngles?> getActualPosition();

  /// Wait until the device physically arrives at the commanded position.
  ///
  /// Throws [BleSettleTimeoutError] if [timeout] is exceeded.
  Future<PanTiltAngles> waitUntilSettled({Duration? timeout});

  /// Subscribe to position updates.
  ///
  /// Returns an unsubscribe function.
  void Function() subscribePosition(
    void Function(PanTiltAngles position) listener,
  );

  // ================================================================
  // Events
  // ================================================================

  /// Subscribe to 4-phase move events.
  ///
  /// Returns an unsubscribe function.
  void Function() onMove(void Function(MoveEvent event) listener);

  /// Subscribe to debug events.
  ///
  /// Returns an unsubscribe function.
  void Function() onDebugEvent(void Function(String message) listener);

  /// Enable/disable debug logging.
  set debugLogging(bool enabled);
}

/// BLE connection state.
enum BleConnectionState { disconnected, connecting, connected, disconnecting }
