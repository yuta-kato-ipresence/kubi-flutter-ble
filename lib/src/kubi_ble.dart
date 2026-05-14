import 'package:flutter/foundation.dart' show ValueListenable;

import 'errors/kubi_ble_error.dart';
import 'types/auto_reconnect_config.dart';
import 'types/ble_availability.dart';
import 'types/ble_connection_state.dart';
import 'types/ble_debug_event.dart';
import 'types/cancel_token.dart';
import 'types/connection_state_event.dart';
import 'types/kubi_device.dart';
import 'types/kubi_state.dart';
import 'types/move_event.dart';
import 'types/move_result.dart';
import 'types/move_spec.dart';
import 'types/move_speed.dart';
import 'types/pan_tilt_angles.dart';
import 'types/position_snapshot.dart';
import 'types/settle_options.dart';
import 'types/subscribe_position_options.dart';

/// Kubi BLE 公開 API (SSOT: `docs/api-design.md` v0.2.0-draft)。
///
/// ## 設計の要約
///
/// - **Stream-first**: 状態通知はすべて `Stream` (callback unsubscribe 関数 API は提供しない)。
/// - **Sealed types**: `MoveSpec` / `MoveSpeed` / `MoveResult` / `KubiBleError` は
///   sealed + final 派生で Dart 3 の exhaustive switch 対応。
/// - **Immutable values**: すべての value type は `@immutable` + 手書き ==/hashCode/toString。
/// - **Flutter 拡張**: [state] (`ValueListenable<KubiState>`) は個別 Stream の集約 view。
///
/// ## Stream 共通セマンティクス (api-design §5.6)
///
/// - **broadcast** (複数購読可)
/// - **購読時の現在値即 emit はしない**。current value は対応 getter から取得
/// - **エラーは `addError` で配信、Stream は close しない** (recoverable error で UI が壊れない)
/// - **close は `disconnect()` 後のクリーンアップ時のみ**
///
/// ## テスト
///
/// `package:kubi_flutter_ble/testing.dart` の `FakeKubiBle` を使うこと。
/// production 依存を増やさないため `mockito` / `mocktail` 不要で widget test を書ける。
abstract interface class KubiBle {
  // ==========================================================================
  // 接続・ライフサイクル (api-design §3.2)
  // ==========================================================================

  /// 周辺の Kubi デバイスを scan する (D1)。
  ///
  /// 内部で `kubi*` name prefix の `ScanFilter` を universal_ble に渡す。
  /// `timeout` 経過後 (省略時は無期限) に自動的に `stopScan()` して Stream を close。
  ///
  /// 同じ deviceId の重複を `KubiDevice.id` ベースで dedup する。
  ///
  /// **Throws (Stream の `addError` 経由):**
  /// - [BleUnavailableError]: BLE が無効 / 権限なし / unsupported platform
  Stream<KubiDevice> scan({Duration? timeout});

  /// `scan()` の最初の 1 件を返す convenience (D1)。
  ///
  /// 複数 Kubi が近くにあるケースで利用者が選択 UI を出したい場合は [scan] を直接使うこと。
  ///
  /// **Throws:**
  /// - [BleUnavailableError]
  /// - `TimeoutException` (`dart:async`): `timeout` 内に 1 件も見つからなかった
  Future<KubiDevice> requestDevice({
    Duration timeout = const Duration(seconds: 5),
  });

  /// `device` に GATT 接続する。
  ///
  /// `timeout` の既定は 3 秒 (`connectionTimeoutMs`)。
  /// `timeout.inMicroseconds <= 0` の場合 [ArgumentError] を即 throw。
  ///
  /// **Throws:**
  /// - [ArgumentError]: `timeout` が非正
  /// - [BleConnectionError]: 接続失敗 / タイムアウト / discovery 失敗
  /// - [BleUnavailableError]: BLE が利用不能
  Future<void> connect(
    KubiDevice device, {
    Duration timeout = const Duration(milliseconds: 3000),
  });

  /// 明示切断。`connectionStateStream` に
  /// `ConnectionStateEvent(state: disconnected, reason: user)` が流れる。
  ///
  /// 自動再接続が有効でも、`disconnect()` 後は再接続しない (user intent を尊重)。
  Future<void> disconnect();

  /// 自動再接続を設定する。`null` で無効化 (B3)。
  void setAutoReconnect(AutoReconnectConfig? config);

  /// 過去接続済みデバイスへの接続を試みる (起動時の resume 用、U3)。
  ///
  /// - Native: `UniversalBle.getSystemDevices(withServices: [servoServiceUuid])`
  /// - **Web: 常に `null` を返す (D5)**。universal_ble v1.2.0 が
  ///   `navigator.bluetooth.getDevices()` を wrap していないため。
  ///
  /// 該当デバイスがない / permission がない場合は `null` を返す
  /// (例外ではない、「探したが居ない」は正常系)。
  Future<KubiDevice?> tryAutoConnect();

  /// 接続状態の遷移ストリーム (broadcast)。
  ///
  /// `ConnectionStateEvent` は `state / reason / timestamp` を持つ。
  /// `reason` は `state` が `disconnected` / `disconnecting` のときのみ非 null。
  ///
  /// **セマンティクス (§5.6):**
  /// - broadcast: 複数 listener 可、購読時の即 emit はなし
  ///   (現在値は [currentConnectionState] で同期取得)
  /// - listener throw は隔離され `onDebugEvent` の `listenerError` に転送
  ///
  /// **D3 (中間状態の補完):** universal_ble の `connectionStream` は
  /// `bool (connected/disconnected)` のみを流すため、
  /// `connecting` / `disconnecting` の中間状態は `KubiBleImpl` が
  /// `connect()` / `disconnect()` 呼び出し時に手動 emit する。
  /// 切断理由 (`reason`) は `UniversalBle.onConnectionChange` callback の
  /// `error` 引数を見て決定する:
  /// - `error != null` → `DisconnectReason.error`
  /// - `error == null && !isConnected` → `DisconnectReason.deviceLost`
  /// - 明示的 `disconnect()` → `DisconnectReason.user`
  Stream<ConnectionStateEvent> get connectionStateStream;

  /// 現在の接続状態を同期取得 (Stream の購読時即 emit が無いため、これで現在値を取る)。
  BleConnectionState get currentConnectionState;

  /// OS BLE adapter の可用性ストリーム (broadcast、§5.8 / D4)。
  ///
  /// **セマンティクス:**
  /// - broadcast: 複数 listener 可、購読時の即 emit はなし
  /// - 値は `UniversalBle.availabilityStream` (`AvailabilityState`) を
  ///   [BleAvailability] に rewrap して配信
  ///
  /// **接続中の自動応答 (D4):** `KubiBleImpl` が内部でこの stream を listen し、
  /// 以下の値を検知すると自動で `disconnect()` を呼び、
  /// `connectionStateStream` に
  /// `ConnectionStateEvent(state: disconnected, reason: deviceLost)` を流す:
  /// - [BleAvailability.poweredOff]
  /// - [BleAvailability.unauthorized]
  /// - [BleAvailability.resetting]
  ///
  /// また `unsupported` / `unauthorized` 中は自動再接続 state machine が
  /// `autoReconnectAbandoned` で停止する (無駄な retry を避けるため)。
  Stream<BleAvailability> get availabilityStream;

  // ==========================================================================
  // 動作 (write、api-design §3.3)
  // ==========================================================================

  /// Fire-and-forget の目標位置設定 (joystick / リアルタイム操縦向け)。
  ///
  /// 連続呼び出しは内部の latest-value buffer で「最新値だけ」に圧縮される (§5.1)。
  /// 通常 await しない (BLE 帯域に律速されて入力遅延する)。
  ///
  /// `speed` 省略時は [defaultSpeed] を使用。
  Future<void> setTarget({
    required PanTiltAngles target,
    MoveSpeed? speed,
  });

  /// 物理到達まで待つ GoTo (U2)。
  ///
  /// 新しい `moveTo` / `setTarget` / `disconnect()` / `cancel.cancel()` のいずれかで
  /// 中断された場合、Future は [MoveResultCancelled] で resolve (throw しない)。
  ///
  /// **Throws:**
  /// - [BleNotConnectedError]: 未接続
  /// - [BleSettleTimeoutError]: `settle.timeoutMs` を超過
  /// - [BleCommandError]: GATT write / register read 失敗
  Future<MoveResult> moveTo({
    required PanTiltAngles target,
    MoveSpec spec = const MoveSpec.independent(),
    SettleOptions settle = const SettleOptions(),
    CancelToken? cancel,
  });

  /// インスタンス共通の既定速度を更新する (B4)。
  /// disconnect でリセットされない (TS と同じ)。
  void setDefaultSpeed(MoveSpeed speed);

  /// 現在の既定速度。初期値は `MoveSpeed.uniform(defaultMoveSpeed)` (= 100)。
  MoveSpeed get defaultSpeed;

  // ==========================================================================
  // 観測 (read、api-design §3.4)
  // ==========================================================================

  /// Goal Position レジスタ (0x1e) の読み値を `PanTiltAngles` で返す (C8)。
  ///
  /// **Throws:**
  /// - [BleNotConnectedError]
  /// - [BleRegisterReadTimeoutError]
  Future<PanTiltAngles> getCommandedPosition();

  /// Present Position レジスタ (0x24) の読み値を `PanTiltAngles` で返す。
  ///
  /// **Throws:**
  /// - [BleNotConnectedError]
  /// - [BleRegisterReadTimeoutError]
  Future<PanTiltAngles> getActualPosition();

  /// `target` への物理到達を polling で待つ (`moveTo` の内部実装でもある)。
  ///
  /// `cancel` で中断された場合は [BleUserCancelledError] を throw。
  /// (`moveTo` のような「Cancelled という戻り値」はここでは提供しない —
  /// 単独で呼ぶケースでは throw のほうが扱いやすい)
  ///
  /// **Throws:**
  /// - [BleSettleTimeoutError]: `options.timeoutMs` を超過
  /// - [BleUserCancelledError]: cancel された
  /// - [BleNotConnectedError] / [BleRegisterReadTimeoutError]
  Future<MoveResultSettled> waitUntilSettled({
    required PanTiltAngles target,
    SettleOptions options = const SettleOptions(),
    CancelToken? cancel,
  });

  /// 位置の定期購読 (broadcast、§5.6)。
  ///
  /// 内部実装は再帰 Timer (overlap 防止)。GATT lock が取れない tick は skip
  /// されて `BleDebugEventType.pollSkipped` が発火する。
  ///
  /// `subscription.cancel()` で内部 Timer も停止する。
  Stream<PositionSnapshot> subscribePosition([
    SubscribePositionOptions options = const SubscribePositionOptions(),
  ]);

  // ==========================================================================
  // イベント (api-design §3.5)
  // ==========================================================================

  /// 4 phase 移動イベント (start / commanded / settled / cancelled)。
  Stream<MoveEvent> get onMove;

  /// 観測・診断イベント (broadcast、§4.6)。
  Stream<BleDebugEvent> get onDebugEvent;

  /// 個別 Stream の集約 view (Flutter 拡張、C5 / §2.5)。
  /// `ValueListenableBuilder` で UI に直接 bind 可能。
  ValueListenable<KubiState> get state;

  // ==========================================================================
  // ライフサイクル
  // ==========================================================================

  /// すべての内部リソース (Stream / Timer / GATT subscription) を解放する。
  ///
  /// 呼び出し後はインスタンスを再利用してはならない。
  Future<void> dispose();
}
