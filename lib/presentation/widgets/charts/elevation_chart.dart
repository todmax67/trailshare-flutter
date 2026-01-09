import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/track.dart';

/// Grafico elevazione per una traccia
class ElevationChart extends StatefulWidget {
  final List<TrackPoint> points;
  final double height;

  const ElevationChart({
    super.key,
    required this.points,
    this.height = 200,
  });

  @override
  State<ElevationChart> createState() => _ElevationChartState();
}

class _ElevationChartState extends State<ElevationChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final data = _buildChartData();
    
    if (data.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'Dati elevazione non disponibili',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    final minEle = data.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    final maxEle = data.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    final maxDist = data.last.x;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.terrain, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Profilo altimetrico',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Text(
                '${minEle.toStringAsFixed(0)} - ${maxEle.toStringAsFixed(0)} m',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),

        // Grafico
        SizedBox(
          height: widget.height,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: _calculateInterval(maxEle - minEle),
                getDrawingHorizontalLine: (value) => FlLine(
                  color: AppColors.border.withOpacity(0.5),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: _calculateDistanceInterval(maxDist),
                    getTitlesWidget: (value, meta) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${value.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 45,
                    interval: _calculateInterval(maxEle - minEle),
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()} m',
                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: const Border(
                  bottom: BorderSide(color: AppColors.border),
                  left: BorderSide(color: AppColors.border),
                ),
              ),
              minX: 0,
              maxX: maxDist,
              minY: (minEle - 20).clamp(0, double.infinity),
              maxY: maxEle + 20,
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (spot) => AppColors.textPrimary.withOpacity(0.9),
                  tooltipBorderRadius: BorderRadius.circular(8),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      return LineTooltipItem(
                        '${spot.y.toStringAsFixed(0)} m\n${spot.x.toStringAsFixed(2)} km',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList();
                  },
                ),
                touchCallback: (event, response) {
                  setState(() {
                    if (response?.lineBarSpots != null && response!.lineBarSpots!.isNotEmpty) {
                      _touchedIndex = response.lineBarSpots!.first.spotIndex;
                    } else {
                      _touchedIndex = null;
                    }
                  });
                },
                handleBuiltInTouches: true,
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: data,
                  isCurved: true,
                  curveSmoothness: 0.2,
                  color: AppColors.primary,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.primary.withOpacity(0.3),
                        AppColors.primary.withOpacity(0.05),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Label asse X
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Center(
            child: Text(
              'Distanza (km)',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ),
        ),
      ],
    );
  }

  /// Costruisce i punti per il grafico
  List<FlSpot> _buildChartData() {
    final List<FlSpot> spots = [];
    double cumulativeDistance = 0;

    for (int i = 0; i < widget.points.length; i++) {
      final point = widget.points[i];
      
      // Calcola distanza cumulativa
      if (i > 0) {
        cumulativeDistance += widget.points[i - 1].distanceTo(point);
      }

      // Aggiungi solo punti con elevazione valida
      if (point.elevation != null) {
        spots.add(FlSpot(
          cumulativeDistance / 1000, // km
          point.elevation!,
        ));
      }
    }

    // Riduci i punti se troppi (per performance)
    if (spots.length > 200) {
      return _reducePoints(spots, 200);
    }

    return spots;
  }

  /// Riduce il numero di punti mantenendo la forma
  List<FlSpot> _reducePoints(List<FlSpot> spots, int maxPoints) {
    final step = (spots.length / maxPoints).ceil();
    final reduced = <FlSpot>[];
    
    for (int i = 0; i < spots.length; i += step) {
      reduced.add(spots[i]);
    }
    
    // Assicura che l'ultimo punto sia incluso
    if (reduced.last != spots.last) {
      reduced.add(spots.last);
    }
    
    return reduced;
  }

  /// Calcola intervallo per le linee orizzontali
  double _calculateInterval(double range) {
    if (range <= 50) return 10;
    if (range <= 100) return 20;
    if (range <= 200) return 50;
    if (range <= 500) return 100;
    if (range <= 1000) return 200;
    return 500;
  }

  /// Calcola intervallo per i label distanza
  double _calculateDistanceInterval(double maxDist) {
    if (maxDist <= 2) return 0.5;
    if (maxDist <= 5) return 1;
    if (maxDist <= 10) return 2;
    if (maxDist <= 20) return 5;
    return 10;
  }
}
