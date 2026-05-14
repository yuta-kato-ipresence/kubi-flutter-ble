import 'package:meta/meta.dart';

import 'ble_connection_state.dart';
import 'disconnect_reason.dart';

/// `connectionStateStream` で配信される接続状態イベント。
///
/// `reason` は `state` が `disconnected` / `disconnecting` のときのみ非 null
/// (それ以外は意味的に不要なため null)。
@immutable
final class ConnectionStateEvent {
  final BleConnectionState state;
  final DisconnectReason? reason;
  final DateTime timestamp;

  const ConnectionStateEvent({
    required this.state,
    required this.timestamp,
    this.reason,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionStateEvent &&
          other.state == state &&
          other.reason == reason &&
          other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(state, reason, timestamp);

  @override
  String toString() => 'ConnectionStateEvent(state: $state, reason: $reason, '
      'timestamp: $timestamp)';
}
