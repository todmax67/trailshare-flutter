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
