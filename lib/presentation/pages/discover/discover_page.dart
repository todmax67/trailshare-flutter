import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/public_trails_repository.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import 'trail_detail_page.dart';
import 'community_track_detail_page.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MapController _mapController = MapController();
  
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
    _loadTrails();
    _loadCommunityTracks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTrails() async {
    setState(() => _isLoadingTrails = true);
    final trails = await _trailsRepository.getTrails(limit: 100);
    setState(() {
      _trails = trails;
      _isLoadingTrails = false;
    });
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
              _loadTrails();
              _loadCommunityTracks();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra di ricerca
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
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

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB SENTIERI OSM
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTrailsTab() {
    if (_isLoadingTrails) {
      return const Center(child: CircularProgressIndicator());
    }

    final trails = _filteredTrails;

    if (trails.isEmpty) {
      return _buildEmptyState(
        icon: Icons.hiking,
        message: _searchQuery.isEmpty 
            ? 'Nessun sentiero disponibile' 
            : 'Nessun risultato per "$_searchQuery"',
      );
    }

    return _showMap ? _buildTrailsMapView(trails) : _buildTrailsList(trails);
  }

  Widget _buildTrailsMapView(List<PublicTrail> trails) {
    const defaultCenter = LatLng(45.95, 9.75);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: trails.isNotEmpty && trails.first.points.isNotEmpty
                ? _calculateCenter(trails.first.points)
                : defaultCenter,
            initialZoom: 11,
            minZoom: 8,
            maxZoom: 18,
            onTap: (_, __) => setState(() => _selectedTrail = null),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.trailshare.app',
            ),
            
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
          ],
        ),

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

        Positioned(
          top: 8,
          left: 8,
          child: _CounterBadge(count: trails.length, label: 'sentieri'),
        ),
      ],
    );
  }

  Widget _buildTrailsList(List<PublicTrail> trails) {
    return RefreshIndicator(
      onRefresh: _loadTrails,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: trails.length,
        itemBuilder: (context, index) {
          final trail = trails[index];
          return _TrailCard(
            trail: trail,
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
    const defaultCenter = LatLng(45.95, 9.75);

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
      ],
    );
  }

  Widget _buildCommunityList(List<CommunityTrack> tracks) {
    return RefreshIndicator(
      onRefresh: _loadCommunityTracks,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return _CommunityTrackCard(
            track: track,
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

  Widget _buildEmptyState({required IconData icon, required String message}) {
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
// WIDGETS
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
  final VoidCallback onTap;

  const _TrailCard({required this.trail, required this.onTap});

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
                  if (trail.length != null) Text('${trail.lengthKm.toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                  if (trail.elevationGain != null) Text('+${trail.elevationGain!.toStringAsFixed(0)} m', style: const TextStyle(color: AppColors.success, fontSize: 12)),
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

class _CommunityTrackCard extends StatelessWidget {
  final CommunityTrack track;
  final VoidCallback onTap;

  const _CommunityTrackCard({required this.track, required this.onTap});

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
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(track.activityIcon, style: const TextStyle(fontSize: 24))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Flexible(child: Text(track.ownerUsername, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis)),
                        if (track.cheerCount > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.favorite, size: 14, color: AppColors.danger),
                          const SizedBox(width: 2),
                          Text('${track.cheerCount}', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                        ],
                      ],
                    ),
                    if (track.sharedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(_formatDate(track.sharedAt!), style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${track.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                  if (track.elevationGain > 0) Text('+${track.elevationGain.toStringAsFixed(0)} m', style: const TextStyle(color: AppColors.success, fontSize: 12)),
                  Text(track.durationFormatted, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Oggi';
    if (diff.inDays == 1) return 'Ieri';
    if (diff.inDays < 7) return '${diff.inDays} giorni fa';
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return weeks == 1 ? '1 settimana fa' : '$weeks settimane fa';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}
