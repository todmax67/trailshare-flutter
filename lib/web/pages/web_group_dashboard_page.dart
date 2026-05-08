import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/group_brand.dart';
import '../../data/repositories/groups_repository.dart';
import '../../presentation/pages/groups/group_customize_page.dart';
import '../../presentation/pages/groups/group_stats_page.dart';
import 'web_group_members_page.dart';
import 'web_group_overview_page.dart';

/// Shell desktop della dashboard B2B per un singolo gruppo.
///
/// Sostituisce il vecchio comportamento "tap → push GroupCustomizePage"
/// con una NavigationRail persistente sul lato sinistro che switcha
/// tra le tre sezioni principali (Personalizza, Statistiche, Membri).
/// Le pagine interne mantengono il loro Scaffold e AppBar; il back
/// button di ciascuna torna alla picker dei gruppi (la rotta padre).
///
/// Mobile non passa mai da qui — ha la sua navigazione push standard.
class WebGroupDashboardPage extends StatefulWidget {
  final Group group;

  const WebGroupDashboardPage({super.key, required this.group});

  @override
  State<WebGroupDashboardPage> createState() => _WebGroupDashboardPageState();
}

class _WebGroupDashboardPageState extends State<WebGroupDashboardPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final accent = groupAccentColor(widget.group);

    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(
              group: widget.group,
              accent: accent,
              selectedIndex: _selectedIndex,
              onSelect: (i) => setState(() => _selectedIndex = i),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // Content area: rebuild della singola pagina ad ogni switch
            // (no IndexedStack) per evitare 3 query Firestore parallele
            // al primo load del dashboard.
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Ogni pagina interna porta il proprio Scaffold + AppBar. Usiamo
    // una Key sul KeyedSubtree per forzare il rebuild quando cambiamo
    // tab, garantendo che le query Firestore della pagina vengano
    // rifatte (utile dopo modifiche da Customize per riflettere su
    // Stats senza ricaricare manualmente).
    final group = widget.group;
    switch (_selectedIndex) {
      case 0:
        return KeyedSubtree(
          key: const ValueKey('overview'),
          child: WebGroupOverviewPage(
            group: group,
            onNavigateTab: (i) => setState(() => _selectedIndex = i),
          ),
        );
      case 1:
        return KeyedSubtree(
          key: const ValueKey('customize'),
          child: GroupCustomizePage(group: group),
        );
      case 2:
        return KeyedSubtree(
          key: const ValueKey('stats'),
          child: GroupStatsPage(group: group),
        );
      case 3:
        return KeyedSubtree(
          key: const ValueKey('members'),
          child: WebGroupMembersPage(group: group),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _Sidebar extends StatelessWidget {
  final Group group;
  final Color accent;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _Sidebar({
    required this.group,
    required this.accent,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupHeader(group: group, accent: accent),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _navItem(
            context,
            icon: Icons.dashboard_outlined,
            iconActive: Icons.dashboard,
            label: 'Panoramica',
            index: 0,
          ),
          _navItem(
            context,
            icon: Icons.brush_outlined,
            iconActive: Icons.brush,
            label: 'Personalizza',
            index: 1,
          ),
          _navItem(
            context,
            icon: Icons.bar_chart_outlined,
            iconActive: Icons.bar_chart,
            label: 'Statistiche',
            index: 2,
          ),
          _navItem(
            context,
            icon: Icons.people_outline,
            iconActive: Icons.people,
            label: 'Membri',
            index: 3,
          ),
          const Spacer(),
          _backToPicker(context),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _navItem(
    BuildContext context, {
    required IconData icon,
    required IconData iconActive,
    required String label,
    required int index,
  }) {
    final isSelected = selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected
            ? accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelect(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? iconActive : icon,
                  color: isSelected ? accent : AppColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? accent : AppColors.textPrimary,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backToPicker(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('Cambia gruppo'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final Group group;
  final Color accent;

  const _GroupHeader({required this.group, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🥾', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                'TrailShare Business',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
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
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      group.businessTierLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
