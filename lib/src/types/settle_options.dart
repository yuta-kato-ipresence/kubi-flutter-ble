import 'package:meta/meta.dart';

import '../kubi_protocol.dart'
    show
        settleDefaultPollIntervalMs,
        settleDefaultToleranceLsb,
        settleDefaultTimeoutMs;

/// `moveTo` / `waitUntilSettled` の到達検出パラメータ。
///
/// 既定値は `settleDefault*` 定数 (B16、kubi-ble `KUBI_CONSTANTS.SETTLE_DEFAULTS` 由来)。
@immutable
final class SettleOptions {
  /// polling 間隔 (ms)。既定 [settleDefaultPollIntervalMs]。
  final int pollIntervalMs;

  /// 到達判定の許容差 (servo LSB 単位)。既定 [settleDefaultToleranceLsb]。
  final int toleranceLsb;

  /// タイムアウト (ms)。既定 [settleDefaultTimeoutMs]。
  /// 超過時は `BleSettleTimeoutError` を throw。
  final int timeoutMs;

  const SettleOptions({
    this.pollIntervalMs = settleDefaultPollIntervalMs,
    this.toleranceLsb = settleDefaultToleranceLsb,
    this.timeoutMs = settleDefaultTimeoutMs,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettleOptions &&
          other.pollIntervalMs == pollIntervalMs &&
          other.toleranceLsb == toleranceLsb &&
          other.timeoutMs == timeoutMs;

  @override
  int get hashCode => Object.hash(pollIntervalMs, toleranceLsb, timeoutMs);

  @override
  String toString() => 'SettleOptions(pollIntervalMs: $pollIntervalMs, '
      'toleranceLsb: $toleranceLsb, timeoutMs: $timeoutMs)';
}
