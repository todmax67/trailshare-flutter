import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../dashboard/dashboard_page.dart';
import '../wishlist/wishlist_page.dart';
import '../follow/follow_list_page.dart';
import '../leaderboard/leaderboard_page.dart';
import '../leaderboard/regional_leaderboard_page.dart';
import '../mountain_finder/saved_peaks_page.dart';
import '../../../data/repositories/saved_peaks_repository.dart';
import '../../../data/models/mountain_peak.dart';
import '../settings/settings_page.dart';
import '../badges/badges_page.dart';
import '../challenges/challenges_page.dart';
import '../groups/groups_list_page.dart';
import '../../../data/repositories/admin_repository.dart';
import '../admin/admin_panel_page.dart';
import '../../../core/extensions/theme_colors_extension.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
  bool _isAdminUser = false;

  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadAdminStatus();
  }

  Future<void> _loadAdminStatus() async {
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    if (mounted) setState(() => _isAdminUser = isAdmin);
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
      _username ??= user.displayName ?? user.email?.split('@').first;
      _avatarUrl ??= user.photoURL;
      
      _usernameController.text = _username ?? '';
      _bioController.text = _bio ?? '';

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[ProfilePage] Errore caricamento: $e');
      if (mounted) setState(() => _isLoading = false);
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
          SnackBar(content: Text(context.l10n.usernameUpdated), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorWithDetails(e.toString())), backgroundColor: AppColors.danger),
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
          SnackBar(content: Text(context.l10n.bioUpdated), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorWithDetails(e.toString())), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.logout),
        content: Text(context.l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.logout),
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
          username: _username ?? context.l10n.defaultUser,
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
          username: _username ?? context.l10n.defaultUser,
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
        title: Text(context.l10n.profile),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: context.textPrimary,
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
                          style: TextStyle(color: context.textMuted),
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
                        const SizedBox(height: 32),

                        // ═══ SEZIONE: La mia attività ═══
                        _buildSectionHeader(context.l10n.sectionMyActivity),
                        _buildTilesSection([
                          _buildActionTile(
                            icon: Icons.bar_chart,
                            label: context.l10n.viewDashboard,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const DashboardPage()),
                            ),
                          ),
                          _buildActionTile(
                            icon: Icons.bookmark_outline,
                            label: context.l10n.savedRoutes,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const WishlistPage()),
                            ),
                          ),
                        ]),

                        // ═══ SEZIONE: Community ═══
                        _buildSectionHeader(context.l10n.sectionCommunity),
                        _buildTilesSection([
                          _buildActionTile(
                            icon: Icons.people_outline,
                            label: context.l10n.myContacts,
                            trailing: _buildContactsBadge(),
                            onTap: _openFollowingList,
                          ),
                          _buildActionTile(
                            icon: Icons.groups_outlined,
                            label: context.l10n.myGroups,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const GroupsListPage()),
                            ),
                          ),
                          _buildActionTile(
                            icon: Icons.leaderboard_outlined,
                            label: context.l10n.weeklyLeaderboard,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => LeaderboardPage()),
                            ),
                          ),
                          _buildActionTile(
                            icon: Icons.flag_circle_outlined,
                            label: context.l10n.regionalLeaderboardTitle,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RegionalLeaderboardPage(),
                              ),
                            ),
                          ),
                        ]),

                        // ═══ SEZIONE: Progressi ═══
                        _buildSectionHeader(context.l10n.sectionProgress),
                        _buildTilesSection([
                          _buildActionTile(
                            icon: Icons.emoji_events_outlined,
                            label: context.l10n.myBadges,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const BadgesPage()),
                            ),
                          ),
                          _buildActionTile(
                            icon: Icons.terrain,
                            label: context.l10n.savedPeaksTitle,
                            trailing: _buildSavedPeaksBadge(),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SavedPeaksPage(),
                              ),
                            ),
                          ),
                          _buildActionTile(
                            icon: Icons.flag_outlined,
                            label: context.l10n.challenges,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ChallengesPage()),
                            ),
                          ),
                        ]),

                        // ═══ SEZIONE: Amministrazione (solo admin) ═══
                        if (_isAdminUser) ...[
                          _buildSectionHeader(context.l10n.sectionAdmin),
                          _buildTilesSection([
                            _buildActionTile(
                              icon: Icons.admin_panel_settings_outlined,
                              label: context.l10n.adminPanel,
                              iconColor: Colors.amber.shade700,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AdminPanelPage()),
                              ),
                            ),
                          ]),
                        ],
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
            Text(
              context.l10n.loginToSeeProfile,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.loginProfileDescription,
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
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
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
            decoration: InputDecoration(
              hintText: context.l10n.username,
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
                child: Text(context.l10n.cancel),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saveUsername,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                child: Text(context.l10n.save),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        Text(
          _username ?? context.l10n.defaultUser,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
        TextButton(
          onPressed: () => setState(() => _isEditingUsername = true),
          child: Text(context.l10n.editNickname, style: const TextStyle(fontSize: 12)),
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
            decoration: InputDecoration(
              hintText: context.l10n.bioHint,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() => _isEditingBio = false),
                child: Text(context.l10n.cancel),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saveBio,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                child: Text(context.l10n.save),
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
            style: TextStyle(fontStyle: FontStyle.italic, color: context.textSecondary),
            textAlign: TextAlign.center,
          ),
        TextButton(
          onPressed: () => setState(() => _isEditingBio = true),
          child: Text(
            _bio == null || _bio!.isEmpty ? context.l10n.addBio : context.l10n.editBio,
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
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
                    context.l10n.levelNumber(_level),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
              Text(
                '$_currentXp / $_xpForNextLevel XP',
                style: TextStyle(color: context.textMuted, fontSize: 13),
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
                  label: context.l10n.tracks,
                  value: '$_totalTracks',
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: context.l10n.distance,
                  value: '${(_totalDistance / 1000).toStringAsFixed(1)} km',
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: context.l10n.elevation,
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
                    label: context.l10n.followers,
                    value: '$_followersCount',
                    isClickable: true,
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _openFollowingList,
                  child: _StatItem(
                    label: context.l10n.following,
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

  // ═══════════════════════════════════════════════════════════════════════
  // ACTIONS — iOS-style grouped list (Opzione B audit UX)
  // ═══════════════════════════════════════════════════════════════════════

  /// Etichetta UPPERCASE piccola sopra una sezione di tile.
  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.textMuted,
        ),
      ),
    );
  }

  /// Container che raggruppa una serie di tile come un "gruppo" stile iOS
  /// Settings, con bordo sottile arrotondato e divider interni.
  Widget _buildTilesSection(List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.themedBorder, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i < tiles.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Divider(height: 1, thickness: 0.5, color: context.themedBorder),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Singolo tile riga: icona in contenitore tenue + label + trailing opzionale + chevron.
  Widget _buildActionTile({
    required IconData icon,
    required String label,
    Widget? trailing,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final color = iconColor ?? AppColors.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
              if (trailing != null) ...[
                trailing,
                const SizedBox(width: 6),
              ],
              Icon(Icons.chevron_right, color: context.textMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  /// Badge trailing per "I miei contatti": "follower · seguiti" in pill compatta.
  Widget _buildContactsBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$_followersCount · $_followingCount',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  /// Badge inline col conteggio delle cime salvate. StreamBuilder
  /// realtime così si aggiorna se l'utente salva/rimuove una cima
  /// senza dover refreshare il profilo.
  Widget _buildSavedPeaksBadge() {
    return StreamBuilder<List<MountainPeak>>(
      stream: SavedPeaksRepository().watchAll(),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
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
            style: TextStyle(fontSize: 12, color: context.textMuted),
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
