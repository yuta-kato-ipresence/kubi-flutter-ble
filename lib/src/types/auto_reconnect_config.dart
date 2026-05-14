import 'package:meta/meta.dart';

/// 自動再接続の設定 (B3)。
///
/// `KubiBleImpl({autoReconnect: ...})` で初期設定可能、
/// `KubiBle.setAutoReconnect(AutoReconnectConfig?)` で動的変更可能 (`null` で無効化)。
///
/// バックオフは **線形**: 各 attempt の待機時間 = `retryDelay × attempt` (1-based)。
/// 例: `retryDelay = 1500ms` → 1.5s, 3.0s, 4.5s, ...
@immutable
final class AutoReconnectConfig {
  /// 最大リトライ回数。超過時 `DisconnectReason.reconnectExhausted` で abandon。
  final int maxRetries;

  /// 線形バックオフの単位遅延。
  final Duration retryDelay;

  const AutoReconnectConfig({
    this.maxRetries = 3,
    this.retryDelay = const Duration(milliseconds: 1500),
  })  : assert(maxRetries >= 0, 'maxRetries must be >= 0'),
        assert(retryDelay > Duration.zero, 'retryDelay must be > 0');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoReconnectConfig &&
          other.maxRetries == maxRetries &&
          other.retryDelay == retryDelay;

  @override
  int get hashCode => Object.hash(maxRetries, retryDelay);

  @override
  String toString() =>
      'AutoReconnectConfig(maxRetries: $maxRetries, retryDelay: $retryDelay)';
}
