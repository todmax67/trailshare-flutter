/// Zone cardio basate sulla % della FC massima
/// Zona 1: Recupero (50-60%)
/// Zona 2: Base aerobica (60-70%)
/// Zona 3: Aerobica (70-80%)
/// Zona 4: Soglia (80-90%)
/// Zona 5: Massimo (90-100%)
class HeartRateZones {
  final int maxHR;

  const HeartRateZones({required this.maxHR});

  /// Restituisce la zona (1-5) per un dato BPM
  int getZone(int bpm) {
    final pct = (bpm / maxHR) * 100;
    if (pct >= 90) return 5;
    if (pct >= 80) return 4;
    if (pct >= 70) return 3;
    if (pct >= 60) return 2;
    return 1;
  }

  /// Range BPM per ogni zona
  Map<int, ZoneRange> get zones => {
    1: ZoneRange(
      zone: 1,
      name: 'Recupero',
      minBpm: (maxHR * 0.50).round(),
      maxBpm: (maxHR * 0.60).round(),
      minPct: 50,
      maxPct: 60,
    ),
    2: ZoneRange(
      zone: 2,
      name: 'Base aerobica',
      minBpm: (maxHR * 0.60).round(),
      maxBpm: (maxHR * 0.70).round(),
      minPct: 60,
      maxPct: 70,
    ),
    3: ZoneRange(
      zone: 3,
      name: 'Aerobica',
      minBpm: (maxHR * 0.70).round(),
      maxBpm: (maxHR * 0.80).round(),
      minPct: 70,
      maxPct: 80,
    ),
    4: ZoneRange(
      zone: 4,
      name: 'Soglia',
      minBpm: (maxHR * 0.80).round(),
      maxBpm: (maxHR * 0.90).round(),
      minPct: 80,
      maxPct: 90,
    ),
    5: ZoneRange(
      zone: 5,
      name: 'Massimo',
      minBpm: (maxHR * 0.90).round(),
      maxBpm: maxHR,
      minPct: 90,
      maxPct: 100,
    ),
  };

  /// Calcola la distribuzione del tempo nelle zone
  /// Prende una mappa timestamp->BPM e restituisce i secondi in ogni zona
  ZoneDistribution calculateDistribution(Map<DateTime, int> heartRateData) {
    if (heartRateData.isEmpty) return ZoneDistribution.empty();

    final entries = heartRateData.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final secondsPerZone = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    int totalSeconds = 0;

    for (int i = 0; i < entries.length - 1; i++) {
      final current = entries[i];
      final next = entries[i + 1];
      final duration = next.key.difference(current.key).inSeconds;

      // Ignora gap > 60 secondi (probabile interruzione sensore)
      if (duration > 0 && duration <= 60) {
        final zone = getZone(current.value);
        secondsPerZone[zone] = (secondsPerZone[zone] ?? 0) + duration;
        totalSeconds += duration;
      }
    }

    return ZoneDistribution(
      secondsPerZone: secondsPerZone,
      totalSeconds: totalSeconds,
    );
  }
}

/// Range di una singola zona
class ZoneRange {
  final int zone;
  final String name;
  final int minBpm;
  final int maxBpm;
  final int minPct;
  final int maxPct;

  const ZoneRange({
    required this.zone,
    required this.name,
    required this.minBpm,
    required this.maxBpm,
    required this.minPct,
    required this.maxPct,
  });
}

/// Distribuzione del tempo nelle zone
class ZoneDistribution {
  final Map<int, int> secondsPerZone;
  final int totalSeconds;

  const ZoneDistribution({
    required this.secondsPerZone,
    required this.totalSeconds,
  });

  factory ZoneDistribution.empty() => const ZoneDistribution(
    secondsPerZone: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
    totalSeconds: 0,
  );

  /// Percentuale di tempo in una zona
  double percentageForZone(int zone) {
    if (totalSeconds == 0) return 0;
    return ((secondsPerZone[zone] ?? 0) / totalSeconds) * 100;
  }

  /// Formatta i secondi in "Xm Ys"
  String formatDuration(int zone) {
    final secs = secondsPerZone[zone] ?? 0;
    final m = secs ~/ 60;
    final s = secs % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}