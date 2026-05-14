import 'package:meta/meta.dart';

import '../types/pan_tilt_angles.dart';

/// すべての KubiBle 関連エラーのルート (sealed)。
///
/// Dart 3 の exhaustive switch + `is` で網羅的にハンドル可能。
/// `ArgumentError` 等 Dart 標準の入力バリデーション系はこの階層に**含めない**
/// (引数誤用は呼び出し側の bug、recoverable error と区別する)。
sealed class KubiBleError implements Exception {
  /// 人間可読なエラーメッセージ (UI / ログ用)。
  final String message;
  const KubiBleError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// universal_ble / OS が BLE を提供できない (権限拒否、Bluetooth OFF、unsupported platform 等)。
@immutable
final class BleUnavailableError extends KubiBleError {
  const BleUnavailableError(super.message);
}

/// 利用者の明示的キャンセル (`disconnect()` / `CancelToken.cancel()`) で Future が完了したことを示す。
/// 通常は `MoveResultCancelled` で配信されるため throw されることは稀。
@immutable
final class BleUserCancelledError extends KubiBleError {
  const BleUserCancelledError(super.message);
}

/// 接続フェーズで失敗 (タイムアウト含む、universal_ble の connect/discover 例外等)。
@immutable
final class BleConnectionError extends KubiBleError {
  const BleConnectionError(super.message);
}

/// 未接続 / 切断中の状態で操作 API (`moveTo` 等) を呼び出した。
@immutable
final class BleNotConnectedError extends KubiBleError {
  const BleNotConnectedError(super.message);
}

/// GATT コマンド (write / read) が失敗した (sealed: register read timeout 等の派生あり)。
sealed class BleCommandError extends KubiBleError {
  const BleCommandError(super.message);
}

/// register read のタイムアウト。
///
/// [motorId] は 1 (pan) または 2 (tilt)、[addr] はレジスタアドレス
/// (例: `regGoalPosition` = 0x1e)、[elapsedMs] は read 開始からの経過 ms。
@immutable
final class BleRegisterReadTimeoutError extends BleCommandError {
  final int motorId;
  final int addr;
  final int elapsedMs;

  BleRegisterReadTimeoutError({
    required this.motorId,
    required this.addr,
    required this.elapsedMs,
    String? message,
  })  : assert(motorId == 1 || motorId == 2, 'motorId must be 1 or 2'),
        super(
          message ??
              'register read timeout (motorId=$motorId, '
                  'addr=0x${addr.toRadixString(16).padLeft(2, '0')}, '
                  'elapsedMs=$elapsedMs)',
        );
}

/// GATT プロトコル違反 (write 失敗、register read 応答の payload 長/header 不一致等)。
///
/// `BleRegisterReadTimeoutError` と異なり「タイムアウト」ではなく
/// 応答が届いたが解釈不能 / write 自体が GATT layer で失敗したケースを表す。
@immutable
final class BleProtocolError extends BleCommandError {
  const BleProtocolError(super.message);
}

/// `moveTo` / `waitUntilSettled` の到達検出タイムアウト。
///
/// [target] は意図した到達位置 (clamp 後)、[lastObserved] はタイムアウト直前に
/// 観測した実位置 (Present Position)、[elapsedMs] は settle 待機開始からの経過 ms。
@immutable
final class BleSettleTimeoutError extends KubiBleError {
  final PanTiltAngles target;
  final PanTiltAngles? lastObserved;
  final int elapsedMs;

  const BleSettleTimeoutError({
    required this.target,
    required this.elapsedMs,
    this.lastObserved,
    String? message,
  }) : super(
          message ??
              'settle timeout (target=$target, lastObserved=$lastObserved, '
                  'elapsedMs=$elapsedMs)',
        );
}
