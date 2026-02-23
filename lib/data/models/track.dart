import 'dart:math';

/// Rappresenta un singolo punto GPS della traccia
class TrackPoint {
  final double latitude;
  final double longitude;
  final double? elevation;
  final DateTime timestamp;
  final double? speed;
  final double? accuracy;
  final double? heading;

  const TrackPoint({
    required this.latitude,
    required this.longitude,
    this.elevation,
    required this.timestamp,
    this.speed,
    this.accuracy,
    this.heading,
  });

  /// Distanza in metri verso un altro punto (Haversine)
  double distanceTo(TrackPoint other) {
    const R = 6371000.0;
    final dLat = _toRad(other.latitude - latitude);
    final dLon = _toRad(other.longitude - longitude);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(latitude)) * cos(_toRad(other.latitude)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  Map<String, dynamic> toMap() {
    return {
      'lat': latitude,
      'lng': longitude,
      'ele': elevation,
      'time': timestamp.toIso8601String(),
      'speed': speed,
      'accuracy': accuracy,
      'heading': heading,
    };
  }

  /// Crea da Map - ROBUSTO per gestire diversi formati dal JS
  factory TrackPoint.fromMap(Map<String, dynamic> map) {
    // Latitude - prova diversi nomi campo
    double lat = 0;
    if (map['lat'] != null) {
      lat = (map['lat'] as num).toDouble();
    } else if (map['latitude'] != null) {
      lat = (map['latitude'] as num).toDouble();
    }

    // Longitude - prova diversi nomi campo
    double lng = 0;
    if (map['lng'] != null) {
      lng = (map['lng'] as num).toDouble();
    } else if (map['lon'] != null) {
      lng = (map['lon'] as num).toDouble();
    } else if (map['longitude'] != null) {
      lng = (map['longitude'] as num).toDouble();
    }

    // Elevation - prova diversi nomi campo
    double? ele;
    if (map['ele'] != null) {
      ele = (map['ele'] as num).toDouble();
    } else if (map['elevation'] != null) {
      ele = (map['elevation'] as num).toDouble();
    } else if (map['altitude'] != null) {
      ele = (map['altitude'] as num).toDouble();
    }

    // Timestamp
    DateTime timestamp = DateTime.now();
    if (map['time'] != null) {
      timestamp = DateTime.tryParse(map['time'].toString()) ?? DateTime.now();
    } else if (map['timestamp'] != null) {
      if (map['timestamp'] is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(map['timestamp']);
      } else {
        timestamp = DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now();
      }
    }

    return TrackPoint(
      latitude: lat,
      longitude: lng,
      elevation: ele,
      timestamp: timestamp,
      speed: (map['speed'] as num?)?.toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      heading: (map['heading'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() => 'TrackPoint($latitude, $longitude, ele: $elevation)';
}


/// Tipo di attività
// ============================================================
// NUOVO ENUM ActivityType per track.dart
// 
// ISTRUZIONI: Sostituire SOLO l'enum ActivityType nel file
// lib/data/models/track.dart (righe 108-140 circa)
// NON toccare il resto del file (TrackPoint, Track, TrackStats)
// ============================================================

// IMPORTANTE: i primi 4 valori (trekking, trailRunning, walking, cycling)
// DEVONO restare nello stesso ordine perché recording_persistence_service
// usa l'indice numerico (ActivityType.values[index]) per deserializzare.
// I nuovi valori vanno SEMPRE aggiunti IN FONDO.

enum ActivityType {
  // === Esistenti (NON cambiare ordine! index 0-3) ===
  trekking,       // 0
  trailRunning,   // 1
  walking,        // 2
  cycling,        // 3

  // === Nuovi - Corsa ===
  running,        // 4

  // === Nuovi - Bicicletta ===
  mountainBiking, // 5
  gravelBiking,   // 6
  eBike,          // 7
  eMountainBike,  // 8

  // === Nuovi - Sport invernali ===
  alpineSkiing,   // 9
  skiTouring,     // 10 (scialpinismo)
  nordicSkiing,   // 11
  snowshoeing,    // 12
  snowboarding;   // 13

  /// Nome visualizzato
  String get displayName {
    switch (this) {
      case ActivityType.trekking:
        return 'Trekking';
      case ActivityType.trailRunning:
        return 'Trail Running';
      case ActivityType.walking:
        return 'Camminata';
      case ActivityType.cycling:
        return 'Ciclismo';
      case ActivityType.running:
        return 'Corsa';
      case ActivityType.mountainBiking:
        return 'Mountain Bike';
      case ActivityType.gravelBiking:
        return 'Gravel Bike';
      case ActivityType.eBike:
        return 'E-Bike';
      case ActivityType.eMountainBike:
        return 'E-Mountain Bike';
      case ActivityType.alpineSkiing:
        return 'Sci Alpino';
      case ActivityType.skiTouring:
        return 'Scialpinismo';
      case ActivityType.nordicSkiing:
        return 'Sci Nordico';
      case ActivityType.snowshoeing:
        return 'Racchette da Neve';
      case ActivityType.snowboarding:
        return 'Snowboard';
    }
  }

  /// Emoji icona
  String get icon {
    switch (this) {
      case ActivityType.trekking:
        return '🥾';
      case ActivityType.trailRunning:
        return '🏃';
      case ActivityType.walking:
        return '🚶';
      case ActivityType.cycling:
        return '🚴';
      case ActivityType.running:
        return '🏃‍♂️';
      case ActivityType.mountainBiking:
        return '🚵';
      case ActivityType.gravelBiking:
        return '🚴‍♂️';
      case ActivityType.eBike:
        return '⚡';
      case ActivityType.eMountainBike:
        return '⚡';
      case ActivityType.alpineSkiing:
        return '⛷️';
      case ActivityType.skiTouring:
        return '🎿';
      case ActivityType.nordicSkiing:
        return '🎿';
      case ActivityType.snowshoeing:
        return '❄️';
      case ActivityType.snowboarding:
        return '🏂';
    }
  }

  /// Categoria sport (per raggruppamento nel selettore)
  String get category {
    switch (this) {
      case ActivityType.trekking:
      case ActivityType.trailRunning:
      case ActivityType.walking:
      case ActivityType.running:
        return 'A piedi';
      case ActivityType.cycling:
      case ActivityType.mountainBiking:
      case ActivityType.gravelBiking:
      case ActivityType.eBike:
      case ActivityType.eMountainBike:
        return 'In bicicletta';
      case ActivityType.alpineSkiing:
      case ActivityType.skiTouring:
      case ActivityType.nordicSkiing:
      case ActivityType.snowshoeing:
      case ActivityType.snowboarding:
        return 'Sport invernali';
    }
  }

  /// Profilo elevazione da usare per il filtraggio GPS
  /// Mappa le nuove attività ai profili esistenti di ElevationProcessor
  String get elevationProfile {
    switch (this) {
      case ActivityType.trekking:
      case ActivityType.skiTouring:
      case ActivityType.snowshoeing:
        return 'trekking';
      case ActivityType.trailRunning:
      case ActivityType.running:
        return 'trailRunning';
      case ActivityType.walking:
      case ActivityType.nordicSkiing:
        return 'walking';
      case ActivityType.cycling:
      case ActivityType.mountainBiking:
      case ActivityType.gravelBiking:
      case ActivityType.eBike:
      case ActivityType.eMountainBike:
        return 'cycling';
      case ActivityType.alpineSkiing:
      case ActivityType.snowboarding:
        return 'cycling'; // Discese veloci, simile a ciclismo
    }
  }
}

/// Statistiche della traccia
class TrackStats {
  final double distance;
  final double elevationGain;
  final double elevationLoss;
  final double maxElevation;
  final double minElevation;
  final Duration duration;
  final Duration movingTime;
  final double currentSpeed;
  final double avgSpeed;
  final double maxSpeed;

  const TrackStats({
    this.distance = 0,
    this.elevationGain = 0,
    this.elevationLoss = 0,
    this.maxElevation = 0,
    this.minElevation = 0,
    this.duration = Duration.zero,
    this.movingTime = Duration.zero,
    this.currentSpeed = 0,
    this.avgSpeed = 0,
    this.maxSpeed = 0,
  });

  double get distanceKm => distance / 1000;
  String get durationFormatted {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  TrackStats copyWith({
    double? distance,
    double? elevationGain,
    double? elevationLoss,
    double? maxElevation,
    double? minElevation,
    Duration? duration,
    Duration? movingTime,
    double? currentSpeed,
    double? avgSpeed,
    double? maxSpeed,
  }) {
    return TrackStats(
      distance: distance ?? this.distance,
      elevationGain: elevationGain ?? this.elevationGain,
      elevationLoss: elevationLoss ?? this.elevationLoss,
      maxElevation: maxElevation ?? this.maxElevation,
      minElevation: minElevation ?? this.minElevation,
      duration: duration ?? this.duration,
      movingTime: movingTime ?? this.movingTime,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      avgSpeed: avgSpeed ?? this.avgSpeed,
      maxSpeed: maxSpeed ?? this.maxSpeed,
    );
  }
}


/// 📸 NUOVO: Metadata foto traccia
class TrackPhotoMetadata {
  final String url;
  final double? latitude;
  final double? longitude;
  final double? elevation;
  final DateTime timestamp;
  final String? caption;

  const TrackPhotoMetadata({
    required this.url,
    this.latitude,
    this.longitude,
    this.elevation,
    required this.timestamp,
    this.caption,
  });

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'latitude': latitude,
      'longitude': longitude,
      'elevation': elevation,
      'timestamp': timestamp.toIso8601String(),
      'caption': caption,
    };
  }

  factory TrackPhotoMetadata.fromMap(Map<String, dynamic> map) {
    return TrackPhotoMetadata(
      url: map['url'] as String,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      elevation: map['elevation'] as double?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      caption: map['caption'] as String?,
    );
  }
}


/// Traccia completa (CON FOTO)
class Track {
  final String? id;
  final String name;
  final String? description;
  final List<TrackPoint> points;
  final ActivityType activityType;
  final DateTime? recordedAt;
  final DateTime createdAt;
  final String? userId;
  final bool isPublic;
  final bool isPlanned;
  final TrackStats stats;
  
  // 📸 NUOVO: Lista foto
  final List<TrackPhotoMetadata> photos;

  // ❤️ Dati battito cardiaco da Health Connect/Apple Health
  // Mappa: timestamp -> BPM
  final Map<DateTime, int>? heartRateData;
  // 🔥 Calorie reali da Health Connect/Apple Health
  final double? healthCalories;
  // 👣 Passi da Health Connect/Apple Health
  final int? healthSteps;

  const Track({
    this.id,
    required this.name,
    this.description,
    required this.points,
    this.activityType = ActivityType.trekking,
    this.recordedAt,
    required this.createdAt,
    this.userId,
    this.isPublic = false,
    this.isPlanned = false,
    this.stats = const TrackStats(),
    this.photos = const [], // 📸 Default: nessuna foto
    this.heartRateData, // ❤️ Battito cardiaco (opzionale)
    this.healthCalories, // 🔥 Calorie reali (opzionale)
    this.healthSteps, // 👣 Passi (opzionale)
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'description': description,
      'points': points.map((p) => p.toMap()).toList(),
      'activityType': activityType.name,
      'recordedAt': recordedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'userId': userId,
      'isPublic': isPublic,
      'isPlanned': isPlanned,
      'distance': stats.distance,
      'elevationGain': stats.elevationGain,
      'elevationLoss': stats.elevationLoss,
      'duration': stats.duration.inSeconds,
      'movingTime': stats.movingTime.inSeconds,
      // 📸 NUOVO
      'photos': photos.map((p) => p.toMap()).toList(),
    };

    // ❤️ Battito cardiaco (aggiunto separatamente per chiarezza)
    if (heartRateData != null && heartRateData!.isNotEmpty) {
      map['heartRateData'] = heartRateData!.map(
        (key, value) => MapEntry(key.millisecondsSinceEpoch.toString(), value),
      );
    }
    if (healthCalories != null) {
      map['healthCalories'] = healthCalories;
    }
    if (healthSteps != null) {
      map['healthSteps'] = healthSteps;
    }

    return map;
  }

  Track copyWith({
    String? id,
    String? name,
    String? description,
    List<TrackPoint>? points,
    ActivityType? activityType,
    DateTime? recordedAt,
    DateTime? createdAt,
    String? userId,
    bool? isPublic,
    bool? isPlanned,
    TrackStats? stats,
    List<TrackPhotoMetadata>? photos, // 📸 NUOVO
    Map<DateTime, int>? heartRateData, // ❤️
    double? healthCalories, // 🔥
    int? healthSteps, // 👣
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      points: points ?? this.points,
      activityType: activityType ?? this.activityType,
      recordedAt: recordedAt ?? this.recordedAt,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      isPublic: isPublic ?? this.isPublic,
      isPlanned: isPlanned ?? this.isPlanned,
      stats: stats ?? this.stats,
      photos: photos ?? this.photos, // 📸 NUOVO
      heartRateData: heartRateData ?? this.heartRateData, // ❤️
      healthCalories: healthCalories ?? this.healthCalories, // 🔥
      healthSteps: healthSteps ?? this.healthSteps, // 👣
    );
  }
}
