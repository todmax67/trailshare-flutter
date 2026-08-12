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

  /// Di quanti **gradi** la cima sta sopra l'ostacolo peggiore lungo il
  /// tragitto verso di lei.
  ///
  /// Sostituisce il vecchio confronto con lo skyline: quello diceva di quanto la
  /// cima sporgeva rispetto al profilo di un raggio *vicino* al suo azimut, che
  /// a 100 km poteva passare 1,7 km di lato. Questo misura il vero tragitto
  /// verso quella cima. Vicino a zero = "spunta appena dietro la cresta".
  final double clearanceDeg;

  /// True quando fra noi e la cima c'è terreno che il DEM non copre: la
  /// mostriamo comunque (non possiamo dimostrare che sia nascosta) ma non è
  /// una certezza, ed è giusto che l'interfaccia lo dica.
  final bool uncertain;

  const VisiblePeak({
    required this.peak,
    required this.azimuthDeg,
    required this.distanceMeters,
    required this.elevationAngleDeg,
    required this.clearanceDeg,
    this.uncertain = false,
  });

  /// True quando la cima spunta di poco: utile per distinguere "la vedi bene"
  /// da "ne vedi la punta" senza mostrare numeri all'utente.
  bool get isMarginal => clearanceDeg < 0.25;

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
