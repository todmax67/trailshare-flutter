import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/track.dart';
import '../../../../data/models/tour.dart';

/// Epic 11 — Grafico altimetria multi-tappa per un Tour.
///
/// Asse X: distanza progressiva totale (km), accumulata da tappa a
/// tappa. Asse Y: elevazione (m). Ogni tappa ha colore proprio
/// (allineato ai colori delle polyline sulla mappa). Tra una tappa
/// e l'altra inseriamo un "gap" visivo (linea tratteggiata sottile
/// che simula la sera in rifugio) — interpretato come distanza zero
/// ma con dt visivamente comunicato.
///
/// Due varianti del costruttore:
/// - [.fromTracks] per la detail owner che ha le tracce private
///   complete (TrackPoint con elevation).
/// - [.fromStageSummaries] per la community detail dove abbiamo
///   solo le polyline downsamplate dentro le stages. Le elevation
///   non sono presenti nelle TourStageSummary attuali → fallback
///   "no data" con messaggio invece di un chart vuoto. (TODO 7.H/11
///   future: aggiungere elevation array al TourStageSummary
///   denormalizzato.)
class MultiStageElevationChart extends StatelessWidget {
  final List<_StageElevationSeries> _series;

  const MultiStageElevationChart._(this._series);

  /// Build dalle tracks private dell'owner. Estrae l'elevation per
  /// ogni punto. Se una traccia non ha elevation registrata, viene
  /// skippata (il grafico funziona comunque con le rimanenti).
  factory MultiStageElevationChart.fromTracks(List<Track> tracks) {
    double cumulativeKm = 0;
    final out = <_StageElevationSeries>[];
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      final points = t.points;
      if (points.length < 2) {
        cumulativeKm += t.stats.distanceKm;
        continue;
      }

      final spots = <FlSpot>[];
      double localKm = 0;
      double? prevLat;
      double? prevLng;
      for (final p in points) {
        if (prevLat != null && prevLng != null) {
          localKm += _haversineKm(prevLat, prevLng, p.latitude, p.longitude);
        }
        prevLat = p.latitude;
        prevLng = p.longitude;
        final elev = p.elevation;
        if (elev != null) {
          spots.add(FlSpot(cumulativeKm + localKm, elev));
        }
      }
      if (spots.isNotEmpty) {
        out.add(_StageElevationSeries(
          stageIndex: i,
          name: t.name,
          spots: spots,
          color: _stageColor(i),
        ));
      }
      cumulativeKm += t.stats.distanceKm;
    }
    return MultiStageElevationChart._(out);
  }

  /// Build dalle stage summaries (community). Per ora ritorna chart
  /// vuoto: le summary non includono elevation array.
  factory MultiStageElevationChart.fromStageSummaries(
      List<TourStageSummary> stages) {
    return const MultiStageElevationChart._([]);
  }

  static Color _stageColor(int i) {
    const palette = [
      AppColors.primary,
      AppColors.info,
      AppColors.success,
      AppColors.warning,
      Colors.purpleAccent,
      Colors.cyan,
      Colors.deepOrange,
      Colors.indigo,
    ];
    return palette[i % palette.length];
  }

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final lat1Rad = lat1 * math.pi / 180.0;
    final lat2Rad = lat2 * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  @override
  Widget build(BuildContext context) {
    if (_series.isEmpty) {
      return Container(
        height: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Dati altimetria non disponibili per questo tour.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    final allSpots = _series.expand((s) => s.spots).toList();
    if (allSpots.isEmpty) return const SizedBox.shrink();

    final maxKm = allSpots.map((s) => s.x).reduce((a, b) => a > b ? a : b);
    final minElev =
        allSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxElev =
        allSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    // Margine 5% sopra e sotto.
    final yMargin = (maxElev - minElev) * 0.05;
    final yMin = minElev - yMargin;
    final yMax = maxElev + yMargin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Altimetria',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxKm,
              minY: yMin,
              maxY: yMax,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (yMax - yMin) / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.border,
                  strokeWidth: 0.5,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: maxKm > 60
                        ? 20
                        : maxKm > 20
                            ? 10
                            : 5,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toStringAsFixed(0)}km',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textMuted),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: (yMax - yMin) / 4,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toStringAsFixed(0)}m',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  bottom: BorderSide(color: AppColors.border),
                  left: BorderSide(color: AppColors.border),
                ),
              ),
              lineBarsData: [
                for (final s in _series)
                  LineChartBarData(
                    spots: s.spots,
                    isCurved: true,
                    barWidth: 2,
                    color: s.color,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: s.color.withValues(alpha: 0.18),
                    ),
                  ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Colors.black87,
                  getTooltipItems: (spots) => spots.map((spot) {
                    return LineTooltipItem(
                      '${spot.x.toStringAsFixed(1)}km · ${spot.y.toStringAsFixed(0)}m',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Legenda compatta
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final s in _series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'T${s.stageIndex + 1}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _StageElevationSeries {
  final int stageIndex;
  final String name;
  final List<FlSpot> spots;
  final Color color;
  const _StageElevationSeries({
    required this.stageIndex,
    required this.name,
    required this.spots,
    required this.color,
  });
}

