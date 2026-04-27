import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Size;

import '../../data/models/mountain_peak.dart';

/// Proiezione **AR** di una cima sul viewport della fotocamera.
///
/// Date la posizione e l'altitudine dell'osservatore, l'orientamento del
/// telefono (heading bussola + pitch dall'accelerometro) e il FOV della
/// fotocamera, calcola se la cima è visibile nel viewfinder e dove
/// disegnare il pin.
///
/// Sistema di coordinate:
/// - bearing: gradi 0..360, 0 = Nord
/// - pitch: gradi -90..+90, 0 = orizzonte, +90 = zenit
/// - viewport (screenX, screenY): origin top-left, X cresce a destra,
///   Y cresce verso il basso
class MountainProjection {
  MountainProjection._();

  /// FOV orizzontale tipico delle camere posteriori smartphone tenute in
  /// portrait. Gli iPhone main camera sono ~63°, gli Android variano fra
  /// 60 e 75°. Usiamo un valore medio prudente; sara' affinabile in
  /// runtime con calibrazione utente in v2.1.
  static const double defaultHorizontalFovDeg = 60.0;

  /// FOV verticale: in portrait il sensor ratio si capovolge, quindi
  /// vediamo "alto e stretto". 80° è un buon range.
  static const double defaultVerticalFovDeg = 80.0;

  /// Calcola la proiezione di una singola cima sul viewport.
  /// Restituisce `null` se la cima è fuori dal cono visibile.
  static ProjectedPeak? project({
    required MountainPeak peak,
    required double observerLat,
    required double observerLng,
    required double observerAltitudeMeters,
    required double phoneHeadingDeg,
    required double phonePitchDeg,
    required Size viewport,
    double horizontalFovDeg = defaultHorizontalFovDeg,
    double verticalFovDeg = defaultVerticalFovDeg,
  }) {
    // 1. Bearing osservatore -> peak
    final bearingDeg = _initialBearing(
      observerLat,
      observerLng,
      peak.latitude,
      peak.longitude,
    );

    // 2. Distanza
    final distanceMeters = _haversine(
      observerLat,
      observerLng,
      peak.latitude,
      peak.longitude,
    );

    // 3. Bearing relativo al puntamento del telefono (-180..+180)
    final relBearing = _normalizeBearing(bearingDeg - phoneHeadingDeg);

    // 4. Angolo verticale: atan2(deltaH, distance). Senza altitudine
    //    osservatore o cima fallback a 0 (vediamola sull'orizzonte).
    double verticalAngleDeg = 0;
    if (peak.elevation != null && distanceMeters > 0) {
      final dh = peak.elevation! - observerAltitudeMeters;
      verticalAngleDeg = math.atan2(dh, distanceMeters) * 180 / math.pi;
    }

    // 5. Pitch relativo (peak sopra/sotto il puntamento del telefono)
    final relPitch = verticalAngleDeg - phonePitchDeg;

    // 6. Test visibilità nel cono FOV
    final hHalf = horizontalFovDeg / 2;
    final vHalf = verticalFovDeg / 2;
    if (relBearing.abs() > hHalf || relPitch.abs() > vHalf) {
      return null;
    }

    // 7. Coordinate viewport
    final w = viewport.width;
    final h = viewport.height;
    final screenX = w / 2 + (relBearing / hHalf) * (w / 2);
    // Y va invertito: pitch positivo = sopra l'orizzonte = verso il top
    final screenY = h / 2 - (relPitch / vHalf) * (h / 2);

    return ProjectedPeak(
      peak: peak,
      screenX: screenX,
      screenY: screenY,
      distanceMeters: distanceMeters,
      bearingDeg: bearingDeg,
      relativeBearingDeg: relBearing,
      relativePitchDeg: relPitch,
    );
  }

  /// Filtra/proietta tutte le [peaks] e ritorna le top [maxVisible]
  /// **più centrate** rispetto al puntamento (Opzione C).
  ///
  /// Tiebreaker: a parità di centratura preferisce l'altitudine maggiore.
  static List<ProjectedPeak> projectAll({
    required Iterable<MountainPeak> peaks,
    required double observerLat,
    required double observerLng,
    required double observerAltitudeMeters,
    required double phoneHeadingDeg,
    required double phonePitchDeg,
    required Size viewport,
    int maxVisible = 5,
    double horizontalFovDeg = defaultHorizontalFovDeg,
    double verticalFovDeg = defaultVerticalFovDeg,
  }) {
    final visible = <ProjectedPeak>[];
    for (final p in peaks) {
      final proj = project(
        peak: p,
        observerLat: observerLat,
        observerLng: observerLng,
        observerAltitudeMeters: observerAltitudeMeters,
        phoneHeadingDeg: phoneHeadingDeg,
        phonePitchDeg: phonePitchDeg,
        viewport: viewport,
        horizontalFovDeg: horizontalFovDeg,
        verticalFovDeg: verticalFovDeg,
      );
      if (proj != null) visible.add(proj);
    }

    // Ordina per "centratura" (distanza euclidea normalizzata dal centro
    // viewport). Tiebreaker su altitudine decrescente.
    visible.sort((a, b) {
      final centerA =
          (a.relativeBearingDeg.abs() / horizontalFovDeg) +
              (a.relativePitchDeg.abs() / verticalFovDeg);
      final centerB =
          (b.relativeBearingDeg.abs() / horizontalFovDeg) +
              (b.relativePitchDeg.abs() / verticalFovDeg);
      final diff = centerA.compareTo(centerB);
      if (diff != 0) return diff;
      final eleA = a.peak.elevation ?? 0;
      final eleB = b.peak.elevation ?? 0;
      return eleB.compareTo(eleA);
    });

    if (visible.length <= maxVisible) return visible;
    return visible.take(maxVisible).toList();
  }

  /// Stima del **pitch del telefono** dato il vettore gravità
  /// dell'accelerometro (in m/s², asse standard Android/iOS).
  ///
  /// Convenzione output:
  /// - 0° quando il telefono è in portrait con la camera che punta
  ///   all'orizzonte
  /// - +90° quando la camera punta verso lo zenit (telefono tilted back)
  /// - -90° quando la camera punta verso il basso (telefono tilted forward)
  static double pitchFromAccelerometer(double ax, double ay, double az) {
    // pitch = atan2(-z, sqrt(x^2 + y^2)) — vedi note progetto.
    final pitchRad = math.atan2(-az, math.sqrt(ax * ax + ay * ay));
    return pitchRad * 180 / math.pi;
  }

  // ─── Geo utilities ────────────────────────────────────────────────

  /// Distanza Haversine in metri.
  static double _haversine(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Bearing iniziale da p1 a p2, gradi 0..360.
  static double _initialBearing(
      double lat1, double lng1, double lat2, double lng2) {
    final y =
        math.sin(_toRad(lng2 - lng1)) * math.cos(_toRad(lat2));
    final x = math.cos(_toRad(lat1)) * math.sin(_toRad(lat2)) -
        math.sin(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.cos(_toRad(lng2 - lng1));
    final brng = _toDeg(math.atan2(y, x));
    return (brng + 360) % 360;
  }

  /// Normalizza un bearing differenza in -180..+180.
  static double _normalizeBearing(double deg) {
    return ((deg + 540) % 360) - 180;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
  static double _toDeg(double rad) => rad * 180 / math.pi;
}

/// Risultato di una proiezione AR.
class ProjectedPeak {
  final MountainPeak peak;

  /// Coordinate di pixel sul viewport, origin top-left.
  final double screenX;
  final double screenY;

  /// Distanza geografica osservatore -> peak in metri.
  final double distanceMeters;

  /// Bearing assoluto (0=Nord) osservatore -> peak.
  final double bearingDeg;

  /// Bearing relativo al puntamento del telefono (-180..+180,
  /// 0 = perfettamente centrato in orizzontale).
  final double relativeBearingDeg;

  /// Pitch relativo al puntamento del telefono in gradi.
  /// 0 = perfettamente centrato in verticale, positivo = sopra il centro,
  /// negativo = sotto.
  final double relativePitchDeg;

  const ProjectedPeak({
    required this.peak,
    required this.screenX,
    required this.screenY,
    required this.distanceMeters,
    required this.bearingDeg,
    required this.relativeBearingDeg,
    required this.relativePitchDeg,
  });

  /// True se la cima è centrata entro il 20% del FOV (utile per highlight).
  bool isCentered(Size viewport) {
    final dx = (screenX - viewport.width / 2).abs();
    final dy = (screenY - viewport.height / 2).abs();
    return dx < viewport.width * 0.10 && dy < viewport.height * 0.10;
  }
}
