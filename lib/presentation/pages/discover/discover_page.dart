import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
// ⭐ Repository con cache e clustering
import '../../../data/repositories/public_trails_repository.dart';
import '../../../core/services/trails_cache_service.dart';
import 'trail_detail_page.dart';
import '../../../core/services/offline_tile_provider.dart';
import '../../../core/services/location_service.dart';
import '../../../core/constants/map_styles.dart';
import '../../widgets/map_layer_button.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ⭐ VIEWPORT-BASED LOADING per sentieri
  Timer? _viewportDebounce;
  LatLngBounds? _lastLoadedBounds;

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
        return;
      }

      // Verifica permessi con Prominent Disclosure
      final hasPermission = await LocationService().checkAndRequestPermission(context: context);
      if (!hasPermission) {
        setState(() => _isLoadingLocation = false);
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
      // Carica comunque i sentieri per il viewport di default
      _loadTrailsForViewport();
    }
  }

  /// Refresh manuale - ricarica sentieri per viewport corrente
  Future<void> _refreshTrails() async {
    _lastLoadedBounds = null;
    _trails.clear();
    _clusters.clear();
    await _trailsRepository.invalidateCache();
    await _loadTrailsForViewport();
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query.toLowerCase());
  }

  List<PublicTrail> get _filteredTrails {
    if (_searchQuery.isEmpty) return _trails;
    return _trails.where((trail) =>
        trail.name.toLowerCase().contains(_searchQuery) ||
        (trail.ref?.toLowerCase().contains(_searchQuery) ?? false)
    ).toList();
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

  LatLng _calculateCenterFromTrackPoints(List points) {
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    
    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
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
        limit: 200,
      );
      
      if (mounted) {
        setState(() {
          _clusters = result.clusters;
          if (result.hasClusters) {
            // In modalità cluster, sostituisci tutto
            _trails = result.trails;
          } else {
            // In modalità trails, accumula con deduplicazione
            final existingIds = _trails.map((t) => t.id).toSet();
            final newTrails = result.trails.where((t) => !existingIds.contains(t.id)).toList();
            if (newTrails.isNotEmpty) {
              _trails = [..._trails, ...newTrails];
            }
          }
          _lastLoadedBounds = bounds;
          _isLoadingTrails = false;
        });
      }
      
      final source = result.fromCache ? '⚡ cache' : '🌐 server';
      final type = result.hasClusters ? 'cluster' : 'trails';
      debugPrint('[DiscoverPage] $source: ${result.totalCount} $type (zoom: ${zoom.toStringAsFixed(1)})');
      
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
              : context.l10n.discoverWithCount(_trails.length),
        ),
        actions: [
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
        color: AppColors.info.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.info.withOpacity(0.3),
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
              child: Text(context.l10n.positionBtn, style: const TextStyle(fontSize: 12)),
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
            onTap: (_, __) => setState(() => _selectedTrail = null),
            onMapEvent: _onMapEvent, // ⭐ Handler per viewport loading
          ),
          children: [
            TileLayer(
              urlTemplate: mapStyles[_currentMapStyle].urlTemplate,
              subdomains: mapStyles[_currentMapStyle].subdomains,
              userAgentPackageName: 'com.trailshare.app',
              tileProvider: OfflineFallbackTileProvider(),
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
                        : color.withOpacity(isHighZoom ? 0.85 : 0.4),
                    pattern: (!isHighZoom && !isSelected)
                        ? StrokePattern.dashed(segments: [8, 6])
                        : const StrokePattern.solid(),
                  );
                }).toList(),
              ),

            // ⭐ NUOVO: Cluster markers (zoom basso)
            if (_clusters.isNotEmpty)
              MarkerLayer(
                markers: _clusters.map((cluster) => Marker(
                  point: cluster.center,
                  width: 56,
                  height: 56,
                  child: GestureDetector(
                    onTap: () {
                      // Zoom in sul cluster
                      _mapController.move(cluster.center, _currentZoom + 2);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${cluster.count}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Text(
                              '🥾',
                              style: TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )).toList(),
              ),

            // Marker punto di partenza con icona attività
            if (_clusters.isEmpty)
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
                                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2)),
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
                                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 3),
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
                            color: AppColors.primary.withOpacity(0.4),
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

        // Bottone cambio stile mappa
        Positioned(
          top: 8,
          right: 8,
          child: MapLayerButton(
            currentIndex: _currentMapStyle,
            onChanged: (i) => setState(() => _currentMapStyle = i),
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
                      color: Colors.black.withOpacity(0.1),
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
                    Text(context.l10n.loading, style: const TextStyle(fontSize: 12)),
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
                    color: Colors.black.withOpacity(0.1),
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
                        const SizedBox(height: 4),
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

        // Pulsante centra su utente
        if (_userPosition != null)
          Positioned(
            bottom: _selectedTrail != null ? 180 : 16,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'center_user_trails',
              onPressed: _centerOnUser,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: AppColors.primary),
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
          Icon(icon, size: 64, color: AppColors.textMuted.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, -4))],
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
                        color: color.withOpacity(0.1),
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
                                Icon(Icons.trending_up, size: 14, color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  '+${trail.elevationGain!.toStringAsFixed(0)} m',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                    const Icon(Icons.chevron_right, color: AppColors.textMuted),
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

    canvas.drawPath(fillPath, Paint()..color = color.withOpacity(0.08));
    canvas.drawPath(path, Paint()
      ..color = color.withOpacity(0.5)
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
      shadowColor: Colors.black.withOpacity(0.15),
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
                            color: AppColors.info.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.info.withOpacity(0.3)),
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
                        const Icon(Icons.business, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            trail.operator!,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
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
                          color: _getDifficultyColor().withOpacity(0.1),
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

  /// Anteprima mappa del sentiero
  Widget _buildMapPreview(BuildContext context) {
    if (trail.points.isEmpty) {
      return Container(
        height: 120,
        color: AppColors.background,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hiking, size: 32, color: AppColors.textMuted),
              const SizedBox(height: 4),
              Text(
                trail.ref ?? context.l10n.trailFallback,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
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
    if (maxDiff > 0.5) zoom = 10;
    else if (maxDiff > 0.2) zoom = 11;
    else if (maxDiff > 0.1) zoom = 12;
    else if (maxDiff > 0.05) zoom = 13;

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
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.loop, size: 14, color: AppColors.info),
                    const SizedBox(width: 4),
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
                color: Colors.white.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
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
