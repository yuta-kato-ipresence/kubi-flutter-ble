import 'package:meta/meta.dart';

import 'move_phase.dart';
import 'pan_tilt_angles.dart';

/// 4 phase 移動イベント。`onMove` Stream で配信される。
///
/// `phase` ごとに有意なフィールドが異なる:
/// - [MovePhase.start] / [MovePhase.commanded]: `target` のみ非 null
/// - [MovePhase.settled]: `target` + `actual` 両方非 null
/// - [MovePhase.cancelled]: `target` のみ非 null (actual は到達してない)
///
/// `target` は clamp 後の値。
@immutable
final class MoveEvent {
  final MovePhase phase;
  final PanTiltAngles? target;
  final PanTiltAngles? actual;
  final DateTime timestamp;

  const MoveEvent({
    required this.phase,
    required this.timestamp,
    this.target,
    this.actual,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveEvent &&
          other.phase == phase &&
          other.target == target &&
          other.actual == actual &&
          other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(phase, target, actual, timestamp);

  @override
  String toString() =>
      'MoveEvent(phase: $phase, target: $target, actual: $actual, '
      'timestamp: $timestamp)';
}
