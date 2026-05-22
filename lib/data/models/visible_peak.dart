import 'mountain_peak.dart';

/// Risultato di un calcolo viewshed: una cima visibile dalla posizione utente
/// con tutti i metadati per render UI (label, freccia direzione, distanza,
/// "quanto sopra l'orizzonte").
class VisiblePeak {
  final MountainPeak peak;

  /// Azimut dalla posizione utente alla cima (gradi, 0 = nord, 90 = est).
  final double azimuthDeg;

  /// Distanza in metri (great-circle) dalla posizione utente.
  final double distanceMeters;

  /// Elevation angle dalla posizione utente al picco (gradi sopra l'orizzonte
  /// teorico, può essere negativo se la cima è "sotto" la testa dell'utente).
  final double elevationAngleDeg;

  /// Angolo dello skyline a quell'azimut (gradi). La cima è visibile sse
  /// `elevationAngleDeg > skylineAngleDeg + margin`.
  final double skylineAngleDeg;

  const VisiblePeak({
    required this.peak,
    required this.azimuthDeg,
    required this.distanceMeters,
    required this.elevationAngleDeg,
    required this.skylineAngleDeg,
  });

  /// Quanto la cima sporge dall'orizzonte locale. Positivo = visibile pulita,
  /// vicino a 0 = "appena sopra il crinale", negativo = occlusa.
  double get prominenceOverSkylineDeg => elevationAngleDeg - skylineAngleDeg;

  /// Label compatta per UI: "Monte Bianco · 12 km · NE".
  String label({bool includeDistance = true, bool includeBearing = true}) {
    final parts = <String>[peak.name];
    if (includeDistance) {
      final km = distanceMeters / 1000;
      parts.add(km < 10
          ? '${km.toStringAsFixed(1)} km'
          : '${km.round()} km');
    }
    if (includeBearing) parts.add(_compass(azimuthDeg));
    return parts.join(' · ');
  }

  static String _compass(double az) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    final idx = ((az + 22.5) % 360 ~/ 45).toInt();
    return dirs[idx];
  }
}
