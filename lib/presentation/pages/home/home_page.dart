import 'package:flutter/material.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/services/recording_status_service.dart';
import '../../widgets/app_snackbar.dart';
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
          AppSnackBar.info(
            context,
            'Garmin: ricezione traccia (${event.totalPoints} punti)…',
          );
          break;
        case 'completed':
          AppSnackBar.success(
            context,
            'Traccia Garmin importata (${event.totalPoints} punti)',
            duration: const Duration(seconds: 4),
          );
          // Vai alla tab Tracce per mostrare la nuova traccia
          setState(() => _currentIndex = 3);
          break;
        case 'error':
          AppSnackBar.error(context, 'Errore Garmin: ${event.error}');
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

/// Pulsante Registra prominente al centro della nav bar.
///
/// Reagisce allo stato globale di [RecordingStatusService]:
/// - **idle**: cerchio statico arancione con pallino rosso (record classico)
/// - **recording**: ring pulsante rosso espanso + icona stop quadrata
/// - **paused**: ring statico ambra + icona pausa
class _RecordButton extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RecordButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  final _service = RecordingStatusService();

  static const _orange = Color(0xFFE07B4C);
  static const _orangeDark = Color(0xFFC4683F);
  static const _red = Color(0xFFE53935);
  static const _amber = Color(0xFFFFA726);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _service.addListener(_onStatusChanged);
    _syncPulse();
  }

  @override
  void dispose() {
    _service.removeListener(_onStatusChanged);
    _pulse.dispose();
    super.dispose();
  }

  void _onStatusChanged() {
    _syncPulse();
    if (mounted) setState(() {});
  }

  void _syncPulse() {
    if (_service.isRecording) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = _service.isRecording;
    final paused = _service.isPaused;

    // Colori in base allo stato.
    final (gradientStart, gradientEnd, shadowColor, icon) = recording
        ? (_red, const Color(0xFFB71C1C), _red, Icons.stop_rounded)
        : paused
            ? (_amber, const Color(0xFFE57E0A), _amber, Icons.pause_rounded)
            : (_orange, _orangeDark, _orange, Icons.fiber_manual_record_rounded);

    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 64,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ring pulsante (solo in recording).
                if (recording)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final t = _pulse.value; // 0 → 1
                      final radius = 26 + t * 14; // 26 → 40
                      final alpha = (1 - t) * 0.55;
                      return Container(
                        width: radius * 2,
                        height: radius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _red.withValues(alpha: alpha),
                            width: 2.5,
                          ),
                        ),
                      );
                    },
                  ),
                // Cerchio principale.
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [gradientStart, gradientEnd],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
              color: widget.isSelected
                  ? (recording ? _red : paused ? _amber : _orange)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}