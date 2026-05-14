import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:meta/meta.dart';

/// `onDebugEvent` Stream で配信されるイベントの種別 (kubi-ble v0.8 と完全 1:1、11 値)。
enum BleDebugEventType {
  /// motorPosition characteristic の生 notify (register read 応答含む)。
  notificationRaw,

  /// register read 成功時。
  registerRead,

  /// register read タイムアウト時 (`BleRegisterReadTimeoutError` 配信前)。
  registerReadTimeout,

  /// `subscribePosition` の poll が GATT lock を取れず skip された。
  pollSkipped,

  /// 公開 Stream の listener が throw した (本体ループは継続、§5.3)。
  listenerError,

  /// connection state が遷移した (universal_ble onConnectionChange 由来含む)。
  connectionStateChange,

  /// 自動再接続: 次の attempt が schedule された。
  autoReconnectScheduled,

  /// 自動再接続: attempt 開始。
  autoReconnectAttempt,

  /// 自動再接続: 成功。
  autoReconnectSuccess,

  /// 自動再接続: attempt 失敗 (次があれば scheduled が続く)。
  autoReconnectFailed,

  /// 自動再接続: max retry 到達、abandoned。
  autoReconnectAbandoned,
}

/// `onDebugEvent` Stream で配信される observability イベント。
///
/// 利用例: `kubi.onDebugEvent.listen((e) => log.info(e))`
@immutable
final class BleDebugEvent {
  final BleDebugEventType type;
  final DateTime timestamp;

  /// 関連する GATT characteristic UUID (`notificationRaw` / `registerRead*` 等)。
  final String? characteristic;

  /// 生バイト列 (`notificationRaw` 等)。要素ごとの値同値で比較。
  final Uint8List? bytes;

  /// `bytes` の hex 表現 (デバッグログ可読性のため)。
  final String? hex;

  /// 任意のメッセージ (`listenerError` の例外 message 等)。
  final String? message;

  /// 構造化ペイロード (auto-reconnect attempt 番号、register addr 等)。
  /// 要素ごとの値同値で比較する (浅い比較)。
  final Map<String, Object?>? detail;

  const BleDebugEvent({
    required this.type,
    required this.timestamp,
    this.characteristic,
    this.bytes,
    this.hex,
    this.message,
    this.detail,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleDebugEvent &&
          other.type == type &&
          other.timestamp == timestamp &&
          other.characteristic == characteristic &&
          listEquals(other.bytes, bytes) &&
          other.hex == hex &&
          other.message == message &&
          mapEquals(other.detail, detail);

  @override
  int get hashCode => Object.hash(
        type,
        timestamp,
        characteristic,
        bytes == null ? null : Object.hashAll(bytes!),
        hex,
        message,
        detail == null
            ? null
            : Object.hashAllUnordered(
                detail!.entries.map((e) => Object.hash(e.key, e.value)),
              ),
      );

  @override
  String toString() =>
      'BleDebugEvent(type: $type, timestamp: $timestamp, '
      'characteristic: $characteristic, hex: $hex, message: $message, '
      'detail: $detail)';
}
