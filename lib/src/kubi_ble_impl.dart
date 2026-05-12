import 'kubi_ble.dart';
import 'types/kubi_device.dart';
import 'types/pan_tilt_angles.dart';
import 'types/move_result.dart';
import 'types/move_event.dart';

/// Implementation of [KubiBle] using universal_ble.
///
/// TODO: Implement all methods.
class KubiBleImpl implements KubiBle {
  KubiDevice? _device;
  BleConnectionState _connectionState = BleConnectionState.disconnected;

  @override
  Future<KubiDevice> requestDevice() async {
    throw UnimplementedError('requestDevice');
  }

  @override
  Future<void> connect(KubiDevice device) async {
    _device = device;
    _connectionState = BleConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    _connectionState = BleConnectionState.disconnected;
    _device = null;
  }

  @override
  void Function() onConnectionStateChange(
    void Function(BleConnectionState) listener,
  ) {
    throw UnimplementedError('onConnectionStateChange');
  }

  @override
  BleConnectionState get currentConnectionState => _connectionState;

  @override
  Future<MoveResult> moveTo({
    required double pan,
    required double tilt,
    double? speed,
  }) async {
    throw UnimplementedError('moveTo');
  }

  @override
  Future<void> setTarget({
    required double pan,
    required double tilt,
    double? speed,
  }) async {
    throw UnimplementedError('setTarget');
  }

  @override
  PanTiltAngles? getCommandedPosition() {
    throw UnimplementedError('getCommandedPosition');
  }

  @override
  Future<PanTiltAngles?> getActualPosition() async {
    throw UnimplementedError('getActualPosition');
  }

  @override
  Future<PanTiltAngles> waitUntilSettled({Duration? timeout}) async {
    throw UnimplementedError('waitUntilSettled');
  }

  @override
  void Function() subscribePosition(
    void Function(PanTiltAngles position) listener,
  ) {
    throw UnimplementedError('subscribePosition');
  }

  @override
  void Function() onMove(void Function(MoveEvent event) listener) {
    throw UnimplementedError('onMove');
  }

  @override
  void Function() onDebugEvent(void Function(String message) listener) {
    throw UnimplementedError('onDebugEvent');
  }

  @override
  set debugLogging(bool enabled) {
    throw UnimplementedError('debugLogging');
  }
}
