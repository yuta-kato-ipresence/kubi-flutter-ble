import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// `UniversalBlePlatform` テスト用 fake。
///
/// - 必要な抽象メソッドのみ最小実装。
/// - `connect`/`disconnect` は呼出時に `updateConnection` で stream 通知も発火。
/// - `writeValue` は `writes` に逐次記録 (順序検証用)。
/// - `pushNotification` ヘルパで notify をテストから明示的に発火。
class FakeUniversalBlePlatform extends UniversalBlePlatform {
  AvailabilityState availability = AvailabilityState.poweredOn;

  /// `(deviceId, service, characteristic, value)` を全 write 順に記録。
  final List<({String deviceId, String service, String char, Uint8List value})>
      writes = [];

  /// `setNotifiable` の呼出履歴。
  final List<({String deviceId, String service, String char, BleInputProperty prop})>
      subscribed = [];

  /// `connect` で例外を投げたい場合に設定。
  Object? connectThrow;

  /// `getSystemDevices(withServices)` の戻り値。
  List<BleDevice> systemDevicesReturn = const [];

  /// `discoverServices` の戻り値 (テストで service 構造を要求する場合用)。
  List<BleService> discoverReturn = const [];

  /// scan されたデバイス。`emitScan` で push。
  void emitScan(BleDevice dev) => updateScanResult(dev);

  void emitAvailability(AvailabilityState state) {
    availability = state;
    updateAvailability(state);
  }

  /// `(motorId, addr, payload)` を notify として `motorPositionUuid` に発火。
  void pushRegisterNotify({
    required String deviceId,
    required String motorPositionUuid,
    required int motorId,
    required int addr,
    required List<int> payload,
  }) {
    final bytes = Uint8List.fromList(<int>[motorId, addr, ...payload]);
    updateCharacteristicValue(deviceId, motorPositionUuid, bytes, null);
  }

  // -------- abstract method 実装 --------

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async => availability;

  @override
  Future<bool> enableBluetooth() async => true;

  @override
  Future<bool> disableBluetooth() async => true;

  @override
  Future<void> startScan({ScanFilter? scanFilter, PlatformConfig? platformConfig}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> isScanning() async => false;

  @override
  Future<void> connect(String deviceId,
      {Duration? connectionTimeout, bool autoConnect = false}) async {
    if (connectThrow != null) throw connectThrow!;
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    updateConnection(deviceId, false);
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId, bool withDescriptors) async =>
      discoverReturn;

  @override
  Future<void> setNotifiable(String deviceId, String service, String characteristic,
      BleInputProperty bleInputProperty) async {
    subscribed.add((
      deviceId: deviceId,
      service: service,
      char: characteristic,
      prop: bleInputProperty,
    ));
  }

  @override
  Future<Uint8List> readValue(String deviceId, String service, String characteristic,
          {Duration? timeout}) async =>
      Uint8List(0);

  @override
  Future<void> writeValue(String deviceId, String service, String characteristic,
      Uint8List value, BleOutputProperty bleOutputProperty) async {
    writes.add((
      deviceId: deviceId,
      service: service,
      char: characteristic.toLowerCase(),
      value: Uint8List.fromList(value),
    ));
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async => expectedMtu;

  @override
  Future<int> readRssi(String deviceId) async => -50;

  @override
  Future<bool> isPaired(String deviceId) async => false;

  @override
  Future<bool> pair(String deviceId) async => true;

  @override
  Future<void> unpair(String deviceId) async {}

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      BleConnectionState.connected;

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) async =>
      systemDevicesReturn;
}
