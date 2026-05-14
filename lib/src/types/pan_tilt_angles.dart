import 'package:meta/meta.dart';

/// Pan / Tilt 角度 (度)。
///
/// - Pan range: -150° 〜 +150°
/// - Tilt range: -20° 〜 +40°
///
/// 範囲外の値も保持可能 (clamp は呼び出し側責務)。
@immutable
final class PanTiltAngles {
  final double pan;
  final double tilt;

  const PanTiltAngles({required this.pan, required this.tilt});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PanTiltAngles && other.pan == pan && other.tilt == tilt;

  @override
  int get hashCode => Object.hash(pan, tilt);

  @override
  String toString() => 'PanTiltAngles(pan: $pan°, tilt: $tilt°)';
}
