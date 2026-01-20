import 'package:cloud_firestore/cloud_firestore.dart';
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

  ActivityType _parseActivityType() {
    switch (activityType.toLowerCase()) {
      case 'trailrunning':
      case 'running':
      case 'run':
        return ActivityType.trailRunning;
      case 'cycling':
      case 'bike':
        return ActivityType.cycling;
      case 'walking':
      case 'walk':
        return ActivityType.walking;
      default:
        return ActivityType.trekking;
    }
  }
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
              
              // ⭐ NUOVO: Parse speed
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
                  speed: speed,  // ⭐ NUOVO: Aggiungi speed
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
}
