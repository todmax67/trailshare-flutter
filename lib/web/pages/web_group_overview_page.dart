import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/group_brand.dart';
import '../../data/repositories/groups_repository.dart';

/// Landing page del singolo gruppo Business — sostituisce la vecchia
/// destinazione "Personalizza" come prima cosa che vede l'admin.
///
/// Mostra: tier badge + invite code, 4 KPI tile (membri / eventi
/// futuri / tracce 30gg / nuovi membri 30gg), quick actions, prossimi
/// eventi (top 3) e trend 6 mesi (membri vs eventi).
class WebGroupOverviewPage extends StatefulWidget {
  final Group group;

  /// Callback usato dalle quick actions per spostarsi su un altro
  /// tab della shell ([WebGroupDashboardPage]) senza dover navigare
  /// fuori. Indici target: 1=Personalizza, 2=Stats, 3=Membri.
  final ValueChanged<int> onNavigateTab;

  const WebGroupOverviewPage({
    super.key,
    required this.group,
    required this.onNavigateTab,
  });

  @override
  State<WebGroupOverviewPage> createState() => _WebGroupOverviewPageState();
}

class _WebGroupOverviewPageState extends State<WebGroupOverviewPage> {
  final _repo = GroupsRepository();

  bool _loading = true;

  // KPI snapshot
  int _memberCount = 0;
  int _newMembers30d = 0;
  int _tracks30d = 0;
  int _upcomingEvents = 0;

  // Trend
  List<MonthlyBucket> _memberTrend = [];
  List<MonthlyBucket> _eventTrend = [];

  // Top 3 eventi prossimi
  List<GroupEvent> _nextEvents = [];

  // Invite code
  String? _inviteCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final groupId = widget.group.id;
    final cutoff30d = DateTime.now().subtract(const Duration(days: 30));

    // Wrappiamo ogni Future con .catchError() così se una singola query
    // fallisce (es. indice mancante per count compound) il dashboard
    // mostra comunque le altre KPI invece di restare in loading
    // infinito. La log dell'errore aiuta a diagnosticare in console.
    Future<T> safe<T>(Future<T> f, T fallback, String tag) {
      return f.catchError((e, st) {
        if (kDebugMode) {
          debugPrint('[Overview] $tag failed: $e');
        }
        return fallback;
      });
    }

    final results = await Future.wait<Object?>([
      safe(_repo.getMembers(groupId), <GroupMember>[], 'getMembers'),
      safe(_repo.getEvents(groupId, upcomingOnly: true),
          <GroupEvent>[], 'getEvents'),
      safe(_repo.getMonthlyMemberJoins(groupId, months: 6),
          <MonthlyBucket>[], 'memberJoins'),
      safe(_repo.getMonthlyEventCreations(groupId, months: 6),
          <MonthlyBucket>[], 'eventCreations'),
      // Tracce 30gg: invece di una count() aggregation con compound
      // filter (groupIds arrayContains + createdAt >) — che richiede
      // un indice composito su collectionGroup non disponibile —
      // riusiamo getMonthlyTrackShares(1) che fa solo
      // `where groupIds arrayContains` (indice single-field già ok)
      // e filtra per data client-side.
      safe(_repo.getMonthlyTrackShares(groupId, months: 1),
          <MonthlyBucket>[], 'trackShares30d'),
      safe(_repo.ensureInviteCode(groupId), null, 'inviteCode'),
    ]);

    if (!mounted) return;

    final members = (results[0] as List).cast<GroupMember>();
    final events = (results[1] as List).cast<GroupEvent>();
    final memberTrend = (results[2] as List).cast<MonthlyBucket>();
    final eventTrend = (results[3] as List).cast<MonthlyBucket>();
    final trackShares30d = (results[4] as List).cast<MonthlyBucket>();
    final inviteCode = results[5] as String?;

    final tracks30d =
        trackShares30d.fold<int>(0, (s, b) => s + b.count);
    final newMembers30d =
        members.where((m) => m.joinedAt.isAfter(cutoff30d)).length;

    final next = [...events];
    next.sort((a, b) => a.date.compareTo(b.date));

    setState(() {
      _memberCount = members.length;
      _newMembers30d = newMembers30d;
      _upcomingEvents = events.length;
      _tracks30d = tracks30d;
      _memberTrend = memberTrend;
      _eventTrend = eventTrend;
      _nextEvents = next.take(3).toList();
      _inviteCode = inviteCode;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = groupAccentColor(widget.group);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${widget.group.name} · Panoramica'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  _HeroBanner(
                    group: widget.group,
                    accent: accent,
                    inviteCode: _inviteCode,
                  ),
                  const SizedBox(height: 20),
                  _KpiGrid(
                    memberCount: _memberCount,
                    newMembers30d: _newMembers30d,
                    upcomingEvents: _upcomingEvents,
                    tracks30d: _tracks30d,
                    accent: accent,
                  ),
                  const SizedBox(height: 20),
                  _QuickActions(
                    accent: accent,
                    onNavigate: widget.onNavigateTab,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _TrendCard(
                          accent: accent,
                          memberTrend: _memberTrend,
                          eventTrend: _eventTrend,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: _NextEventsCard(
                          events: _nextEvents,
                          accent: accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

// ============================================================
// HERO BANNER
// ============================================================

class _HeroBanner extends StatelessWidget {
  final Group group;
  final Color accent;
  final String? inviteCode;
  const _HeroBanner({
    required this.group,
    required this.accent,
    required this.inviteCode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.14),
            accent.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _GroupAvatar(group: group, accent: accent, size: 64),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        group.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _TierBadge(group: group, accent: accent),
                  ],
                ),
                if (group.description != null &&
                    group.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    group.description!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (inviteCode != null) _InviteCodeBox(code: inviteCode!),
        ],
      ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  final Group group;
  final Color accent;
  final double size;
  const _GroupAvatar({
    required this.group,
    required this.accent,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final url = group.avatarUrl;
    final initial = group.name.isNotEmpty ? group.name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: url != null && url.isNotEmpty
          ? ClipOval(
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initial(initial),
              ),
            )
          : _initial(initial),
    );
  }

  Widget _initial(String c) => Center(
        child: Text(
          c,
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
}

class _TierBadge extends StatelessWidget {
  final Group group;
  final Color accent;
  const _TierBadge({required this.group, required this.accent});

  @override
  Widget build(BuildContext context) {
    final label = group.businessTierLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _InviteCodeBox extends StatelessWidget {
  final String code;
  const _InviteCodeBox({required this.code});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Copia codice invito',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Codice $code copiato'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Codice invito',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.content_copy,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// KPI GRID
// ============================================================

class _KpiGrid extends StatelessWidget {
  final int memberCount;
  final int newMembers30d;
  final int upcomingEvents;
  final int tracks30d;
  final Color accent;
  const _KpiGrid({
    required this.memberCount,
    required this.newMembers30d,
    required this.upcomingEvents,
    required this.tracks30d,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
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
          label: 'Membri',
          value: memberCount.toString(),
          sub: newMembers30d > 0 ? '+$newMembers30d in 30gg' : null,
        ),
        _KpiTile(
          icon: Icons.event,
          color: const Color(0xFFE65100),
          label: 'Eventi prossimi',
          value: upcomingEvents.toString(),
        ),
        _KpiTile(
          icon: Icons.route,
          color: const Color(0xFF1976D2),
          label: 'Tracce 30gg',
          value: tracks30d.toString(),
        ),
        _KpiTile(
          icon: Icons.trending_up,
          color: const Color(0xFF2E7D5B),
          label: 'Nuovi membri 30gg',
          value: newMembers30d.toString(),
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? sub;
  const _KpiTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
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
                if (sub != null)
                  Text(
                    sub!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF2E7D5B),
                      fontWeight: FontWeight.w700,
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

// ============================================================
// QUICK ACTIONS
// ============================================================

class _QuickActions extends StatelessWidget {
  final Color accent;
  final ValueChanged<int> onNavigate;
  const _QuickActions({required this.accent, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _ActionButton(
            icon: Icons.palette_outlined,
            label: 'Personalizza brand',
            color: accent,
            onTap: () => onNavigate(1),
          ),
          _ActionButton(
            icon: Icons.bar_chart,
            label: 'Statistiche dettagliate',
            color: accent,
            onTap: () => onNavigate(2),
          ),
          _ActionButton(
            icon: Icons.people_outline,
            label: 'Gestisci membri',
            color: accent,
            onTap: () => onNavigate(3),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// TREND CARD (6 mesi: membri vs eventi)
// ============================================================

class _TrendCard extends StatelessWidget {
  final Color accent;
  final List<MonthlyBucket> memberTrend;
  final List<MonthlyBucket> eventTrend;
  const _TrendCard({
    required this.accent,
    required this.memberTrend,
    required this.eventTrend,
  });

  @override
  Widget build(BuildContext context) {
    final maxMembers = memberTrend.fold<int>(0, (m, b) => b.count > m ? b.count : m);
    final maxEvents = eventTrend.fold<int>(0, (m, b) => b.count > m ? b.count : m);
    final maxV = (maxMembers > maxEvents ? maxMembers : maxEvents).toDouble();
    final maxY = maxV <= 0 ? 5.0 : (maxV * 1.3).ceilToDouble();

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
              const Text(
                'Trend ultimi 6 mesi',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _LegendDot(color: accent, label: 'Nuovi membri'),
              const SizedBox(width: 12),
              _LegendDot(
                color: const Color(0xFFE65100),
                label: 'Eventi creati',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
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
                        const months = [
                          'gen','feb','mar','apr','mag','giu',
                          'lug','ago','set','ott','nov','dic',
                        ];
                        final i = v.toInt();
                        if (i < 0 || i >= memberTrend.length) {
                          return const SizedBox.shrink();
                        }
                        final m = memberTrend[i].month.month - 1;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            months[m],
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
                  LineChartBarData(
                    spots: [
                      for (int i = 0; i < memberTrend.length; i++)
                        FlSpot(i.toDouble(), memberTrend[i].count.toDouble()),
                    ],
                    isCurved: true,
                    color: accent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: accent.withValues(alpha: 0.10),
                    ),
                  ),
                  LineChartBarData(
                    spots: [
                      for (int i = 0; i < eventTrend.length; i++)
                        FlSpot(i.toDouble(), eventTrend[i].count.toDouble()),
                    ],
                    isCurved: true,
                    color: const Color(0xFFE65100),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
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
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// NEXT EVENTS CARD
// ============================================================

class _NextEventsCard extends StatelessWidget {
  final List<GroupEvent> events;
  final Color accent;
  const _NextEventsCard({required this.events, required this.accent});

  String _dateLabel(DateTime d) {
    const months = [
      'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
      'lug', 'ago', 'set', 'ott', 'nov', 'dic',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} · $hh:$mm';
  }

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
            'Prossimi eventi',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.event_available,
                    size: 36,
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Nessun evento in programma',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Crea un evento dall\'app mobile per coinvolgere i tuoi membri.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final e in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.event,
                        color: accent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_dateLabel(e.date)} · '
                            '${e.participants.length} iscritti',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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
