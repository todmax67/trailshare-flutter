import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../data/models/dashboard_stats.dart';
import '../../../data/repositories/dashboard_repository.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DashboardRepository _repository = DashboardRepository();
  
  DashboardStats? _stats;
  bool _isLoading = true;
  String? _error;
  
  // Filtri time series
  String _selectedMetric = 'distance'; // 'distance' | 'elevation'
  String _selectedPeriod = 'weekly'; // 'weekly' | 'monthly' | 'yearly'
  int _periodOffset = 0; // 0 = corrente, -1 = precedente, etc.

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final stats = await _repository.getDashboardStats();
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.dashboard),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _stats == null || _stats!.totalTracks == 0
                  ? _buildEmpty()
                  : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
          const SizedBox(height: 16),
          Text(context.l10n.errorWithDetails(_error ?? ''), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadStats,
            child: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            Text(
              context.l10n.noStatsAvailable,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.recordFirstTrackForStats,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats Grid
            _buildStatsGrid(),
            const SizedBox(height: 24),

            // Record Personali
            _buildRecordsSection(),
            const SizedBox(height: 24),

            // Grafico attività (Pie)
            _buildActivityPieChart(),
            const SizedBox(height: 24),

            // Grafico time series (Bar)
            _buildTimeSeriesChart(),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = _stats!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.summary,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _StatCard(
              icon: Icons.route,
              label: context.l10n.totalTracksLabel,
              value: '${stats.totalTracks}',
              color: AppColors.primary,
            ),
            _StatCard(
              icon: Icons.straighten,
              label: context.l10n.totalDistance,
              value: '${stats.totalDistanceKm.toStringAsFixed(1)} km',
              color: AppColors.info,
            ),
            _StatCard(
              icon: Icons.trending_up,
              label: context.l10n.totalElevation,
              value: '${stats.totalElevationGain.toStringAsFixed(0)} m',
              color: AppColors.success,
            ),
            _StatCard(
              icon: Icons.schedule,
              label: context.l10n.totalTime,
              value: stats.totalDurationFormatted,
              color: AppColors.warning,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecordsSection() {
    final stats = _stats!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events, color: AppColors.warning, size: 24),
            const SizedBox(width: 8),
            Text(
              context.l10n.personalRecords,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _RecordTile(
          icon: Icons.straighten,
          title: context.l10n.longestTrack,
          record: stats.longestTrack,
          color: AppColors.info,
        ),
        const SizedBox(height: 8),
        _RecordTile(
          icon: Icons.landscape,
          title: context.l10n.highestElevationRecord,
          record: stats.highestElevationTrack,
          color: AppColors.success,
        ),
        const SizedBox(height: 8),
        _RecordTile(
          icon: Icons.timer,
          title: context.l10n.longestDuration,
          record: stats.longestDurationTrack,
          color: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildActivityPieChart() {
    final stats = _stats!;
    
    if (stats.activityTypes.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = [
      AppColors.success,
      AppColors.info,
      AppColors.warning,
      AppColors.primary,
      AppColors.danger,
    ];

    final entries = stats.activityTypes.entries.toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.activityDistribution,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: Row(
            children: [
              // Pie chart
              Expanded(
                flex: 2,
                child: PieChart(
                  PieChartData(
                    sections: entries.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final percentage = (item.value / total * 100);
                      
                      return PieChartSectionData(
                        value: item.value.toDouble(),
                        title: '${percentage.toStringAsFixed(0)}%',
                        color: colors[index % colors.length],
                        radius: 60,
                        titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      );
                    }).toList(),
                    sectionsSpace: 2,
                    centerSpaceRadius: 30,
                  ),
                ),
              ),
              
              // Legenda
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: entries.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: colors[index % colors.length],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _formatActivityName(item.key),
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSeriesChart() {
    final stats = _stats!;
    final timeSeries = stats.timeSeries;
    
    if (timeSeries == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.trend,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        
        // Filtri metrica
        Row(
          children: [
            _FilterChip(
              label: context.l10n.distance,
              isSelected: _selectedMetric == 'distance',
              onTap: () => setState(() => _selectedMetric = 'distance'),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: context.l10n.elevation,
              isSelected: _selectedMetric == 'elevation',
              onTap: () => setState(() => _selectedMetric = 'elevation'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Filtri periodo
        Row(
          children: [
            _FilterChip(
              label: context.l10n.week,
              isSelected: _selectedPeriod == 'weekly',
              onTap: () => setState(() {
                _selectedPeriod = 'weekly';
                _periodOffset = 0;
              }),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: context.l10n.month,
              isSelected: _selectedPeriod == 'monthly',
              onTap: () => setState(() {
                _selectedPeriod = 'monthly';
                _periodOffset = 0;
              }),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: context.l10n.year,
              isSelected: _selectedPeriod == 'yearly',
              onTap: () => setState(() {
                _selectedPeriod = 'yearly';
                _periodOffset = 0;
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Navigazione periodo
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _periodOffset--),
            ),
            Text(
              _getPeriodLabel(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _periodOffset >= 0 ? null : () => setState(() => _periodOffset++),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Grafico
        SizedBox(
          height: 220,
          child: _buildBarChart(),
        ),
      ],
    );
  }

  Widget _buildBarChart() {
    final chartData = _getChartData();
    
    if (chartData.isEmpty) {
      return Center(
        child: Text(
          context.l10n.noDataForPeriod,
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    final maxY = chartData.fold<double>(0, (max, item) {
      final total = item.trekking + item.bike + item.run;
      return total > max ? total : max;
    });

    return BarChart(
      BarChartData(
        maxY: maxY * 1.2,
        barGroups: chartData.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: item.trekking + item.bike + item.run,
                width: 16,
                rodStackItems: [
                  BarChartRodStackItem(0, item.trekking, AppColors.success),
                  BarChartRodStackItem(item.trekking, item.trekking + item.bike, AppColors.info),
                  BarChartRodStackItem(item.trekking + item.bike, item.trekking + item.bike + item.run, AppColors.warning),
                ],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  _selectedMetric == 'distance' 
                      ? '${value.toStringAsFixed(0)}' 
                      : '${value.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < chartData.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      chartData[index].label,
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey[200]!,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final item = chartData[group.x];
              final unit = _selectedMetric == 'distance' ? 'km' : 'm';
              return BarTooltipItem(
                '${item.label}\n',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                children: [
                  TextSpan(
                    text: '${context.l10n.total}: ${(item.trekking + item.bike + item.run).toStringAsFixed(1)} $unit',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<_ChartItem> _getChartData() {
    final timeSeries = _stats?.timeSeries;
    if (timeSeries == null) return [];

    final now = DateTime.now();
    final List<_ChartItem> result = [];

    if (_selectedPeriod == 'weekly') {
      // Ultimi 7 giorni
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i + (-_periodOffset * 7)));
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final data = timeSeries.byDay[key];
        
        final dayNames = [context.l10n.daySun, context.l10n.dayMon, context.l10n.dayTue, context.l10n.dayWed, context.l10n.dayThu, context.l10n.dayFri, context.l10n.daySat];
        String label = dayNames[date.weekday % 7];
        if (i == 0 && _periodOffset == 0) label = context.l10n.today;
        
        result.add(_ChartItem(
          label: label,
          trekking: _selectedMetric == 'distance' 
              ? (data?.distance['trekking'] ?? 0)
              : (data?.elevation['trekking'] ?? 0),
          bike: _selectedMetric == 'distance'
              ? (data?.distance['bike'] ?? 0)
              : (data?.elevation['bike'] ?? 0),
          run: _selectedMetric == 'distance'
              ? (data?.distance['run'] ?? 0)
              : (data?.elevation['run'] ?? 0),
        ));
      }
    } else if (_selectedPeriod == 'monthly') {
      // Settimane del mese
      final targetMonth = DateTime(now.year, now.month + _periodOffset, 1);
      final weeksInMonth = _getWeeksInMonth(targetMonth);
      
      for (final weekKey in weeksInMonth) {
        final data = timeSeries.byWeek[weekKey];
        final weekNum = weekKey.split('-W').last;
        
        result.add(_ChartItem(
          label: 'W$weekNum',
          trekking: _selectedMetric == 'distance'
              ? (data?.distance['trekking'] ?? 0)
              : (data?.elevation['trekking'] ?? 0),
          bike: _selectedMetric == 'distance'
              ? (data?.distance['bike'] ?? 0)
              : (data?.elevation['bike'] ?? 0),
          run: _selectedMetric == 'distance'
              ? (data?.distance['run'] ?? 0)
              : (data?.elevation['run'] ?? 0),
        ));
      }
    } else {
      // Mesi dell'anno
      final targetYear = now.year + _periodOffset;
      final monthNames = [context.l10n.monthJanShort, context.l10n.monthFebShort, context.l10n.monthMarShort, context.l10n.monthAprShort, context.l10n.monthMayShort, context.l10n.monthJunShort, context.l10n.monthJulShort, context.l10n.monthAugShort, context.l10n.monthSepShort, context.l10n.monthOctShort, context.l10n.monthNovShort, context.l10n.monthDecShort];
      
      for (int m = 1; m <= 12; m++) {
        final key = '$targetYear-${m.toString().padLeft(2, '0')}';
        final data = timeSeries.byMonth[key];
        
        result.add(_ChartItem(
          label: monthNames[m - 1],
          trekking: _selectedMetric == 'distance'
              ? (data?.distance['trekking'] ?? 0)
              : (data?.elevation['trekking'] ?? 0),
          bike: _selectedMetric == 'distance'
              ? (data?.distance['bike'] ?? 0)
              : (data?.elevation['bike'] ?? 0),
          run: _selectedMetric == 'distance'
              ? (data?.distance['run'] ?? 0)
              : (data?.elevation['run'] ?? 0),
        ));
      }
    }

    return result;
  }

  List<String> _getWeeksInMonth(DateTime month) {
    final result = <String>[];
    var current = DateTime(month.year, month.month, 1);
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    
    while (current.isBefore(nextMonth)) {
      final weekKey = _getWeekKey(current);
      if (!result.contains(weekKey)) {
        result.add(weekKey);
      }
      current = current.add(const Duration(days: 7));
    }
    
    return result;
  }

  String _getWeekKey(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final dayOfYear = d.difference(DateTime.utc(d.year, 1, 1)).inDays;
    final weekOfYear = ((dayOfYear - d.weekday + 10) / 7).floor();
    return '${d.year}-W${weekOfYear.toString().padLeft(2, '0')}';
  }

  String _getPeriodLabel() {
    final now = DateTime.now();
    
    if (_selectedPeriod == 'weekly') {
      if (_periodOffset == 0) return context.l10n.thisWeek;
      if (_periodOffset == -1) return context.l10n.previousWeek;
      final start = now.subtract(Duration(days: now.weekday - 1 + (-_periodOffset * 7)));
      final end = start.add(const Duration(days: 6));
      return '${start.day}/${start.month} - ${end.day}/${end.month}';
    } else if (_selectedPeriod == 'monthly') {
      final target = DateTime(now.year, now.month + _periodOffset, 1);
      final monthNames = [context.l10n.monthJan, context.l10n.monthFeb, context.l10n.monthMar, context.l10n.monthApr, context.l10n.monthMay, context.l10n.monthJun,
                          context.l10n.monthJul, context.l10n.monthAug, context.l10n.monthSep, context.l10n.monthOct, context.l10n.monthNov, context.l10n.monthDec];
      return '${monthNames[target.month - 1]} ${target.year}';
    } else {
      return '${now.year + _periodOffset}';
    }
  }

  String _formatActivityName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('trek')) return 'Trekking';
    if (lower.contains('run') || lower.contains('trail')) return 'Trail Running';
    if (lower.contains('bik') || lower.contains('cycl')) return context.l10n.activityCycling;
    if (lower.contains('walk')) return context.l10n.activityWalking;
    return name[0].toUpperCase() + name.substring(1);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET AUSILIARI
// ═══════════════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final TrackRecord? record;
  final Color color;

  const _RecordTile({
    required this.icon,
    required this.title,
    this.record,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                Text(
                  record?.name ?? context.l10n.noRecord,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (record != null)
            Text(
              record!.formatted,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ChartItem {
  final String label;
  final double trekking;
  final double bike;
  final double run;

  _ChartItem({
    required this.label,
    required this.trekking,
    required this.bike,
    required this.run,
  });
}
