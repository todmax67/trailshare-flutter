import 'package:flutter/material.dart';

import 'group_brand.dart';
import '../../data/repositories/groups_repository.dart';
import '../services/owner_pro_status_cache.dart';
import '../../presentation/widgets/paywall_sheet.dart';

/// Cap dei gruppi nel modello a 3 livelli (Sprint B, 2026-05-10).
///
/// **Modello attuale**:
/// - **Free** (owner del gruppo NON è Consumer Pro): cap su tracce ed
///   eventi, niente co-admin oltre al founder.
/// - **Consumer Pro** (owner del gruppo HA Consumer Pro €2.99/€19.99 via
///   store): tracce illim., eventi illim., fino a [proAdminCap] co-admin.
/// - **Spazio Pro / Business**: entity separata `businesses/{id}`, NON è
///   un tier dei gruppi. Vedi `business.dart`.
///
/// Il flag `isBusinessGroup` + `businessTier` sui gruppi è LEGACY (verrà
/// rimosso in B.4). Per ora viene ignorato dai cap: l'unica cosa che
/// conta è se l'owner del gruppo è Consumer Pro.
class BusinessCaps {
  /// Cap tracce condivise per gruppi Free (owner senza Pro).
  static const int freeTrackCap = 10;

  /// Cap eventi attivi (futuri o in corso) per gruppi Free.
  static const int freeEventCap = 4;

  /// Numero MASSIMO di admin **aggiuntivi** rispetto al founder per i
  /// gruppi Consumer Pro. Free: 0 (solo founder).
  static const int proAdminCap = 5;

  // Manteniamo gli alias legacy per non rompere i call sites legacy
  // ancora presenti (sostituiti gradualmente). Sono identici ai nuovi.
  @Deprecated('Use freeTrackCap instead')
  static const int verifiedTrackCap = freeTrackCap;
  @Deprecated('Use freeEventCap instead')
  static const int verifiedEventCap = freeEventCap;

  /// `true` se al gruppo si applicano i cap (= NON è espanso).
  ///
  /// Un gruppo è "espanso" (cap rimossi) se:
  ///   1. l'OWNER ha Consumer Pro attivo (path utente, via store), OPPURE
  ///   2. l'admin TrailShare ha flagato `isBusinessGroup=true` (path admin,
  ///      es. seed clients program — concesso manualmente da Firestore
  ///      o dalla sezione "Gruppi Business" del pannello admin).
  ///
  /// Async perché legge `user_profiles/{ownerId}.isPro` con cache TTL 5min
  /// (vedi [OwnerProStatusCache]).
  static Future<bool> appliesAsync(Group group) async {
    // Gruppo Pro-equivalent: 3 path possibili (vedi Group.hasCustomLogo).
    if (group.isBusinessGroup || group.isLinkedToBusiness) return false;
    if (group.createdBy.isEmpty) return true;
    final ownerIsPro =
        await OwnerProStatusCache().isOwnerPro(group.createdBy);
    return !ownerIsPro;
  }

  /// Numero max di admin aggiuntivi (oltre al founder). `null` =
  /// illimitato (riservato a casi futuri Enterprise). `0` = solo founder.
  /// Stesso gating di [appliesAsync].
  static Future<int?> additionalAdminCapAsync(Group group) async {
    if (group.isBusinessGroup || group.isLinkedToBusiness) return proAdminCap;
    if (group.createdBy.isEmpty) return 0;
    final ownerIsPro =
        await OwnerProStatusCache().isOwnerPro(group.createdBy);
    return ownerIsPro ? proAdminCap : 0;
  }

  // ─────────────────────────────────────────────────────────────────
  // API LEGACY SYNC — solo per call sites che non possono awaitare
  // (es. build() di widget). Usa il dato `groups.businessTier` legacy
  // come fallback finché non migrati. Da rimuovere in B.4.
  // ─────────────────────────────────────────────────────────────────

  @Deprecated('Use appliesAsync — legge owner.isPro invece del tier legacy')
  static bool applies(Group group) {
    if (!group.isBusinessGroup) return true; // gruppi normali = cap base
    return group.businessTier == 'verified' ||
        group.businessTier == 'trial';
  }

  @Deprecated('Use additionalAdminCapAsync')
  static int? additionalAdminCap(Group group) {
    if (!group.isBusinessGroup) return 0;
    switch (group.businessTier) {
      case 'enterprise':
        return null;
      case 'pro':
        return proAdminCap;
      case 'verified':
      case 'trial':
        return 0;
      default:
        return 0;
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// CAP REACHED SHEET
// Spinge l'owner del gruppo verso Consumer Pro (€2.99/€19.99) via il
// paywall esistente. Niente più Stripe / Business Pro qui — un gruppo
// non è mai un Business: per chi vuole Business c'è Spazio Pro entity.
// ─────────────────────────────────────────────────────────────────

enum _CapResource { tracks, events, admins }

extension _CapResourceX on _CapResource {
  int get freeCap => switch (this) {
        _CapResource.tracks => BusinessCaps.freeTrackCap,
        _CapResource.events => BusinessCaps.freeEventCap,
        _CapResource.admins => 0,
      };

  String get noun => switch (this) {
        _CapResource.tracks => 'tracce condivise',
        _CapResource.events => 'eventi attivi',
        _CapResource.admins => 'co-admin oltre al founder',
      };

  IconData get icon => switch (this) {
        _CapResource.tracks => Icons.route,
        _CapResource.events => Icons.event,
        _CapResource.admins => Icons.admin_panel_settings,
      };

  String get description {
    switch (this) {
      case _CapResource.tracks:
        return 'I gruppi Free includono fino a $freeCap $noun. '
            'Con TrailShare Pro diventano illimitate.';
      case _CapResource.events:
        return 'I gruppi Free includono fino a $freeCap $noun. '
            'Con TrailShare Pro diventano illimitati.';
      case _CapResource.admins:
        return 'Sui gruppi Free solo il founder è admin. '
            'Con TrailShare Pro puoi promuovere fino a '
            '${BusinessCaps.proAdminCap} co-admin.';
    }
  }
}

Future<void> _showCapReachedSheet(
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

Future<void> showTracksCapReached(BuildContext context, Group group) =>
    _showCapReachedSheet(
      context,
      group: group,
      resource: _CapResource.tracks,
    );

Future<void> showEventsCapReached(BuildContext context, Group group) =>
    _showCapReachedSheet(
      context,
      group: group,
      resource: _CapResource.events,
    );

Future<void> showAdminsCapReached(BuildContext context, Group group) =>
    _showCapReachedSheet(
      context,
      group: group,
      resource: _CapResource.admins,
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
              'Hai raggiunto il limite del piano Free',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              resource.description,
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
                      'TrailShare Pro — €2,99/mese o €19,99/anno',
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
                    onPressed: () async {
                      Navigator.of(context).pop();
                      // Apre il paywall Consumer Pro esistente. Solo l'owner
                      // del gruppo può effettivamente upgradare per espandere
                      // i cap di QUESTO gruppo (cap derivati dal Pro
                      // dell'owner). Membri non-owner che cliccano vedranno
                      // comunque il paywall ma sblocca solo i loro benefit
                      // personali.
                      await showPaywallSheet(
                        context,
                        trigger: PaywallTrigger.generic,
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
