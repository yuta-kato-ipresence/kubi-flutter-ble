import 'dart:async';

/// 操作を外部からキャンセルするための token (Web の `AbortSignal` 相当の最小実装)。
///
/// 使用例:
/// ```dart
/// final cancel = CancelToken();
/// final future = kubi.moveTo(target: ..., cancel: cancel);
/// // ... 後でキャンセル
/// cancel.cancel();
/// final result = await future; // MoveResultCancelled
/// ```
///
/// 内部は `Completer<void>` の薄いラッパー。一度キャンセルされた token を再利用しないこと。
final class CancelToken {
  final Completer<void> _completer = Completer<void>();

  /// キャンセル済みかどうか (同期取得)。
  bool get isCancelled => _completer.isCompleted;

  /// キャンセルされたら complete する Future (await 可能、race 用)。
  Future<void> get whenCancelled => _completer.future;

  /// キャンセルを発火する。冪等 (既にキャンセル済の場合は no-op)。
  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}
