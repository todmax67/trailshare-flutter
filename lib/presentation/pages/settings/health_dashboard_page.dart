import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/services/health_service.dart';

/// Dashboard Salute — mostra dati aggregati da Health Connect
class HealthDashboardPage extends StatefulWidget {
  const HealthDashboardPage({super.key});

  @override
  State<HealthDashboardPage> createState() => _HealthDashboardPageState();
}

class _HealthDashboardPageState extends State<HealthDashboardPage> {
  final HealthService _healthService = HealthService();

  bool _isLoading = true;
  int _todaySteps = 0;
  int? _restingHR;
  Map<String, double> _weeklyCalories = {};
  Map<String, int> _weeklySteps = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _healthService.getTodaySteps(),
        _healthService.getRestingHeartRate(),
        _healthService.getWeeklyCalories(),
        _healthService.getWeeklySteps(),
      ]);

      if (mounted) {
        setState(() {
          _todaySteps = results[0] as int;
          _restingHR = results[1] as int?;
          _weeklyCalories = results[2] as Map<String, double>;
          _weeklySteps = results[3] as Map<String, int>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[HealthDashboard] Errore caricamento: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.healthDashboard),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Carte principali
                    _buildMainCards(),
                    const SizedBox(height: 24),

                    // Grafico passi settimanali
                    _buildSectionTitle(context.l10n.stepsLast7Days),
                    const SizedBox(height: 8),
                    _buildWeeklyStepsChart(),
                    const SizedBox(height: 24),

                    // Grafico calorie settimanali
                    _buildSectionTitle(context.l10n.caloriesLast7Days),
                    const SizedBox(height: 8),
                    _buildWeeklyCaloriesChart(),
                    const SizedBox(height: 24),

                    // Info
                    _buildInfoCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMainCards() {
    return Row(
      children: [
        Expanded(
          child: _DashboardCard(
            icon: Icons.directions_walk,
            title: context.l10n.stepsToday,
            value: _formatSteps(_todaySteps),
            subtitle: _stepsGoalText(),
            color: AppColors.primary,
            progress: (_todaySteps / 10000).clamp(0.0, 1.0),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DashboardCard(
            icon: Icons.favorite,
            title: context.l10n.restingHR,
            value: _restingHR != null ? '$_restingHR' : '--',
            subtitle: _restingHR != null ? 'bpm' : context.l10n.notAvailable,
            color: AppColors.danger,
          ),
        ),
      ],
    );
  }

  String _formatSteps(int steps) {
    if (steps >= 1000) {
      return '${(steps / 1000).toStringAsFixed(1)}k';
    }
    return '$steps';
  }

  String _stepsGoalText() {
    final pct = ((_todaySteps / 10000) * 100).round();
    if (_todaySteps >= 10000) return context.l10n.goalReached;
    return context.l10n.percentOfGoal(pct);
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildWeeklyStepsChart() {
    if (_weeklySteps.isEmpty) {
      return _buildEmptyChart(context.l10n.noStepsData);
    }

    final entries = _weeklySteps.entries.toList();
    final maxSteps = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxY = (maxSteps * 1.2).clamp(1000, double.infinity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY.toDouble(),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => Colors.white,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final key = entries[groupIndex].key;
                    return BarTooltipItem(
                      '$key\n${entries[groupIndex].value} ${context.l10n.stepsUnit}',
                      TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx >= 0 && idx < entries.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            entries[idx].key,
                            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              barGroups: entries.asMap().entries.map((entry) {
                final isToday = entry.key == entries.length - 1;
                return BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(
                      toY: entry.value.value.toDouble(),
                      color: isToday ? AppColors.primary : AppColors.primary.withOpacity(0.4),
                      width: 28,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyCaloriesChart() {
    if (_weeklyCalories.isEmpty) {
      return _buildEmptyChart(context.l10n.noCaloriesData);
    }

    final entries = _weeklyCalories.entries.toList();
    final maxCal = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxY = (maxCal * 1.2).clamp(100, double.infinity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY.toDouble(),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => Colors.white,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final key = entries[groupIndex].key;
                    return BarTooltipItem(
                      '$key\n${entries[groupIndex].value.round()} kcal',
                      TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx >= 0 && idx < entries.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            entries[idx].key,
                            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              barGroups: entries.asMap().entries.map((entry) {
                final isToday = entry.key == entries.length - 1;
                return BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(
                      toY: entry.value.value,
                      color: isToday ? AppColors.warning : AppColors.warning.withOpacity(0.4),
                      width: 28,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChart(String message) {
    return Card(
      child: SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart, size: 48, color: Colors.grey[300]),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: AppColors.primary.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.primary.withOpacity(0.7), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.healthDataInfo,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET: Dashboard Card
// ═══════════════════════════════════════════════════════════════════════════

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final double? progress;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: color.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}