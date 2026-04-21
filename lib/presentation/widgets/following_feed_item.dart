import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/community_tracks_repository.dart';
import 'community_track_card.dart';
import '../../core/extensions/theme_colors_extension.dart';

/// Item del feed "Seguiti": header utente con avatar/username/data relativa
/// + `CommunityTrackCard` sottostante.
///
/// ```dart
/// FollowingFeedItem(
///   track: track,
///   authorAvatarUrl: avatars[track.ownerId],
///   onTap: () => openDetail(track),
/// )
/// ```
class FollowingFeedItem extends StatelessWidget {
  final CommunityTrack track;
  final String? authorAvatarUrl;
  final VoidCallback onTap;

  const FollowingFeedItem({
    super.key,
    required this.track,
    this.authorAvatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 6),
          CommunityTrackCard(
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
            onTap: onTap,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            backgroundImage: (authorAvatarUrl != null && authorAvatarUrl!.isNotEmpty)
                ? NetworkImage(authorAvatarUrl!)
                : null,
            child: (authorAvatarUrl == null || authorAvatarUrl!.isEmpty)
                ? Text(
                    track.ownerUsername.isNotEmpty
                        ? track.ownerUsername[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.ownerUsername,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (track.sharedAt != null)
                  Text(
                    _relativeDate(track.sharedAt!),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            track.activityIcon,
            style: const TextStyle(fontSize: 20),
          ),
        ],
      ),
    );
  }

  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} h fa';
    if (diff.inDays < 7) return '${diff.inDays} g fa';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} sett fa';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} mesi fa';
    return '${(diff.inDays / 365).floor()} anni fa';
  }
}
