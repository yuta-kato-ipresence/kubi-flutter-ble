/// OS BLE adapter の可用性 (universal_ble の `AvailabilityState` を rewrap、6 値)。
///
/// 外部依存型 (`AvailabilityState`) を公開 API に漏らさないため、enum を再定義する。
/// 値は universal_ble v1.2.0 と完全 1:1 (順序も同じ)。
enum BleAvailability {
  /// 状態取得前 / 不明。
  unknown,

  /// adapter リセット中。
  resetting,

  /// この platform で BLE がサポートされていない (Web の一部ブラウザ等)。
  unsupported,

  /// 権限が拒否されている。
  unauthorized,

  /// Bluetooth が OFF。
  poweredOff,

  /// Bluetooth が利用可能。
  poweredOn,
}
