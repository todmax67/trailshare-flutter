import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/utils/geohash_util.dart';
import '../models/trail_poi.dart';

/// Repository CRUD per i POI (Points of Interest) di TrailShare.
///
/// Collection Firestore: `poi_points/{poiId}`
///
/// Sub-collection voti: `poi_points/{poiId}/votes/{uid}` per evitare
/// doppi voti. Il conteggio `upvotes`/`downvotes` è denormalizzato
/// sul documento padre via Cloud Function o client-side transaction.
class PoiRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  PoiRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('poi_points');

  String? get _uid => _auth.currentUser?.uid;

  // ═══════════════════════════════════════════════════════════════════
  // MUTATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Crea un nuovo POI. Restituisce l'id assegnato da Firestore.
  Future<String?> createPoi(TrailPoi poi) async {
    if (_uid == null) return null;
    try {
      final doc = _col.doc();
      await doc.set(poi.toFirestoreCreate());
      debugPrint('[PoiRepo] Creato POI ${doc.id}');
      return doc.id;
    } catch (e) {
      debugPrint('[PoiRepo] Errore createPoi: $e');
      return null;
    }
  }

  /// Aggiorna un POI esistente (solo l'autore o admin possono — rules).
  Future<bool> updatePoi(TrailPoi poi) async {
    try {
      await _col.doc(poi.id).update(poi.toFirestoreUpdate());
      return true;
    } catch (e) {
      debugPrint('[PoiRepo] Errore updatePoi: $e');
      return false;
    }
  }

  /// Elimina un POI. Solo autore o admin (rules).
  Future<bool> deletePoi(String poiId) async {
    try {
      await _col.doc(poiId).delete();
      return true;
    } catch (e) {
      debugPrint('[PoiRepo] Errore deletePoi: $e');
      return false;
    }
  }

  /// Rende un POI pubblico (solo autore). Usato dal toggle nel dettaglio
  /// POI quando l'utente vuole condividerlo con la community.
  Future<bool> setPoiPublic(String poiId, bool isPublic) async {
    try {
      await _col.doc(poiId).update({'isPublic': isPublic});
      return true;
    } catch (e) {
      debugPrint('[PoiRepo] Errore setPoiPublic: $e');
      return false;
    }
  }

  /// Cascata: quando una track community viene pubblicata (passa da
  /// privata a pubblica), rende pubblici tutti i POI che hanno
  /// `relatedTrackId` = quella track.
  ///
  /// Chiamato da `CommunityTracksRepository.publishTrack` in coda alla
  /// pubblicazione. Tutto in un batch per atomicità.
  Future<int> cascadePublicForTrackPois(String trackId) async {
    try {
      final snap = await _col
          .where('relatedTrackId', isEqualTo: trackId)
          .where('isPublic', isEqualTo: false)
          .get();
      if (snap.docs.isEmpty) return 0;
      final batch = _firestore.batch();
      for (final d in snap.docs) {
        batch.update(d.reference, {'isPublic': true});
      }
      await batch.commit();
      debugPrint('[PoiRepo] Cascade public: ${snap.docs.length} POI → public');
      return snap.docs.length;
    } catch (e) {
      debugPrint('[PoiRepo] Errore cascadePublicForTrackPois: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // QUERIES
  // ═══════════════════════════════════════════════════════════════════

  /// Legge un POI singolo.
  Future<TrailPoi?> getPoi(String poiId) async {
    try {
      final doc = await _col.doc(poiId).get();
      if (!doc.exists) return null;
      return TrailPoi.fromFirestore(doc);
    } catch (e) {
      debugPrint('[PoiRepo] Errore getPoi: $e');
      return null;
    }
  }

  /// POI pubblici all'interno di un bounding box geografico (viewport
  /// attuale della mappa). Usa geohash per limitare i documenti letti.
  ///
  /// Per semplicità MVP: query a raggio. Restituisce POI il cui geohash
  /// inizia con uno dei prefissi che coprono la zona richiesta.
  Future<List<TrailPoi>> getPoisNear({
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
    int limit = 100,
  }) async {
    try {
      // Determina il livello di precisione geohash in base al raggio.
      // Precisione 5 = ~5km, 6 = ~1km, 7 = ~150m.
      final precision = radiusMeters > 10000
          ? 4
          : radiusMeters > 2000
              ? 5
              : radiusMeters > 500
                  ? 6
                  : 7;
      final centerHash =
          GeoHashUtil.encode(centerLat, centerLng, precision: precision);
      // Prefix query: tutti i POI il cui geohash inizia con centerHash.
      // Per coprire i bordi del bounding box andrebbero anche i 8 neighbors
      // geohash — per MVP facciamo solo il centro, sufficiente per zoom
      // tipico (raggio < dimensione cella geohash).
      final end = centerHash.substring(0, centerHash.length - 1) +
          String.fromCharCode(centerHash.codeUnitAt(centerHash.length - 1) + 1);
      final snap = await _col
          .where('isPublic', isEqualTo: true)
          .where('geohash', isGreaterThanOrEqualTo: centerHash)
          .where('geohash', isLessThan: end)
          .limit(limit)
          .get();
      return snap.docs.map(TrailPoi.fromFirestore).toList();
    } catch (e) {
      debugPrint('[PoiRepo] Errore getPoisNear: $e');
      return [];
    }
  }

  /// POI associati a un trail pubblico OSM.
  Future<List<TrailPoi>> getPoisForTrail(String trailId) async {
    try {
      final snap = await _col
          .where('relatedTrailId', isEqualTo: trailId)
          .where('isPublic', isEqualTo: true)
          .get();
      return snap.docs.map(TrailPoi.fromFirestore).toList();
    } catch (e) {
      debugPrint('[PoiRepo] Errore getPoisForTrail: $e');
      return [];
    }
  }

  /// POI associati a una community track. Se [includePrivate] è true
  /// restituisce anche i POI privati dell'utente corrente (usato dal
  /// proprietario che vede i propri POI anche prima di pubblicare).
  Future<List<TrailPoi>> getPoisForTrack(
    String trackId, {
    bool includePrivate = false,
  }) async {
    try {
      final q = _col.where('relatedTrackId', isEqualTo: trackId);
      final snap = await q.get();
      final all = snap.docs.map(TrailPoi.fromFirestore).toList();
      if (includePrivate && _uid != null) {
        // Restituisci tutti i POI pubblici + i POI privati dell'utente
        return all
            .where((p) => p.isPublic || p.createdBy == _uid)
            .toList();
      }
      return all.where((p) => p.isPublic).toList();
    } catch (e) {
      debugPrint('[PoiRepo] Errore getPoisForTrack: $e');
      return [];
    }
  }

  /// POI creati dall'utente corrente (sezione "I miei POI").
  Future<List<TrailPoi>> getMyPois({int limit = 50}) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final snap = await _col
          .where('createdBy', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(TrailPoi.fromFirestore).toList();
    } catch (e) {
      debugPrint('[PoiRepo] Errore getMyPois: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // VOTES
  // ═══════════════════════════════════════════════════════════════════

  /// Registra un voto dell'utente corrente su un POI. Evita doppi voti
  /// (se l'utente aveva già votato, aggiorna il tipo). Aggiorna il
  /// contatore denormalizzato sul padre in transaction.
  Future<bool> vote(String poiId, bool isUpvote) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final poiRef = _col.doc(poiId);
      final voteRef = poiRef.collection('votes').doc(uid);

      await _firestore.runTransaction((tx) async {
        final voteDoc = await tx.get(voteRef);
        final poiDoc = await tx.get(poiRef);
        if (!poiDoc.exists) throw Exception('POI not found');

        int upDelta = 0;
        int downDelta = 0;

        if (!voteDoc.exists) {
          // Primo voto di questo utente
          upDelta = isUpvote ? 1 : 0;
          downDelta = isUpvote ? 0 : 1;
        } else {
          final prev = voteDoc.data()?['voteType'] as String?;
          final wasUp = prev == 'up';
          if (wasUp == isUpvote) return; // stesso voto, no-op
          upDelta = isUpvote ? 1 : -1;
          downDelta = isUpvote ? -1 : 1;
        }

        tx.set(voteRef, {
          'voteType': isUpvote ? 'up' : 'down',
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(poiRef, {
          'upvotes': FieldValue.increment(upDelta),
          'downvotes': FieldValue.increment(downDelta),
        });
      });
      return true;
    } catch (e) {
      debugPrint('[PoiRepo] Errore vote: $e');
      return false;
    }
  }

  /// Rimuove un voto precedentemente registrato. Decrementa il contatore
  /// corrispondente.
  Future<bool> removeVote(String poiId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final poiRef = _col.doc(poiId);
      final voteRef = poiRef.collection('votes').doc(uid);

      await _firestore.runTransaction((tx) async {
        final voteDoc = await tx.get(voteRef);
        if (!voteDoc.exists) return;
        final prev = voteDoc.data()?['voteType'] as String?;
        tx.delete(voteRef);
        tx.update(poiRef, {
          if (prev == 'up') 'upvotes': FieldValue.increment(-1),
          if (prev == 'down') 'downvotes': FieldValue.increment(-1),
        });
      });
      return true;
    } catch (e) {
      debugPrint('[PoiRepo] Errore removeVote: $e');
      return false;
    }
  }

  /// Ritorna il voto corrente dell'utente su un POI (null se non ha votato).
  Future<String?> getUserVote(String poiId) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final doc =
          await _col.doc(poiId).collection('votes').doc(uid).get();
      if (!doc.exists) return null;
      return doc.data()?['voteType'] as String?;
    } catch (e) {
      return null;
    }
  }
}
