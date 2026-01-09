import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../map/map_page.dart';
import '../record/record_page.dart';
import '../tracks/tracks_page.dart';
import '../profile/profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 1; // Mappa come default

  final List<Widget> _pages = [
    const _DiscoverTab(),
    const MapPage(),
    const RecordPage(),
    const TracksPage(),
    const ProfilePage(),     // ← Profilo vero!
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Scopri',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mappa',
          ),
          NavigationDestination(
            icon: Icon(Icons.radio_button_checked),
            selectedIcon: Icon(Icons.radio_button_checked),
            label: 'Registra',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Tracce',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profilo',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB PLACEHOLDER - Scopri (da implementare)
// ============================================================================

class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scopri')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore, size: 64, color: AppColors.textMuted),
            SizedBox(height: 16),
            Text('Scopri sentieri', style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 8),
            Text('Coming soon...', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
