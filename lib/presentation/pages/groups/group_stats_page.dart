import 'package:flutter/material.dart';

import '../../../core/utils/group_brand.dart';
import '../../../data/models/track.dart';
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

  // Stats avanzate Pro
  List<MonthlyBucket> _monthlyMembers = [];
  List<MonthlyBucket> _monthlyTracks = [];
  List<MonthlyBucket> _monthlyEvents = [];
  List<Track> _recentTracks = [];

  bool get _isProTier {
    final t = _group?.businessTier ?? widget.group.businessTier;
    return t == 'pro' || t == 'enterprise';
  }

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
    final tracks = results[1] as List<Track>;
    final events = results[2] as List;
    final groupResolved = fresh ?? widget.group;
    final isPro = groupResolved.businessTier == 'pro' ||
        groupResolved.businessTier == 'enterprise';

    // Stats Pro: timeline ultimi 6 mesi + recenti tracce. Solo se
    // tier valido — evita query inutili lato client per Verified.
    List<MonthlyBucket> mMembers = [];
    List<MonthlyBucket> mTracks = [];
    List<MonthlyBucket> mEvents = [];
    if (isPro) {
      final advanced = await Future.wait([
        _groupsRepo.getMonthlyMemberJoins(widget.group.id),
        _groupsRepo.getMonthlyTrackShares(widget.group.id),
        _groupsRepo.getMonthlyEventCreations(widget.group.id),
      ]);
      mMembers = advanced[0];
      mTracks = advanced[1];
      mEvents = advanced[2];
    }

    if (!mounted) return;
    setState(() {
      _group = groupResolved;
      _trackCount = tracks.length;
      _activeEventCount = events.length;
      _recentTracks = List.from(tracks.take(10));
      _monthlyMembers = mMembers;
      _monthlyTracks = mTracks;
      _monthlyEvents = mEvents;
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
              if (_isProTier) ...[
                _SectionTitle(
                  accent: accent,
                  title: 'Andamento ultimi 6 mesi',
                  subtitle:
                      'Nuovi membri, tracce condivise ed eventi creati al mese',
                ),
                const SizedBox(height: 12),
                _MonthlyChart(
                  accent: accent,
                  label: 'Nuovi membri',
                  buckets: _monthlyMembers,
                ),
                const SizedBox(height: 12),
                _MonthlyChart(
                  accent: accent,
                  label: 'Tracce condivise',
                  buckets: _monthlyTracks,
                ),
                const SizedBox(height: 12),
                _MonthlyChart(
                  accent: accent,
                  label: 'Eventi nel periodo',
                  buckets: _monthlyEvents,
                ),
                const SizedBox(height: 32),
                _SectionTitle(
                  accent: accent,
                  title: 'Tracce recenti',
                  subtitle:
                      'Ultime 10 condivise nel gruppo (ranking per wishlist '
                      'in arrivo)',
                ),
                const SizedBox(height: 8),
                if (_recentTracks.isEmpty)
                  Text(
                    'Nessuna traccia condivisa.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ..._recentTracks.map((t) => _TrackRow(track: t, accent: accent)),
                const SizedBox(height: 32),
                _ProInArrivoTeaser(accent: accent),
              ] else
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

class _SectionTitle extends StatelessWidget {
  final Color accent;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: Colors.white, size: 11),
                  const SizedBox(width: 3),
                  const Text(
                    'PRO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  final Color accent;
  final String label;
  final List<MonthlyBucket> buckets;

  const _MonthlyChart({
    required this.accent,
    required this.label,
    required this.buckets,
  });

  static const _monthNames = [
    'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
    'lug', 'ago', 'set', 'ott', 'nov', 'dic',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxCount = buckets.fold<int>(0, (m, b) => b.count > m ? b.count : m);
    final total = buckets.fold<int>(0, (s, b) => s + b.count);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Totale: $total',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in buckets) ...[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (b.count > 0)
                          Text(
                            '${b.count}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        const SizedBox(height: 2),
                        Container(
                          height: maxCount == 0
                              ? 4
                              : (b.count / maxCount * 44).clamp(4.0, 44.0),
                          decoration: BoxDecoration(
                            color: b.count == 0
                                ? accent.withValues(alpha: 0.15)
                                : accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (b != buckets.last) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final b in buckets) ...[
                Expanded(
                  child: Text(
                    _monthNames[b.month.month - 1],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (b != buckets.last) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final Track track;
  final Color accent;

  const _TrackRow({required this.track, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final km = (track.stats.distance / 1000).toStringAsFixed(1);
    final ele = track.stats.elevationGain.toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.route, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$km km · ↗ ${ele}m',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
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

class _ProInArrivoTeaser extends StatelessWidget {
  final Color accent;
  const _ProInArrivoTeaser({required this.accent});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'In arrivo nel tier Pro',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• Funnel di acquisizione (QR visto → join → traccia seguita)\n'
            '• Mappa geografica utenti per provincia/regione\n'
            '• Ranking tracce per wishlist (Pro avanzato)\n'
            '• Notifiche push + email automatiche per i membri',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
