import 'pan_tilt_angles.dart';

/// Discriminated union for move results.
sealed class MoveResult {
  const MoveResult();
}

/// Move completed and physically arrived at target.
final class MoveResultSettled extends MoveResult {
  final PanTiltAngles actual;

  const MoveResultSettled({required this.actual});
}

/// Move was cancelled by a newer move or disconnect.
final class MoveResultCancelled extends MoveResult {
  const MoveResultCancelled();
}
