import 'package:flutter/material.dart';

import 'group_brand.dart';
import '../../data/repositories/groups_repository.dart';

/// Limiti del tier Verified (e Trial). I tier Pro/Enterprise non
/// hanno cap.
class BusinessCaps {
  static const int verifiedTrackCap = 10;
  static const int verifiedEventCap = 4;

  /// I tier per cui i cap si applicano. Pro/Enterprise hanno
  /// illimitato. I gruppi non Business non hanno cap né
  /// vincoli — restano al comportamento "free" attuale.
  static bool applies(Group group) {
    if (!group.isBusinessGroup) return false;
    return group.businessTier == 'verified' ||
        group.businessTier == 'trial';
  }
}

/// Modale che informa l'admin Business che ha raggiunto un cap del
/// tier Verified e propone l'upgrade a Pro.
///
/// Per ora l'azione "Passa a Pro" è un placeholder che mostra uno
/// snackbar — l'integrazione Stripe è in attesa del consulto
/// commercialista.
Future<void> showVerifiedCapReachedSheet(
  BuildContext context, {
  required Group group,
  required _CapResource resource,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _CapReachedSheet(group: group, resource: resource),
  );
}

enum _CapResource { tracks, events }

extension _CapResourceX on _CapResource {
  int get cap => switch (this) {
        _CapResource.tracks => BusinessCaps.verifiedTrackCap,
        _CapResource.events => BusinessCaps.verifiedEventCap,
      };

  String get noun => switch (this) {
        _CapResource.tracks => 'tracce condivise',
        _CapResource.events => 'eventi attivi',
      };

  IconData get icon => switch (this) {
        _CapResource.tracks => Icons.route,
        _CapResource.events => Icons.event,
      };
}

/// Wrapper pubblico per evitare di esporre l'enum interno.
Future<void> showTracksCapReached(BuildContext context, Group group) =>
    showVerifiedCapReachedSheet(
      context,
      group: group,
      resource: _CapResource.tracks,
    );

Future<void> showEventsCapReached(BuildContext context, Group group) =>
    showVerifiedCapReachedSheet(
      context,
      group: group,
      resource: _CapResource.events,
    );

class _CapReachedSheet extends StatelessWidget {
  final Group group;
  final _CapResource resource;

  const _CapReachedSheet({required this.group, required this.resource});

  @override
  Widget build(BuildContext context) {
    final accent = groupAccentColor(group);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(resource.icon, color: accent, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'Hai raggiunto il limite Verified',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Il tier Business Verified include fino a ${resource.cap} '
              '${resource.noun} per gruppo. Per togliere il limite passa al '
              'tier Pro: ${resource.noun} illimitati, statistiche dettagliate, '
              'team admin, featured placement nella discovery.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium, color: accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Business Pro — €49,99/mese o €499/anno',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Chiudi'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Upgrade a Pro disponibile a breve — '
                            'pagamenti via Stripe in arrivo',
                          ),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    icon: const Icon(Icons.trending_up),
                    label: const Text('Passa a Pro'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
