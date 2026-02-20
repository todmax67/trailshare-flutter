import 'package:flutter/material.dart';
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Scopri',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Community',
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
