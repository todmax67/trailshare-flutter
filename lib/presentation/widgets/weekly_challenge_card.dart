import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/l10n_extension.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../core/services/weekly_challenges_service.dart';
import '../../data/models/weekly_challenge.dart';
import 'stat_number.dart';

/// Card che mostra la sfida settimanale corrente dell'utente in cima alla
/// Dashboard. Si auto-carica al build ed entra in stato "empty" se nessuna
/// sfida è attiva (utente non loggato, errore Firestore, ecc.).
class WeeklyChallengeCard extends StatefulWidget {
  const WeeklyChallengeCard({super.key});

  @override
  State<WeeklyChallengeCard> createState() => _WeeklyChallengeCardState();
}

class _WeeklyChallengeCardState extends State<WeeklyChallengeCard> {
  WeeklyChallenge? _challenge;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = await WeeklyChallengesService().ensureCurrent();
    if (!mounted) return;
    setState(() {
      _challenge = c;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final c = _challenge;
    if (c == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final accent = _accentForType(c.type);
    final (icon, title, progressText, remainingText) = _labels(context, c);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.14),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.weeklyChallengeTitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (c.isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        context.l10n.weeklyChallengeCompleted,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatNumber.large(
                progressText,
                color: accent,
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '/ ${_targetText(context, c)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (!c.isCompleted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    remainingText,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: c.progressRatio,
              minHeight: 8,
              backgroundColor: accent.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }

  Color _accentForType(WeeklyChallengeType t) {
    switch (t) {
      case WeeklyChallengeType.distance:
        return const Color(0xFF1976D2);
      case WeeklyChallengeType.elevation:
        return AppColors.success;
      case WeeklyChallengeType.tracks:
        return AppColors.primary;
      case WeeklyChallengeType.duration:
        return AppColors.warning;
    }
  }

  (IconData, String, String, String) _labels(
    BuildContext context,
    WeeklyChallenge c,
  ) {
    switch (c.type) {
      case WeeklyChallengeType.distance:
        final targetKm = c.target / 1000;
        final progKm = c.progress / 1000;
        return (
          Icons.straighten,
          context.l10n.weeklyChallengeDistanceTitle(targetKm.toStringAsFixed(targetKm.truncateToDouble() == targetKm ? 0 : 1)),
          progKm.toStringAsFixed(1),
          context.l10n.weeklyChallengeRemaining(
            ((c.target - c.progress) / 1000).clamp(0, double.infinity).toStringAsFixed(1),
            'km',
          ),
        );
      case WeeklyChallengeType.elevation:
        return (
          Icons.trending_up,
          context.l10n.weeklyChallengeElevationTitle(c.target.toStringAsFixed(0)),
          c.progress.toStringAsFixed(0),
          context.l10n.weeklyChallengeRemaining(
            (c.target - c.progress).clamp(0, double.infinity).toStringAsFixed(0),
            'm',
          ),
        );
      case WeeklyChallengeType.tracks:
        return (
          Icons.route,
          context.l10n.weeklyChallengeTracksTitle(c.target.toInt()),
          c.progress.toInt().toString(),
          context.l10n.weeklyChallengeTracksRemaining(
            (c.target - c.progress).clamp(0, double.infinity).toInt(),
          ),
        );
      case WeeklyChallengeType.duration:
        final targetHours = c.target / 3600;
        final progHours = c.progress / 3600;
        return (
          Icons.schedule,
          context.l10n.weeklyChallengeDurationTitle(targetHours.toStringAsFixed(targetHours.truncateToDouble() == targetHours ? 0 : 1)),
          progHours.toStringAsFixed(1),
          context.l10n.weeklyChallengeRemaining(
            ((c.target - c.progress) / 3600).clamp(0, double.infinity).toStringAsFixed(1),
            'h',
          ),
        );
    }
  }

  String _targetText(BuildContext context, WeeklyChallenge c) {
    switch (c.type) {
      case WeeklyChallengeType.distance:
        final km = c.target / 1000;
        return '${km.toStringAsFixed(km.truncateToDouble() == km ? 0 : 1)} km';
      case WeeklyChallengeType.elevation:
        return '${c.target.toStringAsFixed(0)} m';
      case WeeklyChallengeType.tracks:
        return '${c.target.toInt()}';
      case WeeklyChallengeType.duration:
        final h = c.target / 3600;
        return '${h.toStringAsFixed(h.truncateToDouble() == h ? 0 : 1)} h';
    }
  }
}
