import 'dart:math' as math;

/// Algoritmo viewshed "skyline-based" — puro (no I/O), eseguibile in Isolate.
///
/// Idea:
/// 1. Da una posizione utente P (lat,lng,quota_observer), si campiona il
///    DEM lungo 360 raggi (uno per ogni grado di azimut).
/// 2. Per ogni raggio si calcola l'elevation angle massimo lungo il percorso:
///    questo è l'**horizon line** (skyline) in quella direzione.
/// 3. Per ogni cima candidata si calcola azimut + elevation angle.
///    Se peak_angle > skyline[az] + margin → visibile.
///
/// La curvatura terrestre + rifrazione atmosferica vengono applicate:
///   apparent_drop = (1 - k) * d^2 / (2 * R_earth)
/// con k=0.13 (rifrazione standard) e R=6371km.
///
/// Tutto in metri/gradi, nessuna dipendenza esterna.

/// Raggio medio della Terra in metri.
const double _earthRadiusM = 6371000.0;

/// Coefficiente di rifrazione atmosferica standard. Riduce il drop apparente
/// di circa il 13%.
const double _refractionK = 0.13;

class ViewshedRequest {
  final double observerLat;
  final double observerLng;
  /// Altezza dell'osservatore sopra il terreno (m). Default 1.7m = persona in piedi.
  final double observerHeightM;
  final double maxRadiusKm;
  /// Step in metri lungo ogni raggio. 200m = compromesso buono perf/qualità.
  final int rayStepMeters;
  /// Numero di azimut campionati. 360 = uno per grado. 720 = mezzo grado.
  final int azimuthSteps;
  /// Tolleranza per dichiarare visibile (gradi). 0.5° standard PeakFinder.
  final double visibilityMarginDeg;

  /// Cime candidate da testare: [{id, lat, lng, ele}, ...]
  final List<Map<String, dynamic>> candidatePeaks;

  /// Funzione DEM: dato (lat, lng) → quota in metri. Nell'isolate viene
  /// passata come closure su una griglia in memoria già decodificata.
  /// In questa request è invece una **lookup table** pre-popolata, perché
  /// le closure non passano i Isolate boundaries.
  ///
  /// Formato: lista flat di [lat0,lng0,ele0, lat1,lng1,ele1, ...] +
  /// metadati griglia. Vedi DemGrid.
  final DemGrid dem;

  const ViewshedRequest({
    required this.observerLat,
    required this.observerLng,
    required this.dem,
    this.observerHeightM = 1.7,
    this.maxRadiusKm = 50,
    this.rayStepMeters = 200,
    this.azimuthSteps = 360,
    this.visibilityMarginDeg = 0.5,
    required this.candidatePeaks,
  });
}

/// Rappresentazione "flat" di una griglia DEM regolare in lat/lng. Permette
/// di passare tra Isolate (solo tipi primitivi).
///
/// La griglia copre la bbox [minLat..maxLat, minLng..maxLng] con
/// `rows × cols` celle equispaziate. `elevations[row * cols + col]` = quota
/// in metri al centro della cella.
///
/// Lookup: bilineare nelle 4 celle vicine al punto query.
class DemGrid {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final int rows;
  final int cols;
  final List<double> elevations; // length = rows * cols

  const DemGrid({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.rows,
    required this.cols,
    required this.elevations,
  });

  /// Lookup bilineare (lat,lng) → quota in metri. Restituisce
  /// [double.nan] se fuori bbox (così il viewshed sa distinguere "out of
  /// grid" da "sea level = 0").
  double elevationAt(double lat, double lng) {
    if (lat < minLat || lat > maxLat || lng < minLng || lng > maxLng) {
      return double.nan;
    }
    final fy = (lat - minLat) / (maxLat - minLat) * (rows - 1);
    final fx = (lng - minLng) / (maxLng - minLng) * (cols - 1);
    final r0 = fy.floor().clamp(0, rows - 1);
    final r1 = math.min(r0 + 1, rows - 1);
    final c0 = fx.floor().clamp(0, cols - 1);
    final c1 = math.min(c0 + 1, cols - 1);
    final dy = fy - r0;
    final dx = fx - c0;
    final e00 = elevations[r0 * cols + c0];
    final e01 = elevations[r0 * cols + c1];
    final e10 = elevations[r1 * cols + c0];
    final e11 = elevations[r1 * cols + c1];
    final e0 = e00 * (1 - dx) + e01 * dx;
    final e1 = e10 * (1 - dx) + e11 * dx;
    return e0 * (1 - dy) + e1 * dy;
  }
}

class ViewshedResult {
  /// Skyline in gradi per ogni step di azimut. Lunghezza = `azimuthSteps`.
  final List<double> skylineAngles;

  /// Risultati per ogni cima candidata, stessi indici input.
  final List<PeakResult> peaks;

  const ViewshedResult({
    required this.skylineAngles,
    required this.peaks,
  });
}

class PeakResult {
  final String id;
  final double azimuthDeg;
  final double distanceMeters;
  final double elevationAngleDeg;
  final double skylineAngleDeg;
  final bool visible;

  const PeakResult({
    required this.id,
    required this.azimuthDeg,
    required this.distanceMeters,
    required this.elevationAngleDeg,
    required this.skylineAngleDeg,
    required this.visible,
  });
}

/// Calcola lo skyline + visibilità cime. Top-level function = passabile a
/// `compute()` o `Isolate.run()`.
ViewshedResult computeViewshed(ViewshedRequest req) {
  // 1. Quota dell'osservatore = DEM(P) + altezza persona.
  final eyeElev = req.dem.elevationAt(req.observerLat, req.observerLng) +
      req.observerHeightM;

  // 2. Skyline: per ogni azimut, ray-march fino a maxRadius.
  final skyline = List<double>.filled(req.azimuthSteps, -90.0);
  final maxRangeM = req.maxRadiusKm * 1000.0;

  for (int aIdx = 0; aIdx < req.azimuthSteps; aIdx++) {
    final azDeg = aIdx * 360.0 / req.azimuthSteps;
    double maxAngle = -90.0;

    for (double d = req.rayStepMeters.toDouble();
        d <= maxRangeM;
        d += req.rayStepMeters) {
      final pt = _destinationPoint(req.observerLat, req.observerLng, azDeg, d);
      final ele = req.dem.elevationAt(pt[0], pt[1]);
      if (ele.isNaN) continue; // fuori grid
      final apparentEle = ele - _earthDropMeters(d);
      final dy = apparentEle - eyeElev;
      final angle = math.atan2(dy, d) * 180 / math.pi;
      if (angle > maxAngle) maxAngle = angle;
    }
    skyline[aIdx] = maxAngle;
  }

  // 3. Per ogni cima candidata: distanza, azimut, angolo elev, confronto.
  final peaks = <PeakResult>[];
  for (final peak in req.candidatePeaks) {
    final pLat = (peak['lat'] as num).toDouble();
    final pLng = (peak['lng'] as num).toDouble();
    final pEle = (peak['ele'] as num?)?.toDouble() ?? 0.0;
    final id = peak['id']?.toString() ?? '';

    final dist = _haversineMeters(req.observerLat, req.observerLng, pLat, pLng);
    final az = _bearingDeg(req.observerLat, req.observerLng, pLat, pLng);
    final apparentEle = pEle - _earthDropMeters(dist);
    final dy = apparentEle - eyeElev;
    final angle = math.atan2(dy, dist) * 180 / math.pi;

    final azIdx = (az / (360.0 / req.azimuthSteps)).round() % req.azimuthSteps;
    final skyAngle = skyline[azIdx];

    peaks.add(PeakResult(
      id: id,
      azimuthDeg: az,
      distanceMeters: dist,
      elevationAngleDeg: angle,
      skylineAngleDeg: skyAngle,
      visible: angle > skyAngle + req.visibilityMarginDeg,
    ));
  }

  return ViewshedResult(skylineAngles: skyline, peaks: peaks);
}

/// Drop apparente dovuto a curvatura terrestre + rifrazione atmosferica.
double _earthDropMeters(double distanceM) {
  return (1 - _refractionK) * distanceM * distanceM / (2 * _earthRadiusM);
}

/// Distanza haversine in metri tra due coordinate WGS84.
double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * _earthRadiusM * math.asin(math.sqrt(a));
}

/// Bearing iniziale in gradi (0 = nord, 90 = est) da P1 a P2.
double _bearingDeg(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dl = (lng2 - lng1) * math.pi / 180;
  final y = math.sin(dl) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dl);
  final brng = math.atan2(y, x) * 180 / math.pi;
  return (brng + 360) % 360;
}

/// Punto di arrivo dato origine + bearing + distanza (great-circle).
/// Restituisce [lat, lng].
List<double> _destinationPoint(double lat, double lng, double bearingDeg, double distanceM) {
  final phi1 = lat * math.pi / 180;
  final lambda1 = lng * math.pi / 180;
  final theta = bearingDeg * math.pi / 180;
  final delta = distanceM / _earthRadiusM;
  final phi2 = math.asin(math.sin(phi1) * math.cos(delta) +
      math.cos(phi1) * math.sin(delta) * math.cos(theta));
  final lambda2 = lambda1 +
      math.atan2(
        math.sin(theta) * math.sin(delta) * math.cos(phi1),
        math.cos(delta) - math.sin(phi1) * math.sin(phi2),
      );
  return [phi2 * 180 / math.pi, ((lambda2 * 180 / math.pi) + 540) % 360 - 180];
}
