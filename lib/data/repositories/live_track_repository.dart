import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repository per gestire le sessioni LiveTrack
class LiveTrackRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Crea una nuova sessione live
  Future<LiveSession?> createSession({
    required String userName,
    int? batteryLevel,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final docRef = await _firestore.collection('live_sessions').add({
        'userId': user.uid,
        'userName': userName,
        'startTime': FieldValue.serverTimestamp(),
        'lastUpdate': FieldValue.serverTimestamp(),
        'isActive': true,
        'batteryLevel': batteryLevel ?? 100,
        'currentLocation': null,
        'path': [],
      });

      return LiveSession(
        id: docRef.id,
        userId: user.uid,
        userName: userName,
        isActive: true,
        batteryLevel: batteryLevel ?? 100,
      );
    } catch (e) {
      print('[LiveTrackRepo] Errore creazione sessione: $e');
      return null;
    }
  }

  /// Aggiorna la posizione corrente nella sessione
  Future<bool> updatePosition({
    required String sessionId,
    required double latitude,
    required double longitude,
    int? batteryLevel,
  }) async {
    try {
      final geoPoint = GeoPoint(latitude, longitude);
      
      final updateData = <String, dynamic>{
        'currentLocation': geoPoint,
        'lastUpdate': FieldValue.serverTimestamp(),
        'path': FieldValue.arrayUnion([geoPoint]),
      };

      if (batteryLevel != null) {
        updateData['batteryLevel'] = batteryLevel;
      }

      await _firestore.collection('live_sessions').doc(sessionId).update(updateData);
      return true;
    } catch (e) {
      print('[LiveTrackRepo] Errore aggiornamento posizione: $e');
      return false;
    }
  }

  /// Termina una sessione live
  Future<bool> endSession(String sessionId) async {
    try {
      await _firestore.collection('live_sessions').doc(sessionId).update({
        'isActive': false,
        'endTime': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('[LiveTrackRepo] Errore chiusura sessione: $e');
      return false;
    }
  }

  /// Ottiene una sessione per ID
  Future<LiveSession?> getSession(String sessionId) async {
    try {
      final doc = await _firestore.collection('live_sessions').doc(sessionId).get();
      if (!doc.exists) return null;
      return LiveSession.fromFirestore(doc);
    } catch (e) {
      print('[LiveTrackRepo] Errore get sessione: $e');
      return null;
    }
  }

  /// Stream per ascoltare una sessione in tempo reale (per viewer)
  Stream<LiveSession?> watchSession(String sessionId) {
    return _firestore
        .collection('live_sessions')
        .doc(sessionId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return LiveSession.fromFirestore(doc);
    });
  }

  /// Ottiene le sessioni attive dell'utente corrente
  Future<List<LiveSession>> getMyActiveSessions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection('live_sessions')
          .where('userId', isEqualTo: user.uid)
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs.map((doc) => LiveSession.fromFirestore(doc)).toList();
    } catch (e) {
      print('[LiveTrackRepo] Errore get sessioni attive: $e');
      return [];
    }
  }

  /// Genera URL di condivisione per una sessione
  String getShareUrl(String sessionId) {
    // Usa deep link o URL web
    return 'https://trailshare.app/live?id=$sessionId';
  }
}

/// Modello per una sessione LiveTrack
class LiveSession {
  final String id;
  final String userId;
  final String userName;
  final bool isActive;
  final int batteryLevel;
  final GeoPoint? currentLocation;
  final List<GeoPoint> path;
  final DateTime? startTime;
  final DateTime? lastUpdate;
  final DateTime? endTime;

  const LiveSession({
    required this.id,
    required this.userId,
    required this.userName,
    required this.isActive,
    this.batteryLevel = 100,
    this.currentLocation,
    this.path = const [],
    this.startTime,
    this.lastUpdate,
    this.endTime,
  });

  factory LiveSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      return LiveSession(id: doc.id, userId: '', userName: '', isActive: false);
    }

    // Parse path (lista di GeoPoint)
    List<GeoPoint> pathList = [];
    if (data['path'] != null && data['path'] is List) {
      pathList = (data['path'] as List)
          .where((p) => p is GeoPoint)
          .map((p) => p as GeoPoint)
          .toList();
    }

    return LiveSession(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Utente',
      isActive: data['isActive'] ?? false,
      batteryLevel: data['batteryLevel'] ?? 100,
      currentLocation: data['currentLocation'] as GeoPoint?,
      path: pathList,
      startTime: (data['startTime'] as Timestamp?)?.toDate(),
      lastUpdate: (data['lastUpdate'] as Timestamp?)?.toDate(),
      endTime: (data['endTime'] as Timestamp?)?.toDate(),
    );
  }

  /// Durata sessione
  Duration get duration {
    if (startTime == null) return Duration.zero;
    final end = endTime ?? DateTime.now();
    return end.difference(startTime!);
  }

  /// Durata formattata
  String get durationFormatted {
    final d = duration;
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes} min';
  }

  /// Ultimo aggiornamento formattato
  String get lastUpdateFormatted {
    if (lastUpdate == null) return '--';
    final now = DateTime.now();
    final diff = now.difference(lastUpdate!);
    
    if (diff.inSeconds < 60) return 'Adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    return '${diff.inHours}h fa';
  }
}
