import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/gamification_service.dart';

/// Dialog mostrato quando l'utente sale di livello
class LevelUpDialog extends StatefulWidget {
  final int newLevel;
  final String levelName;
  final int totalXp;

  const LevelUpDialog({
    super.key,
    required this.newLevel,
    required this.levelName,
    required this.totalXp,
  });

  @override
  State<LevelUpDialog> createState() => _LevelUpDialogState();
}

class _LevelUpDialogState extends State<LevelUpDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _rotationAnimation = Tween<double>(begin: -0.1, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Transform.rotate(
              angle: _rotationAnimation.value,
              child: child,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary,
                AppColors.primary.withOpacity(0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _AnimatedStars(),
              
              const Text(
                '🎉 LEVEL UP! 🎉',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${widget.newLevel}',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        'LVL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                widget.levelName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                '${widget.totalXp} XP totali',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: const Text(
                  'Continua',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedStars extends StatefulWidget {
  const _AnimatedStars();

  @override
  State<_AnimatedStars> createState() => _AnimatedStarsState();
}

class _AnimatedStarsState extends State<_AnimatedStars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final delay = index * 0.2;
              final value = ((_controller.value + delay) % 1.0);
              final opacity = (1 - (value - 0.5).abs() * 2).clamp(0.3, 1.0);
              final scale = 0.5 + value * 0.5;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: const Text('⭐', style: TextStyle(fontSize: 20)),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class XpGainedSnackBar {
  static void show(BuildContext context, int xpGained, String reason) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'XP',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('+$xpGained XP'),
            const Spacer(),
            Text(
              _getReasonText(reason),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static String _getReasonText(String reason) {
    switch (reason) {
      case 'track_completed':
        return 'Traccia completata';
      case 'cheers_received':
        return 'Cheers ricevuto';
      case 'new_follower':
        return 'Nuovo follower';
      case 'track_published':
        return 'Traccia pubblicata';
      default:
        return '';
    }
  }
}

Future<void> showLevelUpDialog(
  BuildContext context, {
  required int newLevel,
  required int totalXp,
}) async {
  final gamification = GamificationService();
  final levelInfo = gamification.calculateLevelInfo(totalXp);

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => LevelUpDialog(
      newLevel: newLevel,
      levelName: levelInfo.levelName,
      totalXp: totalXp,
    ),
  );
}

Future<void> showBadgeUnlockedDialog(
  BuildContext context,
  GameBadge badge,
) async {
  HapticFeedback.mediumImpact();

  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎊', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          const Text(
            'Nuovo Badge!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(badge.icon, style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                Text(
                  badge.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  badge.description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fantastico!'),
        ),
      ],
    ),
  );
}
