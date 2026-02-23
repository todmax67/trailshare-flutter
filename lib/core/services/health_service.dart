import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/track.dart';

/// Servizio per sincronizzazione con Apple Health / Google Health Connect
class HealthService {
  static final HealthService _instance = HealthService._internal();
  factory HealthService() => _instance;
  HealthService._internal();

  final Health _health = Health();
  bool _isConfigured = false;

  // Chiave per salvare preferenza sync
  static const _prefKey = 'health_sync_enabled';

  // Tipi di dati che leggiamo/scriviamo
  static final List<HealthDataType> _readTypes = [
    HealthDataType.WORKOUT,
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.HEART_RATE,
    HealthDataType.TOTAL_CALORIES_BURNED,
  ];

  static final List<HealthDataType> _writeTypes = [
    HealthDataType.WORKOUT,
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURAZIONE E PERMESSI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Configura il plugin Health (chiamare una volta all'avvio)
  Future<void> configure() async {
    if (_isConfigured) return;
    try {
      await _health.configure();
      _isConfigured = true;
      debugPrint('[HealthService] Configurato');
    } catch (e) {
      debugPrint('[HealthService] Errore configurazione: $e');
    }
  }

  /// Verifica se la sync è abilitata nelle preferenze
  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Abilita/disabilita sync
  Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
    debugPrint('[HealthService] Sync ${enabled ? "abilitata" : "disabilitata"}');
  }

  /// Richiedi permessi per leggere e scrivere dati salute
  Future<bool> requestPermissions() async {
    await configure();
    try {
      // Debug: verifica stato SDK
      final sdkStatus = await _health.getHealthConnectSdkStatus();
      debugPrint('[HealthService] SDK Status: $sdkStatus');
      
      final allTypes = {..._readTypes, ..._writeTypes}.toList();
      debugPrint('[HealthService] Tipi richiesti: ${allTypes.map((t) => t.name).toList()}');
      
      final permissions = allTypes.map((type) {
        if (_writeTypes.contains(type)) {
          return HealthDataAccess.READ_WRITE;
        }
        return HealthDataAccess.READ;
      }).toList();
      debugPrint('[HealthService] Permessi richiesti: ${permissions.map((p) => p.name).toList()}');

      final granted = await _health.requestAuthorization(
        allTypes,
        permissions: permissions,
      );

      debugPrint('[HealthService] Permessi: $granted');
      return granted;
    } catch (e, stack) {
      debugPrint('[HealthService] Errore permessi: $e');
      debugPrint('[HealthService] Stack: $stack');
      return false;
    }
  }

  /// Verifica se Health Connect è disponibile (solo Android)
  Future<bool> isHealthConnectAvailable() async {
    if (!Platform.isAndroid) return true; // iOS ha sempre HealthKit
    try {
      await configure();
      final status = await _health.getHealthConnectSdkStatus();
      return status == HealthConnectSdkStatus.sdkAvailable;
    } catch (e) {
      debugPrint('[HealthService] Health Connect non disponibile: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCRITTURA — Salva workout dopo registrazione
  // ═══════════════════════════════════════════════════════════════════════════

  /// Salva una traccia come workout su Health
  Future<bool> saveTrackAsWorkout(Track track) async {
    final enabled = await isSyncEnabled();
    if (!enabled) return false;

    await configure();

    try {
      final workoutType = _mapActivityType(track.activityType);
      final startTime = track.createdAt;
      final endTime = startTime.add(track.stats.duration);

      // Scrivi il workout
      final success = await _health.writeWorkoutData(
        activityType: workoutType,
        start: startTime,
        end: endTime,
        totalDistance: track.stats.distance.round(),
        totalEnergyBurned: _estimateCalories(track).round(),
      );

      if (success) {
        debugPrint('[HealthService] Workout salvato: ${track.name} '
            '(${track.stats.distance.round()}m, ${track.stats.duration.inMinutes}min)');
      } else {
        debugPrint('[HealthService] Errore salvataggio workout');
      }

      return success;
    } catch (e) {
      debugPrint('[HealthService] Errore writeWorkout: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LETTURA — Importa workout da Health
  // ═══════════════════════════════════════════════════════════════════════════

  /// Legge i workout degli ultimi N giorni
  Future<List<HealthWorkout>> getRecentWorkouts({int days = 30}) async {
    await configure();

    try {
      final now = DateTime.now();
      final start = now.subtract(Duration(days: days));

      final dataPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: start,
        endTime: now,
      );

      final workouts = <HealthWorkout>[];
      for (final dp in dataPoints) {
        if (dp.value is WorkoutHealthValue) {
          final wv = dp.value as WorkoutHealthValue;
          workouts.add(HealthWorkout(
            type: wv.workoutActivityType.name,
            startTime: dp.dateFrom,
            endTime: dp.dateTo,
            totalDistance: wv.totalDistance?.toDouble(),
            totalCalories: wv.totalEnergyBurned?.toDouble(),
            sourceName: dp.sourceName,
            sourceId: dp.sourceId,
          ));
        }
      }

      // Ordina per data, più recenti prima
      workouts.sort((a, b) => b.startTime.compareTo(a.startTime));

      debugPrint('[HealthService] Trovati ${workouts.length} workout negli ultimi $days giorni');
      return workouts;
    } catch (e) {
      debugPrint('[HealthService] Errore lettura workout: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LETTURA — Battito cardiaco per intervallo
  // ═══════════════════════════════════════════════════════════════════════════

  /// Legge i dati del battito cardiaco da Health Connect/Apple Health
  /// per l'intervallo di tempo specificato (es. durata di una traccia)
  /// Restituisce Map<DateTime, int> (timestamp -> BPM)
  Future<Map<DateTime, int>> getHeartRateForTimeRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final enabled = await isSyncEnabled();
    if (!enabled) {
      debugPrint('[HealthService] HR skip: sync disabilitata');
      return {};
    }

    await configure();

    try {
      // Aggiungi margine di 1 minuto prima e dopo
      final queryStart = start.subtract(const Duration(minutes: 1));
      final queryEnd = end.add(const Duration(minutes: 1));

      final dataPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: queryStart,
        endTime: queryEnd,
      );

      final heartRateMap = <DateTime, int>{};

      for (final dp in dataPoints) {
        if (dp.value is NumericHealthValue) {
          final numValue = dp.value as NumericHealthValue;
          final bpm = numValue.numericValue.round();
          if (bpm > 30 && bpm < 250) { // Filtra valori anomali
            heartRateMap[dp.dateFrom] = bpm;
          }
        }
      }

      // Ordina per timestamp
      final sorted = Map.fromEntries(
        heartRateMap.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      );

      debugPrint('[HealthService] HR trovati: ${sorted.length} campioni '
          '(${start.toIso8601String()} → ${end.toIso8601String()})');

      return sorted;
    } catch (e) {
      debugPrint('[HealthService] Errore lettura HR: $e');
      return {};
    }
  }

  /// Legge le calorie bruciate da Health Connect/Apple Health
  /// per l'intervallo di tempo specificato
  /// Restituisce il totale calorie o null se non disponibile
  Future<double?> getCaloriesForTimeRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final enabled = await isSyncEnabled();
    if (!enabled) return null;

    await configure();

    try {
      final queryStart = start.subtract(const Duration(minutes: 1));
      final queryEnd = end.add(const Duration(minutes: 1));

      final dataPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.TOTAL_CALORIES_BURNED],
        startTime: queryStart,
        endTime: queryEnd,
      );

      double totalCalories = 0;
      for (final dp in dataPoints) {
        if (dp.value is NumericHealthValue) {
          final numValue = dp.value as NumericHealthValue;
          totalCalories += numValue.numericValue.toDouble();
        }
      }

      debugPrint('[HealthService] Calorie trovate: ${totalCalories.round()} kcal '
          '(${start.toIso8601String()} → ${end.toIso8601String()})');

      return totalCalories > 0 ? totalCalories : null;
    } catch (e) {
      debugPrint('[HealthService] Errore lettura calorie: $e');
      return null;
    }
  }

  /// Legge i passi da Health Connect/Apple Health
  /// per l'intervallo di tempo specificato
  Future<int?> getStepsForTimeRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final enabled = await isSyncEnabled();
    if (!enabled) return null;

    await configure();

    try {
      final queryStart = start.subtract(const Duration(minutes: 1));
      final queryEnd = end.add(const Duration(minutes: 1));

      final dataPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.STEPS],
        startTime: queryStart,
        endTime: queryEnd,
      );

      int totalSteps = 0;
      for (final dp in dataPoints) {
        if (dp.value is NumericHealthValue) {
          final numValue = dp.value as NumericHealthValue;
          totalSteps += numValue.numericValue.round();
        }
      }

      debugPrint('[HealthService] Passi trovati: $totalSteps '
          '(${start.toIso8601String()} → ${end.toIso8601String()})');

      return totalSteps > 0 ? totalSteps : null;
    } catch (e) {
      debugPrint('[HealthService] Errore lettura passi: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DASHBOARD — Dati giornalieri e settimanali
  // ═══════════════════════════════════════════════════════════════════════════

  /// Passi di oggi
  Future<int> getTodaySteps() async {
    final enabled = await isSyncEnabled();
    if (!enabled) return 0;

    await configure();

    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);

      final dataPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.STEPS],
        startTime: midnight,
        endTime: now,
      );

      int total = 0;
      for (final dp in dataPoints) {
        if (dp.value is NumericHealthValue) {
          total += (dp.value as NumericHealthValue).numericValue.round();
        }
      }

      debugPrint('[HealthService] Passi oggi: $total');
      return total;
    } catch (e) {
      debugPrint('[HealthService] Errore passi oggi: $e');
      return 0;
    }
  }

  /// Battito a riposo (ultimo campione oggi con valore basso)
  Future<int?> getRestingHeartRate() async {
    final enabled = await isSyncEnabled();
    if (!enabled) return null;

    await configure();

    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);

      final dataPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: midnight,
        endTime: now,
      );

      if (dataPoints.isEmpty) return null;

      // Prendi i campioni HR e trova il minimo (approssimazione riposo)
      final hrValues = <int>[];
      for (final dp in dataPoints) {
        if (dp.value is NumericHealthValue) {
          final bpm = (dp.value as NumericHealthValue).numericValue.round();
          if (bpm > 30 && bpm < 120) {
            hrValues.add(bpm);
          }
        }
      }

      if (hrValues.isEmpty) return null;

      // Media dei 5 valori più bassi come stima riposo
      hrValues.sort();
      final lowest = hrValues.take(5).toList();
      final avg = lowest.reduce((a, b) => a + b) ~/ lowest.length;

      debugPrint('[HealthService] HR riposo stimato: $avg bpm (da ${hrValues.length} campioni)');
      return avg;
    } catch (e) {
      debugPrint('[HealthService] Errore HR riposo: $e');
      return null;
    }
  }

  /// Calorie degli ultimi 7 giorni (giorno per giorno)
  Future<Map<String, double>> getWeeklyCalories() async {
    final enabled = await isSyncEnabled();
    if (!enabled) return {};

    await configure();

    try {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));

      final dataPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.TOTAL_CALORIES_BURNED],
        startTime: weekAgo,
        endTime: now,
      );

      final daily = <String, double>{};

      // Inizializza tutti i 7 giorni
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final key = '${date.day}/${date.month}';
        daily[key] = 0;
      }

      for (final dp in dataPoints) {
        if (dp.value is NumericHealthValue) {
          final cal = (dp.value as NumericHealthValue).numericValue.toDouble();
          final key = '${dp.dateFrom.day}/${dp.dateFrom.month}';
          daily[key] = (daily[key] ?? 0) + cal;
        }
      }

      debugPrint('[HealthService] Calorie settimanali: $daily');
      return daily;
    } catch (e) {
      debugPrint('[HealthService] Errore calorie settimanali: $e');
      return {};
    }
  }

  /// Passi degli ultimi 7 giorni (giorno per giorno)
  Future<Map<String, int>> getWeeklySteps() async {
    final enabled = await isSyncEnabled();
    if (!enabled) return {};

    await configure();

    try {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));

      final dataPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.STEPS],
        startTime: weekAgo,
        endTime: now,
      );

      final daily = <String, int>{};

      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final key = '${date.day}/${date.month}';
        daily[key] = 0;
      }

      for (final dp in dataPoints) {
        if (dp.value is NumericHealthValue) {
          final steps = (dp.value as NumericHealthValue).numericValue.round();
          final key = '${dp.dateFrom.day}/${dp.dateFrom.month}';
          daily[key] = (daily[key] ?? 0) + steps;
        }
      }

      debugPrint('[HealthService] Passi settimanali: $daily');
      return daily;
    } catch (e) {
      debugPrint('[HealthService] Errore passi settimanali: $e');
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITÀ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Mappa ActivityType → HealthWorkoutActivityType
  HealthWorkoutActivityType _mapActivityType(ActivityType type) {
    switch (type) {
      case ActivityType.trekking:
        return HealthWorkoutActivityType.HIKING;
      case ActivityType.trailRunning:
      case ActivityType.running:
        return HealthWorkoutActivityType.RUNNING;
      case ActivityType.walking:
        return HealthWorkoutActivityType.WALKING;
      case ActivityType.cycling:
      case ActivityType.gravelBiking:
      case ActivityType.eBike:
        return HealthWorkoutActivityType.BIKING;
      case ActivityType.mountainBiking:
      case ActivityType.eMountainBike:
        return HealthWorkoutActivityType.BIKING;
      case ActivityType.alpineSkiing:
        return HealthWorkoutActivityType.SKIING;
      case ActivityType.skiTouring:
        return HealthWorkoutActivityType.SKIING;
      case ActivityType.nordicSkiing:
        return HealthWorkoutActivityType.CROSS_COUNTRY_SKIING;
      case ActivityType.snowshoeing:
        return HealthWorkoutActivityType.HIKING;
      default:
        return HealthWorkoutActivityType.OTHER;
    }
  }

  /// Stima calorie bruciate (formula base: MET * peso * ore)
  double _estimateCalories(Track track) {
    const weightKg = 70.0; // Peso medio stimato
    final hours = track.stats.duration.inMinutes / 60.0;
    
    // MET approssimativi per attività
    double met;
    switch (track.activityType) {
      case ActivityType.trekking:
      case ActivityType.skiTouring:
        met = 6.0;
        break;
      case ActivityType.trailRunning:
      case ActivityType.running:
        met = 9.0;
        break;
      case ActivityType.walking:
        met = 3.5;
        break;
      case ActivityType.cycling:
      case ActivityType.gravelBiking:
        met = 7.0;
        break;
      case ActivityType.mountainBiking:
      case ActivityType.eMountainBike:
        met = 8.0;
        break;
      case ActivityType.alpineSkiing:
        met = 5.0;
        break;
      case ActivityType.nordicSkiing:
        met = 8.0;
        break;
      case ActivityType.snowshoeing:
        met = 5.5;
        break;
      default:
        met = 5.0;
    }

    return met * weightKg * hours;
  }
}

/// Modello semplificato per workout letti da Health
class HealthWorkout {
  final String type;
  final DateTime startTime;
  final DateTime endTime;
  final double? totalDistance;
  final double? totalCalories;
  final String sourceName;
  final String sourceId;

  HealthWorkout({
    required this.type,
    required this.startTime,
    required this.endTime,
    this.totalDistance,
    this.totalCalories,
    required this.sourceName,
    required this.sourceId,
  });

  Duration get duration => endTime.difference(startTime);

  String get durationFormatted {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String get distanceFormatted {
    if (totalDistance == null) return '--';
    final km = totalDistance! / 1000;
    return '${km.toStringAsFixed(1)} km';
  }
}
