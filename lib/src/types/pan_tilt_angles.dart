/// Pan and tilt angles in degrees.
///
/// Pan range: -150° to +150°
/// Tilt range: -20° to +40°
final class PanTiltAngles {
  final double pan;
  final double tilt;

  const PanTiltAngles({required this.pan, required this.tilt});

  @override
  String toString() => 'PanTiltAngles(pan: $pan°, tilt: $tilt°)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PanTiltAngles && other.pan == pan && other.tilt == tilt;

  @override
  int get hashCode => Object.hash(pan, tilt);
}
