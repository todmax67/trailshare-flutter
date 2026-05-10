import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../data/models/tour.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../../data/repositories/groups_repository.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../data/repositories/follow_repository.dart';
import '../../../data/repositories/tours_repository.dart';
import '../tours/community_tour_detail_page.dart';
import '../../widgets/discovery_carousel.dart';
import '../../widgets/business_group_card_decorations.dart';
import '../../../core/utils/group_brand.dart';
import '../../../presentation/widgets/following_feed_item.dart';
import '../discover/community_track_detail_page.dart';
import '../../../presentation/widgets/community_track_card.dart';
import '../business/business_discovery_page.dart';
import '../groups/create_group_page.dart';
import '../groups/group_detail_page.dart';
import '../follow/search_users_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/offline_tile_provider.dart';
import '../../../core/services/location_service.dart';
import '../../../core/extensions/theme_colors_extension.dart';

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
  List<CommunityTrack> _communityTracks = [];
  bool _isLoadingCommunity = true;
  CommunityTrack? _selectedCommunityTrack;
  bool _showMap = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // Paginazione
  QueryDocumentSnapshot? _lastDocument;
  bool _hasMoreTracks = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();

  // ═══════════════════════════════════════════════════════════════════════
  // STATO: GRUPPI
  // ═══════════════════════════════════════════════════════════════════════
  List<Group> _myGroups = [];
  List<Group> _discoverableGroups = [];
  bool _isLoadingMyGroups = true;
  bool _isLoadingDiscoverable = false;
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

  // ═══════════════════════════════════════════════════════════════════════
  // STATO: FEED SEGUITI
  // ═══════════════════════════════════════════════════════════════════════
  List<CommunityTrack> _followingTracks = [];
  Map<String, String?> _authorAvatars = {};
  bool _isLoadingFollowing = false;
  bool _followingLoaded = false;
  bool _userHasNoFollowing = false;

  // ═══════════════════════════════════════════════════════════════════════
  // STATO: TOUR PUBBLICI
  // ═══════════════════════════════════════════════════════════════════════
  final ToursRepository _toursRepo = ToursRepository();
  List<Tour> _publicTours = [];
  bool _isLoadingPublicTours = false;
  bool _publicToursLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      // Carica lazy i dati quando si cambia tab
      if (_tabController.index == 1 && _myGroups.isEmpty && !_isLoadingMyGroups) {
        _loadMyGroups();
      }
      if (_tabController.index == 2 && _myEvents.isEmpty && !_isLoadingMyEvents) {
        _loadMyEvents();
      }
      if (_tabController.index == 3 && !_followingLoaded && !_isLoadingFollowing) {
        _loadFollowingFeed();
      }
      if (_tabController.index == 4 && !_publicToursLoaded && !_isLoadingPublicTours) {
        _loadPublicTours();
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
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
    _scrollController.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // GEOLOCALIZZAZIONE
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _initializeLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        return;
      }

      final hasPermission = await LocationService().checkAndRequestPermission(context: context);
      if (!mounted) return;
      if (!hasPermission) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;

      setState(() {
        _userPosition = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint('[CommunityPage] Errore geolocalizzazione: $e');
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
    final result = await _communityRepo.getRecentTracksPaginated(limit: 20);
    if (mounted) {
      setState(() {
        _communityTracks = result.tracks;
        _lastDocument = result.lastDocument;
        _hasMoreTracks = result.hasMore;
        _isLoadingCommunity = false;
      });
    }
  }

  Future<void> _loadMoreCommunityTracks() async {
    if (_isLoadingMore || !_hasMoreTracks || _lastDocument == null) return;
    if (mounted) setState(() => _isLoadingMore = true);
    final result = await _communityRepo.getRecentTracksPaginated(
      limit: 20,
      startAfterDoc: _lastDocument,
    );
    if (mounted) {
      setState(() {
        _communityTracks.addAll(result.tracks);
        _lastDocument = result.lastDocument;
        _hasMoreTracks = result.hasMore;
        _isLoadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreCommunityTracks();
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

  Future<void> _loadMyGroups({bool forceServer = false}) async {
    setState(() => _isLoadingMyGroups = true);
    final groups = await _groupsRepo.getMyGroups(forceServer: forceServer);
    if (mounted) {
      setState(() {
        _myGroups = groups;
        _isLoadingMyGroups = false;
      });
    }
  }

  Future<void> _loadDiscoverableGroups() async {
    setState(() => _isLoadingDiscoverable = true);
    final groups = await _groupsRepo.getDiscoverableGroups();
    if (mounted) {
      setState(() {
        _discoverableGroups = groups;
        _isLoadingDiscoverable = false;
      });
    }
  }

  Future<void> _showJoinByCodeDialog() async {
    final codeController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool isJoining = false;
        String? errorMessage;
        
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.vpn_key, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(context.l10n.joinWithCode),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.enterInviteCodeDesc,
                  style: TextStyle(fontSize: 14, color: context.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'XXXXXX',
                    hintStyle: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 24,
                      letterSpacing: 4,
                    ),
                    border: const OutlineInputBorder(),
                    counterText: '',
                    errorText: errorMessage,
                  ),
                  maxLength: 6,
                  onChanged: (_) {
                    if (errorMessage != null) {
                      setDialogState(() => errorMessage = null);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isJoining ? null : () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              ElevatedButton(
                onPressed: isJoining
                    ? null
                    : () async {
                        final code = codeController.text.trim();
                        if (code.length < 6) {
                          setDialogState(() => errorMessage = context.l10n.codeMustBeSixChars);
                          return;
                        }

                        setDialogState(() {
                          isJoining = true;
                          errorMessage = null;
                        });

                        final result = await _groupsRepo.joinByInviteCode(code);

                        if (!context.mounted) return;

                        if (result['success'] == true) {
                          Navigator.pop(context, true);
                        } else {
                          setDialogState(() {
                            isJoining = false;
                            errorMessage = result['error'] ?? context.l10n.unknownError;
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: isJoining
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(context.l10n.joinGroupAction),
              ),
            ],
          ),
        );
      },
    );

    if (result == true && mounted) {
      // Ricarica gruppi dopo l'unione
      _loadMyGroups();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.joinedGroupGeneric),
          backgroundColor: AppColors.success,
        ),
      );
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

  Future<void> _loadFollowingFeed() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) {
      setState(() {
        _followingLoaded = true;
        _userHasNoFollowing = true;
      });
      return;
    }
    setState(() => _isLoadingFollowing = true);

    try {
      final followRepo = FollowRepository();
      final followingIds = await followRepo.getFollowing(currentUid);

      if (followingIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _userHasNoFollowing = true;
          _followingLoaded = true;
          _isLoadingFollowing = false;
        });
        return;
      }

      final tracks = await _communityRepo.getFollowingActivityFeed(followingIds);

      // Carica profili degli autori per gli avatar
      final ownerIds = tracks.map((t) => t.ownerId).toSet().toList();
      final profiles = await followRepo.getUserProfiles(ownerIds);
      final avatars = <String, String?>{
        for (final p in profiles) p.id: p.avatarUrl,
      };

      if (!mounted) return;
      setState(() {
        _followingTracks = tracks;
        _authorAvatars = avatars;
        _userHasNoFollowing = false;
        _followingLoaded = true;
        _isLoadingFollowing = false;
      });
    } catch (e) {
      debugPrint('[CommunityPage] Errore feed seguiti: $e');
      if (!mounted) return;
      setState(() {
        _followingLoaded = true;
        _isLoadingFollowing = false;
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
        title: Text(context.l10n.community),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: context.textMuted,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(
              icon: const Icon(Icons.route),
              text: context.l10n.tracksTabCount(_communityTracks.length),
            ),
            Tab(
              icon: const Icon(Icons.groups),
              text: context.l10n.groupsTabCount(_myGroups.length),
            ),
            Tab(
              icon: const Icon(Icons.event),
              text: context.l10n.eventsTabCount(_myEvents.length),
            ),
            const Tab(
              icon: Icon(Icons.dynamic_feed),
              text: 'Seguiti',
            ),
            Tab(
              icon: const Icon(Icons.map_outlined),
              text: context.l10n.toursTab,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.business_center_outlined),
            tooltip: 'Spazi Pro',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BusinessDiscoveryPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchUsersPage()),
              );
            },
            tooltip: context.l10n.searchUsers,
          ),
          // Toggle mappa/lista (solo per tab Tracce)
          if (_tabController.index == 0)
            IconButton(
              icon: Icon(_showMap ? Icons.list : Icons.map),
              onPressed: () => setState(() {
                _showMap = !_showMap;
                _selectedCommunityTrack = null;
              }),
              tooltip: _showMap ? context.l10n.showList : context.l10n.showMap,
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
          _buildFollowingTab(),
          _buildPublicToursTab(),
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
        if (_showPublicGroups) _loadDiscoverableGroups();
        break;
      case 2:
        _loadMyEvents();
        if (_showPublicEvents) _loadPublicEvents();
        _loadActiveChallenges();
        break;
      case 3:
        _followingLoaded = false;
        _loadFollowingFeed();
        break;
      case 4:
        _loadPublicTours();
        break;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TOUR PUBBLICI — carica e renderizza la lista dei tour community
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _loadPublicTours() async {
    setState(() => _isLoadingPublicTours = true);
    try {
      final tours = await _toursRepo.getPublicTours(limit: 30);
      if (!mounted) return;
      setState(() {
        _publicTours = tours;
        _isLoadingPublicTours = false;
        _publicToursLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPublicTours = false;
        _publicToursLoaded = true;
      });
    }
  }

  Widget _buildPublicToursTab() {
    if (_isLoadingPublicTours && _publicTours.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_publicTours.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPublicTours,
        child: ListView(
          children: [
            const SizedBox(height: 100),
            Center(
              child: Column(
                children: [
                  Icon(Icons.map_outlined, size: 80, color: AppColors.primary.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.noTours,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadPublicTours,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _publicTours.length,
        itemBuilder: (ctx, i) {
          final t = _publicTours[i];
          return _PublicTourCard(
            tour: t,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CommunityTourDetailPage(tourId: t.id),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 1: TRACCE COMMUNITY
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTracksTab() {
    return Column(
      children: [
        // Discovery carousel: card informative sulle funzionalita meno
        // scoperte (Lifeline, Tour, Export FIT, etc). Si auto-collassa se
        // non ci sono prompt attivi o l'utente li ha tutti dismissati.
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: DiscoveryCarousel(),
        ),

        // Barra di ricerca
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: context.l10n.searchTracksOrUsers,
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
              fillColor: Theme.of(context).colorScheme.surface,
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
            ? context.l10n.noSharedTracks
            : context.l10n.noResultsForQuery(_searchQuery),
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
            onTap: (_, _) => setState(() => _selectedCommunityTrack = null),
          ),
          children: [
            TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.trailshare.app',
          tileProvider: OfflineFallbackTileProvider(),
        ),

            // Polylines delle tracce
            PolylineLayer(
              polylines: tracks.map((track) {
                final isSelected = track.id == _selectedCommunityTrack?.id;
                return Polyline(
                  points: track.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                  strokeWidth: isSelected ? 5 : 3,
                  color: isSelected ? AppColors.primary : AppColors.success.withValues(alpha: 0.7),
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
                          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4),
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
                            color: AppColors.primary.withValues(alpha: 0.4),
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
          child: _CounterBadge(count: tracks.length, label: context.l10n.tracksLabel),
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
        // Bottone carica altre tracce
        if (_hasMoreTracks)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              borderRadius: BorderRadius.circular(20),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _isLoadingMore ? null : _loadMoreCommunityTracks,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _isLoadingMore
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add, size: 18, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(context.l10n.loadMore, style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                ),              // chiude Container
              ),                // chiude InkWell
            ),                  // chiude Material
          ),                    // chiude Positioned
      ],
    );
  }

  Widget _buildCommunityList(List<CommunityTrack> tracks) {
    return RefreshIndicator(
      onRefresh: _loadCommunityTracks,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: tracks.length + (_hasMoreTracks ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == tracks.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _isLoadingMore
                    ? const CircularProgressIndicator()
                    : TextButton.icon(
                        onPressed: _loadMoreCommunityTracks,
                        icon: const Icon(Icons.expand_more),
                        label: Text(context.l10n.loadMoreTracks),
                      ),
              ),
            );
          }
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
            if (_showPublicGroups) _loadDiscoverableGroups();
          }
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: Icon(Icons.add),
        label: Text(context.l10n.newGroup),
      ),
      body: Column(
        children: [
          // Filtro: I miei / Scopri
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text(context.l10n.myFilterCount(_myGroups.length)),
                  selected: !_showPublicGroups,
                  onSelected: (value) {
                    setState(() => _showPublicGroups = false);
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(context.l10n.discoverFilter),
                  selected: _showPublicGroups,
                  onSelected: (value) {
                    setState(() => _showPublicGroups = true);
                    if (_discoverableGroups.isEmpty) _loadDiscoverableGroups();
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                ),
                const Spacer(),
                // ⭐ NUOVO: Bottone unisciti con codice
                TextButton.icon(
                  onPressed: _showJoinByCodeDialog,
                  icon: const Icon(Icons.vpn_key, size: 18),
                  label: Text(context.l10n.codeLabel),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
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
              Text(
                context.l10n.noGroups,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.createGroupCTA,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadMyGroups(forceServer: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myGroups.length,
        itemBuilder: (context, index) => _buildGroupCard(_myGroups[index], isMember: true),
      ),
    );
  }

  Widget _buildPublicGroupsList() {
    if (_isLoadingDiscoverable) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_discoverableGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.explore_outlined, size: 80, color: Colors.grey[300]),
              const SizedBox(height: 24),
              Text(
                context.l10n.noGroupsAvailable,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.noPublicGroupsCTA,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDiscoverableGroups,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _discoverableGroups.length,
        itemBuilder: (context, index) => _buildGroupCard(_discoverableGroups[index], isMember: false),
      ),
    );
  }

  Widget _buildGroupCard(Group group, {required bool isMember}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: businessCardShape(group),
      color: businessCardSurface(context, group),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isMember
            ? () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupDetailPage(groupId: group.id, groupName: group.name),
                  ),
                );
                // forceServer per intercettare upload logo / Business flag
                _loadMyGroups(forceServer: true);
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BusinessCoverHeader(group: group),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
            children: [
              // Avatar gruppo: logo Business o lettera iniziale
              _CommunityGroupAvatar(group: group),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            group.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (group.isBusinessGroup) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: groupAccentColor(group),
                          ),
                        ],
                      ],
                    ),
                    if (group.isBusinessGroup) ...[
                      const SizedBox(height: 4),
                      BusinessPill(group: group),
                    ],
                    if (group.description != null && group.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.textSecondary, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.people, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          context.l10n.memberCountPlural(group.memberCount),
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          group.isPublic ? Icons.public : group.isPrivate ? Icons.lock_open : Icons.lock,
                          size: 14, color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          group.isPublic ? context.l10n.publicLabel : group.isPrivate ? context.l10n.privateLabel : context.l10n.secretLabel,
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Bottone unisciti o freccia
              if (isMember)
                Icon(Icons.chevron_right, color: context.textMuted)
              else if (group.isPublic)
                ElevatedButton(
                  onPressed: () async {
                    final success = await _groupsRepo.joinGroup(group.id);
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.joinedGroupSnack(group.name)),
                          backgroundColor: AppColors.success,
                        ),
                      );
                      _loadMyGroups();
                      _loadDiscoverableGroups();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(context.l10n.joinGroupAction, style: const TextStyle(fontSize: 13)),
                )
              else if (group.isPrivate)
                ElevatedButton(
                  onPressed: () async {
                    final hasPending = await _groupsRepo.hasPendingRequest(group.id);
                    if (hasPending) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.requestAlreadySent),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                      return;
                    }
                    final success = await _groupsRepo.requestJoin(group.id);
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.requestSentSnack(group.name)),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(context.l10n.requestAction, style: const TextStyle(fontSize: 13)),
                ),
            ],
          ),
            ),
          ],
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
                label: Text(context.l10n.myFilterCount(_myEvents.length)),
                selected: !_showPublicEvents,
                onSelected: (value) {
                  setState(() => _showPublicEvents = false);
                },
                selectedColor: AppColors.primary.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(context.l10n.publicEventsFilter),
                selected: _showPublicEvents,
                onSelected: (value) {
                  setState(() => _showPublicEvents = true);
                  if (_publicEvents.isEmpty) _loadPublicEvents();
                },
                selectedColor: AppColors.primary.withValues(alpha: 0.2),
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
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                context.l10n.activeChallengesCount(_activeChallenges.length),
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
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.groupName,
                      style: const TextStyle(fontSize: 10, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.daysShort(item.challenge.endDate.difference(DateTime.now()).inDays),
                    style: TextStyle(fontSize: 11, color: context.textMuted),
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
              Text(
                context.l10n.noEventsScheduled,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.groupEventsWillAppear,
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
              Text(
                context.l10n.noPublicEvents,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.publicEventsWillAppear,
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
      color: isPast ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
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
                          : AppColors.primary.withValues(alpha: 0.1),
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
                          _monthName(context, event.date.month),
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
                      color: AppColors.primary.withValues(alpha: 0.1),
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
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        context.l10n.participating,
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
        Icon(icon, size: 14, color: context.textMuted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: context.textSecondary)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 4: FEED SEGUITI
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildFollowingTab() {
    if (_isLoadingFollowing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_userHasNoFollowing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.favorite_border,
                size: 80,
                color: context.textMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              const Text(
                'Non segui ancora nessuno',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Segui altri utenti per vedere le loro attività qui',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchUsersPage()),
                  );
                },
                icon: const Icon(Icons.person_search),
                label: const Text('Cerca utenti'),
              ),
            ],
          ),
        ),
      );
    }

    if (_followingTracks.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          _followingLoaded = false;
          await _loadFollowingFeed();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: _buildEmptyState(
                icon: Icons.inbox_outlined,
                message: 'Nessuna attività recente dai tuoi seguiti',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _followingLoaded = false;
        await _loadFollowingFeed();
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        itemCount: _followingTracks.length,
        itemBuilder: (context, index) {
          final track = _followingTracks[index];
          return FollowingFeedItem(
            track: track,
            authorAvatarUrl: _authorAvatars[track.ownerId],
            onTap: () => _openCommunityTrackDetail(track),
          );
        },
      ),
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

  String _monthName(BuildContext context, int month) {
    final months = [
      context.l10n.monthShortJan, context.l10n.monthShortFeb, context.l10n.monthShortMar,
      context.l10n.monthShortApr, context.l10n.monthShortMay, context.l10n.monthShortJun,
      context.l10n.monthShortJul, context.l10n.monthShortAug, context.l10n.monthShortSep,
      context.l10n.monthShortOct, context.l10n.monthShortNov, context.l10n.monthShortDec,
    ];
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, spreadRadius: 2)],
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
                    color: AppColors.success.withValues(alpha: 0.1),
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
                          Icon(Icons.person, size: 14, color: context.textMuted),
                          const SizedBox(width: 4),
                          Flexible(child: Text(track.ownerUsername, style: TextStyle(color: context.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          Icon(Icons.straighten, size: 14, color: context.textMuted),
                          const SizedBox(width: 4),
                          Text('${track.distanceKm.toStringAsFixed(1)} km', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: onClose, iconSize: 20),
                Icon(Icons.chevron_right, color: context.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicTourCard extends StatelessWidget {
  final Tour tour;
  final VoidCallback onTap;

  const _PublicTourCard({required this.tour, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hours = tour.totalDuration.inHours;
    final mins = tour.totalDuration.inMinutes % 60;
    final durStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.map, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tour.title,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tour.ownerName} · ${context.l10n.tourDays(tour.daysCount)} · ${context.l10n.tourStages(tour.trackIds.length)}',
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _chip(context, Icons.straighten, '${tour.totalDistanceKm.toStringAsFixed(1)} km'),
                  _chip(context, Icons.trending_up, '+${tour.totalElevationGain.toStringAsFixed(0)} m', AppColors.success),
                  if (tour.totalDuration.inMinutes > 0)
                    _chip(context, Icons.schedule, durStr),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String value, [Color? color]) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? context.textSecondary),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 13, color: color ?? context.textPrimary, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Avatar nella lista community gruppi: per i Business mostra il logo
/// se presente, altrimenti la lettera iniziale come prima.
class _CommunityGroupAvatar extends StatelessWidget {
  final Group group;

  const _CommunityGroupAvatar({required this.group});

  @override
  Widget build(BuildContext context) {
    final hasLogo = group.hasCustomLogo;
    debugPrint(
      '[CommunityGroupAvatar] ${group.name}: isBusiness=${group.isBusinessGroup} '
      'avatarUrl=${group.avatarUrl} hasLogo=$hasLogo',
    );
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: hasLogo
            ? null
            : LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.6),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: hasLogo ? Colors.white : null,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? CachedNetworkImage(
              imageUrl: group.avatarUrl!,
              fit: BoxFit.cover,
              placeholder: (_, _) => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              errorWidget: (_, _, _) => _initialFallback(group.name),
            )
          : _initialFallback(group.name),
    );
  }

  Widget _initialFallback(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'G',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
