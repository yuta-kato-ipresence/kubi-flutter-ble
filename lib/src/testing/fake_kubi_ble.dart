import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../../kubi_flutter_ble.dart';

/// テスト用の in-memory `KubiBle` 実装 (api-design §4.5、Phase 4 で本実装予定)。
///
/// 現在は **スケルトン** のみ:
/// - すべての非 void/Future/Stream API は throw [UnimplementedError]
/// - simulate API のシグネチャのみ仮置き
///
/// Phase 4 (universal_ble 不在で動く) で本実装する。
class FakeKubiBle implements KubiBle {
  FakeKubiBle();

  // TODO(phase4): すべて実装する
  @override
  Stream<KubiDevice> scan({Duration? timeout}) => throw UnimplementedError();

  @override
  Future<KubiDevice> requestDevice({
    Duration timeout = const Duration(seconds: 5),
  }) =>
      throw UnimplementedError();

  @override
  Future<void> connect(
    KubiDevice device, {
    Duration timeout = const Duration(milliseconds: 3000),
  }) =>
      throw UnimplementedError();

  @override
  Future<void> disconnect() => throw UnimplementedError();

  @override
  void setAutoReconnect(AutoReconnectConfig? config) =>
      throw UnimplementedError();

  @override
  Future<KubiDevice?> tryAutoConnect() => throw UnimplementedError();

  @override
  Stream<ConnectionStateEvent> get connectionStateStream =>
      throw UnimplementedError();

  @override
  BleConnectionState get currentConnectionState => throw UnimplementedError();

  @override
  Stream<BleAvailability> get availabilityStream => throw UnimplementedError();

  @override
  Future<void> setTarget({required PanTiltAngles target, MoveSpeed? speed}) =>
      throw UnimplementedError();

  @override
  Future<MoveResult> moveTo({
    required PanTiltAngles target,
    MoveSpec spec = const MoveSpec.independent(),
    SettleOptions settle = const SettleOptions(),
    CancelToken? cancel,
  }) =>
      throw UnimplementedError();

  @override
  void setDefaultSpeed(MoveSpeed speed) => throw UnimplementedError();

  @override
  MoveSpeed get defaultSpeed => throw UnimplementedError();

  @override
  Future<PanTiltAngles> getCommandedPosition() => throw UnimplementedError();

  @override
  Future<PanTiltAngles> getActualPosition() => throw UnimplementedError();

  @override
  Future<MoveResultSettled> waitUntilSettled({
    required PanTiltAngles target,
    SettleOptions options = const SettleOptions(),
    CancelToken? cancel,
  }) =>
      throw UnimplementedError();

  @override
  Stream<PositionSnapshot> subscribePosition([
    SubscribePositionOptions options = const SubscribePositionOptions(),
  ]) =>
      throw UnimplementedError();

  @override
  Stream<MoveEvent> get onMove => throw UnimplementedError();

  @override
  Stream<BleDebugEvent> get onDebugEvent => throw UnimplementedError();

  @override
  ValueListenable<KubiState> get state =>
      ValueNotifier<KubiState>(KubiState.initial);

  @override
  Future<void> dispose() => throw UnimplementedError();

  // ===== test-time simulate API (Phase 4 で実装) =====

  void simulateConnectionState(
    BleConnectionState state, {
    DisconnectReason? reason,
  }) =>
      throw UnimplementedError();

  void simulateError(KubiBleError error) => throw UnimplementedError();

  void simulatePositionUpdate(PositionSnapshot snapshot) =>
      throw UnimplementedError();
}
