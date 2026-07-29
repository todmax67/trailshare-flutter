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

  /// Segmenti creati da una specifica traccia personale.
  /// Se [publicOnly] è true, filtra ulteriormente per `isPublic: true`
  /// (usato nelle view community).
  /// I segmenti ATTRAVERSATI da una traccia, col tempo che ci hai messo.
  ///
  /// Diverso da [getSegmentsCreatedFromTrack], che restituisce quelli NATI da
  /// quella traccia: se passi su un segmento creato da un'altra tua uscita o
  /// da qualcun altro, il primo lo trova e il secondo no. La scheda usava
  /// solo il secondo, e restava vuota anche passando su un segmento.
  ///
  /// Si appoggia agli effort, che portano il trackId: una query di gruppo
  /// sulle sottocollezioni `efforts` trova i passaggi, e da li' si risale ai
  /// segmenti.
  Future<List<({Segment segment, SegmentEffort effort})>>
      getSegmentsTraversedByTrack(String trackId) async {
    try {
      final snap = await _firestore
          .collectionGroup('efforts')
          .where('trackId', isEqualTo: trackId)
          .get();
      final out = <({Segment segment, SegmentEffort effort})>[];
      for (final d in snap.docs) {
        final segRef = d.reference.parent.parent;
        if (segRef == null) continue;
        final seg = await segRef.get();
        if (!seg.exists) continue;
        out.add((
          segment: Segment.fromFirestore(seg),
          effort: SegmentEffort.fromFirestore(d),
        ));
      }
      return out;
    } catch (e) {
      // Serve l'indice di gruppo su efforts.trackId: senza, Firestore
      // rifiuta la query e la scheda resta come prima invece di rompersi.
      debugPrint('[Segments] getSegmentsTraversedByTrack: $e');
      return const [];
    }
  }

  Future<List<Segment>> getSegmentsCreatedFromTrack(
    String sourceTrackId, {
    bool publicOnly = false,
  }) async {
    try {
      Query<Map<String, dynamic>> q =
          _segmentsCol.where('sourceTrackId', isEqualTo: sourceTrackId);
      if (publicOnly) {
        q = q.where('isPublic', isEqualTo: true);
      }
      final snap = await q.get();
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
  /// Classifica del segmento, senza gli sforzi con attività incompatibile:
  /// una pedalata a 20 km/h su un segmento di corsa non sta in graduatoria
  /// coi podisti. Si chiede piu' del necessario e si scarta in memoria,
  /// perche' una disuguaglianza su Firestore escluderebbe anche i documenti
  /// privi del campo — cioe' tutti quelli scritti prima della correzione.
  Future<List<SegmentEffort>> getLeaderboard(String segmentId, {int limit = 10}) async {
    try {
      final snap = await _effortsCol(segmentId)
          .orderBy('durationSeconds')
          .limit(limit * 4)
          .get();
      return snap.docs
          .where((d) => d.data()['activityMismatch'] != true)
          .take(limit)
          .map((d) => SegmentEffort.fromFirestore(d))
          .toList();
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
          .limit(20)
          .get();
      final validi = snap.docs.where((d) => d.data()['activityMismatch'] != true);
      if (validi.isEmpty) return null;
      return SegmentEffort.fromFirestore(validi.first);
    } catch (e) {
      debugPrint('[Segments] Errore getUserBestEffort: $e');
      return null;
    }
  }

  /// Miglior effort assoluto (qualsiasi utente) su un segmento.
  /// Gli sforzi registrati con un'attività incompatibile col segmento sono
  /// marcati `activityMismatch` e non entrano in classifica: 13 dei 16
  /// esistenti erano pedalate in e-bike su segmenti di corsa, e vincendo
  /// sempre rendevano la graduatoria priva di senso. Si filtra in memoria
  /// perché gli sforzi per segmento sono pochi e una disuguaglianza su
  /// Firestore escluderebbe anche i documenti privi del campo.
  Future<SegmentEffort?> getTopEffort(String segmentId) async {
    try {
      final snap = await _effortsCol(segmentId)
          .orderBy('durationSeconds')
          .limit(20)
          .get();
      final validi = snap.docs.where((d) => d.data()['activityMismatch'] != true);
      if (validi.isEmpty) return null;
      return SegmentEffort.fromFirestore(validi.first);
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
