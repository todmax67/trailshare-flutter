import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/segment.dart';

/// Repository per segmenti cronometrati e relative classifiche.
///
/// Firestore schema:
/// ```
/// /segments/{segmentId}
/// /segments/{segmentId}/efforts/{effortId}
/// ```
class SegmentsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _segmentsCol =>
      _firestore.collection('segments');

  CollectionReference<Map<String, dynamic>> _effortsCol(String segmentId) =>
      _segmentsCol.doc(segmentId).collection('efforts');

  // ─── Cache statica bulk ──────────────────────────────────────────────────
  static List<Segment>? _allCache;
  static DateTime? _allCacheAt;
  static const _allTtl = Duration(minutes: 10);

  /// Invalida la cache bulk (da chiamare dopo create/delete).
  static void invalidateCache() {
    _allCache = null;
    _allCacheAt = null;
  }

  // ─── Query ───────────────────────────────────────────────────────────────

  /// Restituisce tutti i segmenti visibili all'utente corrente:
  /// - tutti i segmenti pubblici (admin + user pubblici)
  /// - segmenti privati creati dall'utente corrente
  ///
  /// Cache statica TTL 10 min. Due query Firestore in parallelo, union client-side.
  Future<List<Segment>> getAllSegments() async {
    if (_allCache != null && _allCacheAt != null) {
      if (DateTime.now().difference(_allCacheAt!) < _allTtl) {
        return _allCache!;
      }
    }
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
        _segmentsCol.where('isPublic', isEqualTo: true).get(),
      ];
      if (uid != null) {
        futures.add(
          _segmentsCol
              .where('createdBy', isEqualTo: uid)
              .where('isPublic', isEqualTo: false)
              .get(),
        );
      }
      final results = await Future.wait(futures);

      // Union + dedup by id
      final byId = <String, Segment>{};
      for (final snap in results) {
        for (final doc in snap.docs) {
          byId[doc.id] = Segment.fromFirestore(doc);
        }
      }
      final list = byId.values.toList();
      _allCache = list;
      _allCacheAt = DateTime.now();
      return list;
    } catch (e) {
      debugPrint('[Segments] Errore getAllSegments: $e');
      return [];
    }
  }

  /// Segmenti creati da una specifica traccia personale dell'utente.
  Future<List<Segment>> getSegmentsCreatedFromTrack(String sourceTrackId) async {
    try {
      final snap = await _segmentsCol
          .where('sourceTrackId', isEqualTo: sourceTrackId)
          .get();
      return snap.docs.map((d) => Segment.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint('[Segments] Errore getSegmentsCreatedFromTrack: $e');
      return [];
    }
  }

  /// Segmenti di un sentiero specifico.
  Future<List<Segment>> getSegmentsForTrail(String trailId) async {
    try {
      final snap = await _segmentsCol.where('trailId', isEqualTo: trailId).get();
      return snap.docs.map((d) => Segment.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint('[Segments] Errore getSegmentsForTrail: $e');
      return [];
    }
  }

  Future<Segment?> getSegment(String id) async {
    try {
      final doc = await _segmentsCol.doc(id).get();
      if (!doc.exists) return null;
      return Segment.fromFirestore(doc);
    } catch (e) {
      debugPrint('[Segments] Errore getSegment: $e');
      return null;
    }
  }

  // ─── Mutations ───────────────────────────────────────────────────────────

  /// Crea un nuovo segmento. Gli admin vengono validati anche dalle rules.
  /// Restituisce l'id del segmento creato, o null in caso di errore.
  Future<String?> createSegment(Segment s) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final docRef = _segmentsCol.doc();
      await docRef.set(s.toFirestoreCreate());
      invalidateCache();
      debugPrint('[Segments] Creato segmento ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('[Segments] Errore createSegment: $e');
      return null;
    }
  }

  /// Elimina un segmento (anche tutti gli efforts? Per MVP no, best effort).
  Future<bool> deleteSegment(String id) async {
    try {
      await _segmentsCol.doc(id).delete();
      invalidateCache();
      return true;
    } catch (e) {
      debugPrint('[Segments] Errore deleteSegment: $e');
      return false;
    }
  }

  // ─── Leaderboard ─────────────────────────────────────────────────────────

  /// Top N efforts ordinati per durata crescente (il primo è il primatista).
  Future<List<SegmentEffort>> getLeaderboard(String segmentId, {int limit = 10}) async {
    try {
      final snap = await _effortsCol(segmentId)
          .orderBy('durationSeconds')
          .limit(limit)
          .get();
      return snap.docs.map((d) => SegmentEffort.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint('[Segments] Errore getLeaderboard: $e');
      return [];
    }
  }

  /// Miglior effort personale dell'utente su un segmento (o null).
  Future<SegmentEffort?> getUserBestEffort(String segmentId, String userId) async {
    try {
      final snap = await _effortsCol(segmentId)
          .where('userId', isEqualTo: userId)
          .orderBy('durationSeconds')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return SegmentEffort.fromFirestore(snap.docs.first);
    } catch (e) {
      debugPrint('[Segments] Errore getUserBestEffort: $e');
      return null;
    }
  }

  /// Miglior effort assoluto (qualsiasi utente) su un segmento.
  Future<SegmentEffort?> getTopEffort(String segmentId) async {
    try {
      final snap = await _effortsCol(segmentId)
          .orderBy('durationSeconds')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return SegmentEffort.fromFirestore(snap.docs.first);
    } catch (e) {
      debugPrint('[Segments] Errore getTopEffort: $e');
      return null;
    }
  }

  /// Salva un nuovo effort.
  Future<bool> saveEffort(String segmentId, SegmentEffort effort) async {
    try {
      await _effortsCol(segmentId).add(effort.toFirestoreCreate());
      return true;
    } catch (e) {
      debugPrint('[Segments] Errore saveEffort: $e');
      return false;
    }
  }
}
