import 'pan_tilt_angles.dart';

/// 4-phase move event.
enum MovePhase {
  /// Movement started (command issued).
  start,

  /// Target angle has been commanded to servo.
  commanded,

  /// Physical arrival detected.
  settled,

  /// Movement was cancelled.
  cancelled,
}

/// Move event with phase and position data.
final class MoveEvent {
  final MovePhase phase;
  final PanTiltAngles? target;
  final PanTiltAngles? actual;

  const MoveEvent({required this.phase, this.target, this.actual});

  @override
  String toString() =>
      'MoveEvent(phase: $phase, target: $target, actual: $actual)';
}
