import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/business_repository.dart';

/// Pagina statistiche owner-only per uno Spazio Pro.
/// - KPI cards (visite, click contatti, follower, recensioni)
/// - Trend visite ultimi 14 giorni (line chart)
/// - Breakdown click contatti per tipo (barre)
class BusinessAnalyticsPage extends StatefulWidget {
  final Business business;
  const BusinessAnalyticsPage({super.key, required this.business});

  @override
  State<BusinessAnalyticsPage> createState() => _BusinessAnalyticsPageState();
}

class _BusinessAnalyticsPageState extends State<BusinessAnalyticsPage> {
  final _repo = BusinessRepository();
  int _rangeDays = 14;
  Future<List<BusinessAnalyticsDay>>? _dailyFuture;

  @override
  void initState() {
    super.initState();
    _reloadDaily();
  }

  void _reloadDaily() {
    _dailyFuture =
        _repo.getAnalyticsDaily(widget.business.id!, days: _rangeDays);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiche'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_reloadDaily),
          ),
        ],
      ),
      body: StreamBuilder<BusinessAnalyticsTotals>(
        stream: _repo.watchAnalyticsTotals(widget.business.id!),
        builder: (context, snap) {
          final totals = snap.data ?? const BusinessAnalyticsTotals();
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reloadDaily);
              await _dailyFuture;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildKpiGrid(totals),
                const SizedBox(height: 24),
                _buildRangeSelector(),
                const SizedBox(height: 12),
                _buildTrendChart(),
                const SizedBox(height: 24),
                _buildContactBreakdown(totals),
                const SizedBox(height: 24),
                _buildPrivacyNote(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildKpiGrid(BusinessAnalyticsTotals t) {
    final b = widget.business;
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: [
        _KpiCard(
          icon: Icons.visibility,
          color: AppColors.primary,
          label: 'Visite profilo',
          value: '${t.profileViews}',
          subtitle: 'Totale lifetime',
        ),
        _KpiCard(
          icon: Icons.chat_bubble_outline,
          color: AppColors.success,
          label: 'Click contatti',
          value: '${t.totalContactClicks}',
          subtitle: t.profileViews > 0
              ? '${(t.totalContactClicks * 100 / t.profileViews).toStringAsFixed(1)}% conv.'
              : '—',
        ),
        _KpiCard(
          icon: Icons.people,
          color: AppColors.info,
          label: 'Follower',
          value: '${b.followerCount}',
          subtitle: 'Totale',
        ),
        _KpiCard(
          icon: Icons.star_outline,
          color: AppColors.warning,
          label: 'Recensioni',
          value: '${b.reviewCount}',
          subtitle: b.rating != null
              ? '${b.rating!.toStringAsFixed(1)} / 5 ★'
              : '—',
        ),
      ],
    );
  }

  Widget _buildRangeSelector() {
    return Row(
      children: [
        const Text('Periodo:',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(width: 12),
        ChoiceChip(
          label: const Text('7gg'),
          selected: _rangeDays == 7,
          onSelected: (_) => setState(() {
            _rangeDays = 7;
            _reloadDaily();
          }),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('14gg'),
          selected: _rangeDays == 14,
          onSelected: (_) => setState(() {
            _rangeDays = 14;
            _reloadDaily();
          }),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('30gg'),
          selected: _rangeDays == 30,
          onSelected: (_) => setState(() {
            _rangeDays = 30;
            _reloadDaily();
          }),
        ),
      ],
    );
  }

  Widget _buildTrendChart() {
    return FutureBuilder<List<BusinessAnalyticsDay>>(
      future: _dailyFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final days = snap.data ?? [];
        final maxY = days.fold<int>(
            0, (m, d) => d.profileViews > m ? d.profileViews : m);
        final hasData = days.any((d) => d.profileViews > 0);

        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.show_chart,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Visite ultimi $_rangeDays giorni',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const Spacer(),
                    if (hasData)
                      Text(
                        'Tot: ${days.fold<int>(0, (s, d) => s + d.profileViews)}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: hasData
                      ? LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: (maxY + 1).toDouble(),
                            gridData: const FlGridData(
                              show: true,
                              drawVerticalLine: false,
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 28,
                                  interval: maxY <= 4
                                      ? 1
                                      : (maxY / 4).ceilToDouble(),
                                  getTitlesWidget: (v, _) => Text(
                                    v.toInt().toString(),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 24,
                                  interval: (days.length / 5)
                                      .ceilToDouble()
                                      .clamp(1, double.infinity),
                                  getTitlesWidget: (v, _) {
                                    final idx = v.toInt();
                                    if (idx < 0 || idx >= days.length) {
                                      return const SizedBox.shrink();
                                    }
                                    final d = days[idx].date;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '${d.day}/${d.month}',
                                        style:
                                            const TextStyle(fontSize: 10),
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
                                  for (var i = 0; i < days.length; i++)
                                    FlSpot(
                                        i.toDouble(),
                                        days[i].profileViews.toDouble()),
                                ],
                                isCurved: true,
                                curveSmoothness: 0.25,
                                color: AppColors.primary,
                                barWidth: 3,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (s, _, __, ___) =>
                                      FlDotCirclePainter(
                                    radius: 3,
                                    color: AppColors.primary,
                                    strokeColor: Colors.white,
                                    strokeWidth: 1,
                                  ),
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: AppColors.primary
                                      .withValues(alpha: 0.15),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const Center(
                          child: Text(
                            'Nessuna visita registrata in questo periodo',
                            style: TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContactBreakdown(BusinessAnalyticsTotals t) {
    final items = <_ContactItem>[
      _ContactItem('WhatsApp', Icons.chat, t.contactClicksWhatsApp,
          const Color(0xFF25D366)),
      _ContactItem('Telefono', Icons.phone, t.contactClicksPhone,
          AppColors.success),
      _ContactItem('Email', Icons.email, t.contactClicksEmail,
          AppColors.info),
      _ContactItem('Sito web', Icons.language, t.contactClicksWebsite,
          AppColors.primary),
      _ContactItem('Indicazioni', Icons.directions,
          t.contactClicksDirections, AppColors.warning),
    ];
    final maxCount = items.fold<int>(0, (m, i) => i.count > m ? i.count : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Click per tipo di contatto',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            ...items.map((it) {
              final pct = maxCount == 0 ? 0.0 : it.count / maxCount;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(it.icon, size: 16, color: it.color),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: Text(
                        it.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 8,
                          backgroundColor: AppColors.border,
                          color: it.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${it.count}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'Le statistiche sono aggregate e anonime: non vengono salvate '
        'le identità dei visitatori. Le tue stesse visite (come owner) '
        'non vengono conteggiate.',
        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
    );
  }
}

class _ContactItem {
  final String label;
  final IconData icon;
  final int count;
  final Color color;
  const _ContactItem(this.label, this.icon, this.count, this.color);
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String subtitle;

  const _KpiCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
