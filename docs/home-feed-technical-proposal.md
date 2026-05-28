# Home Feed — Proposta Tecnica di Implementazione

> **Destinazione**: Claude Code (CLI) per implementazione coerente.
> **Versione**: 1.0 — 28 maggio 2026
> **Stato**: Da approvare prima di partire.
> **Reference design**: `docs/design-critique-2026-05.md` §6 + mockup conversazione del 28/05/2026.

---

## 0. Goal & Scope

Sostituire la Home attuale (che fa default su Community tab) con una nuova pagina **Home Feed** che aggrega in sezioni separate: Riprendi, Sfida settimanale, Dai tuoi seguiti, Tour del mese, Spazi Pro vicini, Scopri vicino a te. La bottom nav diventa `Home | Comunità | Registra | Tracce | Profilo` (rimuovendo `Scopri` come tab perché esposto come sezione + CTA "Esplora zona →").

**Vincoli chiave:**

- **Niente nuovi repository.** Tutti i building blocks esistono già (`ToursRepository`, `BusinessRepository`, `CommunityTracksRepository`, `WeeklyChallengesRepository`, `FollowRepository`, `PublicTrailsRepository`, `WeatherService`, `RecordingPersistenceService`). Si aggiunge solo un **aggregator** che orchestra le chiamate in parallelo.
- **Niente breaking changes.** `DiscoverPage` e `CommunityPage` restano intatte; cambiano solo punto di entrata e default index.
- **Feature flag.** L'attivazione passa da `AppConfig.useNewHomeFeed` per rollback in 1 min se serve.
- **No regressioni di accessibilità.** Tipografia via `Theme.textTheme`, colori via `AppColors` + `colorScheme` — niente hardcoded (vedi critica WCAG nel doc precedente).

---

## 1. Decisione architetturale

### 1.A Pattern: Aggregator, non Repository nuovo

Si potrebbe creare un `HomeFeedRepository` che ingloba tutte le fetches. **Lo evitiamo**: introdurrebbe una dipendenza ciclica con 6+ repository esistenti e un punto unico di failure. Usiamo invece un **aggregator stateless** in `core/services/`:

```
HomeFeedAggregator (service, no state)
  ↓ chiama in parallelo via Future.wait
  ├─ RecordingPersistenceService.getActiveBackup()
  ├─ ToursRepository.getMyTours() — filtro "in progress"
  ├─ WeeklyChallengesRepository.getCurrent()
  ├─ CommunityTracksRepository.getFollowingActivityFeed(uid, limit: 3)
  ├─ ToursRepository.getPublicTours(limit: 5) — filtra editorial
  ├─ BusinessRepository.getNearby(loc, radiusKm: 50, limit: 6)
  ├─ PublicTrailsRepository.getNearbyTrails(loc, radiusKm: 20, limit: 12)
  └─ WeatherService.getForecast(lat, lng)
```

L'aggregator restituisce un `HomeFeedData` immutabile. Il BLoC è solo lo stato attorno a quel modello.

### 1.B State management: ChangeNotifier (allineato a codebase)

Il codebase usa `ChangeNotifier` per `TrackingBloc`, `RecordingStatusService`, ecc. Manteniamo lo stesso pattern — niente Riverpod/Bloc package nuovi.

### 1.C Loading strategy: parallel + per-section shimmer

Tutte le fetches partono in parallelo via `Future.wait`. Ogni sezione mostra il proprio skeleton finché la sua parte è in `null`. Niente full-page spinner.

---

## 2. File Map

### NEW (10 file)

```
lib/presentation/pages/home_feed/
  home_feed_page.dart                       (~300 righe, page principale)

lib/presentation/blocs/
  home_feed_bloc.dart                       (~120 righe, ChangeNotifier)

lib/presentation/widgets/home_feed/
  home_hero_card.dart                       (~80 righe, meteo + greeting)
  home_resume_card.dart                     (~120 righe, riprendi tour/track)
  home_section_header.dart                  (~50 righe, riusabile)
  home_following_strip.dart                 (~140 righe, scroll H comunità)
  home_editorial_tour_card.dart             (~140 righe, tour del mese)
  home_pro_strip.dart                       (~130 righe, scroll H Spazi Pro)
  home_discover_preview.dart                (~150 righe, mini-mappa)
  home_empty_state.dart                     (~110 righe, onboarding nuovo utente)

lib/core/services/
  home_feed_aggregator.dart                 (~180 righe, parallel fetches)

lib/data/models/
  home_feed_data.dart                       (~90 righe, modello aggregato)
  home_resume_item.dart                     (~60 righe, union type)
```

### MODIFY (3 file)

```
lib/presentation/pages/home/home_page.dart   — sostituisce _pages[0], default index 0
lib/core/config/app_config.dart              — aggiunge bool useNewHomeFeed (default true)
lib/l10n/app_it.arb + app_en.arb             — aggiunge ~12 stringhe nuove (vedi §11)
```

### DON'T TOUCH

- `DiscoverPage` — resta com'è. Viene aperta da Home via `MaterialPageRoute`, non più come tab.
- `CommunityPage` — resta com'è. Viene aperta dal "Vedi tutto →" della strip Seguiti.
- `WeeklyChallengeCard` — riusato as-is dentro `HomeFeedPage` (sezione 3).
- Tutti i repository — usati read-only, nessuna modifica.

---

## 3. Data Layer

### 3.A Modello aggregato

**`lib/data/models/home_feed_data.dart`**

```dart
import 'package:latlong2/latlong.dart';
import 'business.dart';
import 'community_track_preview.dart';
import 'home_resume_item.dart';
import 'tour.dart';
import 'track.dart';
import 'weather_data.dart';
import 'weekly_challenge.dart';

/// Snapshot immutabile dei dati della Home Feed.
///
/// Tutti i campi sono nullable: una sezione vuota/non caricata si
/// auto-collassa nel rendering. `isCompletelyEmpty` distingue il caso
/// "nuovo utente senza nulla" da "caricamento in corso".
class HomeFeedData {
  final LatLng? userLocation;
  final WeatherData? weather;
  final HomeResumeItem? resume;
  final WeeklyChallenge? challenge;
  final List<CommunityTrackPreview> followingPosts;
  final Tour? editorialTour;
  final List<Business> nearbyPro;
  final List<Track> nearbyTrails;
  final DateTime fetchedAt;

  const HomeFeedData({
    this.userLocation,
    this.weather,
    this.resume,
    this.challenge,
    this.followingPosts = const [],
    this.editorialTour,
    this.nearbyPro = const [],
    this.nearbyTrails = const [],
    required this.fetchedAt,
  });

  /// True se l'utente non ha proprio nulla da vedere: né tour in
  /// progress, né follow, né challenge, né Pro/Trails vicini.
  /// Usato per mostrare l'onboarding incrementale (HomeEmptyState).
  bool get isCompletelyEmpty =>
      resume == null &&
      challenge == null &&
      followingPosts.isEmpty &&
      editorialTour == null &&
      nearbyPro.isEmpty &&
      nearbyTrails.isEmpty;

  HomeFeedData copyWith({
    LatLng? userLocation,
    WeatherData? weather,
    HomeResumeItem? resume,
    WeeklyChallenge? challenge,
    List<CommunityTrackPreview>? followingPosts,
    Tour? editorialTour,
    List<Business>? nearbyPro,
    List<Track>? nearbyTrails,
  }) => HomeFeedData(
    userLocation: userLocation ?? this.userLocation,
    weather: weather ?? this.weather,
    resume: resume ?? this.resume,
    challenge: challenge ?? this.challenge,
    followingPosts: followingPosts ?? this.followingPosts,
    editorialTour: editorialTour ?? this.editorialTour,
    nearbyPro: nearbyPro ?? this.nearbyPro,
    nearbyTrails: nearbyTrails ?? this.nearbyTrails,
    fetchedAt: DateTime.now(),
  );
}
```

**`lib/data/models/home_resume_item.dart`** — union type:

```dart
import 'recording_reference.dart';
import 'tour.dart';
import 'track.dart';

/// Una "cosa da riprendere": può essere un backup recording (crash recovery),
/// un tour multi-giorno in progress, o una traccia salvata in wishlist con
/// data programmata oggi/domani.
sealed class HomeResumeItem {
  const HomeResumeItem();
  String get title;
  String get subtitle;
  double get progressPercent; // 0..1
}

class ResumeRecordingBackup extends HomeResumeItem {
  final String backupId;
  final double partialDistanceKm;
  final Duration partialDuration;
  const ResumeRecordingBackup({
    required this.backupId,
    required this.partialDistanceKm,
    required this.partialDuration,
  });
  @override String get title => 'Traccia interrotta';
  @override String get subtitle =>
      '${partialDistanceKm.toStringAsFixed(1)} km già registrati';
  @override double get progressPercent => 0; // non determinabile
}

class ResumeTour extends HomeResumeItem {
  final Tour tour;
  final int completedStages;
  const ResumeTour({required this.tour, required this.completedStages});
  @override String get title => tour.name;
  @override String get subtitle =>
      'Tappa ${completedStages + 1} di ${tour.stageCount}';
  @override double get progressPercent =>
      tour.stageCount == 0 ? 0 : completedStages / tour.stageCount;
}
```

> **Nota implementativa per Claude Code**: i nomi dei campi (`tour.name`, `tour.stageCount`) vanno verificati contro `lib/data/models/tour.dart`. Se i nomi reali differiscono, adattare senza riscrivere la logica.

### 3.B Aggregator service

**`lib/core/services/home_feed_aggregator.dart`**

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/business.dart';
import '../../data/models/community_track_preview.dart';
import '../../data/models/home_feed_data.dart';
import '../../data/models/home_resume_item.dart';
import '../../data/models/tour.dart';
import '../../data/models/track.dart';
import '../../data/models/weather_data.dart';
import '../../data/models/weekly_challenge.dart';
import '../../data/repositories/business_repository.dart';
import '../../data/repositories/community_tracks_repository.dart';
import '../../data/repositories/public_trails_repository.dart';
import '../../data/repositories/tours_repository.dart';
import '../../data/repositories/weekly_challenges_repository.dart';
import 'location_service.dart';
import 'recording_persistence_service.dart';
import 'weather_service.dart';

/// Orchestratore stateless: chiama in parallelo i repository esistenti e
/// restituisce un HomeFeedData. Una failure singola NON propaga: la sezione
/// corrispondente arriva null e il widget la nasconde.
class HomeFeedAggregator {
  HomeFeedAggregator({
    BusinessRepository? businessRepo,
    CommunityTracksRepository? communityRepo,
    PublicTrailsRepository? trailsRepo,
    ToursRepository? toursRepo,
    WeeklyChallengesRepository? challengesRepo,
    WeatherService? weatherService,
    LocationService? locationService,
    RecordingPersistenceService? persistenceService,
  })  : _businessRepo = businessRepo ?? BusinessRepository(),
        _communityRepo = communityRepo ?? CommunityTracksRepository(),
        _trailsRepo = trailsRepo ?? PublicTrailsRepository(),
        _toursRepo = toursRepo ?? ToursRepository(),
        _challengesRepo = challengesRepo ?? WeeklyChallengesRepository(),
        _weatherService = weatherService ?? WeatherService(),
        _locationService = locationService ?? LocationService(),
        _persistence = persistenceService ?? RecordingPersistenceService.instance;

  final BusinessRepository _businessRepo;
  final CommunityTracksRepository _communityRepo;
  final PublicTrailsRepository _trailsRepo;
  final ToursRepository _toursRepo;
  final WeeklyChallengesRepository _challengesRepo;
  final WeatherService _weatherService;
  final LocationService _locationService;
  final RecordingPersistenceService _persistence;

  Future<HomeFeedData> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final location = await _safelyLoadLocation();

    final results = await Future.wait<dynamic>([
      _safe<HomeResumeItem?>(_loadResume),
      _safe<WeeklyChallenge?>(() => _challengesRepo.getCurrent()),
      _safe<List<CommunityTrackPreview>>(() =>
          uid == null ? Future.value([]) : _loadFollowing(uid)),
      _safe<Tour?>(_loadEditorialTour),
      _safe<List<Business>>(() => location == null
          ? Future.value([])
          : _businessRepo.getNearby(
              location: location, radiusKm: 50, limit: 6)),
      _safe<List<Track>>(() => location == null
          ? Future.value([])
          : _loadNearbyTrails(location)),
      _safe<WeatherData?>(() => location == null
          ? Future.value(null)
          : _weatherService.getForecast(
              location.latitude, location.longitude)),
    ]);

    return HomeFeedData(
      userLocation: location,
      resume: results[0] as HomeResumeItem?,
      challenge: results[1] as WeeklyChallenge?,
      followingPosts: results[2] as List<CommunityTrackPreview>,
      editorialTour: results[3] as Tour?,
      nearbyPro: results[4] as List<Business>,
      nearbyTrails: results[5] as List<Track>,
      weather: results[6] as WeatherData?,
      fetchedAt: DateTime.now(),
    );
  }

  // ── Helpers privati ───────────────────────────────────────────────

  Future<T> _safe<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      // Loggare ma non propagare. La sezione singola arriva default/empty.
      // ignore: avoid_print
      print('[HomeFeedAggregator] error: $e\n$st');
      return _defaultFor<T>();
    }
  }

  T _defaultFor<T>() {
    if (T == List<Business>) return <Business>[] as T;
    if (T == List<Track>) return <Track>[] as T;
    if (T == List<CommunityTrackPreview>) {
      return <CommunityTrackPreview>[] as T;
    }
    return null as T;
  }

  Future<LatLng?> _safelyLoadLocation() async {
    try {
      // Verificare nome reale in LocationService — adattare se necessario.
      final pos = await _locationService.getCurrentPosition();
      if (pos == null) return null;
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<HomeResumeItem?> _loadResume() async {
    // Priorità: crash backup > tour in progress > null.
    final backup = await _persistence.getActiveBackup();
    if (backup != null) {
      return ResumeRecordingBackup(
        backupId: backup.id,
        partialDistanceKm: backup.distanceKm,
        partialDuration: backup.duration,
      );
    }
    final tours = await _toursRepo.getMyTours();
    final inProgress = tours.where((t) =>
        t.completedStageIds.isNotEmpty &&
        t.completedStageIds.length < t.stageCount).toList();
    if (inProgress.isEmpty) return null;
    // Più recente prima.
    inProgress.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final tour = inProgress.first;
    return ResumeTour(
      tour: tour,
      completedStages: tour.completedStageIds.length,
    );
  }

  Future<List<CommunityTrackPreview>> _loadFollowing(String uid) async {
    // Il metodo getFollowingActivityFeed esiste già:
    // CommunityTracksRepository.getFollowingActivityFeed(uid, ...).
    // Verificare la firma reale — se ritorna CommunityTrack (not Preview),
    // mappare verso preview oppure usare getRecentTracksPreview con filtro
    // userId IN (followingIds).
    final feed = await _communityRepo.getFollowingActivityFeed(
      uid,
      limit: 3,
    );
    // Adapter to preview se necessario.
    return feed
        .map((t) => CommunityTrackPreview.fromCommunityTrack(t))
        .toList();
  }

  Future<Tour?> _loadEditorialTour() async {
    // Strategia M1: tour pubblici con flag isEditorial=true.
    // Se il flag non esiste ancora nel modello Tour, aggiungerlo opzionale
    // bool isEditorial (default false) + admin lo setta a mano via console.
    // Per ora: prendi il più recente pubblico se nessun editorial.
    final tours = await _toursRepo.getPublicTours(limit: 10);
    if (tours.isEmpty) return null;
    final editorials = tours.where((t) => t.isEditorial == true).toList();
    if (editorials.isNotEmpty) return editorials.first;
    return tours.first; // fallback: tour pubblico più recente
  }

  Future<List<Track>> _loadNearbyTrails(LatLng location) async {
    // PublicTrailsRepository ha metodi diversi (getInBoundingBox / cluster).
    // Verificare il metodo esistente e wrappare un bounding box ~20km
    // attorno a location. Ritornare top 12 per popolarità o distanza.
    return _trailsRepo.getNearby(
      center: location,
      radiusKm: 20,
      limit: 12,
    );
  }
}
```

> **⚠ Note di adattamento per Claude Code**:
> 1. I metodi `_businessRepo.getNearby({location, radiusKm, limit})`, `_communityRepo.getFollowingActivityFeed(uid, limit:)`, `_trailsRepo.getNearby(...)`, `_persistence.getActiveBackup()`, `_locationService.getCurrentPosition()` hanno firme reali da verificare. La logica resta identica; solo i parametri vanno adattati.
> 2. `Tour.isEditorial`, `Tour.completedStageIds`, `Tour.stageCount`, `Tour.updatedAt` sono campi proposti — se non esistono, aggiungerli al modello (nullable per retrocompatibilità Firestore).
> 3. `CommunityTrackPreview.fromCommunityTrack(...)` factory potrebbe non esistere — in tal caso usare direttamente `CommunityTrack` come tipo del campo `followingPosts` in `HomeFeedData`.

---

## 4. State Management

**`lib/presentation/blocs/home_feed_bloc.dart`**

```dart
import 'package:flutter/foundation.dart';
import '../../core/services/home_feed_aggregator.dart';
import '../../data/models/home_feed_data.dart';

enum HomeFeedStatus { idle, loading, ready, error }

class HomeFeedBloc extends ChangeNotifier {
  HomeFeedBloc({HomeFeedAggregator? aggregator})
      : _aggregator = aggregator ?? HomeFeedAggregator();

  final HomeFeedAggregator _aggregator;

  HomeFeedStatus _status = HomeFeedStatus.idle;
  HomeFeedData? _data;
  String? _error;

  HomeFeedStatus get status => _status;
  HomeFeedData? get data => _data;
  String? get error => _error;

  /// True se è il primo load di sempre (skeleton full-page).
  /// Una refresh successiva mostra i dati vecchi mentre carica nuovi.
  bool get isInitialLoading =>
      _status == HomeFeedStatus.loading && _data == null;

  Future<void> load() async {
    if (_status == HomeFeedStatus.loading) return;
    _status = HomeFeedStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _data = await _aggregator.load();
      _status = HomeFeedStatus.ready;
    } catch (e) {
      _error = e.toString();
      _status = HomeFeedStatus.error;
    }
    notifyListeners();
  }

  /// Pull-to-refresh: rinfresca tutto. Non resetta _data (anti-flash).
  Future<void> refresh() async {
    _status = HomeFeedStatus.loading;
    notifyListeners();
    try {
      _data = await _aggregator.load();
      _status = HomeFeedStatus.ready;
    } catch (e) {
      _error = e.toString();
      _status = HomeFeedStatus.error;
    }
    notifyListeners();
  }
}
```

---

## 5. UI Layer

### 5.A Page principale

**`lib/presentation/pages/home_feed/home_feed_page.dart`** (struttura, non implementazione completa):

```dart
class HomeFeedPage extends StatefulWidget {
  const HomeFeedPage({super.key});
  @override
  State<HomeFeedPage> createState() => _HomeFeedPageState();
}

class _HomeFeedPageState extends State<HomeFeedPage>
    with AutomaticKeepAliveClientMixin {
  final HomeFeedBloc _bloc = HomeFeedBloc();

  @override
  bool get wantKeepAlive => true; // non ricaricare quando l'utente cambia tab

  @override
  void initState() {
    super.initState();
    _bloc.addListener(_onBlocChanged);
    _bloc.load();
  }

  void _onBlocChanged() => setState(() {});

  @override
  void dispose() {
    _bloc.removeListener(_onBlocChanged);
    _bloc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // KeepAlive mixin
    final data = _bloc.data;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _bloc.refresh,
          child: _bloc.isInitialLoading
              ? const _HomeFeedSkeleton()
              : data == null
                  ? _ErrorView(error: _bloc.error, onRetry: _bloc.load)
                  : data.isCompletelyEmpty
                      ? HomeEmptyState(onAction: _openOnboarding)
                      : _buildSections(data),
        ),
      ),
    );
  }

  Widget _buildSections(HomeFeedData data) {
    final sections = _orderedSections(DateTime.now(), data);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        HomeHeroCard(weather: data.weather, userLocation: data.userLocation),
        if (data.resume != null)
          HomeResumeCard(
            item: data.resume!,
            onTap: () => _openResume(data.resume!),
          ),
        ...sections.expand((s) => _renderSection(s, data)),
      ],
    );
  }

  // ... section renderer + adaptive ordering: vedi §6 e §7
}
```

### 5.B Header di sezione (riusabile)

**`lib/presentation/widgets/home_feed/home_section_header.dart`**

```dart
class HomeSectionHeader extends StatelessWidget {
  final String title;
  final String? viewAllLabel;
  final VoidCallback? onViewAll;
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.viewAllLabel,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (onViewAll != null && viewAllLabel != null)
            TextButton(
              onPressed: onViewAll,
              child: Text(viewAllLabel!),
            ),
        ],
      ),
    );
  }
}
```

### 5.C Le 7 sezioni — contratto sintetico

| Sezione | Widget | Visibile se | "Vedi tutto" → | Empty fallback |
|---------|--------|-------------|----------------|----------------|
| Hero | `HomeHeroCard` | sempre | — | mostra solo greeting senza meteo |
| Riprendi | `HomeResumeCard` | `data.resume != null` | — | nascosto |
| Sfida | `WeeklyChallengeCard` (esistente) | `data.challenge != null` | `LeaderboardPage` | nascosto |
| Seguiti | `HomeFollowingStrip` | sempre se utente ha follow | `CommunityPage(initialTab: 'seguiti')` | CTA "Trova escursionisti" → `SearchUsersPage` |
| Tour | `HomeEditorialTourCard` | `data.editorialTour != null` | `CommunityPage(initialTab: 'tour')` | nascosto |
| Pro | `HomeProStrip` | `data.nearbyPro.isNotEmpty` | `BusinessDiscoveryPage` | nascosto |
| Scopri | `HomeDiscoverPreview` | `data.nearbyTrails.isNotEmpty` | `DiscoverPage` | nascosto |

---

## 6. Adaptive section ordering

Funzione pura in `home_feed_page.dart`:

```dart
enum HomeSection { challenge, following, tour, pro, discover }

List<HomeSection> _orderedSections(DateTime now, HomeFeedData data) {
  final isWeekend = now.weekday >= 6;
  final isSummer = now.month >= 6 && now.month <= 9;
  final isWinter = now.month == 12 || now.month <= 2;

  int score(HomeSection s) => switch (s) {
        HomeSection.challenge => data.challenge != null ? 10 : 0,
        HomeSection.following => data.followingPosts.isNotEmpty ? 8 : 0,
        HomeSection.tour =>
            data.editorialTour != null ? (isSummer ? 9 : 5) : 0,
        HomeSection.pro =>
            data.nearbyPro.isNotEmpty ? (isWeekend ? 7 : 4) : 0,
        HomeSection.discover =>
            data.nearbyTrails.isNotEmpty ? (isWinter ? 3 : 6) : 0,
      };

  final list = HomeSection.values.toList()
    ..sort((a, b) => score(b).compareTo(score(a)));
  return list.where((s) => score(s) > 0).toList();
}
```

> Ordine "ideale" tipico (giorno feriale primavera con dati pieni): Challenge → Following → Discover → Tour → Pro.
> Weekend estivo: Challenge → Tour → Following → Pro → Discover.

---

## 7. Modifica a `home_page.dart`

Diff minimale (~15 righe):

```dart
// PRIMA
int _currentIndex = 1; // Community come default
final List<Widget> _pages = [
  const DiscoverPage(),       // 0
  const CommunityPage(),      // 1 ← DEFAULT
  const RecordPage(),         // 2
  const TracksPage(),         // 3
  const ProfilePage(),        // 4
];

// DOPO
int _currentIndex = 0; // Home come default
final List<Widget> _pages = [
  const HomeFeedPage(),       // 0 ← DEFAULT
  const CommunityPage(),      // 1
  const RecordPage(),         // 2
  const TracksPage(),         // 3
  const ProfilePage(),        // 4
];
```

E nelle 5 voci di `_NavItem` del `_buildBottomNavBar`:

- voce 0: `Icons.home_outlined / Icons.home`, label `context.l10n.home`
- voce 1: invariata (Community)
- voce 2-3-4: invariate

**Feature flag** in `app.dart` (entry point):

```dart
home: AppConfig.useNewHomeFeed
    ? const HomePage()             // nuova nav con HomeFeedPage[0]
    : const HomeLegacy(),          // wrapper attuale con DiscoverPage[0], Community default
```

Per ridurre rischio, durante M1 si può mantenere `HomeLegacy` come copia 1:1 dell'attuale per rollback istantaneo.

---

## 8. Empty state globale (`HomeEmptyState`)

Mostrato quando `data.isCompletelyEmpty == true` (utente fresh install che non ha seguito nessuno, non è in zona con Pro/Trails, non ha tour pubblici disponibili):

```
┌────────────────────────────────────┐
│  [Illustrazione TopoEmptyState]   │
│                                    │
│  Inizia la tua avventura          │
│  TrailShare si popola con te.     │
│                                    │
│  [+]  Registra la tua prima       │
│       traccia                      │
│  [👥] Trova escursionisti da      │
│       seguire                      │
│  [🗺]  Esplora i sentieri della    │
│       tua zona                     │
└────────────────────────────────────┘
```

3 action tile verticali che mandano rispettivamente a `RecordPage`, `SearchUsersPage`, `DiscoverPage`. Riusa il pattern esistente di `TopoEmptyState`.

---

## 9. Loading & skeleton

**`_HomeFeedSkeleton`** — vista iniziale prima del primo load:

- Hero placeholder (~60dp altezza con shimmer)
- 2 card placeholder grandi (~100dp)
- 2 strip placeholder orizzontali con 2 card ognuna

Usa `shimmer` package se già in pubspec (verificare), altrimenti animazione fade-in semplice con `AnimatedOpacity`. Niente nuove dipendenze.

---

## 10. Stringhe localizzate da aggiungere

In `lib/l10n/app_it.arb` e `app_en.arb`:

| Key | IT | EN |
|-----|-----|-----|
| `home` | Home | Home |
| `homeGreetingMorning` | Buongiorno | Good morning |
| `homeGreetingAfternoon` | Buon pomeriggio | Good afternoon |
| `homeGreetingEvening` | Buonasera | Good evening |
| `homeReadyForTrail` | Pronto per il sentiero? | Ready for the trail? |
| `homeSectionResume` | Riprendi | Resume |
| `homeSectionChallenge` | Sfida settimanale | Weekly challenge |
| `homeSectionFollowing` | Dai tuoi seguiti | From people you follow |
| `homeSectionTour` | Tour del mese | Tour of the month |
| `homeSectionPro` | Spazi Pro vicini | Pro spaces nearby |
| `homeSectionDiscover` | Scopri vicino a te | Discover nearby |
| `homeViewAll` | Vedi tutto | View all |
| `homeExploreArea` | Esplora la zona | Explore the area |
| `homeAllPros` | Tutti gli Spazi Pro | All Pro spaces |
| `homeEditorialBadge` | Editoriale | Editorial |
| `homeEmptyTitle` | Inizia la tua avventura | Start your adventure |
| `homeEmptySubtitle` | TrailShare si popola con te. | TrailShare grows as you do. |
| `homeEmptyRecord` | Registra la tua prima traccia | Record your first track |
| `homeEmptyFollow` | Trova escursionisti da seguire | Find hikers to follow |
| `homeEmptyExplore` | Esplora i sentieri della tua zona | Explore trails in your area |

---

## 11. Implementation order (commits suggeriti)

Ordine pensato per **PR piccole e mergeabili una alla volta**, ognuna con valore standalone:

| # | Commit | File toccati | Test minimo |
|---|--------|--------------|-------------|
| 1 | `feat(home): add HomeFeedData + HomeResumeItem models` | 2 nuovi file in `data/models/` | Unit test serializzazione |
| 2 | `feat(home): add HomeFeedAggregator service` | `home_feed_aggregator.dart` + il `Tour.isEditorial` se necessario | Unit test con repository mockati |
| 3 | `feat(home): add HomeFeedBloc` | `home_feed_bloc.dart` | Unit test stati loading/error/ready |
| 4 | `feat(home): add HomeSectionHeader + skeleton widgets` | `home_section_header.dart`, skeleton interno alla page | Widget golden |
| 5 | `feat(home): add HomeHeroCard with weather` | `home_hero_card.dart` | Widget test con/senza WeatherData |
| 6 | `feat(home): add HomeResumeCard` | `home_resume_card.dart` | Widget test con backup + tour |
| 7 | `feat(home): add HomeFollowingStrip` | `home_following_strip.dart` | Widget test empty/popolato |
| 8 | `feat(home): add HomeEditorialTourCard` | `home_editorial_tour_card.dart` | Widget test |
| 9 | `feat(home): add HomeProStrip` | `home_pro_strip.dart` | Widget test |
| 10 | `feat(home): add HomeDiscoverPreview` | `home_discover_preview.dart` | Widget test con/senza mappa |
| 11 | `feat(home): add HomeEmptyState` | `home_empty_state.dart` | Widget test |
| 12 | `feat(home): assemble HomeFeedPage + adaptive ordering` | `home_feed_page.dart` + l10n keys | Widget test integrazione (mock bloc) |
| 13 | `feat(home): wire HomeFeedPage into HomePage with feature flag` | `home_page.dart`, `app_config.dart` | Smoke test navigazione |
| 14 | `chore(home): tune adaptive ordering thresholds` | solo `home_feed_page.dart` | Unit test della pure function `_orderedSections` |

Ogni commit lascia il codice in stato compilabile e testabile. Lo step 13 è l'unico user-visible: prima di quello, tutto è dormiente dietro feature flag.

---

## 12. Test plan

### Unit tests (priorità alta)

- `HomeFeedAggregator.load()`:
  - Caso utente loggato + location ok → tutti i repo chiamati una volta
  - Caso utente NON loggato → `followingPosts == []`, no crash
  - Caso location null → `nearbyPro == []`, `nearbyTrails == []`, `weather == null`, no crash
  - Caso 1 repo lancia exception → quella sezione default, altre OK
- `_orderedSections(now, data)`:
  - Estate weekend con dati pieni → ordine: Challenge, Tour, Following, Pro, Discover
  - Inverno feriale → Challenge, Following, Discover, Tour, Pro
  - Sezioni con score 0 escluse
- `HomeFeedBloc`:
  - `load()` → status passa da idle → loading → ready
  - `load()` quando già loading → no-op
  - `refresh()` → mantiene `_data` durante il caricamento (anti-flash)

### Widget tests (priorità media)

- `HomeFeedPage` con `HomeFeedData` mock pieno → tutte e 7 sezioni renderizzate
- `HomeFeedPage` con `isCompletelyEmpty` → mostra `HomeEmptyState`
- `HomeFeedPage` con `data.resume == null` → sezione Riprendi assente
- `RefreshIndicator` pull triggera `_bloc.refresh()`

### Manual QA (pre-rollout)

1. Fresh install, no login → empty state corretto
2. Login + 0 follow → strip Following mostra CTA "Trova escursionisti"
3. Login con tour multi-giorno in progress → Riprendi appare in cima
4. Crash durante registrazione → Riprendi appare e link al recovery
5. Pull-to-refresh → tutte le sezioni si aggiornano senza flash
6. Cambio lingua IT↔EN runtime → tutte le label cambiano
7. Dark mode ↔ light mode → nessun `Colors.white` hardcoded leaked
8. Disattiva feature flag → app torna a Community default in 1 sec

---

## 13. Open questions (da chiarire PRIMA di partire)

1. **Editorial Tour: chi cura?** Proposta in §3.B: aggiungere flag `isEditorial: bool` al modello `Tour` + interfaccia admin per il flag. Conferma o alternativa (es: tour curato salvato in `editorial/tours/{season}` come doc separato).
2. **Weather API key**: il `WeatherService` esistente — usa già una key? Quale provider (OpenWeather, MeteoApi)? Quota gratuita basta per il volume Home Feed (1 call per session-start)?
3. **"Riprendi" priority**: in §3.B abbiamo backup recording > tour in progress. Va bene? Alternativa: mostrare backup come banner separato sopra Hero (perché è un'azione recovery, non un "continua").
4. **Nearby Pro radius**: default 50 km. Per zona alpina può essere troppo. Suggerisco config in `AppConfig.homeFeed.proRadiusKm` con valore di default.
5. **Bottom nav: rimuovere "Scopri" dalla nav è un cambio user-visible importante.** Confermare. Alternativa: mantenere Scopri come tab e usare Home come 6° elemento (sconsigliato — 6 tab è troppo).
6. **Feature flag default**: `true` per dev/staging, `false` per prod fino a QA completo? O direttamente `true` dietro flag remoto Firebase Remote Config?
7. **AutomaticKeepAliveClientMixin**: salvataggio in memoria della HomeFeed quando l'utente cambia tab. Pro: tornare a Home è istantaneo. Contro: dati possono diventare stale. Compromesso: TTL di 5 minuti — se `data.fetchedAt > 5min` ricarica automaticamente.

---

## 14. Cosa NON fare (anti-pattern da evitare)

- **No `Color(0xFF...)` hardcoded** nei nuovi widget. Tutti i colori da `AppColors`/`colorScheme`.
- **No `fontSize:` hardcoded.** Tipografia via `Theme.of(context).textTheme.X`.
- **No nuove dipendenze** in `pubspec.yaml` se non strettamente necessarie (shimmer ok solo se non presente già un equivalente).
- **No modifiche a `DiscoverPage` o `CommunityPage`.** Se servono parametri (es. `initialTab`), aggiungerli come optional constructor parameter — niente refactor delle pagine esistenti in questa PR.
- **No `SingleChildScrollView` + `Column`** se la lista può crescere (Following, Pro): usa `ListView` con `shrinkWrap` o sliver. Per la page principale `ListView` standard va benissimo.
- **No `setState` ovunque.** Il `_onBlocChanged` è l'unico bridge. I figli ricevono `HomeFeedData` come parametri immutabili.
- **No fetch dentro `build()`.** Tutti i fetch passano dal Bloc + Aggregator.

---

## 15. Stima effort

| Fase | Effort |
|------|--------|
| Models + Aggregator + Bloc (commit 1-3) | ~3h |
| Widget di sezione (commit 4-11) | ~8h |
| Assembly + integration (commit 12-14) | ~3h |
| Test (unit + widget) | ~4h |
| QA manuale + tuning ordering | ~2h |
| **Totale** | **~20h** |

Distribuibile su 3-4 giorni di lavoro focalizzato. Mergeable a metà: dopo lo step 12 la nuova Home è completa ma dormiente dietro flag.

---

## 16. Riferimenti

- Mockup conversazione: `28 maggio 2026, "trailshare_home_proposal_mockup"`
- Critica design: `docs/design-critique-2026-05.md`
- ROADMAP (sezione "Home Feed"): `ROADMAP.md` — aggiornare con questo doc come reference dopo approvazione.

---

*Documento redatto per consegna a Claude Code. Aggiornare il § "Open questions" con le decisioni di prodotto prima di iniziare l'implementazione del commit #2.*
