import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipo di [WeeklyChallenge]: determina quale metrica viene misurata e
/// l'unità del target/progress.
enum WeeklyChallengeType {
  /// Distanza totale cumulata in metri.
  distance,

  /// Dislivello positivo cumulato in metri.
  elevation,

  /// Numero di tracce registrate (conteggio intero).
  tracks,

  /// Tempo di movimento cumulato in secondi.
  duration;

  String get code {
    switch (this) {
      case WeeklyChallengeType.distance:
        return 'distance';
      case WeeklyChallengeType.elevation:
        return 'elevation';
      case WeeklyChallengeType.tracks:
        return 'tracks';
      case WeeklyChallengeType.duration:
        return 'duration';
    }
  }

  static WeeklyChallengeType fromCode(String code) {
    switch (code) {
      case 'distance':
        return WeeklyChallengeType.distance;
      case 'elevation':
        return WeeklyChallengeType.elevation;
      case 'tracks':
        return WeeklyChallengeType.tracks;
      case 'duration':
        return WeeklyChallengeType.duration;
      default:
        return WeeklyChallengeType.distance;
    }
  }
}

/// Stato corrente della sfida.
enum WeeklyChallengeStatus { active, completed, failed }

/// Sfida settimanale personalizzata per un utente.
///
/// Storage: `users/{uid}/weekly_challenges/{challengeId}`.
/// Viene generata localmente dal [WeeklyChallengesService] al primo
/// ingresso dell'utente in una settimana nuova (lunedì 00:00 local).
class WeeklyChallenge {
  final String id;
  final String userId;
  final WeeklyChallengeType type;

  /// Target da raggiungere.
  /// - distance/elevation: metri
  /// - tracks: int (come double per uniformità)
  /// - duration: secondi
  final double target;

  /// Progresso corrente (stessa unità del target).
  final double progress;

  /// Inizio settimana (lunedì 00:00 ora locale).
  final DateTime weekStart;

  /// Fine settimana (domenica 23:59:59 ora locale).
  final DateTime weekEnd;

  final WeeklyChallengeStatus status;
  final DateTime? completedAt;
  final int xpReward;
  final DateTime createdAt;

  const WeeklyChallenge({
    required this.id,
    required this.userId,
    required this.type,
    required this.target,
    required this.progress,
    required this.weekStart,
    required this.weekEnd,
    required this.status,
    this.completedAt,
    required this.xpReward,
    required this.createdAt,
  });

  double get progressRatio => target <= 0 ? 0 : (progress / target).clamp(0.0, 1.0);

  bool get isCompleted => status == WeeklyChallengeStatus.completed;
  bool get isActive => status == WeeklyChallengeStatus.active;

  WeeklyChallenge copyWith({
    double? progress,
    WeeklyChallengeStatus? status,
    DateTime? completedAt,
  }) {
    return WeeklyChallenge(
      id: id,
      userId: userId,
      type: type,
      target: target,
      progress: progress ?? this.progress,
      weekStart: weekStart,
      weekEnd: weekEnd,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      xpReward: xpReward,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'type': type.code,
      'target': target,
      'progress': progress,
      'weekStart': Timestamp.fromDate(weekStart),
      'weekEnd': Timestamp.fromDate(weekEnd),
      'status': status.name,
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
      'xpReward': xpReward,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory WeeklyChallenge.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime parseTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    final statusStr = data['status']?.toString() ?? 'active';
    final status = WeeklyChallengeStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => WeeklyChallengeStatus.active,
    );

    return WeeklyChallenge(
      id: id,
      userId: data['userId']?.toString() ?? '',
      type: WeeklyChallengeType.fromCode(data['type']?.toString() ?? 'distance'),
      target: (data['target'] as num?)?.toDouble() ?? 0,
      progress: (data['progress'] as num?)?.toDouble() ?? 0,
      weekStart: parseTs(data['weekStart']),
      weekEnd: parseTs(data['weekEnd']),
      status: status,
      completedAt: data['completedAt'] != null ? parseTs(data['completedAt']) : null,
      xpReward: (data['xpReward'] as num?)?.toInt() ?? 50,
      createdAt: parseTs(data['createdAt']),
    );
  }
}

/// Helper per calcolare l'intervallo [weekStart, weekEnd] della settimana
/// corrente, con lunedì come primo giorno.
class WeekBoundaries {
  final DateTime start;
  final DateTime end;

  const WeekBoundaries(this.start, this.end);

  static WeekBoundaries forNow([DateTime? now]) {
    final n = now ?? DateTime.now();
    // DateTime.weekday: 1=lunedì, 7=domenica.
    final daysFromMonday = n.weekday - 1;
    final monday = DateTime(n.year, n.month, n.day).subtract(Duration(days: daysFromMonday));
    final sunday = monday
        .add(const Duration(days: 7))
        .subtract(const Duration(milliseconds: 1));
    return WeekBoundaries(monday, sunday);
  }

  /// Data ISO YYYY-WW (es. "2026-17"). Usato come doc ID stabile per
  /// evitare duplicati se il generator viene chiamato più volte.
  String get isoWeekId {
    final y = start.year.toString().padLeft(4, '0');
    final daysSinceFirstOfYear = start.difference(DateTime(start.year, 1, 1)).inDays;
    final weekNum = ((daysSinceFirstOfYear + DateTime(start.year, 1, 1).weekday - 1) ~/ 7) + 1;
    return '$y-${weekNum.toString().padLeft(2, '0')}';
  }
}
