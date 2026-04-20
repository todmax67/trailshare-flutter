import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import 'track.dart';

/// Riepilogo denormalizzato di una tappa, salvato nel mirror `community_tours`
/// per permettere alla detail community di renderizzare polyline + lista tappe
/// senza accedere alle tracce private dell'autore.
class TourStageSummary {
  final String trackId;
  final String name;
  final String activityType;
  final double distance; // metri
  final double elevationGain; // metri
  final Duration duration;

  /// Polyline overview — punti downsamplati.
  final List<LatLng> points;

  /// true se la traccia sottostante è pubblicata in `community_tracks`
  /// (permette il tap-through alla detail community ricca).
  final bool isTrackPublic;

  /// Doc id in `community_tracks` a cui fa riferimento la tappa, quando
  /// pubblica. Può differire da [trackId] se la traccia è stata pubblicata
  /// dalla vecchia app JS con uno schema di id diverso.
  final String? communityTrackId;

  const TourStageSummary({
    required this.trackId,
    required this.name,
    required this.activityType,
    required this.distance,
    required this.elevationGain,
    required this.duration,
    required this.points,
    required this.isTrackPublic,
    this.communityTrackId,
  });

  double get distanceKm => distance / 1000;

  Map<String, dynamic> toMap() => {
        'trackId': trackId,
        'name': name,
        'activityType': activityType,
        'distance': distance,
        'elevationGain': elevationGain,
        'durationSeconds': duration.inSeconds,
        'points': points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'isTrackPublic': isTrackPublic,
        if (communityTrackId != null) 'communityTrackId': communityTrackId,
      };

  static TourStageSummary fromMap(Map<String, dynamic> map) {
    final rawPoints = (map['points'] as List?) ?? const [];
    final points = <LatLng>[];
    for (final p in rawPoints) {
      if (p is Map) {
        final lat = (p['lat'] as num?)?.toDouble();
        final lng = (p['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) points.add(LatLng(lat, lng));
      }
    }
    return TourStageSummary(
      trackId: map['trackId']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      activityType: map['activityType']?.toString() ?? 'trekking',
      distance: (map['distance'] as num?)?.toDouble() ?? 0,
      elevationGain: (map['elevationGain'] as num?)?.toDouble() ?? 0,
      duration: Duration(seconds: (map['durationSeconds'] as num?)?.toInt() ?? 0),
      points: points,
      isTrackPublic: map['isTrackPublic'] == true,
      communityTrackId: map['communityTrackId']?.toString(),
    );
  }
}

/// Bounding box geografico di un tour (aggregato dai punti delle tracce).
class TourBounds {
  final double north;
  final double south;
  final double east;
  final double west;

  const TourBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  Map<String, dynamic> toMap() => {
        'n': north,
        's': south,
        'e': east,
        'w': west,
      };

  static TourBounds? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final n = (map['n'] as num?)?.toDouble();
    final s = (map['s'] as num?)?.toDouble();
    final e = (map['e'] as num?)?.toDouble();
    final w = (map['w'] as num?)?.toDouble();
    if (n == null || s == null || e == null || w == null) return null;
    return TourBounds(north: n, south: s, east: e, west: w);
  }
}

/// Tour multi-giorno: aggregatore leggero di tracce già registrate.
///
/// Le tracce restano indipendenti in `users/{uid}/tracks`. Il tour memorizza
/// solo l'ordine delle tappe (`trackIds`) e i totali denormalizzati per
/// mostrare la list page senza rileggere N tracce.
class Tour {
  final String id;
  final String ownerId;
  final String ownerName;
  final String? ownerPhotoUrl;

  final String title;
  final String? description;
  final String? coverPhotoUrl;

  /// trackIds ordinati = sequenza delle tappe.
  final List<String> trackIds;

  final double totalDistance; // metri
  final double totalElevationGain; // metri
  final Duration totalDuration;
  final int daysCount;

  final TourBounds? bounds;

  final bool isPublic;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Popolato solo per i tour letti da `community_tours`.
  /// Per i tour privati resta null — la detail owner ricostruisce dalle tracce.
  final List<TourStageSummary>? stages;

  const Tour({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    this.ownerPhotoUrl,
    required this.title,
    this.description,
    this.coverPhotoUrl,
    required this.trackIds,
    required this.totalDistance,
    required this.totalElevationGain,
    required this.totalDuration,
    required this.daysCount,
    this.bounds,
    this.isPublic = false,
    required this.createdAt,
    this.updatedAt,
    this.stages,
  });

  double get totalDistanceKm => totalDistance / 1000;

  Tour copyWith({
    String? title,
    String? description,
    String? coverPhotoUrl,
    List<String>? trackIds,
    double? totalDistance,
    double? totalElevationGain,
    Duration? totalDuration,
    int? daysCount,
    TourBounds? bounds,
    bool? isPublic,
    DateTime? updatedAt,
  }) {
    return Tour(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName,
      ownerPhotoUrl: ownerPhotoUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      trackIds: trackIds ?? this.trackIds,
      totalDistance: totalDistance ?? this.totalDistance,
      totalElevationGain: totalElevationGain ?? this.totalElevationGain,
      totalDuration: totalDuration ?? this.totalDuration,
      daysCount: daysCount ?? this.daysCount,
      bounds: bounds ?? this.bounds,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Serializza per lo storage privato (`users/{uid}/tours`).
  /// Non include [stages] per mantenere il doc leggero.
  Map<String, dynamic> toFirestore() {
    return {
      'ownerId': ownerId,
      'ownerName': ownerName,
      if (ownerPhotoUrl != null) 'ownerPhotoUrl': ownerPhotoUrl,
      'title': title,
      if (description != null) 'description': description,
      if (coverPhotoUrl != null) 'coverPhotoUrl': coverPhotoUrl,
      'trackIds': trackIds,
      'totalDistance': totalDistance,
      'totalElevationGain': totalElevationGain,
      'totalDurationSeconds': totalDuration.inSeconds,
      'daysCount': daysCount,
      if (bounds != null) 'bounds': bounds!.toMap(),
      'isPublic': isPublic,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  /// Serializza per il mirror pubblico (`community_tours`).
  /// Include [stages] con polyline downsamplate per rendering standalone.
  Map<String, dynamic> toCommunityFirestore(List<TourStageSummary> stages) {
    return {
      ...toFirestore(),
      'stages': stages.map((s) => s.toMap()).toList(),
    };
  }

  factory Tour.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic v, {DateTime? fallback}) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? (fallback ?? DateTime.now());
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return fallback ?? DateTime.now();
    }

    return Tour(
      id: id,
      ownerId: data['ownerId']?.toString() ?? '',
      ownerName: data['ownerName']?.toString() ?? '',
      ownerPhotoUrl: data['ownerPhotoUrl']?.toString(),
      title: data['title']?.toString() ?? '',
      description: data['description']?.toString(),
      coverPhotoUrl: data['coverPhotoUrl']?.toString(),
      trackIds: (data['trackIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      totalDistance: (data['totalDistance'] as num?)?.toDouble() ?? 0,
      totalElevationGain: (data['totalElevationGain'] as num?)?.toDouble() ?? 0,
      totalDuration: Duration(seconds: (data['totalDurationSeconds'] as num?)?.toInt() ?? 0),
      daysCount: (data['daysCount'] as num?)?.toInt() ?? 0,
      bounds: TourBounds.fromMap(
        data['bounds'] is Map ? Map<String, dynamic>.from(data['bounds'] as Map) : null,
      ),
      isPublic: data['isPublic'] == true,
      createdAt: parseDate(data['createdAt']),
      updatedAt: data['updatedAt'] != null ? parseDate(data['updatedAt']) : null,
      stages: (data['stages'] as List?)
          ?.whereType<Map>()
          .map((m) => TourStageSummary.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }
}

/// Calcola gli aggregati di un tour a partire dalle tracce che lo compongono.
class TourAggregates {
  final double totalDistance;
  final double totalElevationGain;
  final Duration totalDuration;
  final int daysCount;
  final TourBounds? bounds;

  const TourAggregates({
    required this.totalDistance,
    required this.totalElevationGain,
    required this.totalDuration,
    required this.daysCount,
    required this.bounds,
  });

  /// [tracks] deve essere nell'ordine delle tappe.
  static TourAggregates fromTracks(List<Track> tracks) {
    double dist = 0;
    double elev = 0;
    Duration dur = Duration.zero;
    final days = <String>{};

    double? n, s, e, w;

    for (final t in tracks) {
      dist += t.stats.distance;
      elev += t.stats.elevationGain;
      dur += t.stats.duration;

      final refDate = t.recordedAt ?? t.createdAt;
      days.add('${refDate.year}-${refDate.month}-${refDate.day}');

      for (final p in t.points) {
        n = (n == null || p.latitude > n) ? p.latitude : n;
        s = (s == null || p.latitude < s) ? p.latitude : s;
        e = (e == null || p.longitude > e) ? p.longitude : e;
        w = (w == null || p.longitude < w) ? p.longitude : w;
      }
    }

    final bounds = (n != null && s != null && e != null && w != null)
        ? TourBounds(north: n, south: s, east: e, west: w)
        : null;

    return TourAggregates(
      totalDistance: dist,
      totalElevationGain: elev,
      totalDuration: dur,
      daysCount: days.length,
      bounds: bounds,
    );
  }
}
