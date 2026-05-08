// Web-only file (compilato solo per lib/main_web.dart).
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/group_brand.dart';
import '../../data/models/track.dart';
import '../../data/repositories/groups_repository.dart';
import '../../data/repositories/tracks_repository.dart';

/// Versione **web-native** delle statistiche gruppo Business.
///
/// Migliora il port mobile con:
/// - Selettore periodo (30gg / 3 mesi / 6 mesi / 12 mesi)
/// - KPI tile con delta % vs periodo precedente
/// - LineChart sovrapposto (membri / tracce / eventi)
/// - Breakdown attività per macro-categoria (% del totale)
/// - Top 5 membri più attivi nel periodo (# tracce condivise)
/// - Export CSV delle tracce del periodo
///
/// Le sezioni avanzate (chart, breakdown, top members) sono gating
/// Pro: per Verified si vede solo il blocco KPI base + teaser upgrade.
class WebGroupStatsPage extends StatefulWidget {
  final Group group;
  const WebGroupStatsPage({super.key, required this.group});

  @override
  State<WebGroupStatsPage> createState() => _WebGroupStatsPageState();
}

enum _Period { d30, m3, m6, m12 }

extension _PeriodX on _Period {
  String get label {
    switch (this) {
      case _Period.d30:
        return '30 giorni';
      case _Period.m3:
        return '3 mesi';
      case _Period.m6:
        return '6 mesi';
      case _Period.m12:
        return '12 mesi';
    }
  }

  Duration get duration {
    switch (this) {
      case _Period.d30:
        return const Duration(days: 30);
      case _Period.m3:
        return const Duration(days: 90);
      case _Period.m6:
        return const Duration(days: 180);
      case _Period.m12:
        return const Duration(days: 365);
    }
  }

  /// Mesi del trend chart corrispondenti.
  int get months {
    switch (this) {
      case _Period.d30:
        return 1;
      case _Period.m3:
        return 3;
      case _Period.m6:
        return 6;
      case _Period.m12:
        return 12;
    }
  }
}

class _WebGroupStatsPageState extends State<WebGroupStatsPage> {
  final _groupsRepo = GroupsRepository();
  final _tracksRepo = TracksRepository();

  bool _loading = true;
  _Period _period = _Period.m6;

  // Dati raw — il selettore periodo filtra client-side
  List<GroupMember> _members = [];
  List<Track> _tracks = [];
  List<GroupEvent> _allEvents = [];
  List<MonthlyBucket> _memberTrend = [];
  List<MonthlyBucket> _trackTrend = [];
  List<MonthlyBucket> _eventTrend = [];

  bool get _isProTier {
    final t = widget.group.businessTier;
    return t == 'pro' || t == 'enterprise';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final groupId = widget.group.id;

    Future<T> safe<T>(Future<T> f, T fallback, String tag) {
      return f.catchError((e, st) {
        if (kDebugMode) {
          debugPrint('[Stats] $tag failed: $e');
        }
        return fallback;
      });
    }

    final months = _period.months;
    final results = await Future.wait<Object?>([
      safe(_groupsRepo.getMembers(groupId), <GroupMember>[], 'members'),
      safe(_tracksRepo.getGroupTracksLightweight(groupId), <Track>[],
          'tracks'),
      // upcomingOnly:false per avere TUTTI gli eventi (passati+futuri)
      // — server-side il repo la accetta, lo verifichiamo nel layout.
      safe(
          _groupsRepo.getEvents(groupId, upcomingOnly: false),
          <GroupEvent>[],
          'events'),
      safe(_groupsRepo.getMonthlyMemberJoins(groupId, months: months),
          <MonthlyBucket>[], 'memberTrend'),
      safe(_groupsRepo.getMonthlyTrackShares(groupId, months: months),
          <MonthlyBucket>[], 'trackTrend'),
      safe(_groupsRepo.getMonthlyEventCreations(groupId, months: months),
          <MonthlyBucket>[], 'eventTrend'),
    ]);

    if (!mounted) return;

    setState(() {
      _members = (results[0] as List).cast<GroupMember>();
      _tracks = (results[1] as List).cast<Track>();
      _allEvents = (results[2] as List).cast<GroupEvent>();
      _memberTrend = (results[3] as List).cast<MonthlyBucket>();
      _trackTrend = (results[4] as List).cast<MonthlyBucket>();
      _eventTrend = (results[5] as List).cast<MonthlyBucket>();
      _loading = false;
    });
  }

  // ────────────────────────────────────────────────────────────
  // CALCOLI PERIODO
  // ────────────────────────────────────────────────────────────

  DateTime get _cutoffCurrent =>
      DateTime.now().subtract(_period.duration);
  DateTime get _cutoffPrev =>
      DateTime.now().subtract(_period.duration * 2);

  int _countInRange<T>(
    Iterable<T> items,
    DateTime Function(T) date,
    DateTime from,
    DateTime to,
  ) {
    int n = 0;
    for (final i in items) {
      final d = date(i);
      if (!d.isBefore(from) && d.isBefore(to)) n++;
    }
    return n;
  }

  ({int curr, int prev, double? pct}) _kpi<T>(
    Iterable<T> items,
    DateTime Function(T) date,
  ) {
    final now = DateTime.now();
    final curr = _countInRange(items, date, _cutoffCurrent, now);
    final prev = _countInRange(items, date, _cutoffPrev, _cutoffCurrent);
    double? pct;
    if (prev > 0) {
      pct = (curr - prev) / prev * 100;
    } else if (curr > 0) {
      pct = null; // "nuovo" — niente baseline
    } else {
      pct = 0;
    }
    return (curr: curr, prev: prev, pct: pct);
  }

  // ────────────────────────────────────────────────────────────
  // CSV EXPORT
  // ────────────────────────────────────────────────────────────

  void _exportCsv() {
    final cutoff = _cutoffCurrent;
    final list = _tracks
        .where((t) => (t.recordedAt ?? t.createdAt).isAfter(cutoff))
        .toList();
    final memberById = {for (final m in _members) m.userId: m.username};

    final buf = StringBuffer();
    buf.writeln(
      'Nome,Membro,Attività,Data,Distanza km,D+ m,Durata min',
    );
    for (final t in list) {
      final user =
          (t.userId != null ? memberById[t.userId] : null) ?? 'Sconosciuto';
      final date = (t.recordedAt ?? t.createdAt).toUtc().toIso8601String();
      final km = (t.stats.distance / 1000).toStringAsFixed(2);
      final ele = t.stats.elevationGain.toStringAsFixed(0);
      final mins = t.stats.duration.inMinutes;
      buf.writeln(
        '${_csv(t.name)},${_csv(user)},${t.activityType.name},'
        '$date,$km,$ele,$mins',
      );
    }

    _download(
      buf.toString(),
      'stats-${widget.group.name.replaceAll(' ', '_')}-${_period.name}.csv',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Esportate ${list.length} tracce del periodo'),
        backgroundColor: const Color(0xFF2E7D5B),
      ),
    );
  }

  String _csv(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  void _download(String content, String filename) {
    final blob = html.Blob([content], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  // ────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = groupAccentColor(widget.group);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text('${widget.group.name} · Statistiche')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final kMembers = _kpi<GroupMember>(_members, (m) => m.joinedAt);
    final kTracks = _kpi<Track>(
        _tracks, (t) => t.recordedAt ?? t.createdAt);
    final kEvents = _kpi<GroupEvent>(_allEvents, (e) => e.date);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('${widget.group.name} · Statistiche')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            _buildToolbar(accent),
            const SizedBox(height: 16),
            _buildKpiGrid(accent, kMembers, kTracks, kEvents),
            const SizedBox(height: 20),
            if (_isProTier) ...[
              _buildTrendCard(accent),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 1,
                    child: _ActivityBreakdownCard(
                      tracks: _tracksInPeriod,
                      accent: accent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: _TopMembersCard(
                      tracks: _tracksInPeriod,
                      members: _members,
                      accent: accent,
                    ),
                  ),
                ],
              ),
            ] else
              _UpgradeTeaser(accent: accent),
          ],
        ),
      ),
    );
  }

  List<Track> get _tracksInPeriod {
    final cutoff = _cutoffCurrent;
    return _tracks
        .where((t) => (t.recordedAt ?? t.createdAt).isAfter(cutoff))
        .toList();
  }

  Widget _buildToolbar(Color accent) {
    return Row(
      children: [
        const Text(
          'Periodo:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 12),
        for (final p in _Period.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(p.label),
              selected: _period == p,
              onSelected: (_) {
                setState(() => _period = p);
                _load();
              },
              selectedColor: accent.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: _period == p
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: _period == p ? accent : AppColors.textPrimary,
              ),
              side: BorderSide(
                color: _period == p
                    ? accent.withValues(alpha: 0.4)
                    : AppColors.border,
              ),
              showCheckmark: false,
            ),
          ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _tracksInPeriod.isEmpty ? null : _exportCsv,
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Esporta CSV'),
        ),
      ],
    );
  }

  Widget _buildKpiGrid(
    Color accent,
    ({int curr, int prev, double? pct}) members,
    ({int curr, int prev, double? pct}) tracks,
    ({int curr, int prev, double? pct}) events,
  ) {
    return GridView.count(
      crossAxisCount: 4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _KpiTile(
          icon: Icons.groups,
          color: accent,
          label: 'Membri totali',
          value: _members.length.toString(),
          delta: '+${members.curr} nel periodo',
        ),
        _KpiTile(
          icon: Icons.person_add_alt,
          color: const Color(0xFF2E7D5B),
          label: 'Nuovi membri',
          value: members.curr.toString(),
          deltaPct: members.pct,
        ),
        _KpiTile(
          icon: Icons.route,
          color: const Color(0xFF1976D2),
          label: 'Tracce condivise',
          value: tracks.curr.toString(),
          deltaPct: tracks.pct,
        ),
        _KpiTile(
          icon: Icons.event,
          color: const Color(0xFFE65100),
          label: 'Eventi nel periodo',
          value: events.curr.toString(),
          deltaPct: events.pct,
        ),
      ],
    );
  }

  Widget _buildTrendCard(Color accent) {
    final maxV = [
      ..._memberTrend.map((b) => b.count),
      ..._trackTrend.map((b) => b.count),
      ..._eventTrend.map((b) => b.count),
    ].fold<int>(0, (m, v) => v > m ? v : m);
    final maxY = maxV <= 0 ? 5.0 : (maxV * 1.3).ceilToDouble();
    final months = _memberTrend.length;

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
          Row(
            children: [
              Text(
                'Trend ${_period.label.toLowerCase()}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _LegendDot(color: accent, label: 'Membri'),
              const SizedBox(width: 12),
              _LegendDot(
                  color: const Color(0xFF1976D2), label: 'Tracce'),
              const SizedBox(width: 12),
              _LegendDot(
                  color: const Color(0xFFE65100), label: 'Eventi'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.border,
                    strokeWidth: 1,
                    dashArray: const [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: maxY / 4,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        const labels = [
                          'gen','feb','mar','apr','mag','giu',
                          'lug','ago','set','ott','nov','dic',
                        ];
                        final i = v.toInt();
                        if (i < 0 || i >= _memberTrend.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            labels[_memberTrend[i].month.month - 1],
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  _line(_memberTrend, accent, months),
                  _line(_trackTrend, const Color(0xFF1976D2), months),
                  _line(_eventTrend, const Color(0xFFE65100), months),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _line(
      List<MonthlyBucket> buckets, Color color, int n) {
    return LineChartBarData(
      spots: [
        for (int i = 0; i < buckets.length; i++)
          FlSpot(i.toDouble(), buckets[i].count.toDouble()),
      ],
      isCurved: true,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(show: n <= 6),
    );
  }
}

// ============================================================
// KPI TILE
// ============================================================

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? delta;
  final double? deltaPct;
  const _KpiTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.delta,
    this.deltaPct,
  });

  @override
  Widget build(BuildContext context) {
    String? deltaText = delta;
    Color deltaColor = const Color(0xFF2E7D5B);
    if (deltaPct != null) {
      final pct = deltaPct!;
      final sign = pct >= 0 ? '+' : '';
      deltaText = '$sign${pct.toStringAsFixed(0)}% vs prec.';
      deltaColor = pct >= 0
          ? const Color(0xFF2E7D5B)
          : Colors.red.shade700;
    } else if (deltaPct == null && delta == null) {
      deltaText = 'nuovo';
      deltaColor = const Color(0xFF2E7D5B);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (deltaText != null)
                  Text(
                    deltaText,
                    style: TextStyle(
                      fontSize: 10,
                      color: deltaColor,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }
}

// ============================================================
// ACTIVITY BREAKDOWN
// ============================================================

class _ActivityBreakdownCard extends StatelessWidget {
  final List<Track> tracks;
  final Color accent;
  const _ActivityBreakdownCard({
    required this.tracks,
    required this.accent,
  });

  String _macro(ActivityType t) {
    switch (t) {
      case ActivityType.trekking:
      case ActivityType.walking:
      case ActivityType.snowshoeing:
        return 'Trek/Cammino';
      case ActivityType.trailRunning:
      case ActivityType.running:
        return 'Corsa';
      case ActivityType.cycling:
      case ActivityType.mountainBiking:
      case ActivityType.gravelBiking:
      case ActivityType.eBike:
      case ActivityType.eMountainBike:
        return 'Bici';
      case ActivityType.alpineSkiing:
      case ActivityType.skiTouring:
      case ActivityType.nordicSkiing:
      case ActivityType.snowboarding:
        return 'Neve';
    }
  }

  Color _color(String label) {
    switch (label) {
      case 'Trek/Cammino':
        return const Color(0xFF2E7D5B);
      case 'Corsa':
        return const Color(0xFFE65100);
      case 'Bici':
        return const Color(0xFF1976D2);
      case 'Neve':
        return const Color(0xFF6A1B9A);
      default:
        return accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final t in tracks) {
      final g = _macro(t.activityType);
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
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
            'Tipo attività',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Nessuna traccia nel periodo',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BreakdownRow(
                  label: e.key,
                  count: e.value,
                  pct: e.value / total,
                  color: _color(e.key),
                ),
              ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final int count;
  final double pct;
  final Color color;
  const _BreakdownRow({
    required this.label,
    required this.count,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$count · ${(pct * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
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
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TOP MEMBERS
// ============================================================

class _TopMembersCard extends StatelessWidget {
  final List<Track> tracks;
  final List<GroupMember> members;
  final Color accent;
  const _TopMembersCard({
    required this.tracks,
    required this.members,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final memberById = {for (final m in members) m.userId: m};
    final counts = <String, int>{};
    final kmByUser = <String, double>{};
    for (final t in tracks) {
      final uid = t.userId;
      if (uid == null || uid.isEmpty) continue;
      counts[uid] = (counts[uid] ?? 0) + 1;
      kmByUser[uid] = (kmByUser[uid] ?? 0) + t.stats.distance / 1000;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();

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
            'Top membri attivi',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (top.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Nessuna attività nel periodo',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            for (int i = 0; i < top.length; i++) ...[
              _topRow(i, top[i], memberById, kmByUser),
              if (i < top.length - 1) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _topRow(
    int rank,
    MapEntry<String, int> entry,
    Map<String, GroupMember> memberById,
    Map<String, double> kmByUser,
  ) {
    final m = memberById[entry.key];
    final name = m?.username ?? 'Utente sconosciuto';
    final initial =
        name.isNotEmpty ? name[0].toUpperCase() : '?';
    final km = kmByUser[entry.key] ?? 0;

    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '#${rank + 1}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
            ),
          ),
        ),
        CircleAvatar(
          radius: 14,
          backgroundColor: accent.withValues(alpha: 0.15),
          backgroundImage: m?.avatarUrl != null
              ? NetworkImage(m!.avatarUrl!)
              : null,
          child: m?.avatarUrl == null
              ? Text(
                  initial,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${entry.value} tracce · ${km.toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// UPGRADE TEASER (Verified)
// ============================================================

class _UpgradeTeaser extends StatelessWidget {
  final Color accent;
  const _UpgradeTeaser({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.10),
            accent.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.workspace_premium, color: accent, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Statistiche avanzate disponibili con Pro',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Trend mensili sovrapposti, breakdown per attività, '
                  'top membri attivi e CSV export. Contattaci per '
                  'attivare il tier Pro sul tuo gruppo.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
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
