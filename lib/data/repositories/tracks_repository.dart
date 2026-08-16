import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/track.dart';
import '../../core/utils/difficulty_calculator.dart';
import '../../core/utils/elevation_dem_corrector.dart';
import '../../core/utils/elevation_processor.dart';
import '../../core/utils/perf_trace.dart';
import '../../core/services/growth_analytics_service.dart';
import '../../core/services/save_diagnostics_service.dart';
import '../../core/utils/track_simplify.dart';

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

/// Esito di [TracksRepository.saveTrackDetailed]: oltre all'ID dice se la
/// scrittura è stata **confermata dal server** o se è solo accodata nella
/// coda di mutazioni locale (offline / rete lenta).
///
/// Serve al chiamante per decidere se può buttare via il proprio backup
/// (es. `recording_backup.json`): finché `confirmedByServer` è false la
/// coda Firestore è l'unica copia della registrazione.
class SaveTrackResult {
  final String trackId;
  final bool confirmedByServer;

  const SaveTrackResult({
    required this.trackId,
    required this.confirmedByServer,
  });
}

/// Repository unificato per gestire le tracce su Firestore
/// Compatibile con la struttura dati esistente dall'app JavaScript
class TracksRepository {
  /// Sentinel per [updateTrack]: distingue "non passare il parametro"
  /// (lascia il campo invariato) da "imposta a null" (rimuovi).
  static const Object _unsetManual = Object();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Istanze iniettabili per i test (fake_cloud_firestore + auth mock).
  /// In produzione restano i singleton `.instance`, quindi i chiamanti
  /// esistenti (`TracksRepository()`) non cambiano.
  TracksRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Helper: ottiene la collection delle tracce per un dato userId
  CollectionReference<Map<String, dynamic>> _tracksCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('tracks');
  }

  /// Doc unico che contiene la GEOMETRIA pesante (punti GPS + battito) di
  /// una traccia, fuori dal documento principale per non gonfiarlo (causa
  /// dell'OOM: cache satura). Stesso schema dei public_trail_geometries.
  /// Path: users/{uid}/tracks/{trackId}/geometry/data — una sola read.
  DocumentReference<Map<String, dynamic>> _geometryDoc(
      String userId, String trackId) {
    return _tracksCollection(userId)
        .doc(trackId)
        .collection('geometry')
        .doc('data');
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

  /// Salva una nuova traccia e restituisce l'ID.
  ///
  /// Dopo il save, **lancia in background** la correzione DEM delle
  /// quote GPS (vedi [correctTrackElevationsFromDem]). Non blocca il
  /// return: l'utente vede subito la traccia salvata con stats
  /// preliminari, il chart si aggiorna entro pochi secondi quando la
  /// correzione completa.
  Future<String> saveTrack(Track track) async {
    final result = await saveTrackDetailed(track);
    return result.trackId;
  }

  /// Come [saveTrack] ma restituisce anche l'esito della sincronizzazione
  /// (vedi [SaveTrackResult]). Da usare nei flussi che, dopo il save,
  /// distruggono la propria copia locale dei dati.
  ///
  /// [attemptId] correla questo salvataggio con l'evento `started` emesso dal
  /// chiamante nel funnel di [SaveDiagnosticsService]. Se omesso si usa l'ID
  /// della traccia, che però esiste solo dal momento in cui il doc è creato.
  Future<SaveTrackResult> saveTrackDetailed(
    Track track, {
    String? attemptId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utente non autenticato');

    try {
      // Stats dai punti COMPLETI, riduzione solo per lo storage: e' la
      // traccia salvata a finire sulla mappa, nel GPX esportato e nella
      // condivisione, quindi la sua forma conta anche se i numeri no.
      //
      // La riduzione e' per FORMA (Douglas-Peucker) e non piu' un punto ogni
      // N: quella uniforme trattava tornanti e rettilinei allo stesso modo e
      // tagliava gli angoli, accorciando il percorso — il bug dell'utente Pro
      // col GPX da 34 km mostrato come 26,6. Misurato su una traccia reale, a
      // parita' di punti conservati lo scarto di lunghezza passa da -5,4% a
      // -1,1%.
      final savedPoints = simplifyTrack(track.points);
      final stats = track.isPlanned
          ? track.stats // Percorsi pianificati: usa stats dal router
          : _recalculateStats(track.points, track.stats);

      final metadata = _trackToFirestore(track, user.uid, savedPoints, stats);

      // ID pre-generato + batch: metadati e geometria committano INSIEME
      // (atomico). Mai uno stato "doc dice di avere geometria ma non c'è".
      final docRef = _tracksCollection(user.uid).doc();
      final batch = _firestore.batch();
      batch.set(docRef, metadata);
      if (savedPoints.isNotEmpty) {
        batch.set(_geometryDoc(user.uid, docRef.id),
            _geometryDataFor(savedPoints, track.heartRateData));
      }
      // Offline / rete lenta: con la persistenza Firestore la commit resta in
      // coda locale e non risolve finché non torna il segnale → l'UI restava
      // col a spinner all'infinito (finally mai raggiunto). NON blocchiamo: la
      // traccia è già salvata localmente (ID generato) e sincronizza da sola.
      // Timeout = successo LOCALE, non conferma del server: lo diciamo al
      // chiamante con `confirmedByServer` così può tenersi il proprio backup
      // finché la coda non si svuota (vedi [SaveTrackResult]).
      bool confirmedByServer = true;
      try {
        await batch.commit().timeout(const Duration(seconds: 5));
      } on TimeoutException {
        confirmedByServer = false;
        debugPrint(
            '[TracksRepository] saveTrack: commit offline → salvata in locale, sync differita');
      }

      debugPrint('[TracksRepository] Traccia salvata con ID: ${docRef.id} '
          '(confermata dal server: $confirmedByServer)');

      // Lancia correzione DEM in background, non-bloccante. Eventuali
      // errori (offline, AWS down) sono loggati ma non risalgono al
      // chiamante: la traccia resta salvata con le quote GPS originali.
      // L'utente può ricorreggere manualmente da TrackDetail.
      if (!track.elevationCorrectedFromDem && track.points.isNotEmpty) {
        unawaited(_autoCorrectElevationsInBackground(docRef.id, user.uid));
      }

      // Telemetria: è QUI che sappiamo se il salvataggio è arrivato sul
      // server o è rimasto in coda. Fire-and-forget, non deve mai rallentare
      // né far fallire il salvataggio.
      unawaited(SaveDiagnosticsService.instance.record(
        confirmedByServer
            ? SaveOutcome.confirmedServer
            : SaveOutcome.localOnly,
        attemptId: attemptId ?? docRef.id,
        trackId: docRef.id,
        pointsCount: savedPoints.length,
        distanceMeters: stats.distance,
        durationSeconds: stats.duration.inSeconds,
        activityType: track.activityType.name,
      ));

      // Attivazione: la prima traccia salvata e' il momento in cui un
      // installato diventa un utente vero. E' la metrica su cui si giudica
      // ogni canale di acquisizione — un canale che porta installazioni che
      // non arrivano qui non sta portando niente.
      unawaited(GrowthAnalyticsService.instance.milestone(
        GrowthMilestone.firstTrackSaved,
        params: {
          'activity_type': track.activityType.name,
          'distance_km': (stats.distance / 1000).round(),
          'is_public': track.isPublic ? 1 : 0,
        },
      ));
      if (track.isPublic) {
        unawaited(GrowthAnalyticsService.instance
            .milestone(GrowthMilestone.firstTrackPublic));
      }
      // Oltre alla prima volta: il conteggio dice quanto l'app viene usata,
      // che le milestone da sole non possono dire.
      unawaited(GrowthAnalyticsService.instance
          .recordTrackSaved(isPublic: track.isPublic));

      return SaveTrackResult(
        trackId: docRef.id,
        confirmedByServer: confirmedByServer,
      );
    } catch (e) {
      debugPrint('[TracksRepository] Errore saveTrack: $e');
      unawaited(SaveDiagnosticsService.instance.record(
        SaveOutcome.failed,
        attemptId: attemptId ?? 'unknown',
        pointsCount: track.points.length,
        distanceMeters: track.stats.distance,
        activityType: track.activityType.name,
        error: e,
      ));
      rethrow;
    }
  }

  /// Si risolve quando Firestore ha svuotato la coda di mutazioni locali
  /// (tutte le scritture in sospeso sono state confermate dal server).
  /// Usata dai flussi che tengono un backup su disco finché il save non è
  /// davvero arrivato. Non risolve mai finché l'app resta offline.
  Future<void> waitForPendingWrites() => _firestore.waitForPendingWrites();

  /// `true` se il doc traccia esiste **sul server** (bypassa la cache, che
  /// mostrerebbe come esistente anche una scrittura mai sincronizzata).
  /// `null` se non è possibile saperlo (offline, errore di rete).
  Future<bool?> trackExistsOnServer(String userId, String trackId) async {
    try {
      final snap = await _tracksCollection(userId)
          .doc(trackId)
          .get(const GetOptions(source: Source.server));
      return snap.exists;
    } catch (e) {
      debugPrint('[TracksRepository] trackExistsOnServer($trackId): $e');
      return null;
    }
  }

  /// Esegue la correzione DEM in background dopo il save di una nuova
  /// traccia. Errori silenti (l'utente vedrà ancora le quote GPS, e
  /// può richiedere la correzione manuale da TrackDetail).
  Future<void> _autoCorrectElevationsInBackground(
    String trackId,
    String userId,
  ) async {
    try {
      debugPrint('[TracksRepository] auto-correzione DEM background per $trackId');
      await correctTrackElevationsFromDem(trackId, userId: userId);
    } catch (e) {
      debugPrint('[TracksRepository] auto-correzione DEM background failed: $e');
    }
  }

  /// Ricalcola le quote di una traccia esistente usando il DEM
  /// (AWS Open Terrain Tiles). Aggiorna i punti, elevationGain/loss,
  /// max/minAltitude, computedDifficulty (se dipende dalle stats) e
  /// setta `elevationCorrectedFromDem=true`.
  ///
  /// Ritorna le statistiche della correzione (delta medio/min/max).
  /// Ritorna `null` se la traccia non esiste o se il DEM non è
  /// disponibile (nessun update applicato).
  Future<CorrectionResult?> correctTrackElevationsFromDem(
    String trackId, {
    String? userId,
    void Function(int corrected, int total)? onProgress,
  }) async {
    final uid = userId ?? _auth.currentUser?.uid;
    if (uid == null) return null;

    final docRef = _tracksCollection(uid).doc(trackId);
    final snap = await docRef.get();
    if (!snap.exists) return null;
    final data = snap.data()!;

    // Carica i punti: dal doc geometria (tracce nuove) o inline (legacy).
    // Senza questo, la DEM auto-correzione salterebbe TUTTE le tracce nuove
    // (i cui doc principali non hanno più 'points').
    final hasGeom = data['hasGeometryDoc'] == true;
    final List<TrackPoint> points;
    if (hasGeom) {
      final geo = await _loadGeometry(uid, trackId);
      points = geo?.points ?? const [];
    } else {
      points = _parsePointsList(data['points']);
    }
    if (points.isEmpty) return null;

    // Correzione DEM.
    final result = await ElevationDemCorrector.correct(
      points,
      onProgress: onProgress,
    );
    if (!result.success || !result.hasChanges) return result;

    // Ricalcola gain/loss/max/min con ElevationProcessor sui valori corretti.
    final activityRaw = data['activityType']?.toString() ?? 'trekking';
    final processor = ElevationProcessor.forActivity(activityRaw);
    final eleResult = processor.process(
      result.points.map((p) => p.elevation).toList(),
    );

    // Ricalcola difficulty (se non è override manuale).
    final stats = TrackStats(
      distance: (data['distance'] as num?)?.toDouble() ?? 0,
      elevationGain: eleResult.elevationGain,
      elevationLoss: eleResult.elevationLoss,
    );
    final newDifficulty = DifficultyCalculator.compute(
      stats: stats,
      activityType: _parseActivity(activityRaw),
    );

    // Scrivi i PUNTI corretti dove vivono: nel doc geometria (merge per
    // preservare l'heartRateData) per le tracce nuove, inline per le legacy.
    if (hasGeom) {
      await _geometryDoc(uid, trackId).set({
        'pointsJson': _encodePointsJson(result.points),
        'pointsCount': result.points.length,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // Metadati (stat + flag) sempre sul doc principale.
    final updates = <String, dynamic>{
      if (!hasGeom)
        'points': result.points.map((p) => p.toMap()).toList(),
      'elevationGain': eleResult.elevationGain,
      'elevationLoss': eleResult.elevationLoss,
      'maxAltitude': eleResult.maxElevation,
      'minAltitude': eleResult.minElevation,
      'elevationCorrectedFromDem': true,
      if (newDifficulty != null)
        'computedDifficulty': newDifficulty.firestoreKey,
    };

    await docRef.update(updates);
    debugPrint('[TracksRepository] DEM correction applicata a $trackId: '
        'gain=${eleResult.elevationGain.toStringAsFixed(0)}m '
        'max=${eleResult.maxElevation.toStringAsFixed(0)}m '
        'diff=${newDifficulty?.code ?? "?"}');

    return result;
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
          .limit(limit);

      // Se abbiamo un documento di partenza, inizia da lì
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snapshot = await query.get();

      debugPrint('[TracksRepository] Paginazione: ${snapshot.docs.length} tracce caricate');

      final tracks = snapshot.docs.map((doc) {
        return _trackFromFirestore(doc.id, doc.data(),
            pendingSync: doc.metadata.hasPendingWrites);
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
        return _trackFromFirestore(doc.id, data,
            pendingSync: doc.metadata.hasPendingWrites);
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

  /// Variante di [getMyTracksLightweight] che accetta un userId
  /// arbitrario (es. profilo pubblico di un altro utente). Stessa
  /// strategia: skip `points`, limit alto.
  Future<List<Track>> getUserTracksLightweight(
    String userId, {
    int limit = 1000,
  }) async {
    try {
      final snapshot = await PerfTrace.track(
        'tracks.userLightweight.query[$userId]',
        () => _tracksCollection(userId)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get(),
        describe: (s) => '${s.docs.length} doc, fromCache=${s.metadata.isFromCache}',
      );
      return PerfTrace.trackSync(
        'tracks.userLightweight.parse[$userId]',
        () => snapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data.remove('points');
          final t = _trackFromFirestore(doc.id, data,
              pendingSync: doc.metadata.hasPendingWrites);
          // Fallback userId dal path (per tracce con campo top-level
          // mancante) — qui usiamo userId della firma, non currentUser.
          return t.userId == null ? t.copyWith(userId: userId) : t;
        }).toList(),
      );
    } catch (e) {
      debugPrint(
          '[TracksRepository] Errore getUserTracksLightweight($userId): $e');
      return [];
    }
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
      final snapshot = await PerfTrace.track(
        'tracks.myLightweight.query',
        () => bypassCache
            ? query.get(const GetOptions(source: Source.server))
            : query.get(),
        describe: (s) => '${s.docs.length} doc, fromCache=${s.metadata.isFromCache}',
      );
      return PerfTrace.trackSync(
        'tracks.myLightweight.parse',
        () => snapshot.docs.map((doc) {
          // Copia mutabile + rimozione points prima del parse
          final data = Map<String, dynamic>.from(doc.data());
          data.remove('points');
          final t = _trackFromFirestore(doc.id, data,
              pendingSync: doc.metadata.hasPendingWrites);
          // Fallback userId dal path (tracce vecchie senza campo
          // top-level userId — vedi getTrackById per dettagli).
          return t.userId == null ? t.copyWith(userId: userId) : t;
        }).toList(),
      );
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
            .map((doc) => _trackFromFirestore(doc.id, doc.data(),
                pendingSync: doc.metadata.hasPendingWrites))
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
      final data = doc.data()!;
      final track = _trackFromFirestore(doc.id, data);
      return await _attachGeometryIfNeeded(ownerId, doc.id, data, track);
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
      final doc = await PerfTrace.track(
        'tracks.byId.docGet[$trackId]',
        () => _tracksCollection(userId).doc(trackId).get(),
        describe: (d) => 'exists=${d.exists}, fromCache=${d.metadata.isFromCache}',
      );
      if (!doc.exists || doc.data() == null) return null;
      final data = doc.data()!;
      var track = PerfTrace.trackSync(
        'tracks.byId.parse[$trackId]',
        () => _trackFromFirestore(doc.id, data,
            pendingSync: doc.metadata.hasPendingWrites),
        describe: (t) => '${t.points.length} punti inline',
      );
      // Lazy-load dei punti dalla sub-collezione geometria (tracce nuove).
      track = await _attachGeometryIfNeeded(userId, doc.id, data, track);
      // Fallback: tracce vecchie possono non avere il campo userId
      // salvato top-level (lo si conosce comunque dal path). Senza
      // questo, ownership check (es. _canEdit in WebTrackPhotosEditor)
      // ritorna false e il bottone 'Aggiungi foto' resta nascosto
      // anche sulle proprie tracce.
      return track.userId == null
          ? track.copyWith(userId: userId)
          : track;
    } catch (e) {
      debugPrint('[TracksRepository] Errore getTrackById: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AGGIORNAMENTO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Aggiorna una traccia esistente
  /// Aggiorna campi editabili di una traccia.
  ///
  /// [manualDifficulty]: stringa "t1".."t5" per impostare override
  /// manuale, oppure stringa vuota "" per **rimuovere** l'override
  /// (torna alla classificazione automatica). Non passare il parametro
  /// (null implicito tramite `_unsetManual`) per non toccare il campo.
  Future<void> updateTrack(String trackId, {
    String? name,
    String? description,
    ActivityType? activityType,
    bool? isPublic,
    bool? hiddenFromFeed,
    Object? manualDifficulty = _unsetManual,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (activityType != null) updates['activityType'] = activityType.name;
    if (isPublic != null) updates['isPublic'] = isPublic;
    if (hiddenFromFeed != null) updates['hiddenFromFeed'] = hiddenFromFeed;

    // Override manuale difficoltà:
    // - string non vuota → imposta override
    // - string vuota → rimuove override (torna ad auto)
    // - _unsetManual → non tocca il campo
    if (manualDifficulty != _unsetManual) {
      if (manualDifficulty is String && manualDifficulty.isNotEmpty) {
        updates['manualDifficulty'] = manualDifficulty;
      } else {
        updates['manualDifficulty'] = FieldValue.delete();
      }
    }

    if (updates.isEmpty) return;

    // Komoot K1a — se cambia activityType, oppure se la traccia non
    // ha ancora computedDifficulty (legacy pre-21/5), ricalcoliamo
    // T-grade dalle stats correnti. Fetch del doc per leggere stats
    // + activityType corrente (se non viene cambiato in questo
    // update).
    final docRef = _tracksCollection(userId).doc(trackId);
    final snap = await docRef.get();
    if (snap.exists) {
      final data = snap.data();
      final hasComputed =
          data?['computedDifficulty'] != null;
      if (activityType != null || !hasComputed) {
        final currentActivity = activityType ??
            _parseActivity(data?['activityType']?.toString());
        final stats = TrackStats(
          distance: (data?['distance'] as num?)?.toDouble() ?? 0,
          elevationGain:
              (data?['elevationGain'] as num?)?.toDouble() ?? 0,
          elevationLoss:
              (data?['elevationLoss'] as num?)?.toDouble() ?? 0,
        );
        final newDifficulty = DifficultyCalculator.compute(
          stats: stats,
          activityType: currentActivity,
        );
        if (newDifficulty != null) {
          updates['computedDifficulty'] = newDifficulty.firestoreKey;
        }
      }
    }

    await docRef.update(updates);

    // La prima traccia resa pubblica si segna QUI, non solo al salvataggio.
    //
    // Prima stava unicamente nel ramo `if (track.isPublic)` di saveTrack, che
    // copre il solo caso in cui la traccia nasce gia' pubblica. Ma il gesto
    // vero e' un altro: si salva, si guarda, e si pubblica dopo dalla scheda
    // di dettaglio — cioe' passando di qui. Il risultato era che il funnel
    // riportava zero tracce pubbliche mentre ce n'erano, comprese quelle del
    // founder: il gradino misurava un percorso che quasi nessuno prende.
    //
    // Solo quando si pubblica: togliere il pubblico non e' una milestone, e
    // ripubblicare non conta due volte perche' milestone() e' idempotente.
    if (isPublic == true) {
      unawaited(GrowthAnalyticsService.instance
          .milestone(GrowthMilestone.firstTrackPublic));
    }
  }

  /// Il proprietario dichiara che in certi tratti la registrazione era
  /// interrotta: "quel tratto dritto non e' strada che ho percorso".
  ///
  /// Aggiunge SOLTANTO metadati di assenza — nessun punto viene toccato,
  /// nessun dato inventato entra da nessuna parte. E' la Fase 1 di
  /// docs/tracce_ricostruite.md: statistiche, segmenti, classifiche e salute
  /// non cambiano perche' leggono `points`, che resta identico.
  ///
  /// Ritorna l'elenco completo dei buchi dopo la scrittura, per aggiornare
  /// lo stato locale senza rileggere il documento.
  Future<List<TrackGap>> declareGaps(
      String trackId, List<TrackGap> newGaps) async {
    final userId = _auth.currentUser?.uid;
    // Si LANCIA invece di tornare come se fosse andata: la prima stesura
    // ritornava newGaps e la UI mostrava "Interruzioni dichiarate" senza che
    // fosse stato scritto niente — un successo finto che spariva alla
    // riapertura. Il catch del chiamante mostra gia' il messaggio giusto.
    if (userId == null) throw StateError('dichiarazione senza utente');

    final docRef = _tracksCollection(userId).doc(trackId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('traccia $trackId inesistente');
    }

    final existing = _parseGaps(snap.data()?['gaps']);
    if (newGaps.isEmpty) return existing; // niente da scrivere

    // Difesa in profondita': il rilevamento gia' salta gli archi coperti, ma
    // questo metodo e' pubblico e non deve poter scrivere sovrapposizioni.
    final merged = List<TrackGap>.of(existing);
    for (final g in newGaps) {
      final overlaps = merged.any((e) =>
          e.startedAt.isBefore(g.endedAt) && e.endedAt.isAfter(g.startedAt));
      if (!overlaps) merged.add(g);
    }
    merged.sort((a, b) => a.startedAt.compareTo(b.startedAt));

    await docRef.update({'gaps': merged.map((g) => g.toMap()).toList()});
    return merged;
  }

  /// Ritira le dichiarazioni del proprietario. SOLO quelle: i buchi visti dal
  /// watchdog sono misure, e non esiste un percorso in cui il proprietario
  /// possa cancellarli — altrimenti la retta tornerebbe piena e la traccia
  /// tornerebbe a mentire.
  Future<List<TrackGap>> removeDeclaredGaps(String trackId) async {
    final userId = _auth.currentUser?.uid;
    // Come in declareGaps: un fallimento deve lanciare, non restituire una
    // lista che il chiamante scambierebbe per il nuovo stato.
    if (userId == null) throw StateError('rimozione senza utente');

    final docRef = _tracksCollection(userId).doc(trackId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('traccia $trackId inesistente');
    }

    final remaining = _parseGaps(snap.data()?['gaps'])
        .where((g) => !g.isOwnerDeclared)
        .toList();

    // Vuoto → si toglie il campo: l'assenza torna a voler dire "non lo
    // sappiamo", che era lo stato prima della dichiarazione.
    await docRef.update({
      'gaps': remaining.isEmpty
          ? FieldValue.delete()
          : remaining.map((g) => g.toMap()).toList(),
    });
    return remaining;
  }

  List<TrackGap> _parseGaps(Object? raw) {
    if (raw is! List) return const [];
    final out = <TrackGap>[];
    for (final g in raw) {
      try {
        if (g is Map) out.add(TrackGap.fromMap(Map<String, dynamic>.from(g)));
      } catch (e) {
        debugPrint('[TracksRepository] Errore parsing buco: $e');
      }
    }
    return out;
  }

  /// Parser tolerante per stringhe activityType da Firestore.
  static ActivityType _parseActivity(String? raw) {
    if (raw == null) return ActivityType.trekking;
    for (final t in ActivityType.values) {
      if (t.name == raw) return t;
    }
    return ActivityType.trekking;
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

    // Il battito vive nel doc geometria per le tracce nuove: scriviamolo lì
    // (merge per non toccare i punti), evitando di ri-gonfiare il doc
    // principale e di creare uno split-brain. Legacy → inline come prima.
    final snap = await _tracksCollection(userId).doc(trackId).get();
    final hasGeom = snap.data()?['hasGeometryDoc'] == true;
    if (hasGeom) {
      await _geometryDoc(userId, trackId).set({
        'heartRateData': serialized,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await _tracksCollection(userId).doc(trackId).update({
        'heartRateData': serialized,
      });
    }
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

    // Aggiungere un gruppo rende SEMPRE l'array non vuoto: isGroupShared va a
    // true senza bisogno di leggere lo stato precedente (a differenza della
    // rimozione, dove può restare non vuoto se condivisa a più gruppi).
    await _tracksCollection(userId).doc(trackId).update({
      'groupIds': FieldValue.arrayUnion([groupId]),
      'isGroupShared': true,
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

    // A differenza dello share, qui la traccia potrebbe restare condivisa ad
    // ALTRI gruppi (groupIds supporta condivisione multipla) — serve leggere
    // lo stato risultante per sapere se isGroupShared deve tornare false.
    // Transazione: atomica, corretta anche con rimozioni concorrenti.
    final docRef = _tracksCollection(userId).doc(trackId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final current = List<String>.from(snap.data()?['groupIds'] ?? []);
      current.remove(groupId);
      tx.update(docRef, {
        'groupIds': current,
        'isGroupShared': current.isNotEmpty,
      });
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
      final snap = await PerfTrace.track(
        'tracks.group.query[$groupId]',
        () => _firestore
            .collectionGroup('tracks')
            .where('groupIds', arrayContains: groupId)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .get(),
        describe: (s) => '${s.docs.length} doc, fromCache=${s.metadata.isFromCache}',
      );

      final tracks = PerfTrace.trackSync(
        'tracks.group.parse[$groupId]',
        () => snap.docs
            .map((d) => _trackFromFirestore(d.id, d.data()))
            .toList(),
      );
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
      // Cancella anche il doc geometria (Firestore non lo fa a cascata).
      // No-op se non esiste (tracce legacy senza geometria).
      try {
        await _geometryDoc(userId, trackId).delete();
      } catch (_) {/* best-effort */}
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

  /// Costruisce il documento METADATI della traccia — leggero, SENZA i
  /// punti GPS né l'heartRateData (quelli vivono nel doc geometria, vedi
  /// [_geometryDoc]/[_geometryDataFor]). [savedPoints] è già downsamplato e
  /// [stats] già ricalcolata dal chiamante ([saveTrack]).
  Map<String, dynamic> _trackToFirestore(
    Track track,
    String userId,
    List<TrackPoint> savedPoints,
    TrackStats stats,
  ) {
    return {
      'name': track.name,
      'description': track.description,
      // I punti NON sono più inline → metadati piccoli, niente OOM.
      // 'hasGeometryDoc' segnala al lettore di caricare la sub-collezione;
      // 'pointsCount' permette di mostrare "N punti" senza leggerla.
      'hasGeometryDoc': savedPoints.isNotEmpty,
      'pointsCount': savedPoints.length,
      'activityType': track.activityType.name,
      'recordedAt': track.recordedAt?.toIso8601String(),
      'createdAt': FieldValue.serverTimestamp(),
      // Gemello client-side di `createdAt`. Il serverTimestamp resta null in
      // locale finché la scrittura non arriva al backend (offline possono
      // essere ore): senza questo la traccia in coda veniva mostrata con la
      // data di parsing (`DateTime.now()`), cioè sbagliata.
      // NON è la chiave di ordinamento — le liste continuano a ordinare su
      // `createdAt`, che è l'unico campo presente anche sulle tracce
      // storiche (ordinare su un campo nuovo le escluderebbe tutte).
      'clientCreatedAt': Timestamp.fromDate(DateTime.now()),
      'userId': userId,
      'isPublic': track.isPublic,
      'hiddenFromFeed': track.hiddenFromFeed,
      'isPlanned': track.isPlanned,
      // Gruppi in cui la traccia è condivisa come "percorso consigliato"
      // (B2B groups feature, vedi GroupsRepository.shareTrackToGroup).
      'groupIds': track.groupIds,
      // Flag denormalizzato (#4 sicurezza: prep per stringere in futuro la
      // lettura cross-utente via collection-group, oggi aperta a chiunque
      // autenticato). Sempre false alla creazione: nessun flusso crea una
      // traccia già condivisa a un gruppo, si condivide dopo via
      // shareTrackToGroup/unshareTrackFromGroup che lo mantengono aggiornato.
      'isGroupShared': track.groupIds.isNotEmpty,
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
      // I buchi di registrazione visti dal watchdog. ATTENZIONE: questa mappa
      // e' costruita a mano, NON via track.toMap() — dimenticare un campo qui
      // significa perderlo in silenzio al salvataggio, ed e' esattamente
      // quello che era successo ai gaps: il watchdog li vedeva, il bloc li
      // metteva sulla Track, e questa funzione li buttava.
      if (track.gaps.isNotEmpty)
        'gaps': track.gaps.map((g) => g.toMap()).toList(),
      // 📸 Foto
      'photos': track.photos.map((p) => p.toMap()).toList(),
      if (track.healthCalories != null)
        'healthCalories': track.healthCalories,
      if (track.healthSteps != null)
        'healthSteps': track.healthSteps,
      // Komoot K1a Step 2 — difficoltà computata client-side al save.
      // Preserva valore esistente se passato dall'utente (override
      // manuale), altrimenti ricalcola da stats. null se insufficient.
      'computedDifficulty':
          track.computedDifficulty ??
              DifficultyCalculator.compute(
                stats: stats,
                activityType: track.activityType,
              )?.firestoreKey,
      // Override manuale (può essere null per default, salvato solo se
      // l'utente l'ha esplicitamente impostato dalla edit page).
      if (track.manualDifficulty != null)
        'manualDifficulty': track.manualDifficulty,
    };
  }

  /// Serializza i punti nel formato compatto (stringa JSON) usato dal doc
  /// geometria. Stesso schema dei punti inline legacy: {longitude, latitude,
  /// altitude, timestamp(ms), speed, accuracy}.
  String _encodePointsJson(List<TrackPoint> points) {
    return jsonEncode(points
        .map((p) => {
              'longitude': p.longitude,
              'latitude': p.latitude,
              'altitude': p.elevation ?? 0,
              'timestamp': p.timestamp.millisecondsSinceEpoch,
              'speed': p.speed ?? 0,
              'accuracy': p.accuracy ?? 0,
            })
        .toList());
  }

  /// Dati del documento geometria: punti GPS (come stringa JSON compatta) +
  /// heartRateData. È l'unico posto pesante; il doc metadati resta leggero.
  Map<String, dynamic> _geometryDataFor(
      List<TrackPoint> savedPoints, Map<DateTime, int>? heartRateData) {
    return {
      'pointsJson': _encodePointsJson(savedPoints),
      'pointsCount': savedPoints.length,
      if (heartRateData != null && heartRateData.isNotEmpty)
        'heartRateData': heartRateData.map(
          (key, value) =>
              MapEntry(key.millisecondsSinceEpoch.toString(), value),
        ),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Carica i punti (+ battito) dal documento geometria. Ritorna null se il
  /// doc non esiste. Una sola read.
  Future<({List<TrackPoint> points, Map<DateTime, int>? heartRate})?>
      _loadGeometry(String userId, String trackId) async {
    try {
      final snap = await PerfTrace.track(
        'tracks.geometry.docGet[$trackId]',
        () => _geometryDoc(userId, trackId).get(),
        describe: (d) => 'exists=${d.exists}, fromCache=${d.metadata.isFromCache}',
      );
      if (!snap.exists || snap.data() == null) return null;
      final data = snap.data()!;
      List<TrackPoint> points = const [];
      final pj = data['pointsJson'];
      if (pj is String && pj.isNotEmpty) {
        points = PerfTrace.trackSync(
          'tracks.geometry.parseJson[$trackId]',
          () => _parsePointsList(jsonDecode(pj)),
          describe: (p) => '${p.length} punti',
        );
      } else if (data['points'] is List) {
        // Tollera anche un eventuale array nativo (robustezza).
        points = _parsePointsList(data['points']);
      }
      return (points: points, heartRate: _parseHeartRate(data['heartRateData']));
    } catch (e) {
      debugPrint('[TracksRepository] Errore _loadGeometry($trackId): $e');
      return null;
    }
  }

  /// Se la traccia tiene i punti nel doc geometria ([hasGeometryDoc]) e non
  /// sono già inline (retrocompat: tracce vecchie restano con points inline),
  /// li carica e li attacca. È il "lazy load": una read in più SOLO sulle
  /// viste di dettaglio/export, mai sulle liste.
  Future<Track> _attachGeometryIfNeeded(
    String userId,
    String trackId,
    Map<String, dynamic> data,
    Track track,
  ) async {
    if (data['hasGeometryDoc'] == true && track.points.isEmpty) {
      final geo = await _loadGeometry(userId, trackId);
      if (geo != null && geo.points.isNotEmpty) {
        return track.copyWith(
          points: geo.points,
          heartRateData: geo.heartRate,
        );
      }
    }
    return track;
  }

  /// Parsa una lista di punti (da Firestore inline o da JSON-decoded del doc
  /// geometria) in [TrackPoint]. Gestisce sia oggetti {latitude/longitude/…}
  /// sia array [lon, lat, ele?, speed?]. Tollerante ai dati malformati.
  List<TrackPoint> _parsePointsList(dynamic raw) {
    final points = <TrackPoint>[];
    if (raw is! List) return points;
    for (final p in raw) {
      try {
        if (p is Map) {
          // Formato oggetto: {longitude, latitude, altitude} o {lng, lat, ele}
          final lat = _toDouble(p['latitude'] ?? p['lat']);
          final lng = _toDouble(p['longitude'] ?? p['lng'] ?? p['lon']);
          final ele = _toDouble(p['altitude'] ?? p['ele'] ?? p['elevation']);
          final spd = _toDouble(p['speed']);
          final acc = _toDouble(p['accuracy']);

          DateTime timestamp = DateTime.now();
          final ts = p['timestamp'];
          if (ts != null) {
            if (ts is int) {
              timestamp = DateTime.fromMillisecondsSinceEpoch(ts);
            } else if (ts is String) {
              timestamp = DateTime.tryParse(ts) ?? DateTime.now();
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
    return points;
  }

  /// Parsa l'heartRateData (chiavi = ms-epoch stringa → bpm), filtrando i
  /// valori fuori range [30,250]. Ritorna null se vuoto/assente.
  Map<DateTime, int>? _parseHeartRate(dynamic hrData) {
    if (hrData is! Map) return null;
    final out = <DateTime, int>{};
    for (final entry in hrData.entries) {
      try {
        final ts = DateTime.fromMillisecondsSinceEpoch(
            int.parse(entry.key.toString()));
        final bpm = (entry.value as num).toInt();
        if (bpm > 30 && bpm < 250) out[ts] = bpm;
      } catch (_) {
        // Skip dati malformati
      }
    }
    return out.isEmpty ? null : out;
  }

  /// Converte dati Firestore in Track
  /// Gestisce sia il formato nuovo che quello esistente dell'app JS
  ///
  /// [pendingSync] arriva da `snapshot.metadata.hasPendingWrites`: chi legge
  /// da uno snapshot lo passa così la UI può segnalare la traccia come non
  /// ancora sincronizzata (vedi [Track.pendingSync]).
  Track _trackFromFirestore(String id, Map<String, dynamic> data,
      {bool pendingSync = false}) {
    // Parse points dal formato legacy INLINE. Le tracce nuove non hanno
    // 'points' qui (vivono nel doc geometria): per loro questo resta vuoto e
    // i punti vengono attaccati da _attachGeometryIfNeeded sui full-load.
    final List<TrackPoint> points = _parsePointsList(data['points']);

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

    // Giri chiusi dal dispositivo (orologio Garmin). Assenti su tutto il
    // resto: la scheda torna a calcolarli ogni chilometro da sola.
    List<TrackLap> laps = [];
    final lapsData = data['laps'];
    if (lapsData != null && lapsData is List) {
      for (var l in lapsData) {
        try {
          if (l is Map) {
            laps.add(TrackLap.fromMap(Map<String, dynamic>.from(l)));
          }
        } catch (e) {
          debugPrint('[TracksRepository] Errore parsing giro: $e');
        }
      }
    }

    // I buchi di registrazione. Assenti sulle tracce salvate prima che il
    // campo esistesse: li' l'elenco vuoto vuol dire "non lo sappiamo", non
    // "non ce ne sono stati".
    List<TrackGap> gaps = [];
    final gapsData = data['gaps'];
    if (gapsData != null && gapsData is List) {
      for (var g in gapsData) {
        try {
          if (g is Map) {
            gaps.add(TrackGap.fromMap(Map<String, dynamic>.from(g)));
          }
        } catch (e) {
          debugPrint('[TracksRepository] Errore parsing buco: $e');
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

    // `createdAt` è un serverTimestamp: finché la scrittura è in coda vale
    // null in locale. Ripiega su `clientCreatedAt` (scritto insieme, ora del
    // dispositivo) e poi su `recordedAt`, invece di mostrare "adesso" — che
    // per una traccia registrata offline giorni prima è una data sbagliata.
    DateTime createdAt = DateTime.now();
    final rawCreatedAt = data['createdAt'] ?? data['clientCreatedAt'];
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt);
    } else if (recordedAt != null) {
      createdAt = recordedAt;
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

    // ❤️ Parse battito cardiaco (inline legacy; le tracce nuove l'hanno nel
    // doc geometria, attaccato da _attachGeometryIfNeeded).
    final Map<DateTime, int>? heartRateData =
        _parseHeartRate(data['heartRateData']);

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
      hiddenFromFeed: data['hiddenFromFeed'] == true,
      isPlanned: data['isPlanned'] == true,
      groupIds: (data['groupIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      stats: stats,
      photos: photos, // 📸 Foto
      laps: laps,
      gaps: gaps,
      heartRateData: heartRateData, // ❤️ Battito cardiaco
      healthCalories: healthCalories, // 🔥 Calorie reali
      healthSteps: healthSteps, // 👣 Passi
      importedFromStrava: data['importedFromStrava'] == true,
      stravaSourceActivityId: data['stravaSourceActivityId']?.toString(),
      // 5.5 — Tag personalizzati salvati lowercase
      tags: data['tags'] is List
          ? List<String>.from(data['tags'] as List)
          : const <String>[],
      computedDifficulty: data['computedDifficulty']?.toString(),
      manualDifficulty: data['manualDifficulty']?.toString(),
      elevationCorrectedFromDem: data['elevationCorrectedFromDem'] == true,
      pendingSync: pendingSync,
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

    // ⚠️ DATA LOSS GUARD: la traccia può arrivare da una lista (punti vuoti,
    // formato geometria). Idrata i punti PRIMA di toccare qualsiasi cosa e
    // abortisci se non recuperabili — l'originale viene cancellato in fondo.
    var src = track;
    if (src.points.isEmpty) {
      final fresh = await getTrackById(src.id!);
      if (fresh != null) src = fresh;
    }
    final points = src.points;
    if (points.isEmpty) {
      debugPrint('[TracksRepository] split abort: punti non recuperabili');
      return null;
    }
    if (splitIndex <= 1 || splitIndex >= points.length - 1) return null;

    final first = points.sublist(0, splitIndex);
    final second = points.sublist(splitIndex);

    // Stats ricalcolate dalle distanze cumulative dei punti
    final firstStats = _recomputeStats(first);
    final secondStats = _recomputeStats(second);

    // Ogni meta' porta con se' SOLO i buchi che cadono nel suo intervallo:
    // copyWith erediterebbe src.gaps per intero in entrambe, e la parte
    // "sbagliata" mostrerebbe l'avviso di un'interruzione che sta nell'altra
    // — con mappa e GPX che, giustamente, non troverebbero niente da
    // tratteggiare. Trovato dalla revisione avversariale della Fase 1.
    List<TrackGap> gapsWithin(List<TrackPoint> segment) => src.gaps
        .where((g) =>
            g.startedAt.isBefore(segment.last.timestamp) &&
            g.endedAt.isAfter(segment.first.timestamp))
        .toList();

    final firstTrack = src.copyWith(
      id: null, // nuovo doc
      name: '${src.name} (parte 1)',
      points: first,
      stats: firstStats,
      recordedAt: src.recordedAt,
      createdAt: DateTime.now(),
      gaps: gapsWithin(first),
    );
    final secondTrack = src.copyWith(
      id: null,
      name: '${src.name} (parte 2)',
      points: second,
      stats: secondStats,
      recordedAt: first.last.timestamp,
      createdAt: DateTime.now(),
      gaps: gapsWithin(second),
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

    // ⚠️ DATA LOSS GUARD: `b` arriva tipicamente da getMyTracksLightweight
    // (punti SEMPRE vuoti) e `a` può essere la traccia non idratata della
    // detail page. Idrata entrambe PRIMA di toccare qualsiasi cosa e
    // abortisci se non recuperabili — gli originali vengono cancellati dopo.
    var ha = a, hb = b;
    if (ha.points.isEmpty) {
      final f = await getTrackById(ha.id!);
      if (f != null) ha = f;
    }
    if (hb.points.isEmpty) {
      final f = await getTrackById(hb.id!);
      if (f != null) hb = f;
    }
    if (ha.points.isEmpty || hb.points.isEmpty) {
      debugPrint('[TracksRepository] merge abort: punti non recuperabili');
      return null;
    }

    // Ordina cronologicamente per evitare polilinee zigzaganti.
    final aDate = ha.recordedAt ?? ha.createdAt;
    final bDate = hb.recordedAt ?? hb.createdAt;
    final ordered = aDate.isBefore(bDate) ? [ha, hb] : [hb, ha];
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
      // I buchi di ENTRAMBE le tracce: copyWith da ordered[0] perderebbe
      // quelli della seconda, e il ponte del watchdog tornerebbe linea piena
      // dopo un'operazione di routine. I TrackGap usano timestamp assoluti,
      // quindi restano validi dopo la concatenazione senza rimappature.
      gaps: ([...ordered[0].gaps, ...ordered[1].gaps]
        ..sort((x, y) => x.startedAt.compareTo(y.startedAt))),
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
