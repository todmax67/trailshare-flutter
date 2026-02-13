import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/follow_repository.dart';
import '../../widgets/follow_button.dart';
import '../profile/public_profile_page.dart';

/// Pagina che mostra lista Followers o Following
class FollowListPage extends StatefulWidget {
  final String userId;
  final String username;
  final FollowListType listType;

  const FollowListPage({
    super.key,
    required this.userId,
    required this.username,
    required this.listType,
  });

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage> {
  final FollowRepository _repository = FollowRepository();

  List<UserProfile> _profiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);

    final profiles = widget.listType == FollowListType.followers
        ? await _repository.getFollowersWithProfiles(widget.userId)
        : await _repository.getFollowingWithProfiles(widget.userId);

    if (mounted) {
      setState(() {
        _profiles = profiles;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.listType == FollowListType.followers
        ? 'Follower di ${widget.username}'
        : 'Seguiti da ${widget.username}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_profiles.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadProfiles,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _profiles.length,
        itemBuilder: (context, index) {
          final profile = _profiles[index];
          return _UserListItem(
            profile: profile,
            onTap: () => _openProfile(profile),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFollowers = widget.listType == FollowListType.followers;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isFollowers ? Icons.people_outline : Icons.person_add_outlined,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 24),
            Text(
              isFollowers ? 'Nessun follower ancora' : 'Non segue nessuno',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isFollowers
                  ? 'Condividi le tue escursioni per farti conoscere!'
                  : 'Esplora la community per trovare persone interessanti.',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _openProfile(UserProfile profile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfilePage(
          userId: profile.id,
          username: profile.username,
        ),
      ),
    );
  }
}

/// Tipo di lista
enum FollowListType { followers, following }

/// Item nella lista utenti
class _UserListItem extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback? onTap;

  const _UserListItem({
    required this.profile,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isCurrentUser = currentUserId == profile.id;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primary.withOpacity(0.1),
        backgroundImage: profile.avatarUrl != null
            ? NetworkImage(profile.avatarUrl!)
            : null,
        child: profile.avatarUrl == null
            ? Text(
                profile.initial,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              )
            : null,
      ),
      title: Text(
        profile.username,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: profile.bio != null
          ? Text(
              profile.bio!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            )
          : Text(
              'Livello ${profile.level}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
      trailing: isCurrentUser
          ? null
          : FollowButton(
              targetUserId: profile.id,
              compact: true,
            ),
    );
  }
}
