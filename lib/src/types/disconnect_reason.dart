/// 切断・接続失敗の理由 (kubi-ble v0.8 の `DisconnectReason` と完全 1:1)。
///
/// `ConnectionStateEvent.reason` として配信される。`state` が
/// `disconnected` / `disconnecting` のときのみ非 null。
enum DisconnectReason {
  /// `disconnect()` の明示呼び出しによる切断。
  user,

  /// `connect(timeout)` のタイムアウト。
  timeout,

  /// OS / universal_ble からの disconnect 通知 (gattserverdisconnected 等)。
  deviceLost,

  /// 接続中の例外 (BLE スタックエラー等)。
  error,

  /// 自動再接続のリトライ上限到達。
  reconnectExhausted,

  /// 後方互換のフォールバック (理由不明)。
  unknown,
}
