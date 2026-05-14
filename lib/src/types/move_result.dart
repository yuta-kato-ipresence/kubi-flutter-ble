import 'package:meta/meta.dart';

import 'pan_tilt_angles.dart';

/// `moveTo` の結果 (sealed)。
///
/// Dart 3 exhaustive switch 対応。両 variant に `target` (clamp 後の意図値) を持つ。
sealed class MoveResult {
  final PanTiltAngles target;
  const MoveResult({required this.target});
}

/// 物理到達検出 (tolerance 内) で完了。
@immutable
final class MoveResultSettled extends MoveResult {
  /// 到達時の実位置 (Present Position レジスタ読み値)。
  final PanTiltAngles actual;

  const MoveResultSettled({required super.target, required this.actual});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveResultSettled &&
          other.target == target &&
          other.actual == actual;

  @override
  int get hashCode => Object.hash(target, actual);

  @override
  String toString() => 'MoveResultSettled(target: $target, actual: $actual)';
}

/// 新しい `moveTo` / `disconnect` / `cancel token` のいずれかで中断された。
@immutable
final class MoveResultCancelled extends MoveResult {
  const MoveResultCancelled({required super.target});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveResultCancelled && other.target == target;

  @override
  int get hashCode => target.hashCode;

  @override
  String toString() => 'MoveResultCancelled(target: $target)';
}
