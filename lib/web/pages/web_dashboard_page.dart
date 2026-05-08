import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/track.dart';
import '../../data/repositories/tracks_repository.dart';
import '../business_web_app.dart';

/// Home dashboard della dashboard web — sostituisce il vecchio default
/// "Le mie tracce" come prima pagina post-login. Stile Strava/Garmin:
///
/// - Stats della settimana corrente (km, dislivello, tempo, attività)
/// - Grafico volume ultime 12 settimane
/// - Breakdown per tipo attività
/// - Lista ultime 5 tracce
/// - Lifetime stats (sidecard)
///
/// Tutto computato client-side da getMyTracks() — niente nuove query
/// Firestore, riusa lo stesso fetch della tracks list (cache HTTP).
class WebDashboardPage extends StatefulWidget {
  const WebDashboardPage({super.key});

  @override
  State<WebDashboardPage> createState() => _WebDashboardPageState();
}

class _WebDashboardPageState extends State<WebDashboardPage> {
  final _repo = TracksRepository();
  List<Track>? _tracks;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tracks = await _repo.getMyTracks();
      if (!mounted) return;
      setState(() => _tracks = tracks);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _tracks == null && _error == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _load)
                : _buildContent(_tracks!),
      ),
    );
  }

  Widget _buildContent(List<Track> tracks) {
    final stats = _DashboardStats.compute(tracks);
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(activitiesTotal: stats.lifetime.count),
              const SizedBox(height: 24),

              // Top row: 4 stat cards (this week)
              _StatCardsRow(weekly: stats.thisWeek),
              const SizedBox(height: 24),

              // Middle: chart 12 settimane + breakdown attività
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 900;
                  final chart = _VolumeChart(weeks: stats.last12Weeks);
                  final breakdown =
                      _ActivityBreakdown(perType: stats.thisWeek.perActivity);
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: chart),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: breakdown),
                      ],
                    );
                  }
                  return Column(children: [chart, const SizedBox(height: 16), breakdown]);
                },
              ),
              const SizedBox(height: 24),

              // Bottom: ultime 5 tracce + lifetime sidecard
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 900;
                  final recent = _RecentTracks(tracks: stats.recent5);
                  final lifetime = _LifetimeCard(stats: stats.lifetime);
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: recent),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: lifetime),
                      ],
                    );
                  }
                  return Column(children: [recent, const SizedBox(height: 16), lifetime]);
                },
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ─── Stats computation ───────────────────────────────────────────────

class _DashboardStats {
  final _PeriodStats thisWeek;
  final List<_WeekVolume> last12Weeks;
  final List<Track> recent5;
  final _LifetimeStats lifetime;

  _DashboardStats({
    required this.thisWeek,
    required this.last12Weeks,
    required this.recent5,
    required this.lifetime,
  });

  factory _DashboardStats.compute(List<Track> tracks) {
    final now = DateTime.now();
    final mondayThis = _mondayOf(now);

    // This week tracks
    final thisWeek = tracks
        .where((t) => (t.recordedAt ?? t.createdAt).isAfter(mondayThis))
        .toList();

    // Last 12 weeks volume
    final weeks = <_WeekVolume>[];
    for (int i = 11; i >= 0; i--) {
      final start = mondayThis.subtract(Duration(days: 7 * i));
      final end = start.add(const Duration(days: 7));
      final inWeek = tracks.where((t) {
        final d = t.recordedAt ?? t.createdAt;
        return !d.isBefore(start) && d.isBefore(end);
      });
      double km = 0;
      for (final t in inWeek) {
        km += t.stats.distance / 1000;
      }
      weeks.add(_WeekVolume(start: start, distanceKm: km));
    }

    // Recent 5
    final sorted = [...tracks]..sort((a, b) =>
        (b.recordedAt ?? b.createdAt).compareTo(a.recordedAt ?? a.createdAt));
    final recent = sorted.take(5).toList();

    // Lifetime
    double totalKm = 0;
    double totalGain = 0;
    int totalSecs = 0;
    final activityCount = <String, int>{};
    for (final t in tracks) {
      totalKm += t.stats.distance / 1000;
      totalGain += t.stats.elevationGain;
      totalSecs += t.stats.duration.inSeconds;
      final key = t.activityType.name;
      activityCount[key] = (activityCount[key] ?? 0) + 1;
    }

    return _DashboardStats(
      thisWeek: _PeriodStats.compute(thisWeek),
      last12Weeks: weeks,
      recent5: recent,
      lifetime: _LifetimeStats(
        count: tracks.length,
        totalDistanceKm: totalKm,
        totalElevationGain: totalGain,
        totalDuration: Duration(seconds: totalSecs),
        activityBreakdown: activityCount,
      ),
    );
  }

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }
}

class _PeriodStats {
  final int count;
  final double distanceKm;
  final double elevationGain;
  final Duration duration;
  final Map<String, int> perActivity;

  _PeriodStats({
    required this.count,
    required this.distanceKm,
    required this.elevationGain,
    required this.duration,
    required this.perActivity,
  });

  factory _PeriodStats.compute(List<Track> tracks) {
    double km = 0;
    double gain = 0;
    int secs = 0;
    final per = <String, int>{};
    for (final t in tracks) {
      km += t.stats.distance / 1000;
      gain += t.stats.elevationGain;
      secs += t.stats.duration.inSeconds;
      final key = t.activityType.name;
      per[key] = (per[key] ?? 0) + 1;
    }
    return _PeriodStats(
      count: tracks.length,
      distanceKm: km,
      elevationGain: gain,
      duration: Duration(seconds: secs),
      perActivity: per,
    );
  }
}

class _WeekVolume {
  final DateTime start;
  final double distanceKm;
  _WeekVolume({required this.start, required this.distanceKm});
}

class _LifetimeStats {
  final int count;
  final double totalDistanceKm;
  final double totalElevationGain;
  final Duration totalDuration;
  final Map<String, int> activityBreakdown;
  _LifetimeStats({
    required this.count,
    required this.totalDistanceKm,
    required this.totalElevationGain,
    required this.totalDuration,
    required this.activityBreakdown,
  });
}

// ─── UI components ───────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int activitiesTotal;
  const _Header({required this.activitiesTotal});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? user?.email?.split('@').first ?? 'Tu';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ciao, $name 👋',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          activitiesTotal == 0
              ? 'Nessuna attività registrata. Apri TrailShare sul telefono.'
              : '$activitiesTotal attività totali. Ecco un riassunto della tua settimana.',
          style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _StatCardsRow extends StatelessWidget {
  final _PeriodStats weekly;
  const _StatCardsRow({required this.weekly});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        icon: Icons.straighten,
        label: 'Distanza',
        value: '${weekly.distanceKm.toStringAsFixed(1)} km',
        accent: AppColors.primary,
        sub: 'questa settimana',
      ),
      _StatCard(
        icon: Icons.trending_up,
        label: 'Dislivello',
        value: '+${weekly.elevationGain.round()} m',
        accent: AppColors.success,
        sub: 'questa settimana',
      ),
      _StatCard(
        icon: Icons.schedule,
        label: 'Tempo',
        value: _formatDuration(weekly.duration),
        accent: AppColors.info,
        sub: 'questa settimana',
      ),
      _StatCard(
        icon: Icons.flag,
        label: 'Attività',
        value: '${weekly.count}',
        accent: AppColors.warning,
        sub: 'questa settimana',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 700;
        if (wide) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 12),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '0m';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color accent;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _VolumeChart extends StatelessWidget {
  final List<_WeekVolume> weeks;
  const _VolumeChart({required this.weeks});

  @override
  Widget build(BuildContext context) {
    final maxKm = weeks.fold<double>(
        0, (m, w) => w.distanceKm > m ? w.distanceKm : m);
    final yMax = (maxKm < 10 ? 10 : (maxKm * 1.15)).ceilToDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Volume ultime 12 settimane',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'km percorsi a settimana',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: yMax,
                barGroups: [
                  for (int i = 0; i < weeks.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: weeks[i].distanceKm,
                          color: AppColors.primary,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, meta) {
                        if (v == 0 || v == meta.max) return const SizedBox.shrink();
                        return Text(
                          v.toInt().toString(),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, meta) {
                        // Mostra label ogni 2 settimane
                        final i = v.toInt();
                        if (i < 0 || i >= weeks.length || i % 2 != 0) {
                          return const SizedBox.shrink();
                        }
                        final w = weeks[i];
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${w.start.day}/${w.start.month}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: AppColors.border,
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIdx, rod, rodIdx) {
                      final w = weeks[group.x.toInt()];
                      return BarTooltipItem(
                        '${w.distanceKm.toStringAsFixed(1)} km',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityBreakdown extends StatelessWidget {
  final Map<String, int> perType;
  const _ActivityBreakdown({required this.perType});

  static const _colors = [
    AppColors.primary,
    AppColors.success,
    AppColors.info,
    AppColors.warning,
    AppColors.danger,
  ];

  @override
  Widget build(BuildContext context) {
    final entries = perType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (s, e) => s + e.value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tipi di attività',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'questa settimana',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nessuna attività questa settimana.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            for (int i = 0; i < entries.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BreakdownRow(
                  label: _activityLabel(entries[i].key),
                  count: entries[i].value,
                  total: total,
                  color: _colors[i % _colors.length],
                ),
              ),
        ],
      ),
    );
  }

  String _activityLabel(String code) {
    switch (code) {
      case 'trekking':
        return 'Trekking';
      case 'running':
        return 'Corsa';
      case 'trailRunning':
        return 'Trail running';
      case 'walking':
        return 'Camminata';
      case 'cycling':
        return 'Bici strada';
      case 'mountainBiking':
        return 'MTB';
      case 'gravelBiking':
        return 'Gravel';
      case 'eBike':
        return 'E-Bike';
      case 'eMountainBike':
        return 'E-MTB';
      case 'skiTouring':
        return 'Scialpinismo';
      default:
        return code;
    }
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _BreakdownRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (count / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _RecentTracks extends StatelessWidget {
  final List<Track> tracks;
  const _RecentTracks({required this.tracks});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ultime attività',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (tracks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Nessuna traccia ancora.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            )
          else
            for (final t in tracks)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  final id = t.id;
                  if (id == null) return;
                  Navigator.pushNamed(
                    context,
                    WebRoutes.trackDetail(id),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _iconFor(t.activityType),
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _formatDate(t.recordedAt ?? t.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(t.stats.distance / 1000).toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 16, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  IconData _iconFor(ActivityType t) {
    switch (t) {
      case ActivityType.cycling:
      case ActivityType.gravelBiking:
      case ActivityType.eBike:
        return Icons.directions_bike;
      case ActivityType.mountainBiking:
      case ActivityType.eMountainBike:
        return Icons.pedal_bike;
      case ActivityType.running:
      case ActivityType.trailRunning:
        return Icons.directions_run;
      case ActivityType.skiTouring:
        return Icons.downhill_skiing;
      default:
        return Icons.hiking;
    }
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d).inDays;
    if (diff == 0) return 'Oggi';
    if (diff == 1) return 'Ieri';
    if (diff < 7) return '${diff}g fa';
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _LifetimeCard extends StatelessWidget {
  final _LifetimeStats stats;
  const _LifetimeCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final hours = stats.totalDuration.inHours;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.06),
            AppColors.info.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'Lifetime',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _LifetimeRow(
            label: 'Distanza totale',
            value: '${stats.totalDistanceKm.toStringAsFixed(0)} km',
          ),
          _LifetimeRow(
            label: 'Dislivello totale',
            value: '+${stats.totalElevationGain.round()} m',
          ),
          _LifetimeRow(
            label: 'Tempo totale',
            value: '$hours h',
          ),
          _LifetimeRow(
            label: 'Attività',
            value: '${stats.count}',
          ),
          if (stats.activityBreakdown.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              'PER TIPOLOGIA',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            for (final e in (stats.activityBreakdown.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value))))
              _LifetimeRow(label: _label(e.key), value: '${e.value}'),
          ],
        ],
      ),
    );
  }

  String _label(String code) {
    return code[0].toUpperCase() + code.substring(1);
  }
}

class _LifetimeRow extends StatelessWidget {
  final String label;
  final String value;
  const _LifetimeRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: AppColors.danger.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            'Errore caricamento dashboard',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Riprova'),
          ),
        ],
      ),
    );
  }
}
