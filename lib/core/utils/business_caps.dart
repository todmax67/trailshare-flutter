import 'package:flutter/material.dart';

import 'group_brand.dart';
import '../../data/repositories/groups_repository.dart';

/// Limiti del tier Verified (e Trial). I tier Pro/Enterprise non
/// hanno cap.
class BusinessCaps {
  static const int verifiedTrackCap = 10;
  static const int verifiedEventCap = 4;

  /// Numero MASSIMO di admin **aggiuntivi** rispetto al founder per il
  /// tier Pro. Verified/Trial hanno 0 (solo founder). Enterprise non
  /// ha limite. Gruppi non Business: ignorato (gestione ruoli libera
  /// come oggi).
  static const int proAdminCap = 5;

  /// I tier per cui i cap si applicano. Pro/Enterprise hanno
  /// illimitato. I gruppi non Business non hanno cap né
  /// vincoli — restano al comportamento "free" attuale.
  static bool applies(Group group) {
    if (!group.isBusinessGroup) return false;
    return group.businessTier == 'verified' ||
        group.businessTier == 'trial';
  }

  /// Numero massimo di admin aggiuntivi (oltre al founder) consentiti
  /// in base al tier. `null` = illimitato. `0` = solo founder.
  static int? additionalAdminCap(Group group) {
    if (!group.isBusinessGroup) return null;
    switch (group.businessTier) {
      case 'enterprise':
        return null;
      case 'pro':
        return proAdminCap;
      case 'verified':
      case 'trial':
        return 0;
      default:
        return null;
    }
  }
}

/// Modale che informa l'admin Business che ha raggiunto un cap del
/// tier Verified e propone l'upgrade a Pro.
///
/// Per ora l'azione "Passa a Pro" è un placeholder che mostra uno
/// snackbar — l'integrazione Stripe è in attesa del consulto
/// commercialista.
Future<void> _showVerifiedCapReachedSheet(
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

enum _CapResource { tracks, events, admins }

extension _CapResourceX on _CapResource {
  int get cap => switch (this) {
        _CapResource.tracks => BusinessCaps.verifiedTrackCap,
        _CapResource.events => BusinessCaps.verifiedEventCap,
        _CapResource.admins => 0, // Verified non ha admin aggiuntivi
      };

  String get noun => switch (this) {
        _CapResource.tracks => 'tracce condivise',
        _CapResource.events => 'eventi attivi',
        _CapResource.admins => 'admin oltre al founder',
      };

  IconData get icon => switch (this) {
        _CapResource.tracks => Icons.route,
        _CapResource.events => Icons.event,
        _CapResource.admins => Icons.admin_panel_settings,
      };

  String descriptionFor(String tier) {
    switch (this) {
      case _CapResource.tracks:
        return 'Il tier Verified include fino a $cap $noun per gruppo.';
      case _CapResource.events:
        return 'Il tier Verified include fino a $cap $noun per gruppo.';
      case _CapResource.admins:
        if (tier == 'pro') {
          return 'Il tier Pro permette fino a ${BusinessCaps.proAdminCap} '
              'co-admin oltre al founder. Hai raggiunto il limite massimo '
              'per questo gruppo.';
        }
        return 'Sul tier Verified solo il founder è admin del gruppo: '
            'non puoi promuovere altri membri a co-admin.';
    }
  }

  String upgradePitchFor(String tier) {
    switch (this) {
      case _CapResource.tracks:
      case _CapResource.events:
        return 'Per togliere il limite passa al tier Pro: $noun illimitati, '
            'statistiche dettagliate, team admin, featured placement.';
      case _CapResource.admins:
        if (tier == 'pro') {
          return 'Per più co-admin contattaci per il tier Enterprise '
              '(multi-gruppo, white-label, priority support).';
        }
        return 'Pro permette fino a ${BusinessCaps.proAdminCap} co-admin '
            'oltre al founder, più tracce ed eventi illimitati, '
            'featured placement e statistiche avanzate.';
    }
  }
}

/// Wrapper pubblico per evitare di esporre l'enum interno.
Future<void> showTracksCapReached(BuildContext context, Group group) =>
    _showVerifiedCapReachedSheet(
      context,
      group: group,
      resource: _CapResource.tracks,
    );

Future<void> showEventsCapReached(BuildContext context, Group group) =>
    _showVerifiedCapReachedSheet(
      context,
      group: group,
      resource: _CapResource.events,
    );

Future<void> showAdminsCapReached(BuildContext context, Group group) =>
    _showVerifiedCapReachedSheet(
      context,
      group: group,
      resource: _CapResource.admins,
    );

String _titleForTier(String tier) {
  switch (tier) {
    case 'pro':
      return 'Hai raggiunto il limite Pro';
    case 'enterprise':
      return 'Hai raggiunto il limite Enterprise';
    case 'verified':
    case 'trial':
    default:
      return 'Hai raggiunto il limite Verified';
  }
}

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
              _titleForTier(group.businessTier),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${resource.descriptionFor(group.businessTier)} '
              '${resource.upgradePitchFor(group.businessTier)}',
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
                      group.businessTier == 'pro'
                          ? 'Business Enterprise — su preventivo'
                          : 'Business Pro — €49,99/mese o €499/anno',
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
                        SnackBar(
                          content: Text(
                            group.businessTier == 'pro'
                                ? 'Per Enterprise scrivici a info@trailshare.app'
                                : 'Upgrade a Pro disponibile a breve — pagamenti via Stripe in arrivo',
                          ),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    icon: const Icon(Icons.trending_up),
                    label: Text(
                      group.businessTier == 'pro'
                          ? 'Contatta Enterprise'
                          : 'Passa a Pro',
                    ),
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
