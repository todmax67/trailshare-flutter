import 'package:cloud_firestore/cloud_firestore.dart';

/// Report mensile automatico dell'attività dell'utente.
///
/// Storage: `users/{uid}/monthly_reports/{yyyy-MM}`. Il doc id coincide con
/// [MonthBoundaries.yearMonthId] del mese target, così il generator è
/// idempotente (upsert).
///
/// Generato e mantenuto aggiornato dal `MonthlyReportService`:
/// - al primo ingresso dell'utente in un mese nuovo viene creato/rigenerato
///   il report del mese PRECEDENTE (ormai chiuso) e dato in pasto al
///   Discovery Carousel ("Il tuo mese di marzo è pronto!");
/// - il report del mese CORRENTE è ricalcolato on-demand quando l'utente
///   apre la pagina "Il mio mese".
class MonthlyReport {
  /// Formato `yyyy-MM`, es. `2026-04`.
  final String id;
  final String userId;

  /// Primo istante del mese (giorno 1, 00:00:00 local).
  final DateTime monthStart;

  /// Ultimo istante del mese (ultimo giorno 23:59:59.999 local).
  final DateTime monthEnd;

  // ─── Totali del mese ────────────────────────────────────────────────
  final double distance; // metri
  final double elevationGain; // metri
  final double elevationLoss; // metri
  final int duration; // secondi (tempo totale)
  final int movingTime; // secondi (tempo di movimento)
  final int trackCount;

  /// Giorni distinti in cui l'utente ha registrato almeno una traccia.
  final int activeDays;

  /// Breakdown per tipo di attività: {'trekking': 5, 'bike': 2}.
  final Map<String, int> activityTypes;

  // ─── Record del mese ────────────────────────────────────────────────

  /// Distanza della traccia più lunga del mese (metri).
  final double bestDistance;

  /// Nome della traccia più lunga (display).
  final String? bestDistanceName;

  /// Dislivello della traccia con più D+ del mese (metri).
  final double bestElevation;

  final String? bestElevationName;

  // ─── Confronto col mese precedente ─────────────────────────────────
  /// Delta in percentuale rispetto al mese precedente. `null` se il mese
  /// precedente non ha report (utente nuovo). Positivo = miglioramento.
  final double? distanceDeltaPercent;
  final double? elevationDeltaPercent;
  final double? durationDeltaPercent;
  final double? tracksDeltaPercent;

  // ─── Badge conquistati nel mese ────────────────────────────────────
  /// ID dei badge sbloccati nel mese (vedi [GamificationService.availableBadges]).
  final List<String> badgesUnlocked;

  /// XP totali guadagnati nel mese.
  final int xpEarned;

  final DateTime generatedAt;

  const MonthlyReport({
    required this.id,
    required this.userId,
    required this.monthStart,
    required this.monthEnd,
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    required this.duration,
    required this.movingTime,
    required this.trackCount,
    required this.activeDays,
    required this.activityTypes,
    required this.bestDistance,
    this.bestDistanceName,
    required this.bestElevation,
    this.bestElevationName,
    this.distanceDeltaPercent,
    this.elevationDeltaPercent,
    this.durationDeltaPercent,
    this.tracksDeltaPercent,
    required this.badgesUnlocked,
    required this.xpEarned,
    required this.generatedAt,
  });

  double get distanceKm => distance / 1000;
  Duration get durationAsDuration => Duration(seconds: duration);
  Duration get movingTimeAsDuration => Duration(seconds: movingTime);

  /// True se il mese del report è ancora in corso (report "live").
  bool get isCurrentMonth {
    final now = DateTime.now();
    return now.year == monthStart.year && now.month == monthStart.month;
  }

  /// True se l'utente non ha registrato nulla nel mese.
  bool get isEmpty => trackCount == 0;

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'monthStart': Timestamp.fromDate(monthStart),
      'monthEnd': Timestamp.fromDate(monthEnd),
      'distance': distance,
      'elevationGain': elevationGain,
      'elevationLoss': elevationLoss,
      'duration': duration,
      'movingTime': movingTime,
      'trackCount': trackCount,
      'activeDays': activeDays,
      'activityTypes': activityTypes,
      'bestDistance': bestDistance,
      if (bestDistanceName != null) 'bestDistanceName': bestDistanceName,
      'bestElevation': bestElevation,
      if (bestElevationName != null) 'bestElevationName': bestElevationName,
      if (distanceDeltaPercent != null)
        'distanceDeltaPercent': distanceDeltaPercent,
      if (elevationDeltaPercent != null)
        'elevationDeltaPercent': elevationDeltaPercent,
      if (durationDeltaPercent != null)
        'durationDeltaPercent': durationDeltaPercent,
      if (tracksDeltaPercent != null)
        'tracksDeltaPercent': tracksDeltaPercent,
      'badgesUnlocked': badgesUnlocked,
      'xpEarned': xpEarned,
      'generatedAt': Timestamp.fromDate(generatedAt),
    };
  }

  factory MonthlyReport.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime parseTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    Map<String, int> parseIntMap(dynamic raw) {
      if (raw is! Map) return {};
      final out = <String, int>{};
      raw.forEach((k, v) {
        if (v is num) out[k.toString()] = v.toInt();
      });
      return out;
    }

    List<String> parseStringList(dynamic raw) {
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).toList(growable: false);
    }

    double? nullableDouble(dynamic v) =>
        v is num ? v.toDouble() : null;

    return MonthlyReport(
      id: id,
      userId: data['userId']?.toString() ?? '',
      monthStart: parseTs(data['monthStart']),
      monthEnd: parseTs(data['monthEnd']),
      distance: (data['distance'] as num?)?.toDouble() ?? 0,
      elevationGain: (data['elevationGain'] as num?)?.toDouble() ?? 0,
      elevationLoss: (data['elevationLoss'] as num?)?.toDouble() ?? 0,
      duration: (data['duration'] as num?)?.toInt() ?? 0,
      movingTime: (data['movingTime'] as num?)?.toInt() ?? 0,
      trackCount: (data['trackCount'] as num?)?.toInt() ?? 0,
      activeDays: (data['activeDays'] as num?)?.toInt() ?? 0,
      activityTypes: parseIntMap(data['activityTypes']),
      bestDistance: (data['bestDistance'] as num?)?.toDouble() ?? 0,
      bestDistanceName: data['bestDistanceName']?.toString(),
      bestElevation: (data['bestElevation'] as num?)?.toDouble() ?? 0,
      bestElevationName: data['bestElevationName']?.toString(),
      distanceDeltaPercent: nullableDouble(data['distanceDeltaPercent']),
      elevationDeltaPercent: nullableDouble(data['elevationDeltaPercent']),
      durationDeltaPercent: nullableDouble(data['durationDeltaPercent']),
      tracksDeltaPercent: nullableDouble(data['tracksDeltaPercent']),
      badgesUnlocked: parseStringList(data['badgesUnlocked']),
      xpEarned: (data['xpEarned'] as num?)?.toInt() ?? 0,
      generatedAt: parseTs(data['generatedAt']),
    );
  }
}

/// Helper per calcolare l'intervallo [monthStart, monthEnd] di un mese
/// (dal primo giorno 00:00:00 all'ultimo giorno 23:59:59.999 locali) e
/// per generare id stabili nel formato `yyyy-MM`.
class MonthBoundaries {
  final DateTime start;
  final DateTime end;

  const MonthBoundaries(this.start, this.end);

  static MonthBoundaries forNow([DateTime? now]) {
    final n = now ?? DateTime.now();
    return forYearMonth(n.year, n.month);
  }

  static MonthBoundaries forYearMonth(int year, int month) {
    final start = DateTime(year, month, 1);
    // Primo giorno del mese successivo - 1 ms = ultimo istante del mese.
    final nextMonthStart = (month == 12)
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    final end = nextMonthStart.subtract(const Duration(milliseconds: 1));
    return MonthBoundaries(start, end);
  }

  /// Il mese precedente a questo.
  MonthBoundaries previous() {
    final prevMonth = start.month == 1 ? 12 : start.month - 1;
    final prevYear = start.month == 1 ? start.year - 1 : start.year;
    return forYearMonth(prevYear, prevMonth);
  }

  /// `yyyy-MM`, es. `2026-04`.
  String get yearMonthId {
    final y = start.year.toString().padLeft(4, '0');
    final m = start.month.toString().padLeft(2, '0');
    return '$y-$m';
  }
}
