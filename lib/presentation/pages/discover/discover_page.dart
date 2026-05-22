import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/utils/text_search.dart';
// ⭐ Repository con cache e clustering
import '../../../data/repositories/public_trails_repository.dart';
import '../../../core/services/trails_cache_service.dart';
import 'trail_detail_page.dart';
import '../../../core/services/offline_tile_provider.dart';
import '../../../core/services/location_service.dart';
import '../../../core/constants/api_keys.dart';
import '../../../core/constants/italian_regions.dart';
import '../../../core/constants/map_styles.dart';
import '../../widgets/map_layer_button.dart';
import 'models/discover_filters.dart';
import 'widgets/discover_filter_sheet.dart';
import '../../../data/repositories/heatmap_repository.dart';
import '../../../data/repositories/trail_photos_repository.dart';
import '../../../data/models/track.dart';
import 'dart:ui' as ui;

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final MapController _mapController = MapController();
  
  // Posizione utente (solo per centrare mappa inizialmente e mostrare marker)
  LatLng? _userPosition;
  bool _isLoadingLocation = true;
  
  // ⭐ Repository con cache e clustering
  final PublicTrailsRepository _trailsRepository = PublicTrailsRepository();
  List<PublicTrail> _trails = [];
  List<TrailCluster> _clusters = []; // ⭐ NUOVO: Cluster per zoom basso
  bool _isLoadingTrails = false;
  PublicTrail? _selectedTrail;
  double _currentZoom = 11.0; // ⭐ NUOVO: Traccia zoom corrente
  LatLngBounds? _pendingBounds; // Bounds richiesti durante caricamento
  double? _pendingZoom;

  // UI
  int _currentMapStyle = 0;
  bool _showMap = true;
  DiscoverFilters _filters = const DiscoverFilters.empty();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ⭐ VIEWPORT-BASED LOADING per sentieri
  Timer? _viewportDebounce;
  LatLngBounds? _lastLoadedBounds;

  // Epic 3.4 — Heatmap trail popolari
  final HeatmapRepository _heatmapRepo = HeatmapRepository();
  List<HeatmapCell> _heatmapCells = const [];
  bool _heatmapVisible = false;
  bool _heatmapLoading = false;

  @override
  void initState() {
    super.initState();
    
    // ⭐ Inizializza cache
    trailsCacheService.init();
    
    // Prima ottieni la posizione, poi carica i sentieri
    _initializeLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _viewportDebounce?.cancel();
    super.dispose();
  }

  /// Inizializza la geolocalizzazione (solo per centrare la mappa)
  Future<void> _initializeLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Verifica se il servizio GPS è attivo
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoadingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.gpsServiceDisabled),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Verifica permessi con Prominent Disclosure
      if (!mounted) return;
      final hasPermission = await LocationService().checkAndRequestPermission(context: context);
      if (!hasPermission) {
        setState(() => _isLoadingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.locationPermissionDenied),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Ottieni posizione
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      setState(() {
        _userPosition = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
      });

      debugPrint('[DiscoverPage] Posizione utente: ${_userPosition!.latitude}, ${_userPosition!.longitude}');

      // Centra mappa sulla posizione utente
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(_userPosition!, 11);
          // Carica sentieri per il viewport iniziale
          _loadTrailsForViewport();
        });
      }
      
    } catch (e) {
      debugPrint('[DiscoverPage] Errore geolocalizzazione: $e');
      setState(() => _isLoadingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossibile ottenere la posizione (timeout GPS). Riprova all\'aperto.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      // Carica comunque i sentieri per il viewport di default
      _loadTrailsForViewport();
    }
  }

  /// Refresh manuale - ricarica sentieri per viewport corrente
  Future<void> _refreshTrails() async {
    _lastLoadedBounds = null;
    _trails.clear();
    _clusters = []; // const [] altrove → riassegna a lista mutabile
    await _trailsRepository.invalidateCache();
    await _loadTrailsForViewport();
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query.toLowerCase());
  }

  List<PublicTrail> get _filteredTrails {
    var list = _trails.where((trail) {
      // 4.4 — Ricerca testuale full-text accent-insensitive su:
      // nome, ref (numerazione CAI/SAT), network, operator, regione,
      // difficoltà CAI (es. "ee"), tipo attività (es. "mtb").
      if (_searchQuery.isNotEmpty) {
        final hit = TextSearch.matchesAny(_searchQuery, [
          trail.name,
          trail.ref,
          trail.network,
          trail.operator,
          trail.region,
          trail.difficulty,
          trail.activityType,
          trail.parsedActivityType.displayName,
        ]);
        if (!hit) return false;
      }

      // Difficoltà
      if (_filters.difficulties.isNotEmpty) {
        final diff = trail.difficulty?.toLowerCase();
        if (diff == null || !_filters.difficulties.contains(diff)) return false;
      }

      // Lunghezza
      if (_filters.lengthKm != null) {
        final km = (trail.length ?? 0) / 1000;
        if (km < _filters.lengthKm!.start || km > _filters.lengthKm!.end) return false;
      }

      // Dislivello
      if (_filters.elevation != null) {
        final ele = trail.elevationGain ?? 0;
        if (ele < _filters.elevation!.start || ele > _filters.elevation!.end) return false;
      }

      // Categoria attività
      if (_filters.categories.isNotEmpty &&
          !_matchesCategory(trail.activityType, _filters.categories)) {
        return false;
      }

      // Solo circolari
      if (_filters.onlyCircular && !trail.isCircular) return false;

      // Epic 4.5 — filtro per regione amministrativa.
      // Strategia multipla per robustezza (alcuni trail OSM hanno
      // region taggata, altri no; i points non sono sempre caricati
      // nella versione lightweight):
      //  1) Se il trail ha `region` taggato, match case-insensitive su
      //     nameIt o code della regione selezionata
      //  2) Fallback su bbox di startLat/startLng (sempre presenti).
      // Esce false solo se ENTRAMBI i check falliscono.
      if (_filters.regionCode != null && _filters.regionCode!.isNotEmpty) {
        final region = ItalianRegions.byCode(_filters.regionCode);
        if (region == null) return false;
        bool match = false;
        final trailRegion = trail.region?.trim().toLowerCase();
        if (trailRegion != null && trailRegion.isNotEmpty) {
          final code = region.code.toLowerCase();
          final nameIt = region.nameIt.toLowerCase();
          // Normalizziamo: "trentino-alto adige" ↔ "trentino_alto_adige"
          final normalized = trailRegion
              .replaceAll('-', '_')
              .replaceAll(' ', '_');
          if (normalized == code || trailRegion == nameIt) {
            match = true;
          }
        }
        if (!match) {
          // Fallback bbox su startLat/startLng denormalizzato (sempre
          // disponibile, anche se trail.points è vuoto nella lista
          // lightweight).
          match = region.contains(trail.startLat, trail.startLng);
        }
        if (!match) return false;
      }

      return true;
    }).toList();

    // Ordinamento
    switch (_filters.sortBy) {
      case TrailSortBy.defaultOrder:
        break;
      case TrailSortBy.distance:
        list.sort((a, b) => (a.distanceFromUser ?? double.infinity)
            .compareTo(b.distanceFromUser ?? double.infinity));
        break;
      case TrailSortBy.lengthAsc:
        list.sort((a, b) => (a.length ?? 0).compareTo(b.length ?? 0));
        break;
      case TrailSortBy.lengthDesc:
        list.sort((a, b) => (b.length ?? 0).compareTo(a.length ?? 0));
        break;
      case TrailSortBy.elevationAsc:
        list.sort((a, b) => (a.elevationGain ?? 0).compareTo(b.elevationGain ?? 0));
        break;
      case TrailSortBy.elevationDesc:
        list.sort((a, b) => (b.elevationGain ?? 0).compareTo(a.elevationGain ?? 0));
        break;
      case TrailSortBy.difficultyAsc:
        list.sort((a, b) => _difficultyRank(a.difficulty).compareTo(_difficultyRank(b.difficulty)));
        break;
    }

    return list;
  }

  /// Mappa l'activityType OSM alle categorie raggruppate
  bool _matchesCategory(String? type, Set<ActivityCategory> categories) {
    if (type == null) {
      return categories.contains(ActivityCategory.foot);
    }
    final t = type.toLowerCase();
    if (t.contains('cycl') || t.contains('bike') || t.contains('mtb')) {
      return categories.contains(ActivityCategory.bike);
    }
    if (t.contains('ski') || t.contains('snow')) {
      return categories.contains(ActivityCategory.snow);
    }
    // foot: trekking, walking, running, trail, hiking e default
    return categories.contains(ActivityCategory.foot);
  }

  /// Rank difficoltà per ordinamento (più alto = più difficile)
  int _difficultyRank(String? difficulty) {
    switch (difficulty?.toLowerCase()) {
      case 't':
        return 1;
      case 'e':
        return 2;
      case 'ee':
        return 3;
      case 'eea':
        return 4;
      default:
        return 5;
    }
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DiscoverFilterSheet(
        initial: _filters,
        onApply: (filters) => setState(() => _filters = filters),
      ),
    );
  }

  void _selectTrail(PublicTrail trail) {
    setState(() => _selectedTrail = trail);
    
    if (trail.points.isNotEmpty) {
      final center = _calculateCenter(trail.points);
      _mapController.move(center, 13);
    }
  }

  LatLng _calculateCenter(List points) {
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    
    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  /// Epic 3.4 — toggle heatmap overlay. Al primo "on" fetcha le celle;
  /// successivi toggle riusano la cache locale (le celle cambiano solo
  /// alla domenica notte via Cloud Function).
  Future<void> _toggleHeatmap() async {
    if (_heatmapVisible) {
      setState(() => _heatmapVisible = false);
      return;
    }
    if (_heatmapCells.isEmpty && !_heatmapLoading) {
      setState(() => _heatmapLoading = true);
      final cells = await _heatmapRepo.getAll();
      if (!mounted) return;
      setState(() {
        _heatmapCells = cells;
        _heatmapLoading = false;
        _heatmapVisible = true;
      });
    } else {
      setState(() => _heatmapVisible = true);
    }
  }

  /// Restituisce un colore caldo (giallo → rosso) in base al count
  /// relativo della cella vs il massimo della collezione corrente.
  Color _heatmapColor(int count, int maxCount) {
    if (maxCount <= 0) return Colors.orange;
    final t = (count / maxCount).clamp(0.0, 1.0);
    return Color.lerp(
          const Color(0xFFFFEB3B), // giallo
          const Color(0xFFD32F2F), // rosso
          t,
        ) ??
        Colors.orange;
  }

  void _centerOnUser() {
    if (_userPosition != null) {
      _mapController.move(_userPosition!, 13);
      // Ricarica sentieri per il nuovo viewport
      _loadTrailsForViewport();
    } else {
      _initializeLocation();
    }
  }

 /// Colore per tipo attività
  Color _activityColor(String? type) {
    if (type == null) return AppColors.primary;
    final t = type.toLowerCase();
    if (t.contains('cycl') || t.contains('bike') || t.contains('mtb')) {
      return const Color(0xFF1565C0); // Blu
    }
    if (t.contains('run') || t.contains('trail')) {
      return const Color(0xFF2E7D32); // Verde
    }
    if (t.contains('ski') || t.contains('snow')) {
      return const Color(0xFF5E35B1); // Viola
    }
    return AppColors.primary; // Arancione hiking/walking/default
  }

  /// Icona per tipo attività
  IconData _activityIcon(String? type) {
    if (type == null) return Icons.hiking;
    final t = type.toLowerCase();
    if (t.contains('cycl') || t.contains('bike') || t.contains('mtb')) {
      return Icons.directions_bike;
    }
    if (t.contains('run') || t.contains('trail')) {
      return Icons.directions_run;
    }
    if (t.contains('ski') || t.contains('snow')) {
      return Icons.downhill_skiing;
    }
    return Icons.hiking;
  }

  /// Formatta distanza breve per badge
  String _shortDistance(double? meters) {
    if (meters == null) return '';
    final km = meters / 1000;
    if (km >= 10) return '${km.round()}km';
    return '${km.toStringAsFixed(1)}km';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ⭐ VIEWPORT-BASED LOADING CON CACHE E CLUSTERING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Handler per eventi mappa (zoom, pan) - carica sentieri nel viewport
  void _onMapEvent(MapEvent event) {
    // Log temporaneo per debug
    if (event is! MapEventMove) {
      debugPrint('[DiscoverPage] 🗺️ MapEvent: ${event.runtimeType}');
    }
    
    if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd || event is MapEventRotateEnd) {
      // Debounce per evitare troppe chiamate
      _viewportDebounce?.cancel();
      _viewportDebounce = Timer(const Duration(milliseconds: 300), () {
        // ⭐ Leggi bounds dal controller AL MOMENTO del caricamento
        // così prende la posizione finale della mappa, non quella dell'evento
        final camera = _mapController.camera;
        final bounds = camera.visibleBounds;
        final zoom = camera.zoom;
        _loadTrailsForBounds(bounds, zoom);
      });
    }
  }

  /// ⭐ NUOVO: Carica sentieri con supporto clustering e cache

  /// ⭐ NUOVO: Carica sentieri con supporto clustering e cache
  Future<void> _loadTrailsForBounds(LatLngBounds bounds, double zoom) async {
    // Se già in caricamento, salva la richiesta per dopo
    if (_isLoadingTrails) {
      _pendingBounds = bounds;
      _pendingZoom = zoom;
      debugPrint('[DiscoverPage] ⏳ Pending (già in caricamento)');
      return;
    }
    
    // Evita di ricaricare se bounds E zoom sono molto simili
    if (_lastLoadedBounds != null && 
        _areBoundsSimilar(bounds, _lastLoadedBounds!) &&
        (_currentZoom - zoom).abs() < 0.5) {
      debugPrint('[DiscoverPage] ⏭️ Skip (bounds simili, zoom diff: ${(_currentZoom - zoom).abs().toStringAsFixed(2)})');
      return;
    }
    
    debugPrint('[DiscoverPage] 🚀 Caricamento per zoom: ${zoom.toStringAsFixed(1)}, bounds: ${bounds.south.toStringAsFixed(3)},${bounds.west.toStringAsFixed(3)} → ${bounds.north.toStringAsFixed(3)},${bounds.east.toStringAsFixed(3)}');
    
    if (mounted) {
      setState(() {
        _isLoadingTrails = true;
        _currentZoom = zoom;
      });
    }
    
    try {
      // ⭐ NUOVO: Usa repository ottimizzato con cache e clustering
      final result = await _trailsRepository.getTrailsForViewport(
        minLat: bounds.south,
        maxLat: bounds.north,
        minLng: bounds.west,
        maxLng: bounds.east,
        zoom: zoom,
        // Dopo split geometry i doc sono ~2KB → posso alzare il cap.
        // 800 trail × 2KB ≈ 1.6MB, gestibile.
        limit: 800,
      );
      
      if (mounted) {
        setState(() {
          // Cluster disabilitati (rompevano la ricerca): ignoriamo
          // result.clusters anche se la repo lo ritornasse.
          _clusters = const [];
          // Accumula con deduplicazione
          final existingIds = _trails.map((t) => t.id).toSet();
          final newTrails = result.trails
              .where((t) => !existingIds.contains(t.id))
              .toList();
          if (newTrails.isNotEmpty) {
            _trails = [..._trails, ...newTrails];
          }
          _lastLoadedBounds = bounds;
          _isLoadingTrails = false;
        });
      }

      final source = result.fromCache ? '⚡ cache' : '🌐 server';
      debugPrint(
          '[DiscoverPage] $source: ${result.trails.length} trails (zoom: ${zoom.toStringAsFixed(1)})');
      
    } catch (e) {
      debugPrint('[DiscoverPage] Errore caricamento: $e');
      if (mounted) {
        setState(() => _isLoadingTrails = false);
      }
    }

    // Se ci sono bounds pendenti richiesti durante il caricamento, eseguili ora
    if (_pendingBounds != null && mounted) {
      final nextBounds = _pendingBounds!;
      final nextZoom = _pendingZoom ?? _currentZoom;
      _pendingBounds = null;
      _pendingZoom = null;
      _loadTrailsForBounds(nextBounds, nextZoom);
    }
  }

  /// Carica sentieri basati sul viewport corrente della mappa
  Future<void> _loadTrailsForViewport() async {
    if (_isLoadingTrails) return;
    
    try {
      // Aspetta un frame per assicurarsi che la camera sia aggiornata
      await Future.delayed(const Duration(milliseconds: 50));
      
      if (!mounted) return;
      
      final bounds = _mapController.camera.visibleBounds;
      final zoom = _mapController.camera.zoom;
      await _loadTrailsForBounds(bounds, zoom);
    } catch (e) {
      debugPrint('[DiscoverPage] Errore _loadTrailsForViewport: $e');
    }
  }

  /// Verifica se due bounding box sono simili (per evitare ricaricamenti inutili)
  bool _areBoundsSimilar(LatLngBounds a, LatLngBounds b) {
    // Soglia proporzionale alla dimensione dell'area visibile
    // A zoom basso tollera più movimento, a zoom alto è più sensibile
    final latSpan = (a.north - a.south).abs();
    final lngSpan = (a.east - a.west).abs();
    final threshold = latSpan * 0.15; // 15% dell'area visibile
    final lngThreshold = lngSpan * 0.15;
    
    return (a.north - b.north).abs() < threshold &&
           (a.south - b.south).abs() < threshold &&
           (a.east - b.east).abs() < lngThreshold &&
           (a.west - b.west).abs() < lngThreshold;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _clusters.isNotEmpty
              ? context.l10n.discoverWithCount(_clusters.fold(0, (sum, c) => sum + c.count))
              : context.l10n.discoverWithCount(_filteredTrails.length),
        ),
        actions: [
          // Filtri avanzati
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.tune),
                onPressed: _openFilters,
                tooltip: 'Filtri',
              ),
              if (_filters.activeCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '${_filters.activeCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          // Toggle mappa/lista
          IconButton(
            icon: Icon(_showMap ? Icons.list : Icons.map),
            onPressed: () => setState(() {
              _showMap = !_showMap;
              _selectedTrail = null;
            }),
            tooltip: _showMap ? context.l10n.showList : context.l10n.showMap,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTrails,
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra di ricerca + info posizione
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Barra di ricerca
                TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: context.l10n.searchTrails,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
                const SizedBox(height: 8),
                _buildLocationInfo(),
              ],
            ),
          ),

          // Contenuto sentieri (diretto, senza TabBarView)
          Expanded(
            child: _buildTrailsTab(),
          ),
        ],
      ),
    );
  }

  /// ⭐ NUOVO: Widget info con supporto clustering
  Widget _buildLocationInfo() {
    // Calcola conteggio totale (cluster o trails)
    final totalCount = _clusters.isNotEmpty 
        ? _clusters.fold(0, (sum, c) => sum + c.count)
        : _trails.length;
    
    String message;
    if (_isLoadingTrails && _trails.isEmpty && _clusters.isEmpty) {
      message = context.l10n.loadingTrails;
    } else if (_isLoadingTrails) {
      message = context.l10n.trailsUpdating(totalCount);
    } else if (_clusters.isNotEmpty) {
      message = context.l10n.trailsZoomForDetails(totalCount);
    } else if (_trails.isEmpty) {
      message = context.l10n.moveMapToExplore;
    } else {
      message = context.l10n.trailsInArea(totalCount);
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.info.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isLoadingTrails 
                ? Icons.hourglass_empty 
                : _clusters.isNotEmpty 
                    ? Icons.bubble_chart  // Icona cluster
                    : Icons.explore,
            size: 18,
            color: AppColors.info,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.info,
              ),
            ),
          ),
          if (_userPosition != null)
            TextButton(
              onPressed: _centerOnUser,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(context.l10n.positionBtn, style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB SENTIERI OSM
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTrailsTab() {
    // Mostra sempre la mappa/lista, il loading è indicato nel badge
    final trails = _filteredTrails;

    // ⭐ Se modalità mappa, mostra SEMPRE la mappa (anche se vuota)
    // così l'utente può spostarsi per cercare sentieri
    if (_showMap) {
      return _buildTrailsMapView(trails);
    }

    // Modalità lista: mostra empty state se vuoto (e non ci sono cluster)
    if (trails.isEmpty && _clusters.isEmpty && !_isLoadingTrails) {
      return _buildEmptyState(
        icon: Icons.hiking,
        message: _searchQuery.isEmpty 
            ? context.l10n.moveMapToExplore
            : context.l10n.noResultsFor(_searchQuery),
        showExpandRadius: false,
      );
    }

    return _buildTrailsList(trails);
  }

  Widget _buildTrailsMapView(List<PublicTrail> trails) {
    // Centro di default: posizione utente o Bergamo
    final defaultCenter = _userPosition ?? const LatLng(45.95, 9.75);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: defaultCenter,
            initialZoom: _userPosition != null ? 12 : 11,
            minZoom: 8,
            maxZoom: 18,
            onTap: (_, _) => setState(() => _selectedTrail = null),
            onMapEvent: _onMapEvent, // ⭐ Handler per viewport loading
          ),
          children: [
            TileLayer(
              urlTemplate: mapStyles[_currentMapStyle].urlTemplate,
              subdomains: mapStyles[_currentMapStyle].subdomains,
              // UA richiesto dalla restrizione MapTiler (vedi ApiKeys);
              // i provider free (OSM/OpenTopo/ArcGIS) lo accettano.
              userAgentPackageName: ApiKeys.mapTilerUserAgent,
              tileProvider: OfflineFallbackTileProvider(),
              tileBuilder: mapStyles[_currentMapStyle].tileColorFilter != null
                  ? (context, tileWidget, tile) => ColorFiltered(
                        colorFilter: mapStyles[_currentMapStyle].tileColorFilter!,
                        child: tileWidget,
                      )
                  : null,
            ),

            // Epic 3.4 — Heatmap overlay (sotto le polyline così tracce
            // selezionate restano leggibili sopra). Cerchi semitrasparenti
            // grandi al variare del count (giallo → rosso). Raggio fisso
            // ~10km (mezza cella geohash p4).
            if (_heatmapVisible && _heatmapCells.isNotEmpty)
              CircleLayer(
                circles: () {
                  final maxC = _heatmapCells
                      .map((c) => c.count)
                      .fold<int>(1, (a, b) => a > b ? a : b);
                  return _heatmapCells
                      .map((c) => CircleMarker(
                            point: c.center,
                            radius: 10000, // 10 km
                            useRadiusInMeter: true,
                            color: _heatmapColor(c.count, maxC)
                                .withValues(alpha: 0.35),
                            borderStrokeWidth: 0,
                          ))
                      .toList();
                }(),
              ),

            // Polyline: zoom medio = tratteggio, zoom alto = completo
            if (_clusters.isEmpty && _currentZoom >= 13)
              PolylineLayer(
                polylines: trails.map((trail) {
                  final isSelected = trail.id == _selectedTrail?.id;
                  final color = _activityColor(trail.activityType);
                  final isHighZoom = _currentZoom >= 15;
                  return Polyline(
                    points: trail.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                    strokeWidth: isSelected ? 5 : (isHighZoom ? 3.5 : 2),
                    color: isSelected
                        ? color
                        : color.withValues(alpha: isHighZoom ? 0.85 : 0.4),
                    pattern: (!isHighZoom && !isSelected)
                        ? StrokePattern.dashed(segments: [8, 6])
                        : const StrokePattern.solid(),
                  );
                }).toList(),
              ),

            // Marker punto di partenza con icona attività (cluster
            // disabilitati: rompevano la ricerca su zoom basso).
            MarkerLayer(
                markers: trails.map((trail) {
                  final startLat = trail.startLat;
                  final startLng = trail.startLng;
                  if (startLat == 0 && startLng == 0) return null;
                  final isSelected = trail.id == _selectedTrail?.id;
                  final color = _activityColor(trail.activityType);
                  final icon = _activityIcon(trail.activityType);
                  final isLowZoom = _currentZoom < 13;
                  final size = isSelected ? 44.0 : (isLowZoom ? 40.0 : 28.0);

                  return Marker(
                    point: LatLng(startLat, startLng),
                    width: isLowZoom ? 100 : size,
                    height: isLowZoom ? 44 : size,
                    child: GestureDetector(
                      onTap: () => _selectTrail(trail),
                      child: isLowZoom
                          // Zoom basso: marker grande con icona + badge distanza
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color, width: 2.5),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2)),
                                    ],
                                  ),
                                  child: Icon(icon, color: color, size: 20),
                                ),
                                if (trail.length != null)
                                  Container(
                                    margin: const EdgeInsets.only(left: 2),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _shortDistance(trail.length),
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                              ],
                            )
                          // Zoom medio/alto: marker piccolo colorato
                          : Container(
                              decoration: BoxDecoration(
                                color: isSelected ? color : Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? Colors.white : color, width: 2),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 3),
                                ],
                              ),
                              child: Icon(
                                icon,
                                color: isSelected ? Colors.white : color,
                                size: isSelected ? 20 : 14,
                              ),
                            ),
                    ),
                  );
                }).whereType<Marker>().toList(),
              ),  

            // Marker posizione utente
            if (_userPosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _userPosition!,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),

        // Card info sentiero selezionato
        if (_selectedTrail != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _TrailInfoCard(
              trail: _selectedTrail!,
              onTap: () => _openTrailDetail(_selectedTrail!),
              onClose: () => setState(() => _selectedTrail = null),
            ),
          ),

        // ⭐ NUOVO: Badge contatore aggiornato
        Positioned(
          top: 8,
          left: 8,
          child: _CounterBadge(
            count: _clusters.isNotEmpty 
                ? _clusters.fold(0, (sum, c) => sum + c.count)
                : trails.length, 
            label: context.l10n.trailsLabel,
            isCluster: _clusters.isNotEmpty,
          ),
        ),

        // Indicatore caricamento viewport
        if (_isLoadingTrails)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(context.l10n.loading, style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),

        // Messaggio quando non ci sono sentieri (ma non sta caricando)
        if (trails.isEmpty && _clusters.isEmpty && !_isLoadingTrails)
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.explore, color: AppColors.info, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n.noTrailInArea,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          context.l10n.moveOrZoomMap,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Bottone cambio stile mappa
        Positioned(
          bottom: _selectedTrail != null ? 180 : 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MapLayerButton(
                currentIndex: _currentMapStyle,
                onChanged: (i) => setState(() => _currentMapStyle = i),
              ),
              const SizedBox(height: 8),
              // Epic 3.4 — toggle Heatmap trail popolari
              FloatingActionButton.small(
                heroTag: 'heatmap_toggle',
                onPressed: _heatmapLoading ? null : _toggleHeatmap,
                backgroundColor: _heatmapVisible
                    ? AppColors.primary
                    : Colors.white,
                child: _heatmapLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      )
                    : Icon(
                        Icons.local_fire_department,
                        color: _heatmapVisible
                            ? Colors.white
                            : AppColors.primary,
                      ),
              ),
              const SizedBox(height: 8),
              // Pulsante centra su utente. Sempre visibile: se non abbiamo
              // ancora una posizione (permessi non concessi, fix GPS fallito,
              // timeout su iOS cold-start), al tap ritenta `_initializeLocation`
              // che richiede i permessi e prova a prendere la posizione.
              FloatingActionButton.small(
                heroTag: 'center_user_trails',
                onPressed: _isLoadingLocation ? null : _centerOnUser,
                backgroundColor: Colors.white,
                child: _isLoadingLocation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      )
                    : Icon(
                        _userPosition != null
                            ? Icons.my_location
                            : Icons.location_searching,
                        color: AppColors.primary,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrailsList(List<PublicTrail> trails) {
    return RefreshIndicator(
      onRefresh: _refreshTrails,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: trails.length,
        itemBuilder: (context, index) {
          final trail = trails[index];
          return _TrailCard(
            trail: trail,
            showDistance: false,
            onTap: () => _openTrailDetail(trail),
          );
        },
      ),
    );
  }

  void _openTrailDetail(PublicTrail trail) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TrailDetailPage(trail: trail)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIDGETS COMUNI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState({
    required IconData icon, 
    required String message,
    bool showExpandRadius = false,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: context.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 16, color: context.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (_searchQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              child: Text(context.l10n.clearSearch),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGETS AUSILIARI
// ═══════════════════════════════════════════════════════════════════════════

class _CounterBadge extends StatelessWidget {
  final int count;
  final String label;
  final bool isCluster;

  const _CounterBadge({
    required this.count, 
    required this.label,
    this.isCluster = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCluster) ...[
            const Icon(Icons.bubble_chart, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
          ],
          Text('$count $label', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _TrailInfoCard extends StatelessWidget {
  final PublicTrail trail;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TrailInfoCard({required this.trail, required this.onTap, required this.onClose});

  Color _getColor() {
    final t = (trail.activityType ?? '').toLowerCase();
    if (t.contains('cycl') || t.contains('bike') || t.contains('mtb')) {
      return const Color(0xFF1565C0);
    }
    if (t.contains('run') || t.contains('trail')) {
      return const Color(0xFF2E7D32);
    }
    if (t.contains('ski') || t.contains('snow')) {
      return const Color(0xFF5E35B1);
    }
    return AppColors.primary;
  }

  IconData _getIcon() {
    final t = (trail.activityType ?? '').toLowerCase();
    if (t.contains('cycl') || t.contains('bike') || t.contains('mtb')) {
      return Icons.directions_bike;
    }
    if (t.contains('run') || t.contains('trail')) {
      return Icons.directions_run;
    }
    if (t.contains('ski') || t.contains('snow')) {
      return Icons.downhill_skiing;
    }
    return Icons.hiking;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Contenuto
                Row(
                  children: [
                    // Icona attività
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(_getIcon(), color: color, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            trail.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (trail.length != null) ...[
                                Icon(Icons.straighten, size: 14, color: color),
                                const SizedBox(width: 4),
                                Text(
                                  '${trail.lengthKm.toStringAsFixed(1)} km',
                                  style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 14),
                              ],
                              if (trail.elevationGain != null) ...[
                                Icon(Icons.trending_up, size: 14, color: context.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  '+${trail.elevationGain!.toStringAsFixed(0)} m',
                                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: onClose,
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        padding: const EdgeInsets.all(6),
                        minimumSize: const Size(32, 32),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: context.textMuted),
                  ],
                ),

                // Mini profilo altimetrico
                if (trail.points.length >= 4 && trail.points.any((p) => p.elevation != null))
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    height: 36,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return CustomPaint(
                          size: Size(constraints.maxWidth, 36),
                          painter: _MiniElevationPainter(
                            points: trail.points,
                            color: color,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Painter per mini profilo altimetrico nella card
class _MiniElevationPainter extends CustomPainter {
  final List<TrackPoint> points;
  final Color color;

  _MiniElevationPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final elevations = points
        .where((p) => p.elevation != null)
        .map((p) => p.elevation!)
        .toList();

    if (elevations.length < 2) return;

    final minEle = elevations.reduce((a, b) => a < b ? a : b);
    final maxEle = elevations.reduce((a, b) => a > b ? a : b);
    final range = maxEle - minEle;
    if (range < 1) return;

    final path = ui.Path();
    final fillPath = ui.Path();

    for (int i = 0; i < elevations.length; i++) {
      final x = (i / (elevations.length - 1)) * size.width;
      final y = size.height - ((elevations[i] - minEle) / range) * (size.height - 4) - 2;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.08));
    canvas.drawPath(path, Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ⭐ Card migliorata per sentieri OSM con anteprima mappa
class _TrailCard extends StatelessWidget {
  final PublicTrail trail;
  final bool showDistance;
  final VoidCallback onTap;

  const _TrailCard({
    required this.trail, 
    required this.onTap,
    this.showDistance = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Anteprima mappa
            _buildMapPreview(context),
            
            // Contenuto
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titolo e badge ref
                  Row(
                    children: [
                      if (trail.ref != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            trail.ref!,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.info,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          trail.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Operatore se presente
                  if (trail.operator != null) ...[
                    Row(
                      children: [
                        Icon(Icons.business, size: 14, color: context.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            trail.operator!,
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  
                  // Statistiche
                  Row(
                    children: [
                      // Difficoltà
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getDifficultyColor().withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(trail.difficultyIcon, style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text(
                              trail.difficultyName,
                              style: TextStyle(
                                color: _getDifficultyColor(),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // Distanza
                      if (trail.length != null) ...[
                        const Icon(Icons.straighten, size: 14, color: AppColors.info),
                        const SizedBox(width: 4),
                        Text(
                          '${trail.lengthKm.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.info,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      
                      // Dislivello
                      if (trail.elevationGain != null) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.trending_up, size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(
                          '+${trail.elevationGain!.toStringAsFixed(0)} m',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppColors.success,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Anteprima del sentiero: mostra la prima foto community se presente,
  /// altrimenti cade sulla mini-mappa (polyline / startPoint / placeholder).
  Widget _buildMapPreview(BuildContext context) {
    return FutureBuilder<String?>(
      future: TrailPhotosRepository().getFirstPhotoUrl(trail.id),
      builder: (context, snapshot) {
        final photoUrl = snapshot.data;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          return SizedBox(
            height: 120,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stack) => _buildMapFallback(context),
                ),
                // Badge foto community
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_camera, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Community',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return _buildMapFallback(context);
      },
    );
  }

  /// Fallback quando non ci sono foto community: mini-mappa o placeholder.
  Widget _buildMapFallback(BuildContext context) {
    if (trail.points.isEmpty) {
      // Nessun punto disponibile (metadataOnly) — mostra mappa centrata su startPoint
      if (trail.startLat != 0 && trail.startLng != 0) {
        return SizedBox(
          height: 120,
          child: IgnorePointer(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(trail.startLat, trail.startLng),
                initialZoom: 14,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.trailshare.app',
                  tileProvider: OfflineFallbackTileProvider(),
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(trail.startLat, trail.startLng),
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.hiking, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
      return Container(
        height: 120,
        color: AppColors.background,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hiking, size: 32, color: context.textMuted),
              SizedBox(height: 4),
              Text(
                trail.ref ?? context.l10n.trailFallback,
                style: TextStyle(color: context.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Calcola bounding box
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    final latLngPoints = <LatLng>[];
    
    for (final p in trail.points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
      latLngPoints.add(LatLng(p.latitude, p.longitude));
    }
    
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    
    // Calcola zoom appropriato
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    
    double zoom = 14.0;
    if (maxDiff > 0.5) {
      zoom = 10;
    } else if (maxDiff > 0.2) {
      zoom = 11;
    } else if (maxDiff > 0.1) {
      zoom = 12;
    } else if (maxDiff > 0.05) {
      zoom = 13;
    }

    return SizedBox(
      height: 120,
      child: Stack(
        children: [
          // Mappa
          IgnorePointer(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.trailshare.app',
                  tileProvider: OfflineFallbackTileProvider(),
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: latLngPoints,
                      strokeWidth: 3,
                      color: AppColors.info,
                    ),
                  ],
                ),
                // Marker inizio/fine
                if (latLngPoints.length > 1)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: latLngPoints.first,
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                      Marker(
                        point: latLngPoints.last,
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          
          // Badge circolare se presente
          if (trail.isCircular)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.loop, size: 14, color: AppColors.info),
                    SizedBox(width: 4),
                    Text(
                      context.l10n.circularBadge,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          
          // Freccia dettagli
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chevron_right, size: 18, color: context.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Color _getDifficultyColor() {
    switch (trail.difficulty?.toLowerCase()) {
      case 't':
      case 'turistico':
      case 'facile':
      case 'easy':
        return AppColors.success;
      case 'e':
      case 'escursionistico':
      case 'medio':
      case 'medium':
        return AppColors.info;
      case 'ee':
      case 'escursionisti esperti':
      case 'difficile':
      case 'hard':
        return AppColors.warning;
      case 'eea':
      case 'alpinistico':
      case 'molto difficile':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
    }
  }
}
