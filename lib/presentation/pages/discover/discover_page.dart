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
  
  // Posizione utente
  LatLng? _userPosition;
  bool _isLoadingLocation = true;
  String? _locationError;
  
  // Raggio di ricerca in km
  double _searchRadiusKm = 30;
  
  // Sentieri OSM
  final PublicTrailsRepository _trailsRepository = PublicTrailsRepository();
  List<PublicTrail> _trails = [];
  bool _isLoadingTrails = true;
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
    super.dispose();
  }

  /// Inizializza la geolocalizzazione
  Future<void> _initializeLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      // Verifica se il servizio GPS è attivo
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'GPS disattivato';
          _isLoadingLocation = false;
        });
        // Carica comunque i sentieri di default
        _loadTrailsWithoutLocation();
        return;
      }

      // Verifica permessi
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = 'Permesso posizione negato';
            _isLoadingLocation = false;
          });
          _loadTrailsWithoutLocation();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Permesso posizione negato permanentemente';
          _isLoadingLocation = false;
        });
        _loadTrailsWithoutLocation();
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

      // Carica sentieri vicini
      _loadTrailsNearby();
      
    } catch (e) {
      print('[DiscoverPage] Errore geolocalizzazione: $e');
      setState(() {
        _locationError = 'Impossibile ottenere la posizione';
        _isLoadingLocation = false;
      });
      _loadTrailsWithoutLocation();
    }
  }

  /// Carica sentieri vicini alla posizione utente
  Future<void> _loadTrailsNearby() async {
    if (_userPosition == null) {
      _loadTrailsWithoutLocation();
      return;
    }

    setState(() => _isLoadingTrails = true);
    
    try {
      final trails = await _trailsRepository.getTrailsNearby(
        center: _userPosition!,
        radiusKm: _searchRadiusKm,
        limit: 100,
      );
      
      setState(() {
        _trails = trails;
        _isLoadingTrails = false;
      });
      
      // Centra mappa sulla posizione utente se non ci sono sentieri selezionati
      if (_selectedTrail == null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_mapController.camera.center.latitude == 45.95) {
            // Solo se è ancora al valore di default
            _mapController.move(_userPosition!, 12);
          }
        });
      }
    } catch (e) {
      print('[DiscoverPage] Errore caricamento sentieri: $e');
      setState(() => _isLoadingTrails = false);
    }
  }

  /// Carica sentieri senza posizione (fallback)
  Future<void> _loadTrailsWithoutLocation() async {
    setState(() => _isLoadingTrails = true);
    
    final trails = await _trailsRepository.getTrails(limit: 100);
    
    setState(() {
      _trails = trails;
      _isLoadingTrails = false;
    });
  }

  /// Refresh manuale della posizione e sentieri
  Future<void> _refreshLocation() async {
    await _initializeLocation();
  }

  /// Cambia il raggio di ricerca
  void _showRadiusSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _RadiusSelectorSheet(
        currentRadius: _searchRadiusKm,
        onRadiusChanged: (radius) {
          setState(() => _searchRadiusKm = radius);
          Navigator.pop(context);
          _loadTrailsNearby();
        },
      ),
    );
  }

  Future<void> _loadCommunityTracks() async {
    setState(() => _isLoadingCommunity = true);
    final tracks = await _communityRepository.getRecentTracks(limit: 50);
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
    } else {
      _refreshLocation();
    }
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
              _refreshLocation();
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

  /// Widget che mostra info sulla posizione e raggio di ricerca
  Widget _buildLocationInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _userPosition != null 
            ? AppColors.success.withOpacity(0.1)
            : AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _userPosition != null 
              ? AppColors.success.withOpacity(0.3)
              : AppColors.warning.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isLoadingLocation 
                ? Icons.hourglass_empty
                : _userPosition != null 
                    ? Icons.location_on 
                    : Icons.location_off,
            size: 18,
            color: _userPosition != null ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isLoadingLocation
                  ? 'Ricerca posizione...'
                  : _userPosition != null
                      ? 'Sentieri entro ${_searchRadiusKm.toInt()} km dalla tua posizione'
                      : _locationError ?? 'Posizione non disponibile',
              style: TextStyle(
                fontSize: 12,
                color: _userPosition != null ? AppColors.success : AppColors.warning,
              ),
            ),
          ),
          if (_userPosition != null)
            TextButton(
              onPressed: _showRadiusSelector,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Cambia', style: TextStyle(fontSize: 12)),
            ),
          if (_userPosition == null && !_isLoadingLocation)
            TextButton(
              onPressed: _refreshLocation,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Riprova', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB SENTIERI OSM
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTrailsTab() {
    if (_isLoadingTrails || _isLoadingLocation) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _isLoadingLocation 
                  ? 'Ricerca posizione...' 
                  : 'Caricamento sentieri...',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    final trails = _filteredTrails;

    if (trails.isEmpty) {
      return _buildEmptyState(
        icon: Icons.hiking,
        message: _searchQuery.isEmpty 
            ? _userPosition != null
                ? 'Nessun sentiero trovato entro ${_searchRadiusKm.toInt()} km'
                : 'Nessun sentiero disponibile' 
            : 'Nessun risultato per "$_searchQuery"',
        showExpandRadius: _userPosition != null && _searchQuery.isEmpty,
      );
    }

    return _showMap ? _buildTrailsMapView(trails) : _buildTrailsList(trails);
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
      onRefresh: _loadTrailsNearby,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: trails.length,
        itemBuilder: (context, index) {
          final trail = trails[index];
          return _TrailCard(
            trail: trail,
            showDistance: _userPosition != null,
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
              child: const Text('Cancella ricerca'),
            ),
          ],
          if (showExpandRadius) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _searchRadiusKm = _searchRadiusKm + 20);
                _loadTrailsNearby();
              },
              icon: const Icon(Icons.expand),
              label: Text('Espandi a ${(_searchRadiusKm + 20).toInt()} km'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
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

/// Bottom sheet per selezionare il raggio di ricerca
class _RadiusSelectorSheet extends StatelessWidget {
  final double currentRadius;
  final ValueChanged<double> onRadiusChanged;

  const _RadiusSelectorSheet({
    required this.currentRadius,
    required this.onRadiusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [10.0, 20.0, 30.0, 50.0, 100.0];

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Raggio di ricerca',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...options.map((radius) => ListTile(
            leading: Icon(
              radius == currentRadius ? Icons.check_circle : Icons.circle_outlined,
              color: radius == currentRadius ? AppColors.primary : AppColors.textMuted,
            ),
            title: Text('${radius.toInt()} km'),
            onTap: () => onRadiusChanged(radius),
          )),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

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
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: AppColors.info.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Center(
                  child: trail.ref != null
                      ? Text(trail.ref!, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.info, fontSize: 14), textAlign: TextAlign.center)
                      : const Icon(Icons.hiking, color: AppColors.info),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trail.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(trail.difficultyIcon, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(trail.difficultyName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        if (trail.operator != null) ...[
                          const Text(' • ', style: TextStyle(color: AppColors.textMuted)),
                          Flexible(child: Text(trail.operator!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Mostra distanza dall'utente se disponibile
                  if (showDistance && trail.distanceFromUser != null) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.near_me, size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          trail.distanceFromUserFormatted, 
                          style: const TextStyle(
                            fontWeight: FontWeight.bold, 
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                  ],
                  if (trail.length != null) 
                    Text('${trail.lengthKm.toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.info)),
                  if (trail.elevationGain != null) 
                    Text('+${trail.elevationGain!.toStringAsFixed(0)} m', style: const TextStyle(color: AppColors.success, fontSize: 12)),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
