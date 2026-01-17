import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/follow_repository.dart';

/// Bottone Follow/Unfollow per profili utente
class FollowButton extends StatefulWidget {
  final String targetUserId;
  final bool initialIsFollowing;
  final VoidCallback? onFollowChanged;
  final bool compact;

  const FollowButton({
    super.key,
    required this.targetUserId,
    this.initialIsFollowing = false,
    this.onFollowChanged,
    this.compact = false,
  });

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  final FollowRepository _repository = FollowRepository();
  
  late bool _isFollowing;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.initialIsFollowing;
    _checkFollowStatus();
  }

  Future<void> _checkFollowStatus() async {
    final isFollowing = await _repository.isFollowing(widget.targetUserId);
    if (mounted) {
      setState(() => _isFollowing = isFollowing);
    }
  }

  Future<void> _toggleFollow() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    final result = await _repository.toggleFollow(widget.targetUserId);

    if (result.success && mounted) {
      setState(() => _isFollowing = result.isNowFollowing ?? false);
      widget.onFollowChanged?.call();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? ''),
          backgroundColor: _isFollowing ? AppColors.success : null,
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (!result.success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Errore'),
          backgroundColor: AppColors.danger,
        ),
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompactButton();
    }
    return _buildFullButton();
  }

  Widget _buildFullButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _toggleFollow,
      style: ElevatedButton.styleFrom(
        backgroundColor: _isFollowing ? Colors.grey[200] : AppColors.primary,
        foregroundColor: _isFollowing ? AppColors.textPrimary : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
        ),
      ),
      child: _isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _isFollowing ? AppColors.textPrimary : Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isFollowing ? Icons.check : Icons.person_add,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  _isFollowing ? 'Segui già' : 'Segui',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
    );
  }

  Widget _buildCompactButton() {
    return OutlinedButton(
      onPressed: _isLoading ? null : _toggleFollow,
      style: OutlinedButton.styleFrom(
        backgroundColor: _isFollowing ? AppColors.primary.withOpacity(0.1) : null,
        foregroundColor: _isFollowing ? AppColors.primary : AppColors.textSecondary,
        side: BorderSide(
          color: _isFollowing ? AppColors.primary : AppColors.textMuted,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              _isFollowing ? 'Segui già' : 'Segui',
              style: const TextStyle(fontSize: 12),
            ),
    );
  }
}

/// Widget per mostrare contatori Followers/Following cliccabili
class FollowCountsWidget extends StatelessWidget {
  final int followersCount;
  final int followingCount;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;

  const FollowCountsWidget({
    super.key,
    required this.followersCount,
    required this.followingCount,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildCountItem(
          count: followersCount,
          label: 'Follower',
          onTap: onFollowersTap,
        ),
        Container(
          height: 30,
          width: 1,
          color: AppColors.textMuted.withOpacity(0.3),
          margin: const EdgeInsets.symmetric(horizontal: 24),
        ),
        _buildCountItem(
          count: followingCount,
          label: 'Seguiti',
          onTap: onFollowingTap,
        ),
      ],
    );
  }

  Widget _buildCountItem({
    required int count,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            _formatCount(count),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}
