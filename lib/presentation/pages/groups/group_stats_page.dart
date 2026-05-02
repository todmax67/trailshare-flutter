import 'package:flutter/material.dart';

import '../../../core/utils/group_brand.dart';
import '../../../data/repositories/groups_repository.dart';
import '../../../data/repositories/tracks_repository.dart';

/// Statistiche aggregate base per gruppi Business L1 (tier Verified).
///
/// Mostra una vista d'insieme che il founder Business può guardare
/// per capire come sta funzionando il gruppo: membri, iscritti via
/// codice invito, tracce condivise, eventi attivi.
///
/// Stat per-traccia (wishlist, navigate) sono parte del tier Pro
/// (stats avanzate) e non sono qui.
class GroupStatsPage extends StatefulWidget {
  final Group group;

  const GroupStatsPage({super.key, required this.group});

  @override
  State<GroupStatsPage> createState() => _GroupStatsPageState();
}

class _GroupStatsPageState extends State<GroupStatsPage> {
  final _groupsRepo = GroupsRepository();
  final _tracksRepo = TracksRepository();

  bool _loading = true;
  Group? _group;
  int _trackCount = 0;
  int _activeEventCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _groupsRepo.getGroup(widget.group.id),
      _tracksRepo.getGroupTracks(widget.group.id),
      _groupsRepo.getEvents(widget.group.id, upcomingOnly: true),
    ]);
    if (!mounted) return;
    final fresh = results[0] as Group?;
    final tracks = results[1] as List;
    final events = results[2] as List;
    setState(() {
      _group = fresh ?? widget.group;
      _trackCount = tracks.length;
      _activeEventCount = events.length;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = _group ?? widget.group;
    final accent = groupAccentColor(group);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiche gruppo'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Header(group: group, accent: accent),
            const SizedBox(height: 24),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _StatTile(
                accent: accent,
                icon: Icons.people_outline,
                label: 'Membri totali',
                value: '${group.memberCount}',
                hint: 'Persone iscritte al gruppo',
              ),
              const SizedBox(height: 12),
              _StatTile(
                accent: accent,
                icon: Icons.qr_code_2,
                label: 'Iscritti via codice invito',
                value: '${group.qrJoinCount}',
                hint:
                    'Cumulativo di chi ha usato la card invito brandizzata o '
                    'incollato il codice nell\'app',
              ),
              const SizedBox(height: 12),
              _StatTile(
                accent: accent,
                icon: Icons.route,
                label: 'Tracce condivise',
                value: '$_trackCount',
                hint:
                    'Tracce attualmente disponibili nel tab Percorsi del gruppo',
              ),
              const SizedBox(height: 12),
              _StatTile(
                accent: accent,
                icon: Icons.event_available,
                label: 'Eventi attivi',
                value: '$_activeEventCount',
                hint: 'Eventi futuri o in corso pubblicati nel gruppo',
              ),
              const SizedBox(height: 32),
              _UpgradeTeaser(accent: accent),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Group group;
  final Color accent;

  const _Header({required this.group, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.15),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bar_chart,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Vista d\'insieme — tier Verified',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String label;
  final String value;
  final String hint;

  const _StatTile({
    required this.accent,
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeTeaser extends StatelessWidget {
  final Color accent;

  const _UpgradeTeaser({required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.trending_up,
              color: theme.colorScheme.onSurfaceVariant, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Statistiche avanzate con Pro',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Timeline mensile, breakdown geografico, funnel di '
                  'acquisizione, performance per traccia e per evento. '
                  'Disponibili nel tier Business Pro.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
