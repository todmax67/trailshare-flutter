import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../data/repositories/groups_repository.dart';
import 'web_groups_picker_page.dart';
import 'web_planner_page.dart';
import 'web_tracks_list_page.dart';

/// Home della dashboard web autenticata. Sostituisce la vecchia
/// destinazione "picker gruppi business diretta" con una shell che
/// ospita più sezioni:
///
/// - **Le mie tracce**: visibile a tutti gli utenti loggati
/// - **I miei gruppi Business**: visibile solo se l'utente è admin
///   di almeno un gruppo Business
///
/// In futuro: Pianificatore (per Pro consumer + Business),
/// Profilo/Impostazioni, ecc.
class WebHomePage extends StatefulWidget {
  const WebHomePage({super.key});

  @override
  State<WebHomePage> createState() => _WebHomePageState();
}

class _WebHomePageState extends State<WebHomePage> {
  final _groupsRepo = GroupsRepository();
  int _selectedIndex = 0;
  bool _hasBusinessGroups = false;
  bool _checkingBusiness = true;

  @override
  void initState() {
    super.initState();
    _checkBusinessAccess();
  }

  /// Verifica se l'utente loggato è admin di almeno un gruppo Business.
  /// Solo in tal caso mostriamo la sezione "I miei gruppi Business".
  Future<void> _checkBusinessAccess() async {
    final myGroups = await _groupsRepo.getMyGroups();
    bool found = false;
    for (final g in myGroups) {
      if (!g.isBusinessGroup) continue;
      if (await _groupsRepo.isAdmin(g.id)) {
        found = true;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _hasBusinessGroups = found;
      _checkingBusiness = false;
    });
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (_checkingBusiness) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(
              selectedIndex: _selectedIndex,
              hasBusiness: _hasBusinessGroups,
              userEmail: user?.email,
              onSelect: (i) => setState(() => _selectedIndex = i),
              onSignOut: _signOut,
              onOpenMarketingSite: () =>
                  _openExternal('https://trailshare.app'),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Indici dinamici: pianificatore sempre 1, gruppi business solo se
    // l'utente è admin (e in quel caso è index 2).
    switch (_selectedIndex) {
      case 0:
        return const WebTracksListPage();
      case 1:
        return const WebPlannerPage();
      case 2:
        return const WebGroupsPickerPage();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final bool hasBusiness;
  final String? userEmail;
  final ValueChanged<int> onSelect;
  final VoidCallback onSignOut;
  final VoidCallback onOpenMarketingSite;

  const _Sidebar({
    required this.selectedIndex,
    required this.hasBusiness,
    required this.userEmail,
    required this.onSelect,
    required this.onSignOut,
    required this.onOpenMarketingSite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onOpenMarketingSite,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text('🥾', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 8),
                    Text(
                      'TrailShare',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    Spacer(),
                    Tooltip(
                      message: 'Apri trailshare.app',
                      child: Icon(
                        Icons.open_in_new,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _navItem(
            icon: Icons.route_outlined,
            iconActive: Icons.route,
            label: 'Le mie tracce',
            index: 0,
          ),
          _navItem(
            icon: Icons.edit_road_outlined,
            iconActive: Icons.edit_road,
            label: 'Pianificatore',
            index: 1,
          ),
          if (hasBusiness)
            _navItem(
              icon: Icons.business_outlined,
              iconActive: Icons.business,
              label: 'Gruppi Business',
              index: 2,
            ),
          const Spacer(),
          if (userEmail != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              child: Text(
                userEmail!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: TextButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Esci'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
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
            ? AppColors.primary.withValues(alpha: 0.12)
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
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
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
}
