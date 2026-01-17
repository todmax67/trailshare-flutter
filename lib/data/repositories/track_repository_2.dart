import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/track.dart';

/// Repository per gestire le tracce su Firestore
class TrackRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _tracksCollection {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Utente non autenticato');
    return _firestore.collection('users').doc(userId).collection('tracks');
  }

  /// Salva una nuova traccia e restituisce l'ID
  Future<String> saveTrack(Track track) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Utente non autenticato');

    final trackData = {
      'name': track.name,
      'description': track.description,
      'points': track.points.map((p) => p.toMap()).toList(),
      'activityType': track.activityType.name,
      'recordedAt': track.recordedAt?.toIso8601String(),
      'createdAt': FieldValue.serverTimestamp(),
      'userId': userId,
      'isPublic': track.isPublic,
      'isPlanned': track.isPlanned,
      'distance': track.stats.distance,
      'elevationGain': track.stats.elevationGain,
      'elevationLoss': track.stats.elevationLoss,
      'duration': track.stats.duration.inSeconds,
      'movingTime': track.stats.movingTime.inSeconds,
      'maxSpeed': track.stats.maxSpeed,
      'avgSpeed': track.stats.avgSpeed,
      'photos': track.photos.map((p) => p.toMap()).toList(), // 📸 Foto iniziali
    };

    final docRef = await _tracksCollection.add(trackData);
    return docRef.id;
  }

  /// Ottiene tutte le tracce dell'utente corrente
  Future<List<Track>> getMyTracks() async {
    final snapshot = await _tracksCollection
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => _docToTrack(doc))
        .where((track) => track != null)
        .cast<Track>()
        .toList();
  }

  /// Stream delle tracce dell'utente corrente
  Stream<List<Track>> watchMyTracks() {
    return _tracksCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _docToTrack(doc))
            .where((track) => track != null)
            .cast<Track>()
            .toList());
  }

  /// Ottiene una traccia specifica per ID
  Future<Track?> getTrackById(String trackId) async {
    final doc = await _tracksCollection.doc(trackId).get();
    if (!doc.exists) return null;
    return _docToTrack(doc);
  }

  /// Aggiorna una traccia esistente
  Future<void> updateTrack(String trackId, {String? name, String? description, ActivityType? activityType}) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (activityType != null) updates['activityType'] = activityType.name;

    if (updates.isNotEmpty) {
      await _tracksCollection.doc(trackId).update(updates);
    }
  }

  /// Elimina una traccia
  Future<void> deleteTrack(String trackId) async {
    await _tracksCollection.doc(trackId).delete();
  }

  /// 📸 Aggiorna le foto di una traccia
  Future<void> updateTrackPhotos(String trackId, List<TrackPhotoMetadata> photos) async {
    await _tracksCollection.doc(trackId).update({
      'photos': photos.map((p) => p.toMap()).toList(),
    });
  }

  /// Converte documento Firestore in Track - ROBUSTO per dati da app JS
  Track? _docToTrack(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) return null;

      // Parse punti - gestisce sia 'points' che strutture diverse
      List<TrackPoint> points = [];
      final pointsData = data['points'];
      if (pointsData != null && pointsData is List) {
        for (var p in pointsData) {
          try {
            if (p is Map) {
              points.add(TrackPoint.fromMap(Map<String, dynamic>.from(p)));
            }
          } catch (e) {
            print('[TrackRepository] Errore parsing punto: $e');
            // Continua con gli altri punti
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
            print('[TrackRepository] Errore parsing foto: $e');
            // Continua con le altre foto
          }
        }
      }

      // Parse activity type
      ActivityType activityType = ActivityType.trekking;
      final activityStr = data['activityType']?.toString().toLowerCase();
      if (activityStr != null) {
        if (activityStr.contains('run')) {
          activityType = ActivityType.trailRunning;
        } else if (activityStr.contains('walk') || activityStr.contains('cammin')) {
          activityType = ActivityType.walking;
        } else if (activityStr.contains('cycl') || activityStr.contains('bici')) {
          activityType = ActivityType.cycling;
        }
      }

      // Parse stats - gestisce valori null
      final stats = TrackStats(
        distance: _safeDouble(data['distance']),
        elevationGain: _safeDouble(data['elevationGain']),
        elevationLoss: _safeDouble(data['elevationLoss']),
        duration: Duration(seconds: _safeInt(data['duration'])),
        movingTime: Duration(seconds: _safeInt(data['movingTime'] ?? data['duration'])),
        maxSpeed: _safeDouble(data['maxSpeed']),
        avgSpeed: _safeDouble(data['avgSpeed']),
      );

      // Parse date
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
        } else if (data['createdAt'] is String) {
          createdAt = DateTime.tryParse(data['createdAt']) ?? DateTime.now();
        }
      }

      return Track(
        id: doc.id,
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
    } catch (e) {
      print('[TrackRepository] Errore conversione traccia ${doc.id}: $e');
      return null;
    }
  }

  /// Helper per convertire in double in modo sicuro
  double _safeDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  /// Helper per convertire in int in modo sicuro
  int _safeInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
