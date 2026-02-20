import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../../data/repositories/groups_repository.dart';
import '../discover/community_track_detail_page.dart';
import '../../../presentation/widgets/community_track_card.dart';
import '../groups/create_group_page.dart';
import '../groups/group_detail_page.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ═══════════════════════════════════════════════════════════════════════
  // REPOSITORIES
  // ═══════════════════════════════════════════════════════════════════════
  final CommunityTracksRepository _communityRepo = CommunityTracksRepository();
  final GroupsRepository _groupsRepo = GroupsRepository();

  // ═══════════════════════════════════════════════════════════════════════
  // STATO: TRACCE COMMUNITY
  // ═══════════════════════════════════════════════════════════════════════
  final MapController _mapController = MapController();
  LatLng? _userPosition;
  bool _isLoadingLocation = true;
  List<CommunityTrack> _communityTracks = [];
  bool _isLoadingCommunity = true;
  CommunityTrack? _selectedCommunityTrack;
  bool _showMap = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ═══════════════════════════════════════════════════════════════════════
  // STATO: GRUPPI
  // ═══════════════════════════════════════════════════════════════════════
  List<Group> _myGroups = [];
  List<Group> _publicGroups = [];
  bool _isLoadingMyGroups = true;
  bool _isLoadingPublicGroups = false;
  bool _showPublicGroups = false; // Toggle I miei / Scopri

  // ═══════════════════════════════════════════════════════════════════════
  // STATO: EVENTI
  // ═══════════════════════════════════════════════════════════════════════
  List<GroupEventWithInfo> _myEvents = [];
  List<GroupEventWithInfo> _publicEvents = [];
  List<GroupChallengeWithInfo> _activeChallenges = [];
  bool _isLoadingMyEvents = true;
  bool _isLoadingPublicEvents = false;
  bool _showPublicEvents = false; // Toggle I miei / Pubblici

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      // Carica lazy i dati quando si cambia tab
      if (_tabController.index == 1 && _myGroups.isEmpty && !_isLoadingMyGroups) {
        _loadMyGroups();
      }
      if (_tabController.index == 2 && _myEvents.isEmpty && !_isLoadingMyEvents) {
        _loadMyEvents();
      }
      setState(() {
        _selectedCommunityTrack = null;
      });
    });

    // Carica dati iniziali
    _initializeLocation();
    _loadCommunityTracks();
    _loadMyGroups();
    _loadMyEvents();
    _loadActiveChallenges();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // GEOLOCALIZZAZIONE
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _initializeLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoadingLocation = false);
        return;
      }

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
    } catch (e) {
      print('[CommunityPage] Errore geolocalizzazione: $e');
      setState(() => _isLoadingLocation = false);
    }
  }

  void _centerOnUser() {
    if (_userPosition != null) {
      _mapController.move(_userPosition!, 13);
    } else {
      _initializeLocation();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CARICAMENTO: TRACCE COMMUNITY
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _loadCommunityTracks() async {
    setState(() => _isLoadingCommunity = true);
    final tracks = await _communityRepo.getRecentTracks(limit: 50);
    if (mounted) {
      setState(() {
        _communityTracks = tracks;
        _isLoadingCommunity = false;
      });
    }
  }

  List<CommunityTrack> get _filteredCommunity {
    if (_searchQuery.isEmpty) return _communityTracks;
    return _communityTracks.where((track) =>
        track.name.toLowerCase().contains(_searchQuery) ||
        track.ownerUsername.toLowerCase().contains(_searchQuery)
    ).toList();
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query.toLowerCase());
  }

  void _selectCommunityTrack(CommunityTrack track) {
    setState(() => _selectedCommunityTrack = track);

    if (track.points.isNotEmpty) {
      final center = _calculateCenterFromTrackPoints(track.points);
      _mapController.move(center, 13);
    }
  }

  void _openCommunityTrackDetail(CommunityTrack track) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CommunityTrackDetailPage(track: track)),
    );
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

  // ═══════════════════════════════════════════════════════════════════════
  // CARICAMENTO: GRUPPI
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _loadMyGroups() async {
    setState(() => _isLoadingMyGroups = true);
    final groups = await _groupsRepo.getMyGroups();
    if (mounted) {
      setState(() {
        _myGroups = groups;
        _isLoadingMyGroups = false;
      });
    }
  }

  Future<void> _loadPublicGroups() async {
    setState(() => _isLoadingPublicGroups = true);
    final groups = await _groupsRepo.getPublicGroups();
    if (mounted) {
      setState(() {
        _publicGroups = groups;
        _isLoadingPublicGroups = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CARICAMENTO: EVENTI & SFIDE
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _loadMyEvents() async {
    setState(() => _isLoadingMyEvents = true);
    final events = await _groupsRepo.getAllUpcomingEvents();
    if (mounted) {
      setState(() {
        _myEvents = events;
        _isLoadingMyEvents = false;
      });
    }
  }

  Future<void> _loadPublicEvents() async {
    setState(() => _isLoadingPublicEvents = true);
    final events = await _groupsRepo.getPublicUpcomingEvents();
    if (mounted) {
      setState(() {
        _publicEvents = events;
        _isLoadingPublicEvents = false;
      });
    }
  }

  Future<void> _loadActiveChallenges() async {
    final challenges = await _groupsRepo.getAllActiveChallenges();
    if (mounted) {
      setState(() => _activeChallenges = challenges);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD PRINCIPALE
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(
              icon: const Icon(Icons.route),
              text: 'Tracce (${_communityTracks.length})',
            ),
            Tab(
              icon: const Icon(Icons.groups),
              text: 'Gruppi (${_myGroups.length})',
            ),
            Tab(
              icon: const Icon(Icons.event),
              text: 'Eventi (${_myEvents.length})',
            ),
          ],
        ),
        actions: [
          // Toggle mappa/lista (solo per tab Tracce)
          if (_tabController.index == 0)
            IconButton(
              icon: Icon(_showMap ? Icons.list : Icons.map),
              onPressed: () => setState(() {
                _showMap = !_showMap;
                _selectedCommunityTrack = null;
              }),
              tooltip: _showMap ? 'Mostra lista' : 'Mostra mappa',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCurrentTab,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTracksTab(),
          _buildGroupsTab(),
          _buildEventsTab(),
        ],
      ),
    );
  }

  void _refreshCurrentTab() {
    switch (_tabController.index) {
      case 0:
        _loadCommunityTracks();
        break;
      case 1:
        _loadMyGroups();
        if (_showPublicGroups) _loadPublicGroups();
        break;
      case 2:
        _loadMyEvents();
        if (_showPublicEvents) _loadPublicEvents();
        _loadActiveChallenges();
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 1: TRACCE COMMUNITY
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTracksTab() {
    return Column(
      children: [
        // Barra di ricerca
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Cerca tracce o utenti...',
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        // Contenuto
        Expanded(
          child: _isLoadingCommunity
              ? const Center(child: CircularProgressIndicator())
              : _buildTracksContent(),
        ),
      ],
    );
  }

  Widget _buildTracksContent() {
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
                      child: const Icon(Icons.person, color: Colors.white, size: 22),
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

        // Badge conteggio
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

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 2: GRUPPI
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildGroupsTab() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create_group',
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const CreateGroupPage()),
          );
          if (created == true) {
            _loadMyGroups();
            if (_showPublicGroups) _loadPublicGroups();
          }
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuovo Gruppo'),
      ),
      body: Column(
        children: [
          // Filtro: I miei / Scopri
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text('I miei (${_myGroups.length})'),
                  selected: !_showPublicGroups,
                  onSelected: (value) {
                    setState(() => _showPublicGroups = false);
                  },
                  selectedColor: AppColors.primary.withOpacity(0.2),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Scopri'),
                  selected: _showPublicGroups,
                  onSelected: (value) {
                    setState(() => _showPublicGroups = true);
                    if (_publicGroups.isEmpty) _loadPublicGroups();
                  },
                  selectedColor: AppColors.primary.withOpacity(0.2),
                ),
              ],
            ),
          ),

          // Lista gruppi
          Expanded(
            child: _showPublicGroups
                ? _buildPublicGroupsList()
                : _buildMyGroupsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMyGroupsList() {
    if (_isLoadingMyGroups) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_myGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.groups_outlined, size: 80, color: Colors.grey[300]),
              const SizedBox(height: 24),
              const Text(
                'Nessun gruppo',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea un gruppo per organizzare uscite, lanciare sfide e chattare con i tuoi compagni di avventura!',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyGroups,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myGroups.length,
        itemBuilder: (context, index) => _buildGroupCard(_myGroups[index], isMember: true),
      ),
    );
  }

  Widget _buildPublicGroupsList() {
    if (_isLoadingPublicGroups) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_publicGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.explore_outlined, size: 80, color: Colors.grey[300]),
              const SizedBox(height: 24),
              const Text(
                'Nessun gruppo disponibile',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Non ci sono gruppi pubblici a cui unirti al momento. Creane uno tu!',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPublicGroups,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _publicGroups.length,
        itemBuilder: (context, index) => _buildGroupCard(_publicGroups[index], isMember: false),
      ),
    );
  }

  Widget _buildGroupCard(Group group, {required bool isMember}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isMember
            ? () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupDetailPage(groupId: group.id, groupName: group.name),
                  ),
                );
                _loadMyGroups();
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar gruppo
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primary.withOpacity(0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (group.description != null && group.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.people, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          '${group.memberCount} ${group.memberCount == 1 ? "membro" : "membri"}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                        if (group.isPublic) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.public, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text('Pubblico', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ] else ...[
                          const SizedBox(width: 12),
                          Icon(Icons.lock, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text('Privato', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Bottone unisciti o freccia
              if (isMember)
                const Icon(Icons.chevron_right, color: AppColors.textMuted)
              else
                ElevatedButton(
                  onPressed: () async {
                    final success = await _groupsRepo.joinGroup(group.id);
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Ti sei unito a "${group.name}"!'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                      _loadMyGroups();
                      _loadPublicGroups();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Unisciti', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 3: EVENTI
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildEventsTab() {
    return Column(
      children: [
        // Filtro: I miei / Pubblici
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              FilterChip(
                label: Text('I miei (${_myEvents.length})'),
                selected: !_showPublicEvents,
                onSelected: (value) {
                  setState(() => _showPublicEvents = false);
                },
                selectedColor: AppColors.primary.withOpacity(0.2),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Pubblici'),
                selected: _showPublicEvents,
                onSelected: (value) {
                  setState(() => _showPublicEvents = true);
                  if (_publicEvents.isEmpty) _loadPublicEvents();
                },
                selectedColor: AppColors.primary.withOpacity(0.2),
              ),
            ],
          ),
        ),

        // Sfide attive (solo per "I miei")
        if (!_showPublicEvents && _activeChallenges.isNotEmpty)
          _buildActiveChallengesSection(),

        // Lista eventi
        Expanded(
          child: _showPublicEvents
              ? _buildPublicEventsList()
              : _buildMyEventsList(),
        ),
      ],
    );
  }

  Widget _buildActiveChallengesSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                'Sfide attive (${_activeChallenges.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._activeChallenges.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupDetailPage(
                      groupId: item.groupId,
                      groupName: item.groupName,
                    ),
                  ),
                );
              },
              child: Row(
                children: [
                  Text(item.challenge.typeIcon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.challenge.title,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.groupName,
                      style: const TextStyle(fontSize: 10, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${item.challenge.endDate.difference(DateTime.now()).inDays}g',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildMyEventsList() {
    if (_isLoadingMyEvents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_myEvents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text(
                'Nessun evento in programma',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Gli eventi dei tuoi gruppi appariranno qui',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadMyEvents();
        await _loadActiveChallenges();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myEvents.length,
        itemBuilder: (context, index) => _buildEventCard(_myEvents[index]),
      ),
    );
  }

  Widget _buildPublicEventsList() {
    if (_isLoadingPublicEvents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_publicEvents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.public, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text(
                'Nessun evento pubblico',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Gli eventi dei gruppi pubblici appariranno qui',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPublicEvents,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _publicEvents.length,
        itemBuilder: (context, index) => _buildEventCard(_publicEvents[index]),
      ),
    );
  }

  Widget _buildEventCard(GroupEventWithInfo item) {
    final event = item.event;
    final isPast = event.isPast;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isParticipating = currentUserId != null && event.participants.contains(currentUserId);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isPast ? Colors.grey[50] : null,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupDetailPage(
                groupId: item.groupId,
                groupName: item.groupName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con data e titolo
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isPast
                          ? Colors.grey[200]
                          : AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${event.date.day}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isPast ? Colors.grey : AppColors.primary,
                          ),
                        ),
                        Text(
                          _monthName(event.date.month),
                          style: TextStyle(
                            fontSize: 11,
                            color: isPast ? Colors.grey : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isPast ? Colors.grey : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${event.date.hour.toString().padLeft(2, '0')}:${event.date.minute.toString().padLeft(2, '0')} • ${event.createdByName}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Badge nome gruppo
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.isPublic ? Icons.public : Icons.lock,
                          size: 12,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.groupName,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.people, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${event.participants.length}${event.maxParticipants != null ? "/${event.maxParticipants}" : ""}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  if (isParticipating) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '✓ Partecipo',
                        style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),

              // Dettagli percorso
              if (event.meetingPointName != null || event.estimatedDistance != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (event.meetingPointName != null)
                      _buildEventChip(Icons.location_on, event.meetingPointName!),
                    if (event.estimatedDistance != null)
                      _buildEventChip(Icons.straighten, '${(event.estimatedDistance! / 1000).toStringAsFixed(1)} km'),
                    if (event.estimatedElevation != null)
                      _buildEventChip(Icons.terrain, '+${event.estimatedElevation!.toStringAsFixed(0)} m'),
                    if (event.difficulty != null)
                      _buildEventChip(Icons.signal_cellular_alt, event.difficulty!),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WIDGET COMUNI
  // ═══════════════════════════════════════════════════════════════════════

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

  String _monthName(int month) {
    const months = ['GEN', 'FEB', 'MAR', 'APR', 'MAG', 'GIU', 'LUG', 'AGO', 'SET', 'OTT', 'NOV', 'DIC'];
    return months[month - 1];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET AUSILIARI
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
                          const Icon(Icons.straighten, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text('${track.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
