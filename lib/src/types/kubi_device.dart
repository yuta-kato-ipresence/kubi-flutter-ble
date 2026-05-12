import 'package:universal_ble/universal_ble.dart';

/// Wrapper around universal_ble's BleDevice for Kubi-specific metadata.
final class KubiDevice {
  final String deviceId;
  final String? name;
  final bool isSystemDevice;
  final BleDevice _nativeDevice;

  const KubiDevice({
    required this.deviceId,
    this.name,
    this.isSystemDevice = false,
    required BleDevice nativeDevice,
  }) : _nativeDevice = nativeDevice;

  BleDevice get nativeDevice => _nativeDevice;

  @override
  String toString() => 'KubiDevice(id: $deviceId, name: $name)';
}
