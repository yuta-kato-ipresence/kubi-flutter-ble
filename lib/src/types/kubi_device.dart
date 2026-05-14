import 'package:meta/meta.dart';

/// 接続対象の Kubi デバイスを識別する value object。
///
/// universal_ble の `BleDevice` (native handle) は `KubiBleImpl` 内部に閉じ、
/// 公開 API には公開しない (C1)。これにより:
/// - 利用者が誤って native API に依存することを防止
/// - テスト用 fake が universal_ble なしで `KubiDevice` を生成可能
/// - 別セッションで取得した `KubiDevice` を別 `KubiBleImpl` に渡すと `ArgumentError`
@immutable
final class KubiDevice {
  /// universal_ble の deviceId (BLE スタックが返す一意 ID、platform 依存形式)。
  final String id;

  /// 広告名。permission 不在時等で取得できない場合は `null`。
  final String? name;

  const KubiDevice({required this.id, this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KubiDevice && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'KubiDevice(id: $id, name: $name)';
}
