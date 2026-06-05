import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
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
  })  : _businessRepo = businessRepo ?? BusinessRepository(),
        _communityRepo = communityRepo ?? CommunityTracksRepository(),
        _followRepo = followRepo ?? FollowRepository(),
        _trailsRepo = trailsRepo ?? PublicTrailsRepository(),
        _toursRepo = toursRepo ?? ToursRepository(),
        _challengesRepo = challengesRepo ?? WeeklyChallengesRepository(),
        _weatherService = weatherService ?? WeatherService();

  final BusinessRepository _businessRepo;
  final CommunityTracksRepository _communityRepo;
  final FollowRepository _followRepo;
  final PublicTrailsRepository _trailsRepo;
  final ToursRepository _toursRepo;
  final WeeklyChallengesRepository _challengesRepo;
  final WeatherService _weatherService;

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
    ]);
    return HomeFeedData(
      resume: results[0] as HomeResumeItem?,
      challenge: results[1] as WeeklyChallenge?,
      followingPosts: results[2] as List<CommunityTrack>,
      editorialTour: results[3] as Tour?,
      fetchedAt: DateTime.now(),
    );
  }

  /// **Fase 2 (geo)** — fetch che dipendono dalla posizione: Spazi Pro
  /// vicini, sentieri vicini, meteo. Chiamato dal Bloc DOPO aver
  /// risolto una posizione accurata via [resolveLocation].
  Future<HomeFeedGeo> loadGeo(LatLng loc) async {
    final results = await Future.wait<dynamic>([
      _safe<List<Business>>(
          () => _businessRepo.getNearby(
                lat: loc.latitude,
                lng: loc.longitude,
                radiusKm: 50,
                limit: 6,
              ),
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

  /// Risolve una posizione **accurata** (non last-known) per le sezioni
  /// geo. Usa accuratezza media (sufficiente per "entro 12-50 km").
  /// Eseguito in Fase 2, quindi la lentezza non blocca le sezioni
  /// non-geo già a schermo.
  Future<LatLng?> resolveLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      // NIENTE fallback su last-known: una posizione vecchia di km
      // centrerebbe "Spazi Pro vicini / Scopri" sul posto sbagliato
      // (bug: spazi mostrati spostati di km). Allineato a CommunityPage,
      // che su fix fallito semplicemente non mostra le sezioni geo.
      return null;
    }
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
