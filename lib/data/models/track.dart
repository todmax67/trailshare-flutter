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
enum ActivityType {
  trekking,
  trailRunning,
  walking,
  cycling;

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
    }
  }

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

  String get avgPace {
    if (avgSpeed <= 0) return '--:--';
    final paceSeconds = 1000 / avgSpeed;
    final minutes = (paceSeconds / 60).floor();
    final seconds = (paceSeconds % 60).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  double get avgSpeedKmh => avgSpeed * 3.6;
  double get currentSpeedKmh => currentSpeed * 3.6;
  double get distanceKm => distance / 1000;

  String get durationFormatted {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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


/// Traccia completa
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
  final TrackStats stats;

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
    this.stats = const TrackStats(),
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'points': points.map((p) => p.toMap()).toList(),
      'activityType': activityType.name,
      'recordedAt': recordedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'userId': userId,
      'isPublic': isPublic,
      'distance': stats.distance,
      'elevationGain': stats.elevationGain,
      'elevationLoss': stats.elevationLoss,
      'duration': stats.duration.inSeconds,
      'movingTime': stats.movingTime.inSeconds,
    };
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
    TrackStats? stats,
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
      stats: stats ?? this.stats,
    );
  }
}
