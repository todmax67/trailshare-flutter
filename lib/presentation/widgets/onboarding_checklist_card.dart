import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/onboarding_checklist_service.dart';
import '../../core/extensions/l10n_extension.dart';

/// Card "primi passi" sull'home: guida il nuovo utente alle azioni che lo
/// rendono attivo. I task si spuntano da soli (vedi OnboardingChecklistService)
/// e la card sparisce a obiettivo raggiunto o quando l'utente la chiude.
class OnboardingChecklistCard extends StatelessWidget {
  final OnboardingChecklistState state;
  final VoidCallback onRecord;
  final VoidCallback onExplore;
  final VoidCallback onFavorite;
  final VoidCallback onProfile;
  final VoidCallback onDismiss;

  const OnboardingChecklistCard({
    super.key,
    required this.state,
    required this.onRecord,
    required this.onExplore,
    required this.onFavorite,
    required this.onProfile,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.onboardChecklistTitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${state.doneCount}/${state.total}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: l.onboardDismiss,
                onPressed: onDismiss,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.doneCount / state.total,
                minHeight: 6,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
          _task(l.onboardTaskRecord, Icons.fiber_manual_record,
              state.recorded, onRecord),
          _task(l.onboardTaskExplore, Icons.explore_outlined, state.explored,
              onExplore),
          _task(l.onboardTaskFavorite, Icons.bookmark_outline,
              state.favorited, onFavorite),
          _task(l.onboardTaskProfile, Icons.person_outline,
              state.profileDone, onProfile),
        ],
      ),
    );
  }

  Widget _task(String label, IconData icon, bool done, VoidCallback onTap) {
    return InkWell(
      onTap: done ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: done ? AppColors.success : AppColors.primary,
            ),
            const SizedBox(width: 12),
            Icon(icon,
                size: 18,
                color: done ? Colors.grey : AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: done ? Colors.grey : null,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (!done)
              const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
