import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../widgets/cheer_button.dart';

/// Card per traccia pubblica con bottone Cheer
/// 
/// Esempio di come usare CheerButton in una lista di tracce
class PublicTrackCard extends StatelessWidget {
  final String trackId;
  final String name;
  final String authorName;
  final String? authorAvatarUrl;
  final double distanceKm;
  final double elevationGain;
  final String activityType;
  final int cheersCount;
  final bool hasCheered;
  final VoidCallback? onTap;
  final VoidCallback? onAuthorTap;

  const PublicTrackCard({
    super.key,
    required this.trackId,
    required this.name,
    required this.authorName,
    this.authorAvatarUrl,
    required this.distanceKm,
    required this.elevationGain,
    required this.activityType,
    this.cheersCount = 0,
    this.hasCheered = false,
    this.onTap,
    this.onAuthorTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Autore
              Row(
                children: [
                  GestureDetector(
                    onTap: onAuthorTap,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      backgroundImage: authorAvatarUrl != null 
                          ? NetworkImage(authorAvatarUrl!) 
                          : null,
                      child: authorAvatarUrl == null
                          ? Text(
                              authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: onAuthorTap,
                      child: Text(
                        authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  // Icona attività
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getActivityColor(activityType).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getActivityEmoji(activityType),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Nome traccia
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 12),
              
              // Stats + Cheer
              Row(
                children: [
                  // Distanza
                  _StatChip(
                    icon: Icons.straighten,
                    value: '${distanceKm.toStringAsFixed(1)} km',
                  ),
                  const SizedBox(width: 12),
                  
                  // Dislivello
                  _StatChip(
                    icon: Icons.trending_up,
                    value: '+${elevationGain.toStringAsFixed(0)} m',
                    color: AppColors.success,
                  ),
                  
                  const Spacer(),
                  
                  // 🔥 CHEER BUTTON
                  CheerButton(
                    trackId: trackId,
                    initialCount: cheersCount,
                    initialHasCheered: hasCheered,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getActivityEmoji(String type) {
    switch (type.toLowerCase()) {
      case 'trekking':
      case 'hiking':
        return '🥾';
      case 'cycling':
      case 'bike':
        return '🚴';
      case 'trailrunning':
      case 'run':
        return '🏃';
      case 'walking':
        return '🚶';
      default:
        return '🥾';
    }
  }

  Color _getActivityColor(String type) {
    switch (type.toLowerCase()) {
      case 'trekking':
      case 'hiking':
        return AppColors.success;
      case 'cycling':
      case 'bike':
        return AppColors.info;
      case 'trailrunning':
      case 'run':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;

  const _StatChip({
    required this.icon,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.textMuted),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: color ?? AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
