import 'package:meta/meta.dart';

import '../kubi_protocol.dart' show maxMoveSpeed, minMoveSpeed;

/// 移動速度指定 (sealed)。
///
/// factory:
/// - [MoveSpeed.uniform] — pan/tilt に同じ速度
/// - [MoveSpeed.perAxis] — 軸ごとに個別の速度
///
/// 値は 1〜100 (`MIN_MOVE_SPEED` 〜 `MAX_MOVE_SPEED`)。範囲外は assert で fail-fast。
sealed class MoveSpeed {
  const MoveSpeed();

  /// 全軸同一速度。
  const factory MoveSpeed.uniform(int speed) = MoveSpeedUniform;

  /// 軸ごとの個別速度。
  const factory MoveSpeed.perAxis({required int pan, required int tilt}) =
      MoveSpeedPerAxis;
}

@immutable
final class MoveSpeedUniform extends MoveSpeed {
  final int speed;

  const MoveSpeedUniform(this.speed)
      : assert(
          speed >= minMoveSpeed && speed <= maxMoveSpeed,
          'speed must be in [minMoveSpeed, maxMoveSpeed]',
        );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveSpeedUniform && other.speed == speed;

  @override
  int get hashCode => speed.hashCode;

  @override
  String toString() => 'MoveSpeed.uniform($speed)';
}

@immutable
final class MoveSpeedPerAxis extends MoveSpeed {
  final int pan;
  final int tilt;

  const MoveSpeedPerAxis({required this.pan, required this.tilt})
      : assert(
          pan >= minMoveSpeed && pan <= maxMoveSpeed,
          'pan speed must be in [minMoveSpeed, maxMoveSpeed]',
        ),
        assert(
          tilt >= minMoveSpeed && tilt <= maxMoveSpeed,
          'tilt speed must be in [minMoveSpeed, maxMoveSpeed]',
        );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveSpeedPerAxis && other.pan == pan && other.tilt == tilt;

  @override
  int get hashCode => Object.hash(pan, tilt);

  @override
  String toString() => 'MoveSpeed.perAxis(pan: $pan, tilt: $tilt)';
}
