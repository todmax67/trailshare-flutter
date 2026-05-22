import 'dart:math' as math;

import '../../data/models/terrain_segment.dart';
import '../../data/models/track.dart';

/// Stima del tempo necessario a completare un percorso, dato distanza,
/// dislivello positivo e tipo di attività.
///
/// Usa una variante della **regola di Naismith** per le attività di tipo
/// hiking (4 km/h flat + 1h ogni 600 m di salita) calibrata per ciascun
/// [ActivityType]. È una stima ragionevole per la fase di "preview
/// pre-partenza" — sul campo l'ETA reale è ricalcolato in base al passo
/// dell'utente.
///
/// ```dart
/// final eta = EtaEstimator.estimate(
///   distanceMeters: 8200,
///   elevationGainMeters: 720,
///   activityType: ActivityType.trekking,
/// );
/// // Duration di ~3h 25m
/// ```
class EtaEstimator {
  EtaEstimator._();

  /// Stima il tempo per percorrere [distanceMeters] con [elevationGainMeters]
  /// di dislivello positivo all'attività [activityType].
  ///
  /// Ritorna [Duration.zero] per input invalidi o velocità nulle.
  static Duration estimate({
    required double distanceMeters,
    required double elevationGainMeters,
    required ActivityType activityType,
  }) {
    if (distanceMeters <= 0) return Duration.zero;
    final params = _paramsFor(activityType);
    if (params.speedKmh <= 0) return Duration.zero;

    // Tempo a velocità di crociera, in ore.
    final flatHours = (distanceMeters / 1000) / params.speedKmh;

    // Penalità di salita (Naismith-style): 1 ora ogni
    // [params.metersPerHourClimb] metri di D+.
    final climbHours = params.metersPerHourClimb > 0
        ? (elevationGainMeters / params.metersPerHourClimb)
        : 0;

    final totalSeconds = ((flatHours + climbHours) * 3600).round();
    return Duration(seconds: totalSeconds);
  }

  /// ETA dinamico durante la navigazione: usa la **velocità corrente
  /// dell'utente** quando ragionevole, fallback su Naismith [estimate]
  /// se la velocità non è affidabile (utente fermo, GPS instabile,
  /// inizio sessione).
  ///
  /// La logica è "best-effort":
  /// - se [currentSpeedKmh] >= 1 km/h → ETA = remaining/speed + correzione
  ///   salita rimanente (Naismith pondera 1h ogni metersPerHourClimb)
  /// - altrimenti → fallback su Naismith con i parametri dell'attività
  ///
  /// La salita rimanente è approssimata in modo proporzionale:
  ///   remainingElevation ≈ totalElevation × (remainingDistance / totalDistance)
  /// È un'approssimazione ragionevole; per averla esatta servirebbe
  /// scorrere il profilo altimetrico residuo, che non è sempre
  /// disponibile (track community OSM).
  static Duration estimateDynamic({
    required double remainingDistanceMeters,
    required double remainingElevationGainMeters,
    required ActivityType activityType,
    required double currentSpeedKmh,
  }) {
    if (remainingDistanceMeters <= 0) return Duration.zero;
    final params = _paramsFor(activityType);
    // Se la velocità corrente non è affidabile (utente fermo, GPS rumore,
    // inizio sessione), fallback su Naismith statico.
    if (currentSpeedKmh < 1.0) {
      return estimate(
        distanceMeters: remainingDistanceMeters,
        elevationGainMeters: remainingElevationGainMeters,
        activityType: activityType,
      );
    }
    final flatHours = (remainingDistanceMeters / 1000) / currentSpeedKmh;
    final climbHours = params.metersPerHourClimb > 0
        ? (remainingElevationGainMeters / params.metersPerHourClimb)
        : 0;
    final totalSeconds = ((flatHours + climbHours) * 3600).round();
    return Duration(seconds: totalSeconds.clamp(0, 60 * 60 * 24));
  }

  /// Format orario di arrivo come "HH:mm" (24h locale).
  /// Es. now=14:00, eta=35min → "14:35".
  /// Se la durata supera le 23h ritorna formato compatto Naismith
  /// (l'orario assoluto su >1 giorno è poco utile).
  static String formatArrivalClock(DateTime now, Duration eta) {
    if (eta <= Duration.zero) return '—';
    if (eta.inHours >= 24) return formatCompact(eta);
    final arrival = now.add(eta);
    final h = arrival.hour.toString().padLeft(2, '0');
    final m = arrival.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Formattazione compatta della Duration:
  /// - 0:45  → "45 min"
  /// - 2:00  → "2 h"
  /// - 2:15  → "2h 15m"
  /// - 4h+   → "4h 30m"
  static String formatCompact(Duration d) {
    if (d <= Duration.zero) return '—';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h <= 0) return '$m min';
    if (m == 0) return '$h h';
    return '${h}h ${m}m';
  }

  /// Komoot K1b Step 4 — ETA terrain-aware.
  ///
  /// A differenza di [estimate] (che usa una velocità unica per attività),
  /// questo metodo applica un moltiplicatore di velocità per ogni
  /// segmento di terreno, leggendo i `TerrainSegment` denormalizzati.
  ///
  /// Per ogni segmento:
  /// 1. Calcola distanza percorsa nei punti tra startPointIdx e endPointIdx
  ///    (somma Haversine consecutiva)
  /// 2. Calcola dislivello positivo nei punti del segmento
  /// 3. Calcola velocità effettiva = baseSpeed × [terrainSpeedFactor]
  /// 4. Tempo segmento = distance/speed + climb/metersPerHourClimb
  ///
  /// Somma i tempi dei segmenti.
  ///
  /// Fallback: se [segments] è vuoto, ricade su [estimate] usando
  /// distanza totale + dislivello stimato dai punti.
  static Duration estimateWithTerrain({
    required List<TrackPoint> points,
    required List<TerrainSegment> segments,
    required ActivityType activityType,
  }) {
    if (points.length < 2) return Duration.zero;
    final params = _paramsFor(activityType);
    if (params.speedKmh <= 0) return Duration.zero;

    // Fallback se niente segmenti: comportamento legacy
    if (segments.isEmpty) {
      final totalDist = _haversineCumulative(points);
      final totalGain = _cumulativeGain(points);
      return estimate(
        distanceMeters: totalDist,
        elevationGainMeters: totalGain,
        activityType: activityType,
      );
    }

    double totalSeconds = 0;
    for (final seg in segments) {
      final start = seg.startPointIdx.clamp(0, points.length - 1);
      final end = (seg.endPointIdx + 1).clamp(start + 1, points.length);
      if (end - start < 2) continue;
      final sub = points.sublist(start, end);
      final segDistMeters = _haversineCumulative(sub);
      final segGainMeters = _cumulativeGain(sub);
      final factor = terrainSpeedFactor(seg.type, activityType);
      final effectiveSpeed = params.speedKmh * factor;
      if (effectiveSpeed <= 0) continue;
      final flatHours = (segDistMeters / 1000) / effectiveSpeed;
      // Il climbing factor è meno influenzato dal terreno (su asfalto
      // 1000m gain in salita = comunque ~1h). Però su roccia la salita
      // è ancora più lenta, quindi applichiamo un mezzo factor.
      final climbFactor = 0.5 + factor * 0.5; // smorzato
      final adjustedClimbRate = params.metersPerHourClimb * climbFactor;
      final climbHours = adjustedClimbRate > 0
          ? (segGainMeters / adjustedClimbRate)
          : 0;
      totalSeconds += (flatHours + climbHours) * 3600;
    }

    return Duration(seconds: totalSeconds.round());
  }

  /// Moltiplicatore di velocità per ogni combinazione
  /// (TerrainType × ActivityType). Valori empirici:
  /// - 1.0 = velocità base per quell'attività
  /// - 0.5 = metà velocità (terreno difficile)
  /// - 1.1 = leggermente più veloce (asfalto in bici)
  /// - 0.0 = praticamente fermo (ferrata = arrampicata cauta)
  ///
  /// Esposto pubblicamente per UI tooltip / debug.
  static double terrainSpeedFactor(TerrainType terrain, ActivityType activity) {
    // Categorizza attività in "pedestre" vs "ciclo" per semplicità
    final isCycling = switch (activity) {
      ActivityType.cycling ||
      ActivityType.gravelBiking ||
      ActivityType.mountainBiking ||
      ActivityType.eBike ||
      ActivityType.eMountainBike =>
        true,
      _ => false,
    };

    switch (terrain) {
      case TerrainType.asphalt:
        if (isCycling) return 1.10; // bici è ottimizzata per asfalto
        return 1.00; // pedestre normale
      case TerrainType.gravel:
        if (isCycling) {
          return activity == ActivityType.cycling ? 0.65 : 0.85;
        }
        return 0.95;
      case TerrainType.path:
        if (isCycling) {
          return activity == ActivityType.cycling ? 0.40 : 0.70;
        }
        return 1.00;
      case TerrainType.rocky:
        if (isCycling) return 0.30; // a piedi quasi
        return 0.55;
      case TerrainType.viaFerrata:
        return 0.20; // procedi cauto, attrezzatura
      case TerrainType.unknown:
        return 0.95; // leggermente conservativo
    }
  }

  /// Somma cumulativa delle distanze Haversine tra punti consecutivi.
  static double _haversineCumulative(List<TrackPoint> pts) {
    double total = 0;
    for (var i = 1; i < pts.length; i++) {
      total += _haversineMeters(pts[i - 1], pts[i]);
    }
    return total;
  }

  /// Somma dei dislivelli positivi tra punti consecutivi (filtrando
  /// micro-variazioni < 1m che sono rumore GPS).
  static double _cumulativeGain(List<TrackPoint> pts) {
    double total = 0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1].elevation;
      final b = pts[i].elevation;
      if (a == null || b == null) continue;
      final diff = b - a;
      if (diff > 1) total += diff;
    }
    return total;
  }

  static double _haversineMeters(TrackPoint a, TrackPoint b) {
    const r = 6371000.0;
    double toRad(double d) => d * math.pi / 180;
    final dLat = toRad(b.latitude - a.latitude);
    final dLng = toRad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(a.latitude)) *
            math.cos(toRad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  static _Params _paramsFor(ActivityType t) {
    switch (t) {
      case ActivityType.trekking:
      case ActivityType.walking:
        return const _Params(speedKmh: 4, metersPerHourClimb: 600);
      case ActivityType.trailRunning:
        return const _Params(speedKmh: 8, metersPerHourClimb: 900);
      case ActivityType.running:
        return const _Params(speedKmh: 10, metersPerHourClimb: 1100);
      case ActivityType.cycling:
        return const _Params(speedKmh: 18, metersPerHourClimb: 1500);
      case ActivityType.mountainBiking:
        return const _Params(speedKmh: 12, metersPerHourClimb: 900);
      case ActivityType.gravelBiking:
        return const _Params(speedKmh: 16, metersPerHourClimb: 1200);
      case ActivityType.eBike:
        return const _Params(speedKmh: 20, metersPerHourClimb: 2200);
      case ActivityType.eMountainBike:
        return const _Params(speedKmh: 16, metersPerHourClimb: 1800);
      case ActivityType.alpineSkiing:
      case ActivityType.snowboarding:
        // Discese: distanza percorsa rapidamente, salita praticamente nulla.
        return const _Params(speedKmh: 25, metersPerHourClimb: 3000);
      case ActivityType.skiTouring:
        // Scialpinismo: salita lenta ma costante.
        return const _Params(speedKmh: 3, metersPerHourClimb: 400);
      case ActivityType.nordicSkiing:
        return const _Params(speedKmh: 12, metersPerHourClimb: 900);
      case ActivityType.snowshoeing:
        return const _Params(speedKmh: 3, metersPerHourClimb: 400);
    }
  }
}

class _Params {
  /// Velocità di crociera in piano (km/h).
  final double speedKmh;

  /// Metri di dislivello positivo che si possono guadagnare in 1 ora a
  /// velocità di crociera (oltre al tempo di percorrenza piano).
  final double metersPerHourClimb;

  const _Params({
    required this.speedKmh,
    required this.metersPerHourClimb,
  });
}
