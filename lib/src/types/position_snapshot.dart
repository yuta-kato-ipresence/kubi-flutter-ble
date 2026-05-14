import 'package:meta/meta.dart';

import 'pan_tilt_angles.dart';

/// `subscribePosition` Stream / `getCommandedPosition` 等で配信される位置スナップショット。
///
/// `commanded` / `actual` は `PositionSource` に応じて片方または両方が非 null。
@immutable
final class PositionSnapshot {
  /// Goal Position レジスタ (0x1e) の値。`PositionSource.commanded` / `both` で配信。
  final PanTiltAngles? commanded;

  /// Present Position レジスタ (0x24) の値。`PositionSource.actual` / `both` で配信。
  final PanTiltAngles? actual;

  /// この snapshot の取得時刻。
  final DateTime timestamp;

  /// `moveTo` の write 完了 〜 settle 完了の間 `true`。
  final bool isMoving;

  const PositionSnapshot({
    required this.timestamp,
    required this.isMoving,
    this.commanded,
    this.actual,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionSnapshot &&
          other.commanded == commanded &&
          other.actual == actual &&
          other.timestamp == timestamp &&
          other.isMoving == isMoving;

  @override
  int get hashCode => Object.hash(commanded, actual, timestamp, isMoving);

  @override
  String toString() => 'PositionSnapshot(commanded: $commanded, '
      'actual: $actual, timestamp: $timestamp, isMoving: $isMoving)';
}
