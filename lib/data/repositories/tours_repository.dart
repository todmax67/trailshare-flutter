import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/tour.dart';
import '../models/track.dart';
import 'tracks_repository.dart';

/// Repository per i tour multi-giorno.
///
/// Storage:
/// - `users/{uid}/tours/{tourId}` — copia privata del proprietario
/// - `community_tours/{tourId}` — copia pubblica (mirror, solo se isPublic)
class ToursRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final TracksRepository _tracksRepository;

  ToursRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    TracksRepository? tracksRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _tracksRepository = tracksRepository ?? TracksRepository();

  CollectionReference<Map<String, dynamic>> _toursCollection(String userId) =>
      _firestore.collection('users').doc(userId).collection('tours');

  CollectionReference<Map<String, dynamic>> get _communityTours =>
      _firestore.collection('community_tours');

  String get _requireUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Utente non autenticato');
    return uid;
  }

  // ─── Creazione ─────────────────────────────────────────────────────────────

  /// Crea un nuovo tour aggregando le tracce indicate (nell'ordine fornito).
  Future<String> createTour({
    required String title,
    String? description,
    String? coverPhotoUrl,
    required List<String> trackIds,
    bool isPublic = false,
  }) async {
    final uid = _requireUid;
    final user = _auth.currentUser!;

    if (trackIds.isEmpty) {
      throw ArgumentError('Un tour deve contenere almeno una traccia');
    }

    final tracks = await _loadTracksInOrder(trackIds);
    final agg = TourAggregates.fromTracks(tracks);

    final docRef = _toursCollection(uid).doc();
    final tour = Tour(
      id: docRef.id,
      ownerId: uid,
      ownerName: user.displayName ?? user.email ?? 'Utente',
      ownerPhotoUrl: user.photoURL,
      title: title,
      description: description,
      coverPhotoUrl: coverPhotoUrl,
      trackIds: trackIds,
      totalDistance: agg.totalDistance,
      totalElevationGain: agg.totalElevationGain,
      totalDuration: agg.totalDuration,
      daysCount: agg.daysCount,
      bounds: agg.bounds,
      isPublic: isPublic,
      createdAt: DateTime.now(),
    );

    await docRef.set(tour.toFirestore());
    if (isPublic) {
      final stages = await _buildStageSummaries(tracks, uid);
      await _communityTours.doc(docRef.id).set(tour.toCommunityFirestore(stages));
    }

    debugPrint('[ToursRepository] Tour creato: ${docRef.id}');
    return docRef.id;
  }

  /// Downsample uniforme di [points] a max [maxPoints] preservando primo/ultimo.
  List<LatLng> _downsamplePolyline(List<TrackPoint> points, {int maxPoints = 200}) {
    if (points.isEmpty) return const [];
    if (points.length <= maxPoints) {
      return points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    }
    final result = <LatLng>[LatLng(points.first.latitude, points.first.longitude)];
    final step = points.length / (maxPoints - 2);
    for (var i = 1; i < maxPoints - 1; i++) {
      final idx = (i * step).round();
      if (idx < points.length - 1) {
        result.add(LatLng(points[idx].latitude, points[idx].longitude));
      }
    }
    result.add(LatLng(points.last.latitude, points.last.longitude));
    return result;
  }

  /// Costruisce le stage summary denormalizzate + mapping pubblico.
  Future<List<TourStageSummary>> _buildStageSummaries(
    List<Track> tracks,
    String ownerId,
  ) async {
    final publicMap = await _resolvePublicTrackMap(tracks, ownerId);

    return [
      for (final t in tracks)
        TourStageSummary(
          trackId: t.id ?? '',
          name: t.name,
          activityType: t.activityType.name,
          distance: t.stats.distance,
          elevationGain: t.stats.elevationGain,
          duration: t.stats.duration,
          points: _downsamplePolyline(t.points),
          isTrackPublic: t.id != null && publicMap.containsKey(t.id),
          communityTrackId: t.id != null ? publicMap[t.id] : null,
        ),
    ];
  }

  /// Risolve la mappa `privateTrackId -> communityDocId` per le tracce
  /// indicate in [tracks] che hanno una copia in `community_tracks`.
  ///
  /// Strategia:
  /// 1. Prova doc-id diretto: per tracce pubblicate dall'app Flutter i due
  ///    id coincidono.
  /// 2. Fallback per tracce pubblicate dalla vecchia app JS (doc id
  ///    diverso): legge tutte le `community_tracks` del proprietario e fa
  ///    match per nome + distanza (tolleranza 100m).
  Future<Map<String, String>> _resolvePublicTrackMap(
    List<Track> tracks,
    String ownerId,
  ) async {
    if (tracks.isEmpty) return const {};

    final mapping = <String, String>{};
    final unmatched = <Track>[];

    // Step 1: doc id diretto
    final directResults = await Future.wait(
      tracks.map((t) async {
        final id = t.id;
        if (id == null) return null;
        try {
          final doc = await _firestore.collection('published_tracks').doc(id).get();
          return doc.exists ? t : null;
        } catch (_) {
          return null;
        }
      }),
    );
    final directMatched = directResults.whereType<Track>().map((t) => t.id).toSet();
    for (final t in tracks) {
      if (t.id == null) continue;
      if (directMatched.contains(t.id)) {
        mapping[t.id!] = t.id!;
      } else {
        unmatched.add(t);
      }
    }

    // Step 2: fallback per-owner (solo se ci sono unmatched)
    if (unmatched.isNotEmpty) {
      try {
        final snap = await _firestore
            .collection('published_tracks')
            .where('originalOwnerId', isEqualTo: ownerId)
            .limit(100)
            .get();
        debugPrint('[ToursRepository] fallback owner-query: ${snap.docs.length} community_tracks di $ownerId');

        for (final track in unmatched) {
          String? matchId;
          final privDist = track.stats.distance;
          final privName = track.name.trim().toLowerCase();
          for (final doc in snap.docs) {
            final data = doc.data();
            final cName = (data['name']?.toString() ?? '').trim().toLowerCase();
            final cDist = (data['distance'] as num?)?.toDouble() ?? 0;
            // Match: stesso nome + distanza entro 100m
            if (cName == privName && (cDist - privDist).abs() < 100) {
              matchId = doc.id;
              break;
            }
          }
          if (matchId != null && track.id != null) {
            mapping[track.id!] = matchId;
          }
        }
      } catch (e) {
        debugPrint('[ToursRepository] fallback query error: $e');
      }
    }

    debugPrint(
      '[ToursRepository] resolvePublicTrackMap: ${mapping.length}/${tracks.length} risolte',
    );
    return mapping;
  }

  /// API esposta al picker (edit page) e alla community detail.
  /// Accetta le tracce e l'ownerId e ritorna la mappa `privateId → communityId`.
  Future<Map<String, String>> resolvePublicTrackMap(List<Track> tracks, String ownerId) =>
      _resolvePublicTrackMap(tracks, ownerId);

  /// Helper legacy: solo il set dei private id che hanno corrispettivo pubblico.
  /// Usato dal picker dove serve solo il badge.
  Future<Set<String>> getPublicTrackIds(List<String> trackIds) async {
    if (trackIds.isEmpty) return const {};
    // Solo lookup diretto: il picker sa usare gli id privati.
    final results = await Future.wait(
      trackIds.map((id) async {
        try {
          final doc = await _firestore.collection('published_tracks').doc(id).get();
          return doc.exists ? id : null;
        } catch (_) {
          return null;
        }
      }),
    );
    return results.whereType<String>().toSet();
  }

  // ─── Lettura ───────────────────────────────────────────────────────────────

  Future<List<Tour>> getMyTours() async {
    final uid = _requireUid;
    final snap = await _toursCollection(uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    return snap.docs.map((d) => Tour.fromFirestore(d.id, d.data())).toList();
  }

  Stream<List<Tour>> watchMyTours() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _toursCollection(uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Tour.fromFirestore(d.id, d.data())).toList());
  }

  Future<Tour?> getTourById(String tourId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _toursCollection(uid).doc(tourId).get();
    if (!doc.exists || doc.data() == null) return null;
    return Tour.fromFirestore(doc.id, doc.data()!);
  }

  Future<Tour?> getPublicTourById(String tourId) async {
    final doc = await _communityTours.doc(tourId).get();
    if (!doc.exists || doc.data() == null) return null;
    return Tour.fromFirestore(doc.id, doc.data()!);
  }

  /// Carica le tracce di un tour nell'ordine corretto.
  /// Tracce mancanti vengono saltate silenziosamente.
  Future<List<Track>> loadTourTracks(Tour tour) =>
      _loadTracksInOrder(tour.trackIds);

  Future<List<Track>> _loadTracksInOrder(List<String> trackIds) async {
    final fetched = <String, Track>{};
    for (final id in trackIds) {
      final t = await _tracksRepository.getTrackById(id);
      if (t != null) fetched[id] = t;
    }
    return [
      for (final id in trackIds)
        if (fetched[id] != null) fetched[id]!,
    ];
  }

  // ─── Aggiornamento ─────────────────────────────────────────────────────────

  /// Aggiorna i metadati del tour. Se cambiano [trackIds] ricalcola gli aggregati.
  Future<void> updateTour(
    String tourId, {
    String? title,
    String? description,
    String? coverPhotoUrl,
    List<String>? trackIds,
    bool? isPublic,
  }) async {
    final uid = _requireUid;
    final docRef = _toursCollection(uid).doc(tourId);
    final snap = await docRef.get();
    if (!snap.exists || snap.data() == null) {
      throw Exception('Tour non trovato: $tourId');
    }
    final current = Tour.fromFirestore(snap.id, snap.data()!);

    Tour updated = current.copyWith(
      title: title,
      description: description,
      coverPhotoUrl: coverPhotoUrl,
      isPublic: isPublic,
      updatedAt: DateTime.now(),
    );

    final tracksChanged =
        trackIds != null && !_listEquals(trackIds, current.trackIds);
    if (tracksChanged) {
      if (trackIds.isEmpty) {
        throw ArgumentError('Un tour deve contenere almeno una traccia');
      }
      final tracks = await _loadTracksInOrder(trackIds);
      final agg = TourAggregates.fromTracks(tracks);
      updated = updated.copyWith(
        trackIds: trackIds,
        totalDistance: agg.totalDistance,
        totalElevationGain: agg.totalElevationGain,
        totalDuration: agg.totalDuration,
        daysCount: agg.daysCount,
        bounds: agg.bounds,
      );
    }

    await docRef.set(updated.toFirestore());

    if (updated.isPublic) {
      // Rigenera le stage summary quando: va pubblico per la prima volta,
      // oppure è già pubblico ma le tappe sono cambiate.
      final needsRebuild = !current.isPublic || tracksChanged;
      if (needsRebuild) {
        final tracks = await _loadTracksInOrder(updated.trackIds);
        final stages = await _buildStageSummaries(tracks, uid);
        await _communityTours.doc(tourId).set(updated.toCommunityFirestore(stages));
      } else {
        // Solo metadati cambiati: merge per preservare le stage esistenti.
        await _communityTours.doc(tourId).set(
              updated.toFirestore(),
              SetOptions(merge: true),
            );
      }
    } else if (current.isPublic) {
      await _communityTours.doc(tourId).delete();
    }
  }

  // ─── Eliminazione ──────────────────────────────────────────────────────────

  Future<void> deleteTour(String tourId) async {
    final uid = _requireUid;
    await _toursCollection(uid).doc(tourId).delete();
    await _communityTours.doc(tourId).delete().catchError((_) {});
    debugPrint('[ToursRepository] Tour eliminato: $tourId');
  }

  // ─── Community feed ────────────────────────────────────────────────────────

  Future<List<Tour>> getPublicTours({int limit = 20}) async {
    final snap = await _communityTours
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => Tour.fromFirestore(d.id, d.data())).toList();
  }

  // ─── Helper ────────────────────────────────────────────────────────────────

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
