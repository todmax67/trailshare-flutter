import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/business_repository.dart';
import '../../../data/repositories/groups_repository.dart';
import '../../widgets/app_snackbar.dart';
import '../groups/group_detail_page.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Bottom sheet che gestisce il link bidirezionale Spazio Pro ↔ Group
/// (Community VIP del business).
///
/// Modi:
/// - Se il business non ha un gruppo collegato: due CTA "Crea community"
///   o "Collega gruppo esistente".
/// - Se ne ha uno: "Apri community" + "Scollega".
///
/// Usage:
/// ```dart
/// await showBusinessCommunitySheet(context, business);
/// ```
Future<void> showBusinessCommunitySheet(
  BuildContext context,
  Business business,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CommunitySheet(business: business),
  );
}

class _CommunitySheet extends StatefulWidget {
  final Business business;
  const _CommunitySheet({required this.business});

  @override
  State<_CommunitySheet> createState() => _CommunitySheetState();
}

class _CommunitySheetState extends State<_CommunitySheet> {
  final _businessRepo = BusinessRepository();
  final _groupsRepo = GroupsRepository();
  bool _busy = false;

  Future<void> _createCommunity() async {
    if (_busy) return;
    setState(() => _busy = true);
    final business = widget.business;
    try {
      // Crea il gruppo. Visibility privata: la community è invito-only.
      final groupId = await _groupsRepo.createGroup(
        name: '${business.name} • Community',
        description:
            'Community VIP di ${business.name}. Invito gestito da ${business.name}.',
        visibility: 'private',
      );
      if (groupId == null) {
        if (!mounted) return;
        AppSnackBar.error(context, 'Errore creazione gruppo');
        return;
      }
      await _businessRepo.linkGroupAsCommunity(
        businessId: business.id!,
        groupId: groupId,
        businessName: business.name,
      );
      if (!mounted) return;
      Navigator.pop(context);
      AppSnackBar.success(context, 'Community VIP creata');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupDetailPage(
            groupId: groupId,
            groupName: '${business.name} • Community',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, 'Errore: $e');
      setState(() => _busy = false);
    }
  }

  Future<void> _linkExisting() async {
    if (_busy) return;
    final myGroups = await _groupsRepo.getMyGroups();
    if (!mounted) return;
    // Picker: solo gruppi di cui l'utente è creatore (per evitare di
    // legare community altrui per sbaglio). Esclude gruppi già linkati
    // a un altro business.
    final eligible = myGroups
        .where((g) => !g.isLinkedToBusiness)
        .toList();
    if (eligible.isEmpty) {
      AppSnackBar.info(
        context,
        'Nessun gruppo disponibile da collegare. Crea una community nuova.',
      );
      return;
    }
    final selected = await showModalBottomSheet<Group>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _GroupPickerSheet(groups: eligible),
    );
    if (selected == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _businessRepo.linkGroupAsCommunity(
        businessId: widget.business.id!,
        groupId: selected.id,
        businessName: widget.business.name,
      );
      if (!mounted) return;
      Navigator.pop(context);
      AppSnackBar.success(
        context,
        'Gruppo "${selected.name}" collegato come community VIP',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, 'Errore: $e');
      setState(() => _busy = false);
    }
  }

  Future<void> _unlink() async {
    final business = widget.business;
    final groupId = business.linkedGroupId;
    if (groupId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scollegare la community?'),
        content: const Text(
            'Il gruppo non verrà eliminato, ma perderà il legame con il '
            'tuo Spazio Pro (logo/colore custom potrebbero sparire se '
            'l\'owner non ha TrailShare Pro).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Scollega'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _businessRepo.unlinkCommunityGroup(
        businessId: business.id!,
        groupId: groupId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      AppSnackBar.success(context, 'Community scollegata');
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, 'Errore: $e');
      setState(() => _busy = false);
    }
  }

  void _openLinked() {
    final groupId = widget.business.linkedGroupId;
    if (groupId == null) return;
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDetailPage(
          groupId: groupId,
          groupName: '${widget.business.name} • Community',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLinked = widget.business.linkedGroupId != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_2, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Community VIP',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasLinked
                  ? 'Questo Spazio Pro ha una community collegata. '
                      'I membri vedono il tuo brand sul gruppo.'
                  : 'Crea o collega un gruppo come community VIP del tuo '
                      'Spazio Pro. I membri avranno cap espansi (tracce '
                      'illimitate, eventi illimitati, branding custom) '
                      'gratis come benefit.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (hasLinked) ...[
              _ActionTile(
                icon: Icons.open_in_new,
                label: 'Apri community',
                onTap: _openLinked,
              ),
              const SizedBox(height: 8),
              _ActionTile(
                icon: Icons.link_off,
                label: 'Scollega',
                color: AppColors.danger,
                onTap: _unlink,
              ),
            ] else ...[
              _ActionTile(
                icon: Icons.add_circle_outline,
                label: 'Crea community',
                color: AppColors.primary,
                onTap: _createCommunity,
              ),
              const SizedBox(height: 8),
              _ActionTile(
                icon: Icons.link,
                label: 'Collega gruppo esistente',
                onTap: _linkExisting,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Material(
      color: c.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: c),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, color: c.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupPickerSheet extends StatelessWidget {
  final List<Group> groups;
  const _GroupPickerSheet({required this.groups});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Scegli un gruppo da collegare',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: groups.length,
                separatorBuilder: (_, _2) => const SizedBox(height: 4),
                itemBuilder: (_, i) {
                  final g = groups[i];
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.group, color: Colors.white),
                    ),
                    title: Text(g.name),
                    subtitle: Text('${g.memberCount} membri'),
                    onTap: () => Navigator.pop(context, g),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
