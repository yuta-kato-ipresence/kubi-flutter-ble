/// BLE 接続状態 (4 値)。
///
/// 状態遷移:
/// `disconnected → connecting → connected → disconnecting → disconnected`
///
/// 失敗時の追加情報は `ConnectionStateEvent.reason` (`DisconnectReason`) で配信される。
enum BleConnectionState { disconnected, connecting, connected, disconnecting }
