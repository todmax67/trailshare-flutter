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

  Future<HomeFeedData> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // La posizione GPS può richiedere secondi (fix satellitare). NON la
    // aspettiamo prima di tutto: lanciamo subito i fetch che non
    // dipendono dalla location, e quelli geo-dipendenti aspettano
    // internamente questa Future condivisa. Così le sezioni non-geo
    // (sfida, seguiti, tour) compaiono senza attendere il GPS.
    final locationFuture = _safelyLoadLocation();

    final results = await Future.wait<dynamic>([
      _safe<HomeResumeItem?>(_loadResume, null),
      _safe<WeeklyChallenge?>(() => _challengesRepo.getCurrent(), null),
      _safe<List<CommunityTrack>>(
          () => uid == null ? Future.value(const []) : _loadFollowing(uid),
          const []),
      _safe<Tour?>(_loadEditorialTour, null),
      _safe<List<Business>>(() async {
        final loc = await locationFuture;
        if (loc == null) return const [];
        return _businessRepo.getNearby(
          lat: loc.latitude,
          lng: loc.longitude,
          radiusKm: 50,
          limit: 6,
        );
      }, const []),
      _safe<List<PublicTrail>>(() async {
        final loc = await locationFuture;
        if (loc == null) return const [];
        return _loadNearbyTrails(loc);
      }, const []),
      _safe<WeatherData?>(() async {
        final loc = await locationFuture;
        if (loc == null) return null;
        return _weatherService.getForecast(loc.latitude, loc.longitude);
      }, null),
    ]);

    return HomeFeedData(
      userLocation: await locationFuture,
      resume: results[0] as HomeResumeItem?,
      challenge: results[1] as WeeklyChallenge?,
      followingPosts: results[2] as List<CommunityTrack>,
      editorialTour: results[3] as Tour?,
      nearbyPro: results[4] as List<Business>,
      nearbyTrails: results[5] as List<PublicTrail>,
      weather: results[6] as WeatherData?,
      fetchedAt: DateTime.now(),
    );
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

  Future<LatLng?> _safelyLoadLocation() async {
    // Per la Home Feed la posizione "last known" (istantanea, dalla
    // cache OS) è più che sufficiente: serve solo per "sentieri/Pro
    // entro ~12-50 km", non per il tracking. Evita il fix GPS ad alta
    // accuratezza (fino a 10s) che rendeva lenta la Home.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return LatLng(last.latitude, last.longitude);
      }
    } catch (_) {
      // ignora, prova il fallback sotto
    }
    // Nessuna last-known (primo avvio dopo install/clear): fix normale.
    try {
      final tp = await _locationService.getCurrentPosition();
      if (tp == null) return null;
      return LatLng(tp.latitude, tp.longitude);
    } catch (_) {
      return null;
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
