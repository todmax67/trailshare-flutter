import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/business.dart';
import '../../data/models/home_feed_data.dart';
import '../../data/models/home_resume_item.dart';
import '../../data/models/tour.dart';
import '../../data/models/weather_data.dart';
import '../../data/models/weekly_challenge.dart';
import '../../data/repositories/business_repository.dart';
import '../../data/repositories/community_tracks_repository.dart';
import '../../data/repositories/follow_repository.dart';
import '../../data/repositories/public_trails_repository.dart';
import '../../data/repositories/tours_repository.dart';
import '../../data/repositories/weekly_challenges_repository.dart';
import 'location_service.dart';
import 'recording_persistence_service.dart';
import 'weather_service.dart';

/// Orchestratore stateless della Home Feed: chiama in parallelo i
/// repository esistenti e restituisce un [HomeFeedData]. Una failure
/// singola NON propaga — la sezione corrispondente arriva vuota/null
/// e il widget la nasconde.
///
/// Nessun repository nuovo: si appoggia interamente a quelli esistenti.
class HomeFeedAggregator {
  HomeFeedAggregator({
    BusinessRepository? businessRepo,
    CommunityTracksRepository? communityRepo,
    FollowRepository? followRepo,
    PublicTrailsRepository? trailsRepo,
    ToursRepository? toursRepo,
    WeeklyChallengesRepository? challengesRepo,
    WeatherService? weatherService,
    LocationService? locationService,
  })  : _businessRepo = businessRepo ?? BusinessRepository(),
        _communityRepo = communityRepo ?? CommunityTracksRepository(),
        _followRepo = followRepo ?? FollowRepository(),
        _trailsRepo = trailsRepo ?? PublicTrailsRepository(),
        _toursRepo = toursRepo ?? ToursRepository(),
        _challengesRepo = challengesRepo ?? WeeklyChallengesRepository(),
        _weatherService = weatherService ?? WeatherService(),
        _locationService = locationService ?? LocationService();

  final BusinessRepository _businessRepo;
  final CommunityTracksRepository _communityRepo;
  final FollowRepository _followRepo;
  final PublicTrailsRepository _trailsRepo;
  final ToursRepository _toursRepo;
  final WeeklyChallengesRepository _challengesRepo;
  final WeatherService _weatherService;
  final LocationService _locationService;

  /// Bounding box ~12 km attorno alla posizione utente.
  /// 1° lat ≈ 111 km → 12 km ≈ 0.11°. Più stretto di prima (era 0.18)
  /// per evitare di mostrare sentieri troppo lontani.
  static const double _trailBboxDeg = 0.11;

  /// Distanza per calcoli haversine (riusato per ordinamento sentieri).
  static const Distance _distance = Distance();

  /// **Fase 1 (veloce)** — fetch che NON dipendono dalla posizione:
  /// recovery registrazione, sfida settimanale, feed seguiti, tour del
  /// mese. Ritorna un HomeFeedData con i soli campi non-geo popolati.
  /// Il Bloc lo mostra subito mentre la Fase 2 (geo) è ancora in corso.
  Future<HomeFeedData> loadCore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final results = await Future.wait<dynamic>([
      _safe<HomeResumeItem?>(_loadResume, null),
      _safe<WeeklyChallenge?>(() => _challengesRepo.getCurrent(), null),
      _safe<List<CommunityTrack>>(
          () => uid == null ? Future.value(const []) : _loadFollowing(uid),
          const []),
      _safe<Tour?>(_loadEditorialTour, null),
      // Community generale: sempre ricca → risolve il cold-start del
      // nuovo utente (che non ha ancora seguiti). Limit contenuto: i doc
      // traccia hanno i points GPS embedded (pesanti) → meno doc = avvio
      // più rapido su Android.
      _safe<List<CommunityTrack>>(
          () => _communityRepo.getRecentTracks(limit: 5), const []),
      // I sentieri più amati (popolarità/rating) — criterio non geografico.
      _safe<List<CommunityTrack>>(
          () => _communityRepo.getPopularTracks(limit: 5), const []),
      // NB: i Rifugi NON sono qui — il parsing del bundle 20k POI è pesante e
      // bloccherebbe il primo paint. Caricati in differita via loadRifugi().
    ]);
    return HomeFeedData(
      resume: results[0] as HomeResumeItem?,
      challenge: results[1] as WeeklyChallenge?,
      followingPosts: results[2] as List<CommunityTrack>,
      editorialTour: results[3] as Tour?,
      community: results[4] as List<CommunityTrack>,
      popularTracks: results[5] as List<CommunityTrack>,
      fetchedAt: DateTime.now(),
    );
  }

  /// **Fase 2 (geo)** — fetch che dipendono dalla posizione: Spazi Pro
  /// vicini, sentieri vicini, meteo. Chiamato dal Bloc DOPO aver
  /// risolto una posizione accurata via [resolveLocation].
  Future<HomeFeedGeo> loadGeo(LatLng loc) async {
    final results = await Future.wait<dynamic>([
      // NB CRUCIALE: il `limit` di getNearby tronca il PREFILTRO geohash, che
      // è ordinato per STRINGA geohash (non per distanza). Con l'import OSM
      // (migliaia di rifugi come business) la fascia geohash è affollata: un
      // limit basso (6, 100) si esaurisce su celle lontane PRIMA di arrivare
      // alla cella dell'utente → si perdono i vicini (Due Erre a 0.7km mentre
      // restava roba a 16km). Come la pagina Spazi Pro (BusinessDiscoveryPage),
      // NON passiamo limit → default ampio (1000), poi teniamo i 6 più vicini.
      _safe<List<Business>>(
          () async {
            final pool = await _businessRepo.getNearby(
              lat: loc.latitude,
              lng: loc.longitude,
              radiusKm: 50,
            );
            return pool.take(6).toList();
          },
          const []),
      _safe<List<PublicTrail>>(() => _loadNearbyTrails(loc), const []),
      _safe<WeatherData?>(
          () => _weatherService.getForecast(loc.latitude, loc.longitude),
          null),
    ]);
    return HomeFeedGeo(
      nearbyPro: results[0] as List<Business>,
      nearbyTrails: results[1] as List<PublicTrail>,
      weather: results[2] as WeatherData?,
    );
  }

  /// Risolve una posizione **accurata** per le sezioni geo.
  ///
  /// Usa il `LocationService` condiviso (`LocationAccuracy.high` = GPS, non
  /// la rete): al cold start `accuracy.medium` poteva tornare una posizione
  /// network/cella anche di decine di km → Spazi Pro/Scopri sul posto
  /// sbagliato (es. Travagliato invece di Gazzaniga). `getCurrentPosition`
  /// gestisce anche permessi; ritorna null su fallimento (niente sezioni geo).
  Future<LatLng?> resolveLocation() async {
    final tp = await _locationService.getCurrentPosition();
    if (tp == null) return null;
    return LatLng(tp.latitude, tp.longitude);
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /// Esegue [fn], ritornando [fallback] su qualsiasi errore (loggato).
  Future<T> _safe<T>(Future<T> Function() fn, T fallback) async {
    try {
      return await fn();
    } catch (e, st) {
      debugPrint('[HomeFeedAggregator] section error: $e\n$st');
      return fallback;
    }
  }

  Future<HomeResumeItem?> _loadResume() async {
    final backup = await RecordingPersistenceService.instance.loadState();
    if (backup == null || backup.points.isEmpty) return null;

    // Distanza parziale: somma haversine fra punti consecutivi.
    double distM = 0;
    final pts = backup.points;
    for (var i = 1; i < pts.length; i++) {
      distM += pts[i - 1].distanceTo(pts[i]);
    }
    final elapsed =
        DateTime.now().difference(backup.startTime) - backup.pausedDuration;

    return ResumeRecordingBackup(
      partialDistanceKm: distM / 1000,
      partialDuration: elapsed.isNegative ? Duration.zero : elapsed,
    );
  }

  Future<List<CommunityTrack>> _loadFollowing(String uid) async {
    final followingIds = await _followRepo.getFollowing(uid);
    if (followingIds.isEmpty) return const [];
    return _communityRepo.getFollowingActivityFeed(followingIds, limit: 5);
  }

  /// Rifugi "da visitare" dagli **Spazi Pro** (Business `type: rifugio`), NON
  /// dai POI OSM: così sono **editabili dal gestore/utente** (foto, descrizione,
  /// contatti) e mostrano le immagini caricate. La collection contiene già i
  /// ~2200 rifugi OSM importati. Il filtro UI ordina per quota o distanza.
  ///
  /// Caricato in **DIFFERITA** (non in loadCore) per non pesare sul primo paint.
  /// NB: i doc Business sono piccoli (niente points GPS) → fetch leggero, e con
  /// la persistence Firestore i load successivi vengono dalla cache.
  Future<List<Business>> loadRifugi() async {
    try {
      return await _businessRepo.getAllNationwide(
        type: BusinessType.rifugio,
        limit: 2000,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<Tour?> _loadEditorialTour() async {
    // Il modello Tour non ha (ancora) un flag isEditorial: usiamo il
    // tour pubblico più recente come "Tour del mese". Quando si
    // aggiungerà la curatela editoriale, filtrare qui.
    final tours = await _toursRepo.getPublicTours(limit: 10);
    if (tours.isEmpty) return null;
    return tours.first;
  }

  Future<List<PublicTrail>> _loadNearbyTrails(LatLng loc) async {
    // Carichiamo più sentieri del necessario (bbox può contenerne tanti
    // sparsi) e poi ordiniamo per vicinanza reale al punto di partenza,
    // tenendo i 12 più vicini. Senza questo, Firestore ritorna in
    // ordine arbitrario e l'utente vede sentieri lontani prima.
    final trails = await _trailsRepo.getTrailsInBounds(
      minLat: loc.latitude - _trailBboxDeg,
      maxLat: loc.latitude + _trailBboxDeg,
      minLng: loc.longitude - _trailBboxDeg,
      maxLng: loc.longitude + _trailBboxDeg,
      limit: 60,
    );
    trails.sort((a, b) {
      final da = _distance.as(LengthUnit.Meter, loc,
          LatLng(a.startLat, a.startLng));
      final db = _distance.as(LengthUnit.Meter, loc,
          LatLng(b.startLat, b.startLng));
      return da.compareTo(db);
    });
    return trails.take(12).toList();
  }
}
