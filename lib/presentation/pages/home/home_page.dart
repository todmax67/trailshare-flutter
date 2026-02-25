import 'package:flutter/material.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../community/community_page.dart';
import '../record/record_page.dart';
import '../tracks/tracks_page.dart';
import '../profile/profile_page.dart';
import '../discover/discover_page.dart';

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
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: context.l10n.discover,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: context.l10n.community,
          ),
          NavigationDestination(
            icon: const Icon(Icons.radio_button_checked),
            selectedIcon: const Icon(Icons.radio_button_checked),
            label: context.l10n.recordLabel,
          ),
          NavigationDestination(
            icon: const Icon(Icons.route_outlined),
            selectedIcon: const Icon(Icons.route),
            label: context.l10n.tracksNavLabel,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: context.l10n.profile,
          ),
        ],
      ),
    );
  }
}