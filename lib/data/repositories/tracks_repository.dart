import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/track.dart';

/// Risultato paginato per le tracce
class PaginatedTracksResult {
  final List<Track> tracks;
  final DocumentSnapshot? lastDocument;
  final bool hasMore;

  PaginatedTracksResult({
    required this.tracks,
    this.lastDocument,
    required this.hasMore,
  });
}

/// Repository unificato per gestire le tracce su Firestore
/// Compatibile con la struttura dati esistente dall'app JavaScript
class TracksRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Helper: ottiene la collection delle tracce per un dato userId
  CollectionReference<Map<String, dynamic>> _tracksCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('tracks');
  }

  /// Helper: ottiene la collection delle tracce per l'utente corrente
  CollectionReference<Map<String, dynamic>> get _myTracksCollection {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Utente non autenticato');
    return _tracksCollection(userId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CREAZIONE E SALVATAGGIO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Salva una nuova traccia e restituisce l'ID
  Future<String> saveTrack(Track track) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utente non autenticato');

    try {
      final data = _trackToFirestore(track, user.uid);
      final docRef = await _tracksCollection(user.uid).add(data);

      print('[TracksRepository] Traccia salvata con ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('[TracksRepository] Errore saveTrack: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LETTURA TRACCE - PAGINATA
  // ═══════════════════════════════════════════════════════════════════════════

  /// ⭐ NUOVO: Ottiene le tracce con paginazione
  /// [limit] - Numero di tracce per pagina (default 10)
  /// [lastDocument] - Ultimo documento della pagina precedente per paginazione
  Future<PaginatedTracksResult> getUserTracksPaginated(
    String userId, {
    int limit = 10,
    DocumentSnapshot? lastDocument,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _tracksCollection(userId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .limit(limit);

      // Se abbiamo un documento di partenza, inizia da lì
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snapshot = await query.get();

      print('[TracksRepository] Paginazione: ${snapshot.docs.length} tracce caricate');

      final tracks = snapshot.docs.map((doc) {
        return _trackFromFirestore(doc.id, doc.data());
      }).toList();

      return PaginatedTracksResult(
        tracks: tracks,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length == limit,
      );
    } catch (e) {
      print('[TracksRepository] Errore getUserTracksPaginated: $e');
      return PaginatedTracksResult(tracks: [], hasMore: false);
    }
  }

  /// Ottiene tutte le tracce dell'utente specificato (con limit di sicurezza)
  Future<List<Track>> getUserTracks(String userId) async {
    try {
      final snapshot = await _tracksCollection(userId)
          .orderBy('createdAt', descending: true)
          .limit(20) // ⚠️ LIMITE per evitare OutOfMemory
          .get();

      print('[TracksRepository] Trovate ${snapshot.docs.length} tracce per utente $userId');

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return _trackFromFirestore(doc.id, data);
      }).toList();
    } catch (e) {
      print('[TracksRepository] Errore getUserTracks: $e');
      return [];
    }
  }

  /// Ottiene tutte le tracce dell'utente corrente
  Future<List<Track>> getMyTracks() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return [];
    return getUserTracks(userId);
  }

  /// ⭐ NUOVO: Ottiene le mie tracce con paginazione
  Future<PaginatedTracksResult> getMyTracksPaginated({
    int limit = 10,
    DocumentSnapshot? lastDocument,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return PaginatedTracksResult(tracks: [], hasMore: false);
    }
    return getUserTracksPaginated(userId, limit: limit, lastDocument: lastDocument);
  }

  /// Stream delle tracce dell'utente corrente (real-time) - CON LIMITE
  Stream<List<Track>> watchMyTracks() {
    return _myTracksCollection
        .orderBy('createdAt', descending: true)
        .limit(20) // ⚠️ LIMITE per evitare OutOfMemory
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _trackFromFirestore(doc.id, doc.data()))
            .toList());
  }

  /// Ottiene una traccia specifica per ID
  Future<Track?> getTrackById(String trackId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return null;

    try {
      final doc = await _tracksCollection(userId).doc(trackId).get();
      if (!doc.exists || doc.data() == null) return null;
      return _trackFromFirestore(doc.id, doc.data()!);
    } catch (e) {
      print('[TracksRepository] Errore getTrackById: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AGGIORNAMENTO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Aggiorna una traccia esistente
  Future<void> updateTrack(String trackId, {
    String? name,
    String? description,
    ActivityType? activityType,
    bool? isPublic,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (activityType != null) updates['activityType'] = activityType.name;
    if (isPublic != null) updates['isPublic'] = isPublic;

    if (updates.isNotEmpty) {
      await _tracksCollection(userId).doc(trackId).update(updates);
    }
  }

  /// 📸 Aggiorna le foto di una traccia
  Future<void> updateTrackPhotos(String trackId, List<TrackPhotoMetadata> photos) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Utente non autenticato');

    await _tracksCollection(userId).doc(trackId).update({
      'photos': photos.map((p) => p.toMap()).toList(),
    });
    print('[TracksRepository] ${photos.length} foto aggiornate per traccia $trackId');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ELIMINAZIONE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Elimina una traccia
  Future<void> deleteTrack(String trackId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      await _tracksCollection(userId).doc(trackId).delete();
      print('[TracksRepository] Traccia eliminata: $trackId');
    } catch (e) {
      print('[TracksRepository] Errore deleteTrack: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONVERSIONI DATI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Converte Track in Map per Firestore (formato compatibile con app JS)
  Map<String, dynamic> _trackToFirestore(Track track, String userId) {
    return {
      'name': track.name,
      'description': track.description,
      // Salva punti nel formato dell'app JS esistente
      'points': _downsamplePoints(track.points).map((p) => {
        'longitude': p.longitude,
        'latitude': p.latitude,
        'altitude': p.elevation ?? 0,
        'timestamp': p.timestamp.millisecondsSinceEpoch,
        'speed': p.speed ?? 0,
        'accuracy': p.accuracy ?? 0,
      }).toList(),
      'activityType': track.activityType.name,
      'recordedAt': track.recordedAt?.toIso8601String(),
      'createdAt': FieldValue.serverTimestamp(),
      'userId': userId,
      'isPublic': track.isPublic,
      'isPlanned': track.isPlanned,
      // Stats pre-calcolate
      'distance': track.stats.distance,
      'elevationGain': track.stats.elevationGain,
      'elevationLoss': track.stats.elevationLoss,
      'duration': track.stats.duration.inSeconds,
      'movingTime': track.stats.movingTime.inSeconds,
      'maxSpeed': track.stats.maxSpeed,
      'avgSpeed': track.stats.avgSpeed,
      'maxAltitude': track.stats.maxElevation,
      'minAltitude': track.stats.minElevation,
      // 📸 Foto
      'photos': track.photos.map((p) => p.toMap()).toList(),
    };
  }

  /// Riduce il numero di punti per ottimizzare storage e performance
  List<TrackPoint> _downsamplePoints(List<TrackPoint> points, {int maxPoints = 1000}) {
    if (points.length <= maxPoints) return points;
    
    final result = <TrackPoint>[points.first];
    final step = points.length / (maxPoints - 2);
    
    for (int i = 1; i < maxPoints - 1; i++) {
      final index = (i * step).round();
      if (index < points.length - 1) {
        result.add(points[index]);
      }
    }
    
    result.add(points.last);
    return result;
  }

  /// Converte dati Firestore in Track
  /// Gestisce sia il formato nuovo che quello esistente dell'app JS
  Track _trackFromFirestore(String id, Map<String, dynamic> data) {
    // Parse points - gestisce vari formati
    List<TrackPoint> points = [];
    final pointsData = data['points'];
    
    if (pointsData != null && pointsData is List) {
      for (var p in pointsData) {
        try {
          if (p is Map<String, dynamic>) {
            // Formato oggetto: {longitude, latitude, altitude} o {lng, lat, ele}
            final lat = _toDouble(p['latitude'] ?? p['lat']);
            final lng = _toDouble(p['longitude'] ?? p['lng'] ?? p['lon']);
            final ele = _toDouble(p['altitude'] ?? p['ele'] ?? p['elevation']);
            final spd = _toDouble(p['speed']);
            final acc = _toDouble(p['accuracy']);
            
            DateTime timestamp = DateTime.now();
            if (p['timestamp'] != null) {
              if (p['timestamp'] is int) {
                timestamp = DateTime.fromMillisecondsSinceEpoch(p['timestamp']);
              } else if (p['timestamp'] is String) {
                timestamp = DateTime.tryParse(p['timestamp']) ?? DateTime.now();
              }
            } else if (p['time'] != null) {
              timestamp = DateTime.tryParse(p['time'].toString()) ?? DateTime.now();
            }
            
            if (lat != null && lng != null) {
              points.add(TrackPoint(
                latitude: lat,
                longitude: lng,
                elevation: ele,
                timestamp: timestamp,
                speed: spd,
                accuracy: acc,
              ));
            }
          } else if (p is List && p.length >= 2) {
            // Formato array: [lon, lat, ele?, speed?]
            points.add(TrackPoint(
              longitude: _toDouble(p[0]) ?? 0,
              latitude: _toDouble(p[1]) ?? 0,
              elevation: p.length > 2 ? _toDouble(p[2]) : null,
              timestamp: DateTime.now(),
              speed: p.length > 3 ? _toDouble(p[3]) : null,
            ));
          }
        } catch (e) {
          print('[TracksRepository] Errore parsing punto: $e');
        }
      }
    }

    // 📸 Parse foto
    List<TrackPhotoMetadata> photos = [];
    final photosData = data['photos'];
    if (photosData != null && photosData is List) {
      for (var p in photosData) {
        try {
          if (p is Map) {
            photos.add(TrackPhotoMetadata.fromMap(Map<String, dynamic>.from(p)));
          }
        } catch (e) {
          print('[TracksRepository] Errore parsing foto: $e');
        }
      }
    }

    // Activity type
    ActivityType activityType = ActivityType.trekking;
    final activityStr = data['activityType'] as String?;
    if (activityStr != null) {
      activityType = ActivityType.values.firstWhere(
        (e) => e.name.toLowerCase() == activityStr.toLowerCase(),
        orElse: () => ActivityType.trekking,
      );
    }

    // Dates
    DateTime? recordedAt;
    if (data['recordedAt'] != null) {
      if (data['recordedAt'] is Timestamp) {
        recordedAt = (data['recordedAt'] as Timestamp).toDate();
      } else if (data['recordedAt'] is String) {
        recordedAt = DateTime.tryParse(data['recordedAt']);
      }
    }

    DateTime createdAt = DateTime.now();
    if (data['createdAt'] != null) {
      if (data['createdAt'] is Timestamp) {
        createdAt = (data['createdAt'] as Timestamp).toDate();
      } else if (data['createdAt'] is int) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(data['createdAt']);
      }
    }

    // Stats - usa valori pre-calcolati se disponibili
    final stats = TrackStats(
      distance: _toDouble(data['distance']) ?? 0,
      elevationGain: _toDouble(data['elevationGain']) ?? 0,
      elevationLoss: _toDouble(data['elevationLoss']) ?? 0,
      duration: Duration(seconds: _toInt(data['duration']) ?? 0),
      movingTime: Duration(seconds: _toInt(data['movingTime'] ?? data['duration']) ?? 0),
      maxSpeed: _toDouble(data['maxSpeed']) ?? 0,
      avgSpeed: _toDouble(data['avgSpeed']) ?? 0,
      minElevation: _toDouble(data['minAltitude'] ?? data['minElevation']) ?? 0,
      maxElevation: _toDouble(data['maxAltitude'] ?? data['maxElevation']) ?? 0,
    );

    return Track(
      id: id,
      name: data['name']?.toString() ?? 'Senza nome',
      description: data['description']?.toString(),
      points: points,
      activityType: activityType,
      recordedAt: recordedAt,
      createdAt: createdAt,
      userId: data['userId']?.toString(),
      isPublic: data['isPublic'] == true,
      isPlanned: data['isPlanned'] == true,
      stats: stats,
      photos: photos, // 📸 Foto
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Helper per convertire in double
  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Helper per convertire in int
  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
