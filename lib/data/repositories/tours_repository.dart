import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/tour.dart';
import '../models/track.dart';
import 'public_trails_repository.dart';
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

  final PublicTrailsRepository _trailRepo = PublicTrailsRepository();

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
    TourType type = TourType.consecutive,
    List<String> galleryUrls = const [],
    String? bestPeriod,
    String? difficultyGrade,
    String? equipment,
    String? naturalNotes,
    required List<String> trackIds,
    Map<String, String> stageAccommodations = const {},
    int? daysCount, // override manuale; default = trackIds.length
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
      type: type,
      galleryUrls: galleryUrls,
      bestPeriod: bestPeriod,
      difficultyGrade: difficultyGrade,
      equipment: equipment,
      naturalNotes: naturalNotes,
      trackIds: trackIds,
      stageAccommodations: stageAccommodations,
      totalDistance: agg.totalDistance,
      totalElevationGain: agg.totalElevationGain,
      totalDuration: agg.totalDuration,
      daysCount: daysCount ?? agg.daysCount,
      bounds: agg.bounds,
      isPublic: isPublic,
      createdAt: DateTime.now(),
    );

    await docRef.set(tour.toFirestore());
    if (isPublic) {
      final stages =
          await _buildStageSummaries(tracks, uid, stageAccommodations,
              trackIds, tour.stageSources);
      await _communityTours.doc(docRef.id).set(tour.toCommunityFirestore(stages));
    }

    debugPrint('[ToursRepository] Tour creato: ${docRef.id}');
    return docRef.id;
  }

  /// Downsample uniforme delle elevazioni a max [maxSamples] valori.
  /// Punti senza elevation vengono skippati (l'array risultante può
  /// essere più corto se la traccia ha lacune). Se nessun punto ha
  /// elevation, ritorna vuoto → il chart fa fallback "no data".
  List<double> _downsampleElevations(List<TrackPoint> points,
      {int maxSamples = 60}) {
    if (points.isEmpty) return const [];
    final withElev = <double>[];
    for (final p in points) {
      if (p.elevation != null) withElev.add(p.elevation!);
    }
    if (withElev.isEmpty) return const [];
    if (withElev.length <= maxSamples) return withElev;
    final result = <double>[withElev.first];
    final step = withElev.length / (maxSamples - 2);
    for (var i = 1; i < maxSamples - 1; i++) {
      final idx = (i * step).round();
      if (idx < withElev.length - 1) result.add(withElev[idx]);
    }
    result.add(withElev.last);
    return result;
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

  /// Stesse riduzioni, ma su liste gia' pronte: le tappe del catalogo
  /// arrivano come LatLng e quote separate, non come TrackPoint.
  List<T> _riduci<T>(List<T> v, int max) {
    if (v.length <= max) return v;
    final r = <T>[v.first];
    final step = v.length / (max - 2);
    for (var i = 1; i < max - 1; i++) {
      final idx = (i * step).round();
      if (idx < v.length - 1) r.add(v[idx]);
    }
    r.add(v.last);
    return r;
  }

  List<LatLng> _downsamplePolylineLatLng(List<LatLng> p, {int maxPoints = 200}) =>
      p.isEmpty ? const [] : _riduci(p, maxPoints);

  List<double> _downsampleValues(List<double> v, {int maxSamples = 60}) =>
      v.isEmpty ? const [] : _riduci(v, maxSamples);

  /// Costruisce le stage summary denormalizzate + mapping pubblico.
  /// Una tappa presa dal catalogo invece che dalle tracce dell'utente.
  ///
  /// Ha tutto quello che serve a [TourStageSummary], e in due casi meglio:
  /// la geometria completa sta in `public_trail_geometries/{id}` come
  /// `coordinatesJson` — 890 punti CON LA QUOTA contro la polilinea
  /// decimata — e la durata viene da `oreStimate`, calcolato col passo
  /// dell'attività invece che cronometrato.
  ///
  /// ATTENZIONE all'ordine: in coordinatesJson e' [lon, lat, quota],
  /// longitudine PRIMA. E' l'opposto di come le scriviamo altrove.
  Future<TourStageSummary?> _publicTrailAsStage(
    String trailId,
    Map<String, String> stageAccommodations,
    Map<String, ({String name, String slug})> accommodationById,
  ) async {
    try {
      final doc = await _firestore.collection('public_trails').doc(trailId).get();
      if (!doc.exists) return null;
      final x = doc.data()!;

      var punti = <LatLng>[];
      var quote = <double>[];
      final g = await _firestore
          .collection('public_trail_geometries').doc(trailId).get();
      final raw = g.data()?['coordinatesJson'];
      if (raw is String && raw.isNotEmpty) {
        for (final c in (jsonDecode(raw) as List)) {
          if (c is List && c.length >= 2) {
            punti.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
            quote.add(c.length > 2 ? (c[2] as num).toDouble() : 0);
          }
        }
      }
      if (punti.isEmpty) {
        // Ripiego sui punti campionati per la mappa: pochi, ma meglio di nulla.
        for (final p in (x['simplifiedPoints'] as List? ?? const [])) {
          if (p is List && p.length >= 2) {
            punti.add(LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()));
          }
        }
      }

      final ore = (x['oreStimate'] as num?)?.toDouble();
      final bizId = stageAccommodations[trailId];
      final acc = bizId != null ? accommodationById[bizId] : null;
      return TourStageSummary(
        trackId: trailId,
        name: x['name']?.toString() ?? 'Tappa',
        activityType: x['activityType']?.toString() ?? 'trekking',
        distance: (x['distance'] as num?)?.toDouble() ?? 0,
        elevationGain: (x['elevationGain'] as num?)?.toDouble() ?? 0,
        duration: Duration(seconds: ((ore ?? 0) * 3600).round()),
        points: _downsamplePolylineLatLng(punti),
        elevationSamples: _downsampleValues(quote),
        isTrackPublic: false,
        communityTrackId: null,
        accommodationBusinessId: bizId,
        accommodationName: acc?.name,
        accommodationSlug: acc?.slug,
        isPublicTrail: true,
      );
    } catch (e) {
      debugPrint('[ToursRepository] tappa da catalogo $trailId non caricata: $e');
      return null;
    }
  }

  /// Costruisce le tappe rispettando l'ORDINE degli id, non quello delle
  /// tracce caricate: una tappa presa dal catalogo non e' fra `tracks`, e
  /// senza l'elenco ordinato finirebbe in coda o sparirebbe.
  Future<List<TourStageSummary>> _buildStageSummaries(
    List<Track> tracks,
    String ownerId, [
    Map<String, String> stageAccommodations = const {},
    List<String> ordine = const [],
    Map<String, String> stageSources = const {},
  ]) async {
    final publicMap = await _resolvePublicTrackMap(tracks, ownerId);

    // Fetch denormalizzato dei business accommodation: 1 read per
    // ogni businessId distinto referenziato. Risultato cachato per
    // questa build call (i tour pluri-giorno tipici hanno 3-7
    // accommodation distinti).
    final accommodationById = <String, ({String name, String slug})>{};
    final distinctBusinessIds = stageAccommodations.values.toSet();
    if (distinctBusinessIds.isNotEmpty) {
      for (final bizId in distinctBusinessIds) {
        try {
          final snap = await _firestore
              .collection('businesses')
              .doc(bizId)
              .get();
          if (snap.exists) {
            final data = snap.data();
            accommodationById[bizId] = (
              name: data?['name']?.toString() ?? 'Spazio Pro',
              slug: data?['slug']?.toString() ?? '',
            );
          }
        } catch (_) {
          // Best-effort: se il business è cancellato, skippa silenziosamente
        }
      }
    }

    // Senza provenienze da smistare si resta sul percorso di sempre.
    if (stageSources.isEmpty || ordine.isEmpty) {
      return _daTracce(tracks, stageAccommodations, accommodationById, publicMap);
    }

    final perTraccia = <String, TourStageSummary>{
      for (final st in _daTracce(tracks, stageAccommodations, accommodationById, publicMap))
        st.trackId: st,
    };
    final out = <TourStageSummary>[];
    for (final id in ordine) {
      if (stageSources[id] == 'public_trail') {
        final st = await _publicTrailAsStage(id, stageAccommodations, accommodationById);
        if (st != null) out.add(st);
      } else if (perTraccia[id] != null) {
        out.add(perTraccia[id]!);
      }
    }
    return out;
  }

  List<TourStageSummary> _daTracce(
    List<Track> tracks,
    Map<String, String> stageAccommodations,
    Map<String, ({String name, String slug})> accommodationById,
    Map<String, String> publicMap,
  ) {
    return [
      for (final t in tracks)
        () {
          final bizId = stageAccommodations[t.id ?? ''];
          final acc = bizId != null ? accommodationById[bizId] : null;
          return TourStageSummary(
            trackId: t.id ?? '',
            name: t.name,
            activityType: t.activityType.name,
            distance: t.stats.distance,
            elevationGain: t.stats.elevationGain,
            duration: t.stats.duration,
            points: _downsamplePolyline(t.points),
            elevationSamples: _downsampleElevations(t.points),
            isTrackPublic: t.id != null && publicMap.containsKey(t.id),
            communityTrackId: t.id != null ? publicMap[t.id] : null,
            accommodationBusinessId: bizId,
            accommodationName: acc?.name,
            accommodationSlug: acc?.slug,
          );
        }(),
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
  /// Le tappe di un tour come Track, da qualunque sorgente vengano.
  ///
  /// Sta qui e non nelle pagine perche' serve a tutte: la scheda del
  /// proprietario, l'editor, e chiunque altro debba mostrare le tappe. La
  /// prima versione la teneva solo nell'editor, e la scheda restava vuota.
  Future<List<Track>> loadTourTracks(Tour tour) async {
    final daTracce = await _loadTracksInOrder(tour.trackIds);
    if (tour.stageSources.isEmpty) return daTracce;

    final perId = {for (final t in daTracce) t.id: t};
    final out = <Track>[];
    for (final id in tour.trackIds) {
      if (tour.stageSources[id] == 'public_trail') {
        final t = await _trailRepo.getTrailById(id);
        if (t == null) continue;
        out.add(Track(
          id: id,
          name: t.name,
          points: t.points,
          activityType: t.parsedActivityType,
          createdAt: DateTime.now(),
          isPlanned: true,
          stats: TrackStats(
            distance: t.length ?? 0,
            elevationGain: t.elevationGain ?? 0,
          ),
        ));
      } else if (perId[id] != null) {
        out.add(perId[id]!);
      }
    }
    return out;
  }

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
    TourType? type,
    List<String>? galleryUrls,
    String? bestPeriod,
    String? difficultyGrade,
    String? equipment,
    String? naturalNotes,
    List<String>? trackIds,
    Map<String, String>? stageAccommodations,
    int? daysCount, // override manuale dell'auto-calcolo da numero tappe
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
      type: type,
      galleryUrls: galleryUrls,
      bestPeriod: bestPeriod,
      difficultyGrade: difficultyGrade,
      equipment: equipment,
      naturalNotes: naturalNotes,
      stageAccommodations: stageAccommodations,
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
        // Quando l'utente passa daysCount esplicito ha priorità,
        // altrimenti ricalcoliamo dal numero tappe (auto-default).
        daysCount: daysCount ?? agg.daysCount,
        bounds: agg.bounds,
      );
    } else if (daysCount != null && daysCount != current.daysCount) {
      // Solo daysCount modificato (no riassetto tappe).
      updated = updated.copyWith(daysCount: daysCount);
    }

    final accommodationsChanged = stageAccommodations != null &&
        !_mapEquals(stageAccommodations, current.stageAccommodations);

    await docRef.set(updated.toFirestore());

    if (updated.isPublic) {
      // Rigenera le stage summary quando: va pubblico per la prima volta,
      // tappe cambiate, oppure cambia l'assegnazione accommodation
      // (le accommodation sono denormalizzate dentro le stages).
      final needsRebuild =
          !current.isPublic || tracksChanged || accommodationsChanged;
      if (needsRebuild) {
        final tracks = await _loadTracksInOrder(updated.trackIds);
        final stages = await _buildStageSummaries(
            tracks, uid, updated.stageAccommodations,
            updated.trackIds, updated.stageSources);
        // Il rebuild è un set() pieno: rileggiamo il flag editoriale
        // dalla copia pubblica per non azzerarlo ad ogni modifica.
        final existing = await _communityTours.doc(tourId).get();
        final wasEditorial = existing.data()?['isEditorial'] == true;
        await _communityTours.doc(tourId).set(
              updated.toCommunityFirestore(stages, keepEditorial: wasEditorial),
            );
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

  bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
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

  // ─── Curatela editoriale ("Tour del mese") ─────────────────────────────────

  /// Il tour scelto dalla redazione per la Home, se c'è.
  ///
  /// Query di sola uguaglianza: i tour senza il campo semplicemente non
  /// matchano (nessuna migrazione necessaria) e non serve indice composito.
  Future<Tour?> getEditorialTour() async {
    try {
      final snap = await _communityTours
          .where('isEditorial', isEqualTo: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final d = snap.docs.first;
      return Tour.fromFirestore(d.id, d.data());
    } catch (e) {
      debugPrint('[ToursRepository] getEditorialTour fallita: $e');
      return null;
    }
  }

  /// Mette (o toglie) un tour dallo spazio "Tour del mese". Solo admin —
  /// il gate è lato UI, come per le altre azioni redazionali.
  ///
  /// Lo spazio è singolo: impostandone uno, il flag viene tolto agli
  /// altri, così non resta mai ambiguo quale sia in evidenza.
  Future<void> setEditorialTour(String tourId, bool isEditorial) async {
    if (isEditorial) {
      final previous = await _communityTours
          .where('isEditorial', isEqualTo: true)
          .get();
      for (final doc in previous.docs) {
        if (doc.id == tourId) continue;
        await doc.reference.update({'isEditorial': false});
      }
    }
    await _communityTours.doc(tourId).update({'isEditorial': isEditorial});
    debugPrint('[ToursRepository] Tour $tourId editoriale: $isEditorial');
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
