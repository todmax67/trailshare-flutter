import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/gamification_service.dart';
import '../../../core/services/monthly_report_service.dart';
import '../../../data/models/monthly_report.dart';
import '../../../data/models/track.dart';
import '../../widgets/stat_number.dart';
import '../../widgets/topo_empty_state.dart';

/// Pagina "Il mio mese" — report mensile automatico con stats aggregate,
/// confronto col mese precedente, badge sbloccati e record del mese.
///
/// La pagina permette di navigare tra i mesi passati con frecce < / >.
/// Il mese corrente è sempre rigenerato on-demand; i mesi passati sono
/// letti dalla cache Firestore (se esistono).
class MonthlyReportPage extends StatefulWidget {
  /// Se fornito, la pagina apre direttamente su questo mese (yyyy-MM).
  /// Default: mese corrente.
  final String? initialYearMonthId;

  const MonthlyReportPage({super.key, this.initialYearMonthId});

  @override
  State<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  late String _currentId;
  MonthlyReport? _report;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _currentId =
        widget.initialYearMonthId ?? MonthBoundaries.forNow().yearMonthId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final service = MonthlyReportService();
    MonthlyReport? r;
    // Per il mese corrente e per il mese precedente entro i primi 7 giorni
    // rigeneriamo (le tracce potrebbero essere state aggiunte). Per mesi
    // più vecchi leggiamo solo il doc storico.
    final nowId = MonthBoundaries.forNow().yearMonthId;
    final previousId = MonthBoundaries.forNow().previous().yearMonthId;
    if (_currentId == nowId) {
      r = await service.generateForMonth(_currentId);
    } else if (_currentId == previousId && DateTime.now().day <= 7) {
      r = await service.generateForMonth(_currentId);
    } else {
      r = await service.getForMonth(_currentId);
    }

    // Se è il mese precedente e l'utente lo sta aprendo, marchiamolo come
    // visto così il prompt Discovery scompare.
    if (_currentId == previousId) {
      await service.markPreviousReportViewed();
    }

    if (!mounted) return;
    setState(() {
      _report = r;
      _loading = false;
    });
  }

  void _goPrevious() {
    final parts = _currentId.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final prevMonth = month == 1 ? 12 : month - 1;
    final prevYear = month == 1 ? year - 1 : year;
    setState(() {
      _currentId = MonthBoundaries.forYearMonth(prevYear, prevMonth).yearMonthId;
    });
    _load();
  }

  void _goNext() {
    final parts = _currentId.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final nextMonth = month == 12 ? 1 : month + 1;
    final nextYear = month == 12 ? year + 1 : year;
    final candidate = MonthBoundaries.forYearMonth(nextYear, nextMonth);
    // Blocca la navigazione oltre il mese corrente.
    final currentBounds = MonthBoundaries.forNow();
    if (candidate.start.isAfter(currentBounds.start)) return;
    setState(() {
      _currentId = candidate.yearMonthId;
    });
    _load();
  }

  bool get _canGoNext {
    return _currentId != MonthBoundaries.forNow().yearMonthId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.monthlyReportTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: context.textPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMonthSelector(),
            const SizedBox(height: 16),
            if (_report == null || _report!.isEmpty)
              _buildEmpty()
            else ...[
              _buildHero(_report!),
              const SizedBox(height: 20),
              _buildStatsGrid(_report!),
              const SizedBox(height: 20),
              if (_report!.activeDays > 0) _buildActiveDays(_report!),
              const SizedBox(height: 20),
              if (_report!.bestDistance > 0 || _report!.bestElevation > 0)
                _buildRecords(_report!),
              const SizedBox(height: 20),
              if (_report!.activityTypes.isNotEmpty)
                _buildActivityBreakdown(_report!),
              const SizedBox(height: 20),
              if (_report!.badgesUnlocked.isNotEmpty)
                _buildBadges(_report!),
              const SizedBox(height: 20),
              if (_report!.xpEarned > 0) _buildXpBanner(_report!),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final parts = _currentId.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final monthName = DateFormat.yMMMM(locale).format(DateTime(year, month));
    final capitalized = monthName.isNotEmpty
        ? '${monthName[0].toUpperCase()}${monthName.substring(1)}'
        : monthName;

    return Row(
      children: [
        IconButton(
          onPressed: _goPrevious,
          icon: const Icon(Icons.chevron_left),
          tooltip: context.l10n.monthlyReportPrevious,
        ),
        Expanded(
          child: Text(
            capitalized,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
        ),
        IconButton(
          onPressed: _canGoNext ? _goNext : null,
          icon: const Icon(Icons.chevron_right),
          tooltip: context.l10n.monthlyReportNext,
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    final isCurrent = _currentId == MonthBoundaries.forNow().yearMonthId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: TopoEmptyState(
        title: context.l10n.monthlyReportEmptyTitle,
        message: isCurrent
            ? context.l10n.monthlyReportEmptyCurrent
            : context.l10n.monthlyReportEmptyPast,
        variant: 2,
      ),
    );
  }

  Widget _buildHero(MonthlyReport r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.monthlyReportHeroLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatNumber.hero(
                r.distanceKm.toStringAsFixed(1),
                unit: 'km',
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (r.distanceDeltaPercent != null)
            _DeltaChip(percent: r.distanceDeltaPercent!)
          else
            Text(
              context.l10n.monthlyReportNoPrevious,
              style: TextStyle(
                fontSize: 12,
                color: context.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(MonthlyReport r) {
    final items = <_StatItem>[
      _StatItem(
        icon: Icons.trending_up,
        label: context.l10n.elevation,
        value: r.elevationGain.toStringAsFixed(0),
        unit: 'm',
        delta: r.elevationDeltaPercent,
      ),
      _StatItem(
        icon: Icons.schedule,
        label: context.l10n.duration,
        value: _formatDurationShort(r.durationAsDuration),
        unit: '',
        delta: r.durationDeltaPercent,
      ),
      _StatItem(
        icon: Icons.route,
        label: context.l10n.tracks,
        value: r.trackCount.toString(),
        unit: '',
        delta: r.tracksDeltaPercent,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.monthlyReportStatsSection,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              Expanded(child: _StatCard(item: items[i])),
              if (i != items.length - 1) const SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildActiveDays(MonthlyReport r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.themedBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.calendar_today_outlined,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.monthlyReportActiveDays(r.activeDays),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.monthlyReportActiveDaysSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecords(MonthlyReport r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.monthlyReportRecords,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        if (r.bestDistance > 0)
          _RecordTile(
            icon: Icons.straighten,
            color: const Color(0xFF1976D2),
            label: context.l10n.monthlyReportRecordLongest,
            value: '${(r.bestDistance / 1000).toStringAsFixed(1)} km',
            subtitle: r.bestDistanceName,
          ),
        if (r.bestDistance > 0 && r.bestElevation > 0)
          const SizedBox(height: 8),
        if (r.bestElevation > 0)
          _RecordTile(
            icon: Icons.trending_up,
            color: AppColors.success,
            label: context.l10n.monthlyReportRecordHighest,
            value: '${r.bestElevation.toStringAsFixed(0)} m',
            subtitle: r.bestElevationName,
          ),
      ],
    );
  }

  Widget _buildActivityBreakdown(MonthlyReport r) {
    final total = r.activityTypes.values.fold<int>(0, (s, v) => s + v);
    if (total == 0) return const SizedBox.shrink();

    // Ordina per frequenza decrescente.
    final entries = r.activityTypes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.monthlyReportActivities,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        for (final e in entries) _buildActivityRow(e.key, e.value, total),
      ],
    );
  }

  Widget _buildActivityRow(String key, int count, int total) {
    ActivityType? activity;
    try {
      activity = ActivityType.values.firstWhere((a) => a.name == key);
    } catch (_) {
      activity = null;
    }
    final ratio = count / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            activity?.icon ?? '🏃',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              activity?.displayName ?? key,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 32,
            child: Text(
              count.toString(),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadges(MonthlyReport r) {
    final badges = r.badgesUnlocked.map((id) {
      try {
        return GamificationService.availableBadges.firstWhere(
          (b) => b.id == id,
        );
      } catch (_) {
        return null;
      }
    }).whereType<GameBadge>().toList();

    if (badges.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.monthlyReportBadges(badges.length),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: badges.map((b) => _BadgeChip(badge: b)).toList(),
        ),
      ],
    );
  }

  Widget _buildXpBanner(MonthlyReport r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.warning.withValues(alpha: 0.18),
            AppColors.warning.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '✨',
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.monthlyReportXpEarned(r.xpEarned),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.monthlyReportXpSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers formatting ────────────────────────────────────────────
  String _formatDurationShort(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h${m > 0 ? ' ${m}m' : ''}';
    return '${m}m';
  }
}

// ══════════════════════════════════════════════════════════════════════
// Inner widgets
// ══════════════════════════════════════════════════════════════════════

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final double? delta;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.delta,
  });
}

class _StatCard extends StatelessWidget {
  final _StatItem item;

  const _StatCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.themedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 18, color: context.textSecondary),
          const SizedBox(height: 8),
          StatNumber.medium(
            item.value,
            unit: item.unit.isEmpty ? null : item.unit,
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textMuted,
              letterSpacing: 0.3,
            ),
          ),
          if (item.delta != null) ...[
            const SizedBox(height: 6),
            _DeltaChip(percent: item.delta!, small: true),
          ],
        ],
      ),
    );
  }
}

/// Chip che mostra la delta rispetto al mese precedente con freccia up/down.
class _DeltaChip extends StatelessWidget {
  final double percent;
  final bool small;

  const _DeltaChip({required this.percent, this.small = false});

  @override
  Widget build(BuildContext context) {
    final isUp = percent >= 0;
    final color = isUp ? AppColors.success : const Color(0xFFEF5350);
    final bg = color.withValues(alpha: 0.14);
    final fontSize = small ? 10.5 : 12.0;
    final iconSize = small ? 12.0 : 14.0;
    final pad = small ? 6.0 : 10.0;

    // Nelle stat card "small" la stringa completa "X% vs mese scorso"
    // crea overflow (3 card affiancate → ognuna troppo stretta).
    // Mostriamo solo "↓ X%": il "vs mese scorso" è implicito dal
    // contesto della pagina monthly report. Per il chip grande
    // (DISTANZA TOTALE in cima) lasciamo invece la stringa completa.
    final label = small
        ? '${percent.abs().toStringAsFixed(0)}%'
        : '${percent.abs().toStringAsFixed(0)}% ${context.l10n.monthlyReportVsPrevious}';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.arrow_upward : Icons.arrow_downward,
            size: iconSize,
            color: color,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? subtitle;

  const _RecordTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.themedBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.textMuted,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final GameBadge badge;

  const _BadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.themedBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            badge.icon,
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(width: 8),
          Text(
            badge.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
