import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/group_brand.dart';
import '../../data/repositories/groups_repository.dart';
import '../../presentation/pages/groups/group_customize_page.dart';

/// Selettore gruppo per la dashboard B2B web. Mostra solo i gruppi
/// Business di cui l'utente loggato è admin (founder o coadmin in
/// futuro). Cliccare un gruppo apre la sua dashboard.
class WebGroupsPickerPage extends StatefulWidget {
  const WebGroupsPickerPage({super.key});

  @override
  State<WebGroupsPickerPage> createState() => _WebGroupsPickerPageState();
}

class _WebGroupsPickerPageState extends State<WebGroupsPickerPage> {
  final _repo = GroupsRepository();
  bool _loading = true;
  List<Group> _businessGroups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final myGroups = await _repo.getMyGroups();
    final adminBusinessGroups = <Group>[];
    for (final g in myGroups) {
      if (!g.isBusinessGroup) continue;
      final isAdmin = await _repo.isAdmin(g.id);
      if (isAdmin) adminBusinessGroups.add(g);
    }
    if (!mounted) return;
    setState(() {
      _businessGroups = adminBusinessGroups;
      _loading = false;
    });
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🥾'),
            const SizedBox(width: 8),
            Text(
              'TrailShare Business',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (user?.email != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  user!.email!,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Esci',
            onPressed: _signOut,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 16),
                      const Text(
                        'Seleziona un gruppo',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'I gruppi Business di cui sei admin.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_businessGroups.isEmpty)
                        const _EmptyState()
                      else
                        ..._businessGroups
                            .map((g) => _GroupTile(group: g)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.business_outlined,
              size: 36, color: AppColors.textMuted),
          const SizedBox(height: 12),
          const Text(
            'Nessun gruppo Business',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Non sei admin di nessun gruppo marcato Business. La '
            'dashboard web è riservata ai gruppi Business attivi. '
            'Per attivare un gruppo contatta TrailShare per il '
            'piano Verified o Pro.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).pushNamed('/business'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Vedi i piani Business'),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final Group group;
  const _GroupTile({required this.group});

  @override
  Widget build(BuildContext context) {
    final accent = groupAccentColor(group);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: group.isFeatured
              ? accent.withValues(alpha: 0.55)
              : AppColors.border,
          width: group.isFeatured ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // Per ora riusiamo direttamente la GroupCustomizePage mobile.
          // Da lì sono accessibili anche Statistiche, Card invito,
          // Pinned post (Pro). UX desktop dedicato in un round
          // successivo (sidebar nav + content area).
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupCustomizePage(group: group),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: group.hasCustomLogo
                    ? CachedNetworkImage(
                        imageUrl: group.avatarUrl!,
                        fit: BoxFit.cover,
                      )
                    : Center(
                        child: Text(
                          group.name.isNotEmpty
                              ? group.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: accent,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            group.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.verified, color: accent, size: 16),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      group.businessTierLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.memberCount} membri',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
