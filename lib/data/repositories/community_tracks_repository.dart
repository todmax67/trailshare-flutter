import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/track.dart';

/// Modello per traccia della community
class CommunityTrack {
  final String id;
  final String name;
  final String? description;
  final String activityType;
  final String? difficulty;
  final double distance;
  final double elevationGain;
  final int duration;
  final List<TrackPoint> points;
  final String ownerId;
  final String ownerUsername;
  final DateTime? sharedAt;
  final int cheerCount;
  final List<String> photoUrls;

  const CommunityTrack({
    required this.id,
    required this.name,
    this.description,
    required this.activityType,
    this.difficulty,
    required this.distance,
    required this.elevationGain,
    required this.duration,
    required this.points,
    required this.ownerId,
    required this.ownerUsername,
    this.sharedAt,
    this.cheerCount = 0,
    this.photoUrls = const [],
  });

  double get distanceKm => distance / 1000;

  String get durationFormatted {
    if (duration == 0) return '--';
    
    // Normalizza la durata: potrebbe essere in millisecondi (vecchie tracce JS)
    int durationSeconds = duration;
    
    // Se la durata > 24 ore E abbiamo la distanza, verifica con velocità implicita
    if (duration > 86400 && distance > 0) {
      // Velocità implicita se interpretiamo come secondi
      final speedAsSeconds = (distance / 1000) / (duration / 3600);
      
      // Se velocità < 1 km/h, probabilmente è in millisecondi
      if (speedAsSeconds < 1) {
        final durationFromMs = (duration / 1000).round();
        final speedAsMs = (distance / 1000) / (durationFromMs / 3600);
        
        // Se velocità come ms è ragionevole (1-25 km/h), usa quella
        if (speedAsMs >= 1 && speedAsMs <= 25) {
          durationSeconds = durationFromMs;
        }
      }
    }
    
    final hours = durationSeconds ~/ 3600;
    final mins = (durationSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  String get activityIcon {
    switch (activityType.toLowerCase()) {
      case 'trekking':
      case 'hiking':
        return '🥾';
      case 'trailrunning':
      case 'running':
      case 'run':
        return '🏃';
      case 'cycling':
      case 'bike':
        return '🚴';
      case 'walking':
      case 'walk':
        return '🚶';
      case 'mountainbiking':
      case 'mountain_biking':
        return '🚵';
      case 'gravelbiking':
      case 'gravel_biking':
        return '🚴‍♂️';
      case 'ebike':
      case 'e_bike':
      case 'emountainbike':
      case 'e_mountain_bike':
        return '⚡';
      case 'alpineskiing':
      case 'alpine_skiing':
        return '⛷️';
      case 'skitouring':
      case 'ski_touring':
      case 'scialpinismo':
        return '🎿';
      case 'nordicskiing':
      case 'nordic_skiing':
        return '🎿';
      case 'snowshoeing':
        return '❄️';
      case 'snowboarding':
        return '🏂';
      default:
        return '🥾';
    }
  }

  String get difficultyIcon {
    switch (difficulty?.toLowerCase()) {
      case 'facile':
      case 'easy':
        return '🟢';
      case 'medio':
      case 'media':
      case 'medium':
        return '🔵';
      case 'difficile':
      case 'hard':
        return '🔴';
      default:
        return '⚪';
    }
  }

  /// Converte in Track per riusare i widget
  Track toTrack() {
    return Track(
      id: 'community_$id',
      name: name,
      description: description,
      points: points,
      activityType: _parseActivityType(),
      createdAt: sharedAt ?? DateTime.now(),
      stats: TrackStats(
        distance: distance,
        elevationGain: elevationGain,
        duration: Duration(seconds: duration),
      ),
    );
  }

  /// Converte la stringa activityType in enum ActivityType
  ActivityType _parseActivityType() {
    // Prima prova match diretto per nome enum
    for (final type in ActivityType.values) {
      if (type.name == activityType) return type;
    }

    // Fallback per vecchi formati stringa
    switch (activityType.toLowerCase()) {
      case 'trail_running':
      case 'trailrunning':
        return ActivityType.trailRunning;
      case 'cycling':
      case 'ciclismo':
      case 'bike':
        return ActivityType.cycling;
      case 'walking':
      case 'camminata':
      case 'walk':
        return ActivityType.walking;
      case 'running':
      case 'corsa':
      case 'run':
        return ActivityType.running;
      case 'mountain_biking':
      case 'mountainbiking':
        return ActivityType.mountainBiking;
      case 'gravel_biking':
      case 'gravelbiking':
        return ActivityType.gravelBiking;
      case 'ebike':
      case 'e_bike':
        return ActivityType.eBike;
      case 'emountainbike':
      case 'e_mountain_bike':
        return ActivityType.eMountainBike;
      case 'alpine_skiing':
      case 'alpineskiing':
        return ActivityType.alpineSkiing;
      case 'ski_touring':
      case 'skitouring':
      case 'scialpinismo':
        return ActivityType.skiTouring;
      case 'nordic_skiing':
      case 'nordicskiing':
        return ActivityType.nordicSkiing;
      case 'snowshoeing':
        return ActivityType.snowshoeing;
      case 'snowboarding':
        return ActivityType.snowboarding;
      default:
        return ActivityType.trekking;
    }
  }
}

/// Risultato paginato
class PaginatedCommunityTracks {
  final List<CommunityTrack> tracks;
  final QueryDocumentSnapshot? lastDocument;
  final bool hasMore;

  PaginatedCommunityTracks({
    required this.tracks,
    this.lastDocument,
    this.hasMore = true,
  });
}

/// Repository per le tracce della community
class CommunityTracksRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _tracksCollection {
    return _firestore.collection('published_tracks');
  }

  /// Ottieni tracce recenti della community
  Future<List<CommunityTrack>> getRecentTracks({int limit = 30}) async {
    try {
      final snapshot = await _tracksCollection
          .orderBy('sharedAt', descending: true)
          .limit(limit)
          .get();

      final tracks = <CommunityTrack>[];
      for (final doc in snapshot.docs) {
        final track = _docToTrack(doc);
        if (track != null) {
          tracks.add(track);
        }
      }

      print('[CommunityTracks] Caricate ${tracks.length} tracce');
      return tracks;
    } catch (e) {
      print('[CommunityTracks] Errore: $e');
      return [];
    }
  }

  /// Tracce recenti con paginazione
  Future<PaginatedCommunityTracks> getRecentTracksPaginated({
    int limit = 20,
    QueryDocumentSnapshot? startAfterDoc,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _tracksCollection
          .orderBy('sharedAt', descending: true)
          .limit(limit);

      if (startAfterDoc != null) {
        query = query.startAfterDocument(startAfterDoc);
      }

      final snapshot = await query.get();
      final tracks = <CommunityTrack>[];
      for (final doc in snapshot.docs) {
        final track = _docToTrack(doc);
        if (track != null) tracks.add(track);
      }

      debugPrint('[CommunityTracks] Paginate: ${tracks.length} tracce (hasMore: ${snapshot.docs.length == limit})');

      return PaginatedCommunityTracks(
        tracks: tracks,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length == limit,
      );
    } catch (e) {
      debugPrint('[CommunityTracks] Errore paginazione: $e');
      return PaginatedCommunityTracks(tracks: [], hasMore: false);
    }
  }

  /// Ottieni tracce più apprezzate
  Future<List<CommunityTrack>> getPopularTracks({int limit = 30}) async {
    try {
      final snapshot = await _tracksCollection
          .orderBy('cheerCount', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => _docToTrack(doc))
          .where((track) => track != null)
          .cast<CommunityTrack>()
          .toList();
    } catch (e) {
      print('[CommunityTracks] Errore: $e');
      return [];
    }
  }

  /// Cerca tracce per nome
  Future<List<CommunityTrack>> searchTracks(String query, {int limit = 20}) async {
    try {
      final snapshot = await _tracksCollection
          .orderBy('sharedAt', descending: true)
          .limit(100)
          .get();

      final queryLower = query.toLowerCase();

      return snapshot.docs
          .map((doc) => _docToTrack(doc))
          .where((track) => track != null)
          .cast<CommunityTrack>()
          .where((track) =>
              track.name.toLowerCase().contains(queryLower) ||
              track.ownerUsername.toLowerCase().contains(queryLower))
          .take(limit)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Ottieni tracce di un utente specifico
  Future<List<CommunityTrack>> getTracksByUser(String userId, {int limit = 20}) async {
    try {
      final snapshot = await _tracksCollection
          .where('originalOwnerId', isEqualTo: userId)
          .orderBy('sharedAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => _docToTrack(doc))
          .where((track) => track != null)
          .cast<CommunityTrack>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Ottieni singola traccia
  Future<CommunityTrack?> getTrackById(String trackId) async {
    try {
      final doc = await _tracksCollection.doc(trackId).get();
      if (!doc.exists) return null;
      return _docToTrack(doc);
    } catch (e) {
      return null;
    }
  }

  CommunityTrack? _docToTrack(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) return null;

      List<TrackPoint> points = [];

      // Parse points - possono essere in vari formati
      final pointsData = data['points'];
      if (pointsData != null && pointsData is List) {
        for (var p in pointsData) {
          try {
            double? lat, lon, ele, speed;
            DateTime? timestamp;

            if (p is Map) {
              // Formato oggetto {x/lon, y/lat, ele, timestamp, speed}
              lat = (p['y'] ?? p['lat'] ?? p['latitude'] as num?)?.toDouble();
              lon = (p['x'] ?? p['lon'] ?? p['lng'] ?? p['longitude'] as num?)?.toDouble();
              ele = (p['ele'] ?? p['elevation'] ?? p['altitude'] ?? p['z'] as num?)?.toDouble();
              
              // Parse speed
              speed = (p['speed'] as num?)?.toDouble();
              
              // Timestamp - gestisce vari formati
              final ts = p['timestamp'] ?? p['time'];
              if (ts is Timestamp) {
                timestamp = ts.toDate();
              } else if (ts is int) {
                timestamp = DateTime.fromMillisecondsSinceEpoch(ts);
              } else if (ts is String) {
                timestamp = DateTime.tryParse(ts);
              }
            } else if (p is List && p.length >= 2) {
              // Formato array [lon, lat, ele?, speed?]
              lon = (p[0] as num).toDouble();
              lat = (p[1] as num).toDouble();
              ele = p.length > 2 ? (p[2] as num?)?.toDouble() : null;
              speed = p.length > 3 ? (p[3] as num?)?.toDouble() : null;
            }

            if (lat != null && lon != null && lat != 0 && lon != 0) {
              if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
                points.add(TrackPoint(
                  latitude: lat,
                  longitude: lon,
                  elevation: ele,
                  timestamp: timestamp ?? DateTime.now(),
                  speed: speed,
                ));
              }
            }
          } catch (e) {
            // Skip punto invalido
          }
        }
      }

      if (points.isEmpty) {
        return null;
      }

      // Parse sharedAt
      DateTime? sharedAt;
      final sharedAtData = data['sharedAt'];
      if (sharedAtData is Timestamp) {
        sharedAt = sharedAtData.toDate();
      }

      // Parse photoUrls
      List<String> photoUrls = [];
      final photos = data['photoUrls'];
      if (photos is List) {
        photoUrls = photos.whereType<String>().toList();
      }

      return CommunityTrack(
        id: doc.id,
        name: data['name']?.toString() ?? 'Traccia senza nome',
        description: data['description']?.toString(),
        activityType: data['activityType']?.toString() ?? 'trekking',
        difficulty: data['difficulty']?.toString(),
        distance: (data['distance'] as num?)?.toDouble() ?? 0,
        elevationGain: (data['elevationGain'] as num?)?.toDouble() ?? 0,
        duration: (data['duration'] as num?)?.toInt() ?? 0,
        points: points,
        ownerId: data['originalOwnerId']?.toString() ?? '',
        ownerUsername: data['ownerUsername']?.toString() ?? 'Utente',
        sharedAt: sharedAt,
        cheerCount: (data['cheerCount'] as num?)?.toInt() ?? 0,
        photoUrls: photoUrls,
      );
    } catch (e) {
      print('[CommunityTracks] Errore parsing ${doc.id}: $e');
      return null;
    }
  }

  /// Pubblica una traccia nella community
  Future<bool> publishTrack({
    required String trackId,
    required String name,
    required String? description,
    required String activityType,
    required double distance,
    required double elevationGain,
    required int durationSeconds,
    required List<TrackPoint> points,
    required String ownerId,
    required String ownerUsername,
    List<String>? photoUrls,
    String? difficulty,
  }) async {
    try {
      // Converti punti in formato Firestore
      final pointsData = points.map((p) => {
        'lat': p.latitude,
        'lng': p.longitude,
        'ele': p.elevation,
        'time': p.timestamp.toIso8601String(),
        'speed': p.speed,
      }).toList();

      await _tracksCollection.doc(trackId).set({
        'name': name,
        'description': description,
        'activityType': activityType,
        'distance': distance,
        'elevationGain': elevationGain,
        'duration': durationSeconds,
        'points': pointsData,
        'originalOwnerId': ownerId,
        'ownerUsername': ownerUsername,
        'sharedAt': FieldValue.serverTimestamp(),
        'cheerCount': 0,
        'photoUrls': photoUrls ?? [],
        'difficulty': difficulty,
        'startLat': points.isNotEmpty ? points.first.latitude : null,
        'startLng': points.isNotEmpty ? points.first.longitude : null,
      });

      debugPrint('[CommunityTracks] Traccia pubblicata: $trackId');
      return true;
    } catch (e) {
      debugPrint('[CommunityTracks] Errore pubblicazione: $e');
      return false;
    }
  }

  /// Rimuovi una traccia dalla community
  Future<bool> unpublishTrack(String trackId) async {
    try {
      await _tracksCollection.doc(trackId).delete();
      debugPrint('[CommunityTracks] Traccia rimossa: $trackId');
      return true;
    } catch (e) {
      debugPrint('[CommunityTracks] Errore rimozione: $e');
      return false;
    }
  }
}
