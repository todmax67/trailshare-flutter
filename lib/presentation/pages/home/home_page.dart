import 'package:flutter/material.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../community/community_page.dart';
import '../record/record_page.dart';
import '../tracks/tracks_page.dart';
import '../profile/profile_page.dart';
import '../discover/discover_page.dart';
import 'dart:async';
import '../../../core/services/garmin_sync_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 1; // Community come default

  final List<Widget> _pages = [
    const DiscoverPage(),       // 0 - Scopri (Sentieri OSM)
    const CommunityPage(),      // 1 - Community (Tracce + Gruppi + Eventi) ← DEFAULT
    const RecordPage(),         // 2 - Registra
    const TracksPage(),         // 3 - Tracce
    const ProfilePage(),        // 4 - Profilo
  ];

  StreamSubscription? _garminSub;

  @override
  void initState() {
    super.initState();
    _garminSub = GarminSyncService().syncEvents.listen((event) {
      if (!mounted) return;
      switch (event.type) {
        case 'started':
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⌚ Garmin: ricezione traccia (${event.totalPoints} punti)...'),
              duration: const Duration(seconds: 3),
            ),
          );
          break;
        case 'completed':
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Traccia Garmin importata! (${event.totalPoints} punti)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
          // Vai alla tab Tracce per mostrare la nuova traccia
          setState(() => _currentIndex = 3);
          break;
        case 'error':
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Errore Garmin: ${event.error}'),
              backgroundColor: Colors.red,
            ),
          );
          break;
      }
    });
  }

  @override
  void dispose() {
    _garminSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNavBar(context),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Scopri
              _NavItem(
                icon: Icons.explore_outlined,
                activeIcon: Icons.explore,
                label: context.l10n.discover,
                isSelected: _currentIndex == 0,
                primaryColor: primaryColor,
                onTap: () => setState(() => _currentIndex = 0),
              ),
              // Community
              _NavItem(
                icon: Icons.people_outline,
                activeIcon: Icons.people,
                label: context.l10n.community,
                isSelected: _currentIndex == 1,
                primaryColor: primaryColor,
                onTap: () => setState(() => _currentIndex = 1),
              ),
              // Registra (prominente)
              _RecordButton(
                label: context.l10n.recordLabel,
                isSelected: _currentIndex == 2,
                onTap: () => setState(() => _currentIndex = 2),
              ),
              // Tracce
              _NavItem(
                icon: Icons.route_outlined,
                activeIcon: Icons.route,
                label: context.l10n.tracksNavLabel,
                isSelected: _currentIndex == 3,
                primaryColor: primaryColor,
                onTap: () => setState(() => _currentIndex = 3),
              ),
              // Profilo
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: context.l10n.profile,
                isSelected: _currentIndex == 4,
                primaryColor: primaryColor,
                onTap: () => setState(() => _currentIndex = 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tab normale della navigation bar
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicatore attivo
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: isSelected ? 24 : 0,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? primaryColor : colorScheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? primaryColor : colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsante Registra prominente al centro
class _RecordButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RecordButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE07B4C),  // AppColors.primary
                  Color(0xFFC4683F),  // AppColors.primaryDark
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE07B4C).withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFFE07B4C)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}