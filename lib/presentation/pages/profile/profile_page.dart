import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/follow_repository.dart';
import '../dashboard/dashboard_page.dart';
import '../wishlist/wishlist_page.dart';
import '../follow/follow_list_page.dart';
import '../leaderboard/leaderboard_page.dart';
import '../settings/settings_page.dart';
import '../badges/badges_page.dart';
import '../challenges/challenges_page.dart';
import '../groups/groups_list_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FollowRepository _followRepo = FollowRepository();
  
  // Profile data
  String? _username;
  String? _bio;
  String? _avatarUrl;
  int _level = 1;
  int _currentXp = 0;
  int _xpForNextLevel = 1000;
  
  // Stats
  int _totalTracks = 0;
  double _totalDistance = 0;
  double _totalElevation = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  
  // UI state
  bool _isLoading = true;
  bool _isEditingUsername = false;
  bool _isEditingBio = false;
  
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Carica profilo utente
      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();

      if (profileDoc.exists) {
        final data = profileDoc.data()!;
        _username = data['username'] as String?;
        _bio = data['bio'] as String?;
        _avatarUrl = data['avatarUrl'] as String?;
        _level = (data['level'] as num?)?.toInt() ?? 1;
        _currentXp = (data['xp'] as num?)?.toInt() ?? 0;
        
        // Conta followers e following dagli array
        final followers = data['followers'] as List?;
        final following = data['following'] as List?;
        _followersCount = followers?.length ?? 0;
        _followingCount = following?.length ?? 0;
      }

      // Calcola XP per prossimo livello
      _xpForNextLevel = _calculateXpForLevel(_level + 1);

      // Carica stats dalle tracce
      final tracksSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
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

      // Fallback username
      _username ??= user.displayName ?? user.email?.split('@').first ?? 'Utente';
      _avatarUrl ??= user.photoURL;
      
      _usernameController.text = _username ?? '';
      _bioController.text = _bio ?? '';

      setState(() => _isLoading = false);
    } catch (e) {
      print('[ProfilePage] Errore caricamento: $e');
      setState(() => _isLoading = false);
    }
  }

  int _calculateXpForLevel(int level) {
    // Formula: 1000 * level^1.5
    return (1000 * (level * 1.5)).toInt();
  }

  Future<void> _saveUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final newUsername = _usernameController.text.trim();
    if (newUsername.isEmpty) return;

    try {
      await _firestore.collection('user_profiles').doc(user.uid).set({
        'username': newUsername,
      }, SetOptions(merge: true));

      setState(() {
        _username = newUsername;
        _isEditingUsername = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username aggiornato!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _saveBio() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final newBio = _bioController.text.trim();

    try {
      await _firestore.collection('user_profiles').doc(user.uid).set({
        'bio': newBio,
      }, SetOptions(merge: true));

      setState(() {
        _bio = newBio.isEmpty ? null : newBio;
        _isEditingBio = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bio aggiornata!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Esci'),
        content: const Text('Vuoi uscire dal tuo account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Esci'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  void _openFollowersList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowListPage(
          userId: user.uid,
          username: _username ?? 'Utente',
          listType: FollowListType.followers,
        ),
      ),
    );
  }

  void _openFollowingList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowListPage(
          userId: user.uid,
          username: _username ?? 'Utente',
          listType: FollowListType.following,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilo'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          if (user != null)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          if (user != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _signOut,
            ),
        ],
      ),
      body: user == null
          ? _buildLoginPrompt()
          : _isLoading
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
                        _buildUsernameSection(),
                        const SizedBox(height: 4),

                        // Email
                        Text(
                          user.email ?? '',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 16),

                        // Bio
                        _buildBioSection(),
                        const SizedBox(height: 24),

                        // XP Bar
                        _buildXpSection(),
                        const SizedBox(height: 24),

                        // Stats Grid
                        _buildStatsGrid(),
                        const SizedBox(height: 24),

                        // Contatti Button
                        _buildContactsButton(),
                        const SizedBox(height: 12),

                        // Gruppi Button
                        _buildGroupsButton(),
                        const SizedBox(height: 12),

                        // Dashboard Button
                        _buildDashboardButton(),
                        const SizedBox(height: 12),

                        // Wishlist Button
                        _buildWishlistButton(),
                        const SizedBox(height: 32),

                        // Leaderboard Button
                        _buildLeaderboardButton(),
                        const SizedBox(height: 32),

                        // Badges Button
                        _buildBadgesButton(),
                        const SizedBox(height: 32),

                        // Challenges Button  <-- AGGIUNGI QUESTO
                        _buildChallengesButton(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            const Text(
              'Accedi per vedere il tuo profilo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Salva le tue tracce, segui altri escursionisti e molto altro.',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
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
                  _username?.isNotEmpty == true ? _username![0].toUpperCase() : '?',
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

  Widget _buildUsernameSection() {
    if (_isEditingUsername) {
      return Column(
        children: [
          TextField(
            controller: _usernameController,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              hintText: 'Username',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() => _isEditingUsername = false),
                child: const Text('Annulla'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saveUsername,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                child: const Text('Salva'),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        Text(
          _username ?? 'Utente',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
        TextButton(
          onPressed: () => setState(() => _isEditingUsername = true),
          child: const Text('Modifica nickname', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildBioSection() {
    if (_isEditingBio) {
      return Column(
        children: [
          TextField(
            controller: _bioController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Racconta qualcosa di te...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() => _isEditingBio = false),
                child: const Text('Annulla'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saveBio,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                child: const Text('Salva'),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        if (_bio != null && _bio!.isNotEmpty)
          Text(
            _bio!,
            style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        TextButton(
          onPressed: () => setState(() => _isEditingBio = true),
          child: Text(
            _bio == null || _bio!.isEmpty ? 'Aggiungi una bio' : 'Modifica bio',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildXpSection() {
    final progress = _currentXp / _xpForNextLevel;

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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
              Text(
                '$_currentXp / $_xpForNextLevel XP',
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
          // Prima riga: Tracce, Distanza, Dislivello
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: 'Tracce',
                  value: '$_totalTracks',
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: 'Distanza',
                  value: '${(_totalDistance / 1000).toStringAsFixed(1)} km',
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: 'Dislivello',
                  value: '${_totalElevation.toStringAsFixed(0)} m',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Seconda riga: Follower, Following (cliccabili)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _openFollowersList,
                  child: _StatItem(
                    label: 'Follower',
                    value: '$_followersCount',
                    isClickable: true,
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _openFollowingList,
                  child: _StatItem(
                    label: 'Following',
                    value: '$_followingCount',
                    isClickable: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactsButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _openFollowingList,
        icon: const Icon(Icons.people),
        label: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('I miei contatti'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_followersCount follower · $_followingCount seguiti',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary.withOpacity(0.8),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildGroupsButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GroupsListPage()),
          );
        },
        icon: const Icon(Icons.groups),
        label: const Text('I miei Gruppi'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary.withOpacity(0.9),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildDashboardButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
          );
        },
        icon: const Icon(Icons.bar_chart),
        label: const Text('Vedi Dashboard'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildWishlistButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WishlistPage()),
          );
        },
        icon: const Icon(Icons.bookmark_outline),
        label: const Text('Percorsi Salvati'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildLeaderboardButton() {
    return SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => LeaderboardPage()),
        );
      },
      icon: const Icon(Icons.leaderboard),
      label: const Text('Classifica Settimanale'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.warning,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
          side: const BorderSide(color: AppColors.warning),
        ),
      ),
    );
  }

  Widget _buildBadgesButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BadgesPage()),
          );
        },
        icon: const Icon(Icons.emoji_events_outlined),
        label: const Text('I Miei Badge'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.success,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: AppColors.success),
        ),
      ),
    );
  }
  Widget _buildChallengesButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChallengesPage()),
          );
        },
        icon: const Icon(Icons.emoji_events),
        label: const Text('Sfide'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: AppColors.danger),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final bool isClickable;

  const _StatItem({
    required this.label,
    required this.value,
    this.isClickable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: isClickable
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.transparent,
            )
          : null,
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    maxLines: 1,
                  ),
                ),
              ),
              if (isClickable) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
