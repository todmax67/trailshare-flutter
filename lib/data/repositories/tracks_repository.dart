import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/track.dart';
import '../../core/utils/elevation_processor.dart';

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

      debugPrint('[TracksRepository] Traccia salvata con ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('[TracksRepository] Errore saveTrack: $e');
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

      debugPrint('[TracksRepository] Paginazione: ${snapshot.docs.length} tracce caricate');

      final tracks = snapshot.docs.map((doc) {
        return _trackFromFirestore(doc.id, doc.data());
      }).toList();

      return PaginatedTracksResult(
        tracks: tracks,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length == limit,
      );
    } catch (e) {
      debugPrint('[TracksRepository] Errore getUserTracksPaginated: $e');
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

      debugPrint('[TracksRepository] Trovate ${snapshot.docs.length} tracce per utente $userId');

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return _trackFromFirestore(doc.id, data);
      }).toList();
    } catch (e) {
      debugPrint('[TracksRepository] Errore getUserTracks: $e');
      return [];
    }
  }

  /// Ottiene tutte le tracce dell'utente corrente
  Future<List<Track>> getMyTracks() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return [];
    return getUserTracks(userId);
  }

  /// Versione **lightweight**: tutte le tracce dell'utente corrente
  /// senza i punti GPS, pensata per dashboard/lista/profilo web dove
  /// servono solo stats, nome, date e activity type.
  ///
  /// Salta la deserializzazione del campo `points` per evitare di
  /// allocare migliaia di [TrackPoint] × N tracce (OOM su mobile,
  /// memoria sprecata su web). Il documento Firestore arriva comunque
  /// per intero via wire, ma viene ridotto prima del parse.
  ///
  /// Per il dettaglio mappa (che richiede i punti) usare
  /// [getTrackById] — fa una read singola completa.
  ///
  /// [bypassCache] = true: usa `Source.server` per evitare decoding della
  /// cache locale (utile quando i doc sono pesanti per points embedded e
  /// la cache satura va in OOM). Default false per non rompere offline.
  Future<List<Track>> getMyTracksLightweight({
    int limit = 1000,
    bool bypassCache = false,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return [];
    try {
      final query = _tracksCollection(userId)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      final snapshot = await (bypassCache
          ? query.get(const GetOptions(source: Source.server))
          : query.get());
      return snapshot.docs.map((doc) {
        // Copia mutabile + rimozione points prima del parse
        final data = Map<String, dynamic>.from(doc.data());
        data.remove('points');
        return _trackFromFirestore(doc.id, data);
      }).toList();
    } catch (e) {
      debugPrint('[TracksRepository] Errore getMyTracksLightweight: $e');
      return [];
    }
  }

  /// Epic 4.7 — calcola i Personal Records dell'utente per le tracce
  /// dello stesso `activityType`, escludendo opzionalmente la traccia
  /// corrente (così il "best" rappresenta lo storico vs cui confrontarla).
  ///
  /// Best:
  /// - distance (metri)
  /// - duration (secondi)
  /// - elevation gain (metri)
  /// - avg pace (sec/km) per attività di velocità (running/cycling/etc.)
  ///
  /// Implementazione lightweight: usa [getMyTracksLightweight] (skip
  /// points), filtra in-memory. Cap a 500 tracce per limitare memoria.
  Future<PersonalRecords?> getPersonalRecordsForActivity({
    required String activityType,
    String? excludeTrackId,
  }) async {
    final tracks = await getMyTracksLightweight(limit: 500);
    final sameActivity = tracks.where((t) {
      if (excludeTrackId != null && t.id == excludeTrackId) return false;
      return t.activityType.name == activityType;
    }).toList();
    if (sameActivity.isEmpty) return null;

    Track? bestDistance;
    Track? bestDuration;
    Track? bestElevation;
    for (final t in sameActivity) {
      if (bestDistance == null ||
          t.stats.distance > bestDistance.stats.distance) {
        bestDistance = t;
      }
      if (bestDuration == null ||
          t.stats.duration.inSeconds > bestDuration.stats.duration.inSeconds) {
        bestDuration = t;
      }
      if (bestElevation == null ||
          t.stats.elevationGain > bestElevation.stats.elevationGain) {
        bestElevation = t;
      }
    }
    return PersonalRecords(
      activityType: activityType,
      bestDistance: bestDistance,
      bestDuration: bestDuration,
      bestElevation: bestElevation,
      sampleSize: sameActivity.length,
    );
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

  /// Ottiene una traccia di un altro utente (path users/{ownerId}/tracks/{trackId}).
  /// Le rules permettono read pubblico ai signed-in. Utile per percorsi
  /// consigliati su Spazi Pro dove l'owner del business ha consigliato
  /// una traccia di un altro utente.
  Future<Track?> getTrackByOwnerAndId(
      String ownerId, String trackId) async {
    try {
      final doc = await _tracksCollection(ownerId).doc(trackId).get();
      if (!doc.exists || doc.data() == null) return null;
      return _trackFromFirestore(doc.id, doc.data()!);
    } catch (e) {
      debugPrint('[TracksRepository] Errore getTrackByOwnerAndId: $e');
      return null;
    }
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
      debugPrint('[TracksRepository] Errore getTrackById: $e');
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
    debugPrint('[TracksRepository] ${photos.length} foto aggiornate per traccia $trackId');
  }

  /// ❤️ Aggiorna i dati battito cardiaco di una traccia
  Future<void> updateTrackHeartRate(String trackId, Map<DateTime, int> heartRateData) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Utente non autenticato');

    final serialized = heartRateData.map(
      (key, value) => MapEntry(key.millisecondsSinceEpoch.toString(), value),
    );

    await _tracksCollection(userId).doc(trackId).update({
      'heartRateData': serialized,
    });
    debugPrint('[TracksRepository] ${heartRateData.length} campioni HR salvati per traccia $trackId');
  }

  /// Aggiorna un singolo campo di una traccia
  Future<void> updateTrackField(String trackId, String field, dynamic value) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Utente non autenticato');

    await _tracksCollection(userId).doc(trackId).update({
      field: value,
    });
    debugPrint('[TracksRepository] Campo "$field" aggiornato per traccia $trackId');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONDIVISIONE NEI GRUPPI (B2B Groups feature)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Aggiunge [groupId] al campo `groupIds` della traccia, rendendola
  /// visibile come "percorso consigliato" nel tab Percorsi del gruppo.
  ///
  /// Il chiamante deve essere il **proprietario della traccia** (regola
  /// Firestore) e tipicamente anche admin del gruppo (controllo lato
  /// UI prima di chiamare). Idempotente — Firestore arrayUnion non
  /// duplica.
  Future<void> shareTrackToGroup(String trackId, String groupId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Utente non autenticato');

    await _tracksCollection(userId).doc(trackId).update({
      'groupIds': FieldValue.arrayUnion([groupId]),
    });
    debugPrint(
      '[TracksRepository] Traccia $trackId condivisa nel gruppo $groupId',
    );
  }

  /// Rimuove [groupId] dal campo `groupIds` della traccia. La traccia
  /// sparirà dal tab Percorsi del gruppo ma resta nelle "Le mie tracce"
  /// del proprietario. Idempotente.
  Future<void> unshareTrackFromGroup(String trackId, String groupId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Utente non autenticato');

    await _tracksCollection(userId).doc(trackId).update({
      'groupIds': FieldValue.arrayRemove([groupId]),
    });
    debugPrint(
      '[TracksRepository] Traccia $trackId rimossa dal gruppo $groupId',
    );
  }

  /// Restituisce le tracce condivise nel gruppo [groupId] da tutti i
  /// suoi membri. Usa una `collectionGroup` query su `tracks` con
  /// `array-contains` su [groupId]. Richiede l'indice composito:
  ///
  ///   collection: tracks (collectionGroup), groupIds: ARRAYS asc
  ///
  /// Le regole Firestore devono permettere a chi è membro del gruppo
  /// di leggere i documenti tracks con `request.auth.uid in resource.data.groupIds`
  /// implicito tramite la membership.
  Future<List<Track>> getGroupTracks(String groupId) async {
    try {
      final snap = await _firestore
          .collectionGroup('tracks')
          .where('groupIds', arrayContains: groupId)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      final tracks = snap.docs
          .map((d) => _trackFromFirestore(d.id, d.data()))
          .toList();
      debugPrint(
        '[TracksRepository] getGroupTracks($groupId): ${tracks.length} tracce',
      );
      return tracks;
    } catch (e) {
      debugPrint('[TracksRepository] Errore getGroupTracks: $e');
      return [];
    }
  }

  /// Versione **lightweight** di [getGroupTracks]: stesse tracce ma
  /// senza `points` (skip TrackPoint allocation) e con cap alzato a
  /// 1000 invece di 100. Pensata per stats/dashboard web dove servono
  /// solo metadata aggregati (distance, elevation, date, userId,
  /// activityType) — i punti GPS non servono.
  Future<List<Track>> getGroupTracksLightweight(
    String groupId, {
    int limit = 1000,
  }) async {
    try {
      final snap = await _firestore
          .collectionGroup('tracks')
          .where('groupIds', arrayContains: groupId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data.remove('points');
        return _trackFromFirestore(d.id, data);
      }).toList();
    } catch (e) {
      debugPrint(
          '[TracksRepository] Errore getGroupTracksLightweight: $e');
      return [];
    }
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
      debugPrint('[TracksRepository] Traccia eliminata: $trackId');
    } catch (e) {
      debugPrint('[TracksRepository] Errore deleteTrack: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONVERSIONI DATI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ricalcola le statistiche direttamente dai punti GPS.
  /// Garantisce coerenza tra dati riassuntivi e grafici/stats per km.
  /// USA ElevationProcessor (filtro mediano + smoothing + isteresi)
  /// — stesso algoritmo usato da LapSplitsWidget.
  TrackStats _recalculateStats(List<TrackPoint> points, TrackStats originalStats) {
    if (points.isEmpty) return originalStats;

    // Distanza dai punti originali (precisa, non serve smoothing)
    double distance = 0;
    double maxSpeed = 0;

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];

      distance += prev.distanceTo(curr);

      // Velocità max (filtra valori assurdi > 180 km/h = 50 m/s)
      if (curr.speed != null && curr.speed! > maxSpeed && curr.speed! < 50.0) {
        maxSpeed = curr.speed!;
      }
    }

    // Elevazione con ElevationProcessor (filtro mediano + smoothing + isteresi)
    // Stesso identico processore usato da LapSplitsWidget
    const elevationProcessor = ElevationProcessor();
    final rawElevations = points.map((p) => p.elevation).toList();
    final eleResult = elevationProcessor.process(rawElevations);

    // Log per debug
    debugPrint('[TracksRepository] ═══ RICALCOLO STATS DAI PUNTI ═══');
    debugPrint('[TracksRepository] Punti: ${points.length}');
    debugPrint('[TracksRepository] Distanza: ${(originalStats.distance / 1000).toStringAsFixed(2)}km → ${(distance / 1000).toStringAsFixed(2)}km');
    debugPrint('[TracksRepository] Dislivello+: ${originalStats.elevationGain.toStringAsFixed(0)}m → ${eleResult.elevationGain.toStringAsFixed(0)}m');
    debugPrint('[TracksRepository] Dislivello-: ${originalStats.elevationLoss.toStringAsFixed(0)}m → ${eleResult.elevationLoss.toStringAsFixed(0)}m');
    debugPrint('[TracksRepository] Quota max: ${originalStats.maxElevation.toStringAsFixed(0)}m → ${eleResult.maxElevation.toStringAsFixed(0)}m');
    debugPrint('[TracksRepository] Quota min: ${originalStats.minElevation.toStringAsFixed(0)}m → ${eleResult.minElevation.toStringAsFixed(0)}m');

    return TrackStats(
      distance: distance,
      elevationGain: eleResult.elevationGain,
      elevationLoss: eleResult.elevationLoss,
      maxElevation: eleResult.maxElevation,
      minElevation: eleResult.minElevation,
      // Mantieni durata e tempi dall'originale (non calcolabili dai soli punti)
      duration: originalStats.duration,
      movingTime: originalStats.movingTime,
      maxSpeed: maxSpeed > 0 ? maxSpeed : originalStats.maxSpeed,
      avgSpeed: originalStats.avgSpeed,
    );
  }

  /// Converte Track in Map per Firestore (formato compatibile con app JS)
  Map<String, dynamic> _trackToFirestore(Track track, String userId) {
    // Prima downsample i punti
    final savedPoints = _downsamplePoints(track.points);
    
    // ⭐ RICALCOLA stats dai punti reali che verranno salvati
    // Questo garantisce coerenza tra dati riassuntivi e grafici/stats per km
    final stats = track.isPlanned 
        ? track.stats  // Percorsi pianificati: usa stats dal router
        : _recalculateStats(savedPoints, track.stats);

    return {
      'name': track.name,
      'description': track.description,
      // Salva punti nel formato dell'app JS esistente
      'points': savedPoints.map((p) => {
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
      // Gruppi in cui la traccia è condivisa come "percorso consigliato"
      // (B2B groups feature, vedi GroupsRepository.shareTrackToGroup).
      'groupIds': track.groupIds,
      // Stats RICALCOLATE dai punti (non più da track.stats)
      'distance': stats.distance,
      'elevationGain': stats.elevationGain,
      'elevationLoss': stats.elevationLoss,
      'duration': stats.duration.inSeconds,
      'movingTime': stats.movingTime.inSeconds,
      'maxSpeed': stats.maxSpeed,
      'avgSpeed': stats.avgSpeed,
      'maxAltitude': stats.maxElevation,
      'minAltitude': stats.minElevation,
      // 📸 Foto
      'photos': track.photos.map((p) => p.toMap()).toList(),
      // ❤️ Battito cardiaco
      if (track.heartRateData != null && track.heartRateData!.isNotEmpty)
        'heartRateData': track.heartRateData!.map(
          (key, value) => MapEntry(key.millisecondsSinceEpoch.toString(), value),
        ),
      if (track.healthCalories != null)
        'healthCalories': track.healthCalories,  
      if (track.healthSteps != null)
        'healthSteps': track.healthSteps,  
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
          debugPrint('[TracksRepository] Errore parsing punto: $e');
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
          debugPrint('[TracksRepository] Errore parsing foto: $e');
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

    // 🔥 Calorie reali
    final healthCalories = (data['healthCalories'] as num?)?.toDouble();

    // 👣 Passi
    final healthSteps = (data['healthSteps'] as num?)?.toInt();

    // ❤️ Parse battito cardiaco
    Map<DateTime, int>? heartRateData;
    final hrData = data['heartRateData'];
    if (hrData != null && hrData is Map) {
      heartRateData = {};
      for (final entry in hrData.entries) {
        try {
          final timestamp = DateTime.fromMillisecondsSinceEpoch(int.parse(entry.key.toString()));
          final bpm = (entry.value as num).toInt();
          if (bpm > 30 && bpm < 250) {
            heartRateData[timestamp] = bpm;
          }
        } catch (e) {
          // Skip dati malformati
        }
      }
      if (heartRateData.isEmpty) heartRateData = null;
    }

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
      groupIds: (data['groupIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      stats: stats,
      photos: photos, // 📸 Foto
      heartRateData: heartRateData, // ❤️ Battito cardiaco
      healthCalories: healthCalories, // 🔥 Calorie reali
      healthSteps: healthSteps, // 👣 Passi
      importedFromStrava: data['importedFromStrava'] == true,
      stravaSourceActivityId: data['stravaSourceActivityId']?.toString(),
      // 5.5 — Tag personalizzati salvati lowercase
      tags: data['tags'] is List
          ? List<String>.from(data['tags'] as List)
          : const <String>[],
    );
  }

  /// 5.5 — Aggiorna SOLO il campo `tags` di una traccia esistente.
  /// I tag vengono normalizzati lowercase + trimmed + dedup prima del save.
  Future<bool> updateTrackTags(String trackId, List<String> tags) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final normalized = tags
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty && t.length <= 30)
        .toSet()
        .toList();
    try {
      await _tracksCollection(user.uid).doc(trackId).update({
        'tags': normalized,
      });
      return true;
    } catch (e) {
      debugPrint('[TracksRepository] updateTrackTags error: $e');
      return false;
    }
  }

  /// 5.5 — Restituisce l'insieme di tutti i tag usati dall'utente
  /// nelle sue tracce (per autocomplete del tag editor).
  Future<List<String>> getAllUserTags() async {
    final tracks = await getMyTracksLightweight(limit: 500);
    final set = <String>{};
    for (final t in tracks) {
      set.addAll(t.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// 5.4 — Spezza una traccia in due al [splitIndex] (esclusivo: primo
  /// pezzo include points[0..splitIndex-1], secondo pezzo
  /// points[splitIndex..end]). Le stats vengono ricalcolate per
  /// distance/duration/elevation in modo coerente. Salva i 2 nuovi
  /// documenti, cancella l'originale. Ritorna gli ID dei 2 nuovi
  /// oppure null su errore.
  Future<({String firstId, String secondId})?> splitTrack(
    Track track,
    int splitIndex,
  ) async {
    if (track.id == null) return null;
    final points = track.points;
    if (splitIndex <= 1 || splitIndex >= points.length - 1) return null;

    final first = points.sublist(0, splitIndex);
    final second = points.sublist(splitIndex);

    // Stats ricalcolate dalle distanze cumulative dei punti
    final firstStats = _recomputeStats(first);
    final secondStats = _recomputeStats(second);

    final firstTrack = track.copyWith(
      id: null, // nuovo doc
      name: '${track.name} (parte 1)',
      points: first,
      stats: firstStats,
      recordedAt: track.recordedAt,
      createdAt: DateTime.now(),
    );
    final secondTrack = track.copyWith(
      id: null,
      name: '${track.name} (parte 2)',
      points: second,
      stats: secondStats,
      recordedAt: first.last.timestamp,
      createdAt: DateTime.now(),
    );

    try {
      final firstId = await saveTrack(firstTrack);
      final secondId = await saveTrack(secondTrack);
      await deleteTrack(track.id!);
      debugPrint(
          '[TracksRepository] split OK: ${track.id} → $firstId + $secondId');
      return (firstId: firstId, secondId: secondId);
    } catch (e) {
      debugPrint('[TracksRepository] split error: $e');
      return null;
    }
  }

  /// 5.4 — Unisce due tracce concatenando i punti (in ordine cronologico
  /// di [recordedAt]/[createdAt]). Stats sommate. Salva nuova traccia,
  /// cancella le originali. Ritorna l'ID della nuova traccia o null.
  Future<String?> mergeTracks(Track a, Track b) async {
    if (a.id == null || b.id == null) return null;
    if (a.id == b.id) return null;

    // Ordina cronologicamente per evitare polilinee zigzaganti.
    final aDate = a.recordedAt ?? a.createdAt;
    final bDate = b.recordedAt ?? b.createdAt;
    final ordered = aDate.isBefore(bDate) ? [a, b] : [b, a];
    final allPoints = [...ordered[0].points, ...ordered[1].points];
    final newStats = _recomputeStats(allPoints);

    final merged = ordered[0].copyWith(
      id: null,
      name: '${ordered[0].name} + ${ordered[1].name}',
      points: allPoints,
      stats: newStats,
      recordedAt: ordered[0].recordedAt,
      createdAt: DateTime.now(),
      // Unisci anche i tag dedup-lowercase.
      tags: {...ordered[0].tags, ...ordered[1].tags}.toList(),
    );

    try {
      final newId = await saveTrack(merged);
      await deleteTrack(a.id!);
      await deleteTrack(b.id!);
      debugPrint(
          '[TracksRepository] merge OK: ${a.id}+${b.id} → $newId');
      return newId;
    } catch (e) {
      debugPrint('[TracksRepository] merge error: $e');
      return null;
    }
  }

  /// Helper: ricalcola distance / duration / elevation gain & loss /
  /// min & max elevation per una sequenza di punti. Usato da split e
  /// merge per produrre stats coerenti con i nuovi point[].
  TrackStats _recomputeStats(List<TrackPoint> points) {
    if (points.isEmpty) return const TrackStats();
    double distance = 0;
    double elevationGain = 0;
    double elevationLoss = 0;
    double minEle = double.infinity;
    double maxEle = -double.infinity;
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.elevation != null) {
        if (p.elevation! < minEle) minEle = p.elevation!;
        if (p.elevation! > maxEle) maxEle = p.elevation!;
      }
      if (i > 0) {
        final prev = points[i - 1];
        distance += _haversine(prev, p);
        if (prev.elevation != null && p.elevation != null) {
          final diff = p.elevation! - prev.elevation!;
          if (diff > 0) {
            elevationGain += diff;
          } else {
            elevationLoss += -diff;
          }
        }
      }
    }
    final duration =
        points.last.timestamp.difference(points.first.timestamp);
    return TrackStats(
      distance: distance,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      duration: duration,
      movingTime: duration, // approssimazione: senza i flag di auto-pause
      minElevation: minEle == double.infinity ? 0 : minEle,
      maxElevation: maxEle == -double.infinity ? 0 : maxEle,
    );
  }

  /// Haversine in metri tra due TrackPoint (lat/lng decimali).
  double _haversine(TrackPoint a, TrackPoint b) {
    const r = 6371000.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final lat1 = _toRad(a.latitude);
    final lat2 = _toRad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) *
            math.sin(dLng / 2) *
            math.cos(lat1) *
            math.cos(lat2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  double _toRad(double deg) => deg * math.pi / 180.0;

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

/// Epic 4.7 — Personal Records dell'utente per uno specifico activityType.
/// Vengono passati alla [PersonalRecordsCard] nella track detail page per
/// confrontare la traccia corrente vs lo storico personale.
class PersonalRecords {
  final String activityType;
  final Track? bestDistance;
  final Track? bestDuration;
  final Track? bestElevation;
  /// Numero tracce dello stesso tipo (utile per disclaimer "su N attività").
  final int sampleSize;

  const PersonalRecords({
    required this.activityType,
    this.bestDistance,
    this.bestDuration,
    this.bestElevation,
    this.sampleSize = 0,
  });

  /// `true` se la traccia [current] è il nuovo best per la metrica.
  bool isNewDistanceRecord(Track current) =>
      bestDistance == null ||
      current.stats.distance > bestDistance!.stats.distance;
  bool isNewDurationRecord(Track current) =>
      bestDuration == null ||
      current.stats.duration.inSeconds > bestDuration!.stats.duration.inSeconds;
  bool isNewElevationRecord(Track current) =>
      bestElevation == null ||
      current.stats.elevationGain > bestElevation!.stats.elevationGain;
}
