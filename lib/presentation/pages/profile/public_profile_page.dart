import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/follow_repository.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../follow/follow_list_page.dart';
import '../discover/community_track_detail_page.dart';

/// Pagina profilo pubblico di un altro utente
class PublicProfilePage extends StatefulWidget {
  final String userId;
  final String? username; // opzionale, per mostrare subito

  const PublicProfilePage({
    super.key,
    required this.userId,
    this.username,
  });

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  final _firestore = FirebaseFirestore.instance;
  final _followRepo = FollowRepository();
  final _communityRepo = CommunityTracksRepository();

  bool _isLoading = true;
  String _username = 'Utente';
  String? _bio;
  String? _avatarUrl;
  int _level = 1;
  int _currentXp = 0;
  int _totalTracks = 0;
  double _totalDistance = 0;
  double _totalElevation = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  bool _isFollowing = false;
  bool _isTogglingFollow = false;
  bool _isOwnProfile = false;
  List<CommunityTrack> _communityTracks = [];

  @override
  void initState() {
    super.initState();
    _checkIfOwnProfile();
    _loadProfile();
    _loadCommunityTracks();
  }

  void _checkIfOwnProfile() {
    final currentUser = FirebaseAuth.instance.currentUser;
    _isOwnProfile = currentUser?.uid == widget.userId;
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      // Carica profilo utente
      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(widget.userId)
          .get();

      if (profileDoc.exists) {
        final data = profileDoc.data()!;
        _username = data['username'] ?? data['displayName'] ?? widget.username ?? 'Utente';
        _bio = data['bio'] as String?;
        _avatarUrl = data['avatarUrl'] ?? data['photoURL'];
        _level = (data['level'] as num?)?.toInt() ?? 1;
        _currentXp = (data['xp'] as num?)?.toInt() ?? 0;

        final followers = data['followers'] as List?;
        final following = data['following'] as List?;
        _followersCount = followers?.length ?? 0;
        _followingCount = following?.length ?? 0;
      } else {
        _username = widget.username ?? 'Utente';
      }

      // Carica stats tracce
      final tracksSnapshot = await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('tracks')
          .get();

      _totalTracks = tracksSnapshot.docs.length;
      _totalDistance = 0;
      _totalElevation = 0;

      for (final doc in tracksSnapshot.docs) {
        final data = doc.data();
        _totalDistance += (data['distance'] as num?)?.toDouble() ?? 0;
        _totalElevation += (data['elevationGain'] as num?)?.toDouble() ?? 0;
      }

      // Verifica se lo seguo
      if (!_isOwnProfile) {
        _isFollowing = await _followRepo.isFollowing(widget.userId);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('[PublicProfile] Errore caricamento: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCommunityTracks() async {
    try {
      final tracks = await _communityRepo.getTracksByUser(widget.userId, limit: 10);
      if (mounted) {
        setState(() => _communityTracks = tracks);
      }
    } catch (e) {
      print('[PublicProfile] Errore caricamento tracce: $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (_isOwnProfile || _isTogglingFollow) return;

    setState(() => _isTogglingFollow = true);

    final result = await _followRepo.toggleFollow(widget.userId);

    if (mounted) {
      setState(() {
        _isTogglingFollow = false;
        if (result.success) {
          _isFollowing = result.isNowFollowing == true;
          _followersCount += result.isNowFollowing == true ? 1 : -1;
        }
      });

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? ''),
            backgroundColor: result.isNowFollowing == true ? AppColors.success : null,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Errore'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_username),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Avatar
                    _buildAvatar(),
                    const SizedBox(height: 16),

                    // Username
                    Text(
                      _username,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Bio
                    if (_bio != null && _bio!.isNotEmpty) ...[
                      Text(
                        _bio!,
                        style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Tasto Segui
                    if (!_isOwnProfile) ...[
                      _buildFollowButton(),
                      const SizedBox(height: 24),
                    ],

                    // XP Bar
                    _buildXpSection(),
                    const SizedBox(height: 24),

                    // Stats Grid
                    _buildStatsGrid(),
                    const SizedBox(height: 24),

                    // Tracce Community
                    if (_communityTracks.isNotEmpty) ...[
                      _buildCommunityTracksSection(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAvatar() {
    return Stack(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: AppColors.primary.withOpacity(0.1),
          backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
          child: _avatarUrl == null
              ? Text(
                  _username.isNotEmpty ? _username[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                )
              : null,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.warning,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text(
              '$_level',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFollowButton() {
    return SizedBox(
      width: 200,
      child: ElevatedButton.icon(
        onPressed: _isTogglingFollow ? null : _toggleFollow,
        icon: _isTogglingFollow
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(_isFollowing ? Icons.person_remove : Icons.person_add),
        label: Text(_isFollowing ? 'Smetti di seguire' : 'Segui'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isFollowing ? Colors.grey[600] : AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
    );
  }

  Widget _buildXpSection() {
    final xpForNextLevel = (1000 * (_level * 1.5)).toInt();
    final progress = _currentXp / xpForNextLevel;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.star, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Livello $_level',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              Text(
                '$_currentXp / $xpForNextLevel XP',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildStatItem('Tracce', '$_totalTracks')),
              Expanded(
                child: _buildStatItem(
                  'Distanza',
                  '${(_totalDistance / 1000).toStringAsFixed(1)} km',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Dislivello',
                  '${_totalElevation.toStringAsFixed(0)} m',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openFollowList(FollowListType.followers),
                  child: _buildStatItem('Follower', '$_followersCount'),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _openFollowList(FollowListType.following),
                  child: _buildStatItem('Seguiti', '$_followingCount'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityTracksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tracce condivise',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._communityTracks.map((track) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: const Icon(Icons.route, color: AppColors.primary),
            ),
            title: Text(
              track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${(track.distance / 1000).toStringAsFixed(1)} km • +${track.elevationGain.toStringAsFixed(0)} m',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityTrackDetailPage(track: track),
                ),
              );
            },
          ),
        )),
      ],
    );
  }

  void _openFollowList(FollowListType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowListPage(
          userId: widget.userId,
          username: _username,
          listType: type,
        ),
      ),
    );
  }
}