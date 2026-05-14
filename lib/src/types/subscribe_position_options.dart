import 'package:meta/meta.dart';

import '../kubi_protocol.dart'
    show
        subscribeDefaultIntervalMs,
        subscribeDefaultSource,
        subscribeMinIntervalMs;
import 'position_source.dart';

/// `subscribePosition` の購読パラメータ。
///
/// 既定値は `subscribeDefault*` 定数 (B16、kubi-ble `KUBI_CONSTANTS.SUBSCRIBE_DEFAULTS` 由来)。
@immutable
final class SubscribePositionOptions {
  /// polling 間隔 (ms)。既定 [subscribeDefaultIntervalMs] (= 250)。
  ///
  /// [subscribeMinIntervalMs] (= 50ms) 未満が指定された場合、
  /// `KubiBleImpl` 内部で 50ms にクランプする (例外は throw しない)。
  final int intervalMs;

  /// 観測対象。既定 [subscribeDefaultSource] (= [PositionSource.commanded])。
  final PositionSource source;

  const SubscribePositionOptions({
    this.intervalMs = subscribeDefaultIntervalMs,
    this.source = subscribeDefaultSource,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscribePositionOptions &&
          other.intervalMs == intervalMs &&
          other.source == source;

  @override
  int get hashCode => Object.hash(intervalMs, source);

  @override
  String toString() =>
      'SubscribePositionOptions(intervalMs: $intervalMs, source: $source)';
}
