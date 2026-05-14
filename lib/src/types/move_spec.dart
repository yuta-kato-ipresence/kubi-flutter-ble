import 'package:meta/meta.dart';

import '../kubi_protocol.dart' show maxMoveSpeed, minMoveSpeed;
import 'move_speed.dart';

/// `moveTo` の動作モード指定 (sealed)。
///
/// factory:
/// - [MoveSpec.independent] — 各軸独立に動く (既定)。`speed` を指定可能
/// - [MoveSpec.synced] — 両軸が同時到達するよう slow 軸基準で速度配分 (`maxSpeed` 上限)
///
/// `independent` と `synced` は API レベルで排他 (sealed + factory で保証)。
sealed class MoveSpec {
  const MoveSpec();

  /// 各軸独立 (既定)。`speed` を省略すると `defaultMoveSpeed` (= 100)。
  const factory MoveSpec.independent({MoveSpeed? speed}) =
      MoveSpecIndependent;

  /// 両軸同時到達 (slow 軸基準で速度配分、補正テーブル使用)。
  const factory MoveSpec.synced({required int maxSpeed}) = MoveSpecSynced;
}

@immutable
final class MoveSpecIndependent extends MoveSpec {
  final MoveSpeed? speed;
  const MoveSpecIndependent({this.speed});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveSpecIndependent && other.speed == speed;

  @override
  int get hashCode => speed.hashCode;

  @override
  String toString() => 'MoveSpec.independent(speed: $speed)';
}

@immutable
final class MoveSpecSynced extends MoveSpec {
  final int maxSpeed;

  const MoveSpecSynced({required this.maxSpeed})
      : assert(
          maxSpeed >= minMoveSpeed && maxSpeed <= maxMoveSpeed,
          'maxSpeed must be in [minMoveSpeed, maxMoveSpeed]',
        );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveSpecSynced && other.maxSpeed == maxSpeed;

  @override
  int get hashCode => maxSpeed.hashCode;

  @override
  String toString() => 'MoveSpec.synced(maxSpeed: $maxSpeed)';
}
