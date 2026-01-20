import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/public_trails_repository.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import 'trail_detail_page.dart';
import 'community_track_detail_page.dart';
import '../../../presentation/widgets/community_track_card.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MapController _mapController = MapController();
  
  // Posizione utente (solo per centrare mappa inizialmente e mostrare marker)
  LatLng? _userPosition;
  bool _isLoadingLocation = true;
  
  // Sentieri OSM - caricati in base al viewport della mappa
  final PublicTrailsRepository _trailsRepository = PublicTrailsRepository();
  List<PublicTrail> _trails = [];
  bool _isLoadingTrails = false; // Cambiato: false inizialmente, carica su viewport
  PublicTrail? _selectedTrail;

  // Community
  final CommunityTracksRepository _communityRepository = CommunityTracksRepository();
  List<CommunityTrack> _communityTracks = [];
  bool _isLoadingCommunity = true;
  CommunityTrack? _selectedCommunityTrack;

  // UI
  bool _showMap = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ⭐ VIEWPORT-BASED LOADING per sentieri
  Timer? _viewportDebounce;
  LatLngBounds? _lastLoadedBounds;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // Reset selezione quando si cambia tab
      setState(() {
        _selectedTrail = null;
        _selectedCommunityTrack = null;
      });
    });
    
    // Prima ottieni la posizione, poi carica i sentieri
    _initializeLocation();
    _loadCommunityTracks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _viewportDebounce?.cancel(); // ⭐ Cancella timer viewport
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

      // Verifica permessi
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
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

      print('[DiscoverPage] Posizione utente: ${_userPosition!.latitude}, ${_userPosition!.longitude}');

      // Centra mappa sulla posizione utente
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(_userPosition!, 11);
          // Carica sentieri per il viewport iniziale
          _loadTrailsForViewport();
        });
      }
      
    } catch (e) {
      print('[DiscoverPage] Errore geolocalizzazione: $e');
      setState(() => _isLoadingLocation = false);
      // Carica comunque i sentieri per il viewport di default
      _loadTrailsForViewport();
    }
  }

  /// Refresh manuale - ricarica sentieri per viewport corrente
  Future<void> _refreshTrails() async {
    _lastLoadedBounds = null; // Reset per forzare ricaricamento
    await _loadTrailsForViewport();
  }

  Future<void> _loadCommunityTracks() async {
    setState(() => _isLoadingCommunity = true);
    final tracks = await _communityRepository.getRecentTracks(limit: 30); // ⭐ Ridotto da 50
    setState(() {
      _communityTracks = tracks;
      _isLoadingCommunity = false;
    });
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

  List<CommunityTrack> get _filteredCommunity {
    if (_searchQuery.isEmpty) return _communityTracks;
    return _communityTracks.where((track) =>
        track.name.toLowerCase().contains(_searchQuery) ||
        track.ownerUsername.toLowerCase().contains(_searchQuery)
    ).toList();
  }

  void _selectTrail(PublicTrail trail) {
    setState(() => _selectedTrail = trail);
    
    if (trail.points.isNotEmpty) {
      final center = _calculateCenter(trail.points);
      _mapController.move(center, 13);
    }
  }

  void _selectCommunityTrack(CommunityTrack track) {
    setState(() => _selectedCommunityTrack = track);
    
    if (track.points.isNotEmpty) {
      final center = _calculateCenterFromTrackPoints(track.points);
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

  // ═══════════════════════════════════════════════════════════════════════════
  // ⭐ VIEWPORT-BASED LOADING (solo per sentieri)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Handler per eventi mappa (zoom, pan) - carica sentieri nel viewport
  void _onMapEvent(MapEvent event) {
    // Solo per tab sentieri e quando l'utente finisce di muovere la mappa
    if (_tabController.index != 0) return;
    
    if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
      // Debounce per evitare troppe chiamate
      _viewportDebounce?.cancel();
      _viewportDebounce = Timer(const Duration(milliseconds: 300), () {
        _loadTrailsForViewport();
      });
    }
  }

  /// Carica sentieri basati sul viewport corrente della mappa
  Future<void> _loadTrailsForViewport() async {
    if (_isLoadingTrails) return;
    
    try {
      final bounds = _mapController.camera.visibleBounds;
      
      // Evita di ricaricare se i bounds sono molto simili
      if (_lastLoadedBounds != null && _areBoundsSimilar(bounds, _lastLoadedBounds!)) {
        return;
      }
      
      setState(() => _isLoadingTrails = true);
      
      final trails = await _trailsRepository.getTrailsInBounds(
        minLat: bounds.south,
        maxLat: bounds.north,
        minLng: bounds.west,
        maxLng: bounds.east,
        limit: 200, // ⭐ Aumentato da 50 a 200 con GeoHash
      );
      
      if (mounted) {
        setState(() {
          _trails = trails;
          _lastLoadedBounds = bounds;
          _isLoadingTrails = false;
        });
      }
      
      print('[DiscoverPage] ⭐ Caricati ${trails.length} sentieri per viewport');
    } catch (e) {
      print('[DiscoverPage] Errore caricamento viewport: $e');
      if (mounted) {
        setState(() => _isLoadingTrails = false);
      }
    }
  }

  /// Verifica se due bounding box sono simili (per evitare ricaricamenti inutili)
  bool _areBoundsSimilar(LatLngBounds a, LatLngBounds b) {
    const threshold = 0.005; // ~500m - più sensibile per esplorazione
    return (a.north - b.north).abs() < threshold &&
           (a.south - b.south).abs() < threshold &&
           (a.east - b.east).abs() < threshold &&
           (a.west - b.west).abs() < threshold;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scopri'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.hiking),
              text: 'Sentieri (${_trails.length})',
            ),
            Tab(
              icon: const Icon(Icons.people),
              text: 'Community (${_communityTracks.length})',
            ),
          ],
        ),
        actions: [
          // Toggle mappa/lista
          IconButton(
            icon: Icon(_showMap ? Icons.list : Icons.map),
            onPressed: () => setState(() {
              _showMap = !_showMap;
              _selectedTrail = null;
              _selectedCommunityTrack = null;
            }),
            tooltip: _showMap ? 'Mostra lista' : 'Mostra mappa',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _refreshTrails();
              _loadCommunityTracks();
            },
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
                    hintText: 'Cerca...',
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
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
                
                // Info posizione (solo per tab Sentieri)
                if (_tabController.index == 0) ...[
                  const SizedBox(height: 8),
                  _buildLocationInfo(),
                ],
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTrailsTab(),
                _buildCommunityTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Widget che mostra info sulla mappa (viewport-based)
  Widget _buildLocationInfo() {
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
            _isLoadingTrails ? Icons.hourglass_empty : Icons.explore,
            size: 18,
            color: AppColors.info,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isLoadingTrails
                  ? 'Caricamento sentieri...'
                  : _trails.isEmpty
                      ? 'Sposta la mappa per esplorare i sentieri'
                      : '${_trails.length} sentieri in questa zona',
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
              child: const Text('📍 Posizione', style: TextStyle(fontSize: 12)),
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

    // Modalità lista: mostra empty state se vuoto
    if (trails.isEmpty && !_isLoadingTrails) {
      return _buildEmptyState(
        icon: Icons.hiking,
        message: _searchQuery.isEmpty 
            ? 'Sposta la mappa per esplorare i sentieri'
            : 'Nessun risultato per "$_searchQuery"',
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
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.trailshare.app',
            ),
            
            // Polylines dei sentieri
            PolylineLayer(
              polylines: trails.map((trail) {
                final isSelected = trail.id == _selectedTrail?.id;
                return Polyline(
                  points: trail.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                  strokeWidth: isSelected ? 5 : 3,
                  color: isSelected ? AppColors.primary : AppColors.info.withOpacity(0.7),
                );
              }).toList(),
            ),

            // Markers dei sentieri
            MarkerLayer(
              markers: trails.map((trail) {
                if (trail.points.isEmpty) return null;
                final start = trail.points.first;
                final isSelected = trail.id == _selectedTrail?.id;
                
                return Marker(
                  point: LatLng(start.latitude, start.longitude),
                  width: isSelected ? 40 : 30,
                  height: isSelected ? 40 : 30,
                  child: GestureDetector(
                    onTap: () => _selectTrail(trail),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.info,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          trail.ref ?? '•',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSelected ? 12 : 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
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

        // Badge contatore
        Positioned(
          top: 8,
          left: 8,
          child: _CounterBadge(count: trails.length, label: 'sentieri'),
        ),

        // ⭐ Indicatore caricamento viewport
        if (_isLoadingTrails)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Caricamento...', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),

        // ⭐ Messaggio quando non ci sono sentieri (ma non sta caricando)
        if (trails.isEmpty && !_isLoadingTrails)
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
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
                        const Text(
                          'Nessun sentiero in questa zona',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sposta o zooma la mappa per esplorare altre aree',
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
            showDistance: false, // Non mostriamo più la distanza dall'utente
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
  // TAB COMMUNITY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCommunityTab() {
    if (_isLoadingCommunity) {
      return const Center(child: CircularProgressIndicator());
    }

    final tracks = _filteredCommunity;

    if (tracks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline,
        message: _searchQuery.isEmpty 
            ? 'Nessuna traccia condivisa' 
            : 'Nessun risultato per "$_searchQuery"',
      );
    }

    return _showMap ? _buildCommunityMapView(tracks) : _buildCommunityList(tracks);
  }

  Widget _buildCommunityMapView(List<CommunityTrack> tracks) {
    final defaultCenter = _userPosition ?? const LatLng(45.95, 9.75);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: tracks.isNotEmpty && tracks.first.points.isNotEmpty
                ? _calculateCenterFromTrackPoints(tracks.first.points)
                : defaultCenter,
            initialZoom: 11,
            minZoom: 8,
            maxZoom: 18,
            onTap: (_, __) => setState(() => _selectedCommunityTrack = null),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.trailshare.app',
            ),
            
            // Polylines delle tracce
            PolylineLayer(
              polylines: tracks.map((track) {
                final isSelected = track.id == _selectedCommunityTrack?.id;
                return Polyline(
                  points: track.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                  strokeWidth: isSelected ? 5 : 3,
                  color: isSelected ? AppColors.primary : AppColors.success.withOpacity(0.7),
                );
              }).toList(),
            ),

            // Markers inizio tracce
            MarkerLayer(
              markers: tracks.map((track) {
                if (track.points.isEmpty) return null;
                final start = track.points.first;
                final isSelected = track.id == _selectedCommunityTrack?.id;
                
                return Marker(
                  point: LatLng(start.latitude, start.longitude),
                  width: isSelected ? 44 : 36,
                  height: isSelected ? 44 : 36,
                  child: GestureDetector(
                    onTap: () => _selectCommunityTrack(track),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          track.activityIcon,
                          style: TextStyle(fontSize: isSelected ? 18 : 14),
                        ),
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

        // Card info traccia selezionata
        if (_selectedCommunityTrack != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _CommunityTrackInfoCard(
              track: _selectedCommunityTrack!,
              onTap: () => _openCommunityTrackDetail(_selectedCommunityTrack!),
              onClose: () => setState(() => _selectedCommunityTrack = null),
            ),
          ),

        Positioned(
          top: 8,
          left: 8,
          child: _CounterBadge(count: tracks.length, label: 'tracce'),
        ),

        // Pulsante centra su utente
        if (_userPosition != null)
          Positioned(
            bottom: _selectedCommunityTrack != null ? 180 : 16,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'center_user_community',
              onPressed: _centerOnUser,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: AppColors.primary),
            ),
          ),
      ],
    );
  }

  Widget _buildCommunityList(List<CommunityTrack> tracks) {
    return RefreshIndicator(
      onRefresh: _loadCommunityTracks,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return CommunityTrackCard(
            trackId: track.id,
            name: track.name,
            ownerUsername: track.ownerUsername,
            activityIcon: track.activityIcon,
            distanceKm: track.distanceKm,
            elevationGain: track.elevationGain,
            durationFormatted: track.durationFormatted,
            cheerCount: track.cheerCount,
            sharedAt: track.sharedAt,
            difficulty: track.difficulty,
            photoUrls: track.photoUrls,
            points: track.points,
            onTap: () => _openCommunityTrackDetail(track),
          );
        },
      ),
    );
  }

  void _openCommunityTrackDetail(CommunityTrack track) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CommunityTrackDetailPage(track: track)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIDGETS COMUNI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState({
    required IconData icon, 
    required String message,
    bool showExpandRadius = false, // Parametro mantenuto per compatibilità ma ignorato
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
              child: const Text('Cancella ricerca'),
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

  const _CounterBadge({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
      ),
      child: Text('$count $label', style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

class _TrailInfoCard extends StatelessWidget {
  final PublicTrail trail;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TrailInfoCard({required this.trail, required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, spreadRadius: 2)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text(trail.difficultyIcon, style: const TextStyle(fontSize: 24))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(trail.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (trail.distanceFromUser != null) ...[
                            Icon(Icons.near_me, size: 14, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(trail.distanceFromUserFormatted, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
                          ],
                          if (trail.length != null) ...[
                            Icon(Icons.straighten, size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 4),
                            Text('${trail.lengthKm.toStringAsFixed(1)} km', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            const SizedBox(width: 12),
                          ],
                          if (trail.elevationGain != null) ...[
                            Icon(Icons.trending_up, size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 4),
                            Text('+${trail.elevationGain!.toStringAsFixed(0)} m', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: onClose, iconSize: 20),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityTrackInfoCard extends StatelessWidget {
  final CommunityTrack track;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _CommunityTrackInfoCard({required this.track, required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, spreadRadius: 2)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text(track.activityIcon, style: const TextStyle(fontSize: 24))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(track.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Flexible(child: Text(track.ownerUsername, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          Icon(Icons.straighten, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text('${track.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (track.cheerCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, size: 14, color: AppColors.danger),
                        const SizedBox(width: 4),
                        Text('${track.cheerCount}', style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                IconButton(icon: const Icon(Icons.close), onPressed: onClose, iconSize: 20),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
            // ⭐ Anteprima mappa
            _buildMapPreview(),
            
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
  Widget _buildMapPreview() {
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
                trail.ref ?? 'Sentiero',
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.loop, size: 14, color: AppColors.info),
                    SizedBox(width: 4),
                    Text(
                      'Circolare',
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
