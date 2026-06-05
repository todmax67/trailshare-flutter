import 'package:latlong2/latlong.dart';

import '../repositories/community_tracks_repository.dart' show CommunityTrack;
import '../repositories/public_trails_repository.dart' show PublicTrail;
import 'business.dart';
import 'home_resume_item.dart';
import 'tour.dart';
import 'weather_data.dart';
import 'weekly_challenge.dart';

/// Snapshot immutabile dei dati della Home Feed.
///
/// Tutti i campi sono nullable/vuoti di default: una sezione
/// vuota/non caricata si auto-collassa nel rendering.
/// [isCompletelyEmpty] distingue il caso "nuovo utente senza nulla"
/// da "caricamento in corso".
///
/// Nota tipi (adattati al codice reale, non alla proposta originale):
/// - `nearbyTrails` è `List<PublicTrail>` (sentieri OSM), non Track.
/// - `followingPosts` è `List<CommunityTrack>` (no Preview factory).
class HomeFeedData {
  final LatLng? userLocation;
  final WeatherData? weather;
  final HomeResumeItem? resume;
  final WeeklyChallenge? challenge;
  final List<CommunityTrack> community;
  final List<CommunityTrack> popularTracks;
  final List<Business> rifugi;
  final List<CommunityTrack> followingPosts;
  final Tour? editorialTour;
  final List<Business> nearbyPro;
  final List<PublicTrail> nearbyTrails;
  final DateTime fetchedAt;

  const HomeFeedData({
    this.userLocation,
    this.weather,
    this.resume,
    this.challenge,
    this.community = const [],
    this.popularTracks = const [],
    this.rifugi = const [],
    this.followingPosts = const [],
    this.editorialTour,
    this.nearbyPro = const [],
    this.nearbyTrails = const [],
    required this.fetchedAt,
  });

  /// True se l'utente non ha proprio nulla da vedere: né recovery, né
  /// follow, né challenge, né tour/Pro/Trails vicini. Usato per
  /// mostrare l'onboarding (HomeEmptyState).
  bool get isCompletelyEmpty =>
      resume == null &&
      challenge == null &&
      community.isEmpty &&
      followingPosts.isEmpty &&
      editorialTour == null &&
      nearbyPro.isEmpty &&
      nearbyTrails.isEmpty;

  /// True se i dati sono più vecchi di [maxAge] (per auto-refresh
  /// quando si torna sulla tab Home dopo un po').
  bool isStale({Duration maxAge = const Duration(minutes: 5)}) =>
      DateTime.now().difference(fetchedAt) > maxAge;

  /// Ritorna una copia con i campi geo (Fase 2) popolati, mantenendo
  /// i campi non-geo (Fase 1) invariati.
  HomeFeedData withGeo({
    required LatLng? userLocation,
    required HomeFeedGeo geo,
  }) =>
      HomeFeedData(
        userLocation: userLocation,
        weather: geo.weather,
        resume: resume,
        challenge: challenge,
        community: community,
        popularTracks: popularTracks,
        rifugi: rifugi,
        followingPosts: followingPosts,
        editorialTour: editorialTour,
        nearbyPro: geo.nearbyPro,
        nearbyTrails: geo.nearbyTrails,
        fetchedAt: fetchedAt,
      );

  /// Copia con i [rifugi] popolati (caricamento differito, off critical path).
  HomeFeedData withRifugi(List<Business> r) => HomeFeedData(
        userLocation: userLocation,
        weather: weather,
        resume: resume,
        challenge: challenge,
        community: community,
        popularTracks: popularTracks,
        rifugi: r,
        followingPosts: followingPosts,
        editorialTour: editorialTour,
        nearbyPro: nearbyPro,
        nearbyTrails: nearbyTrails,
        fetchedAt: fetchedAt,
      );
}

/// Risultato della Fase 2 (geo) dell'aggregator: solo i campi che
/// dipendono dalla posizione utente.
class HomeFeedGeo {
  final WeatherData? weather;
  final List<Business> nearbyPro;
  final List<PublicTrail> nearbyTrails;

  const HomeFeedGeo({
    this.weather,
    this.nearbyPro = const [],
    this.nearbyTrails = const [],
  });
}
