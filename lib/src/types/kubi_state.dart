import 'package:meta/meta.dart';

import '../errors/kubi_ble_error.dart';
import 'ble_connection_state.dart';
import 'pan_tilt_angles.dart';

/// `KubiBle.state` (`ValueListenable<KubiState>`) の中身。
///
/// **Flutter 拡張** (TS 版に対応物なし、設計書 §2.5 参照)。
/// 個別 Stream (`connectionStateStream` / `subscribePosition` / `onMove` /
/// `onDebugEvent`) の集約 view であり、二重事実源ではない。
///
/// 内部実装は `ValueNotifier<KubiState>` 1 つを各 Stream の listener から
/// `copyWith` 更新する単純な fan-in。
@immutable
final class KubiState {
  final BleConnectionState connectionState;
  final PanTiltAngles? commanded;
  final PanTiltAngles? actual;
  final bool isMoving;

  /// 最後に発生した recoverable / non-recoverable エラー (UI 表示用)。
  /// disconnect / connect 成功でクリア。
  final KubiBleError? lastError;

  const KubiState({
    required this.connectionState,
    required this.isMoving,
    this.commanded,
    this.actual,
    this.lastError,
  });

  /// 初期状態 (disconnected, 全 null, isMoving=false)。
  static const KubiState initial = KubiState(
    connectionState: BleConnectionState.disconnected,
    isMoving: false,
  );

  KubiState copyWith({
    BleConnectionState? connectionState,
    PanTiltAngles? commanded,
    PanTiltAngles? actual,
    bool? isMoving,
    KubiBleError? lastError,
    bool clearLastError = false,
  }) {
    return KubiState(
      connectionState: connectionState ?? this.connectionState,
      commanded: commanded ?? this.commanded,
      actual: actual ?? this.actual,
      isMoving: isMoving ?? this.isMoving,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KubiState &&
          other.connectionState == connectionState &&
          other.commanded == commanded &&
          other.actual == actual &&
          other.isMoving == isMoving &&
          other.lastError == lastError;

  @override
  int get hashCode =>
      Object.hash(connectionState, commanded, actual, isMoving, lastError);

  @override
  String toString() => 'KubiState(connection: $connectionState, '
      'commanded: $commanded, actual: $actual, isMoving: $isMoving, '
      'lastError: $lastError)';
}
