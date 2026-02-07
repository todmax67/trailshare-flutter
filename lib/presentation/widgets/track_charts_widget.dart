import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/elevation_processor.dart';
import '../../data/models/track.dart';

/// Tipo di grafico disponibile
enum ChartType {
  elevation,
  speed,
  heartRate,
  combined, // Elevazione + Velocità sovrapposti
}

/// Widget unificato per visualizzare grafici della traccia
/// 
/// Supporta:
/// - Grafico elevazione
/// - Grafico velocità
/// - Grafico battito cardiaco (se disponibile)
/// - Vista combinata con overlay
/// - Tap per vedere dettagli punto
class TrackChartsWidget extends StatefulWidget {
  /// Punti della traccia
  final List<TrackPoint> points;
  
  /// Dati battito cardiaco (opzionale)
  /// Mappa: timestamp -> BPM
  final Map<DateTime, int>? heartRateData;
  
  /// Altezza del grafico
  final double height;
  
  /// Callback quando si tocca un punto sul grafico
  /// Restituisce l'indice del punto e la distanza dall'inizio
  final void Function(int index, double distance)? onPointTap;
  
  /// Mostra selettore tipo grafico
  final bool showSelector;
  
  /// Durata totale della traccia (per calcolo velocità se timestamp non validi)
  final Duration? totalDuration;

  const TrackChartsWidget({
    super.key,
    required this.points,
    this.heartRateData,
    this.height = 200,
    this.onPointTap,
    this.showSelector = true,
    this.totalDuration,
  });

  @override
  State<TrackChartsWidget> createState() => _TrackChartsWidgetState();
}

class _TrackChartsWidgetState extends State<TrackChartsWidget> {
  ChartType _selectedChart = ChartType.elevation;
  int? _touchedIndex;
  
  // Dati calcolati
  List<double> _distances = [];
  List<double?> _elevations = [];
  List<double?> _speeds = [];
  List<int?> _heartRates = [];
  
  // Stats
  double _totalDistance = 0;
  double _maxElevation = 0;
  double _minElevation = double.infinity;
  double _maxSpeed = 0;
  double _avgSpeed = 0;
  int _maxHeartRate = 0;
  int _avgHeartRate = 0;

  @override
  void initState() {
    super.initState();
    _calculateData();
  }

  @override
  void didUpdateWidget(TrackChartsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points || 
        oldWidget.heartRateData != widget.heartRateData) {
      _calculateData();
    }
  }

  void _calculateData() {
    if (widget.points.isEmpty) return;

    _distances = [0.0];
    _elevations = [];
    _speeds = [];
    _heartRates = [];
    
    double cumulativeDistance = 0;
    double totalSpeed = 0;
    int speedCount = 0;
    int totalHR = 0;
    int hrCount = 0;
    
    // Debug
    int pointsWithSpeed = 0;
    int pointsWithCalculatedSpeed = 0;
    int pointsWithSameTimestamp = 0;

    // Prima passata: calcola distanze e verifica timestamp
    for (int i = 0; i < widget.points.length; i++) {
      final point = widget.points[i];
      
      // Distanza cumulativa
      if (i > 0) {
        final prev = widget.points[i - 1];
        cumulativeDistance += prev.distanceTo(point);
        _distances.add(cumulativeDistance);
        
        // Conta punti con stesso timestamp
        final timeDiff = point.timestamp.difference(prev.timestamp).inSeconds;
        if (timeDiff == 0) {
          pointsWithSameTimestamp++;
        }
      }
    }
    
    _totalDistance = cumulativeDistance;

    // Processa elevazioni con smoothing per grafico pulito
    final rawElevations = widget.points.map((p) => p.elevation).toList();
    final processor = const ElevationProcessor();
    final eleResult = processor.process(rawElevations);

    // Usa elevazioni smoothed per il grafico
    if (eleResult.smoothedElevations.isNotEmpty) {
      _elevations = eleResult.smoothedElevations
          .map((e) => e)
          .toList();
      _maxElevation = eleResult.maxElevation;
      _minElevation = eleResult.minElevation;
    } else {
      // Fallback: usa dati raw se il processing fallisce
      for (final point in widget.points) {
        _elevations.add(point.elevation);
        if (point.elevation != null) {
          if (point.elevation! > _maxElevation) _maxElevation = point.elevation!;
          if (point.elevation! < _minElevation) _minElevation = point.elevation!;
        }
      }
    }
    
    // Determina se i timestamp sono validi (almeno 50% dei punti con timestamp diversi)
    final validTimestamps = pointsWithSameTimestamp < (widget.points.length * 0.5);
    
    // Calcola velocità media stimata dalla durata totale (se disponibile)
    double? estimatedAvgSpeed;
    if (!validTimestamps && widget.totalDuration != null && widget.totalDuration!.inSeconds > 0) {
      // Velocità media in km/h
      estimatedAvgSpeed = (_totalDistance / widget.totalDuration!.inSeconds) * 3.6;
      debugPrint('[TrackCharts] Usando velocità stimata da durata: ${estimatedAvgSpeed.toStringAsFixed(1)} km/h');
    }

    // Seconda passata: calcola velocità
    for (int i = 0; i < widget.points.length; i++) {
      final point = widget.points[i];
      double? speedKmh;
      
      // Prima prova il campo speed del punto
      if (point.speed != null && point.speed! > 0) {
        speedKmh = point.speed! * 3.6;
        pointsWithSpeed++;
      } 
      // Altrimenti calcola dalla distanza/tempo (se timestamp validi)
      else if (validTimestamps && i > 0) {
        final prev = widget.points[i - 1];
        final timeDiff = point.timestamp.difference(prev.timestamp).inSeconds;
        
        if (timeDiff > 0) {
          final dist = prev.distanceTo(point);
          final calculatedSpeed = (dist / timeDiff) * 3.6; // m/s -> km/h
          // Filtra valori assurdi (> 50 km/h per hiking)
          if (calculatedSpeed > 0.5 && calculatedSpeed < 50) {
            speedKmh = calculatedSpeed;
            pointsWithCalculatedSpeed++;
          }
        }
      }
      // Se abbiamo velocità stimata dalla durata, usiamo quella con variazione
      else if (estimatedAvgSpeed != null && i > 0) {
        // Aggiungi variazione basata sulla pendenza (più lento in salita, più veloce in discesa)
        double variation = 1.0;
        if (i < _elevations.length && i > 0 && _elevations[i] != null && _elevations[i-1] != null) {
          final elevDiff = _elevations[i]! - _elevations[i-1]!;
          final dist = widget.points[i-1].distanceTo(widget.points[i]);
          if (dist > 0) {
            final gradient = elevDiff / dist; // pendenza
            // -10% velocità per ogni 10% di pendenza positiva
            variation = 1.0 - (gradient * 1.0).clamp(-0.5, 0.5);
          }
        }
        speedKmh = estimatedAvgSpeed * variation;
        if (speedKmh > 0.5 && speedKmh < 50) {
          pointsWithCalculatedSpeed++;
        } else {
          speedKmh = null;
        }
      }
      
      _speeds.add(speedKmh);
      if (speedKmh != null && speedKmh > 0) {
        if (speedKmh > _maxSpeed) _maxSpeed = speedKmh;
        totalSpeed += speedKmh;
        speedCount++;
      }
      
      // Battito cardiaco
      if (widget.heartRateData != null) {
        final hr = _findNearestHeartRate(point.timestamp);
        _heartRates.add(hr);
        if (hr != null) {
          if (hr > _maxHeartRate) _maxHeartRate = hr;
          totalHR += hr;
          hrCount++;
        }
      } else {
        _heartRates.add(null);
      }
    }

    _avgSpeed = speedCount > 0 ? totalSpeed / speedCount : 0;
    _avgHeartRate = hrCount > 0 ? totalHR ~/ hrCount : 0;
    
    // Fix minElevation se non ci sono dati
    if (_minElevation == double.infinity) _minElevation = 0;
    
    // Debug output
    debugPrint('[TrackCharts] ===== CALCOLO DATI =====');
    debugPrint('[TrackCharts] Punti totali: ${widget.points.length}');
    debugPrint('[TrackCharts] Punti con speed nel model: $pointsWithSpeed');
    debugPrint('[TrackCharts] Punti con speed calcolata: $pointsWithCalculatedSpeed');
    debugPrint('[TrackCharts] Punti con stesso timestamp: $pointsWithSameTimestamp');
    debugPrint('[TrackCharts] Timestamp validi: $validTimestamps');
    debugPrint('[TrackCharts] Durata totale fornita: ${widget.totalDuration}');
    debugPrint('[TrackCharts] Speed valide totali: $speedCount');
    debugPrint('[TrackCharts] hasSpeedData: $_hasSpeedData');
    debugPrint('[TrackCharts] hasElevationData: $_hasElevationData');
  }

  int? _findNearestHeartRate(DateTime timestamp) {
    if (widget.heartRateData == null || widget.heartRateData!.isEmpty) {
      return null;
    }
    
    int? nearest;
    Duration minDiff = const Duration(days: 365);
    
    for (final entry in widget.heartRateData!.entries) {
      final diff = (entry.key.difference(timestamp)).abs();
      if (diff < minDiff) {
        minDiff = diff;
        nearest = entry.value;
      }
    }
    
    // Solo se entro 30 secondi
    if (minDiff.inSeconds <= 30) {
      return nearest;
    }
    return null;
  }

  bool get _hasElevationData => _elevations.any((e) => e != null);
  bool get _hasSpeedData => _speeds.any((s) => s != null && s > 0);
  bool get _hasHeartRateData => _heartRates.any((hr) => hr != null);

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text('Nessun dato disponibile'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con selettore
            if (widget.showSelector) ...[
              _buildHeader(),
              const SizedBox(height: 12),
            ],
            
            // Grafico
            SizedBox(
              height: widget.height,
              child: _buildChart(),
            ),
            
            // Statistiche
            const SizedBox(height: 12),
            _buildStats(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (_hasElevationData)
            _ChartTypeButton(
              icon: Icons.terrain,
              label: 'Elevazione',
              isSelected: _selectedChart == ChartType.elevation,
              color: AppColors.success,
              onTap: () => setState(() => _selectedChart = ChartType.elevation),
            ),
          if (_hasSpeedData) ...[
            const SizedBox(width: 8),
            _ChartTypeButton(
              icon: Icons.speed,
              label: 'Velocità',
              isSelected: _selectedChart == ChartType.speed,
              color: AppColors.info,
              onTap: () => setState(() => _selectedChart = ChartType.speed),
            ),
          ],
          if (_hasHeartRateData) ...[
            const SizedBox(width: 8),
            _ChartTypeButton(
              icon: Icons.favorite,
              label: 'Battito',
              isSelected: _selectedChart == ChartType.heartRate,
              color: AppColors.danger,
              onTap: () => setState(() => _selectedChart = ChartType.heartRate),
            ),
          ],
          // Mostra combinato se ci sono almeno 2 tipi di dati
          if ((_hasElevationData && _hasSpeedData) || 
              (_hasElevationData && _hasHeartRateData) ||
              (_hasSpeedData && _hasHeartRateData)) ...[
            const SizedBox(width: 8),
            _ChartTypeButton(
              icon: Icons.stacked_line_chart,
              label: 'Combinato',
              isSelected: _selectedChart == ChartType.combined,
              color: AppColors.primary,
              onTap: () => setState(() => _selectedChart = ChartType.combined),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChart() {
    switch (_selectedChart) {
      case ChartType.elevation:
        return _buildElevationChart();
      case ChartType.speed:
        return _buildSpeedChart();
      case ChartType.heartRate:
        return _buildHeartRateChart();
      case ChartType.combined:
        return _buildCombinedChart();
    }
  }

  Widget _buildElevationChart() {
    final spots = <FlSpot>[];
    
    // Riduce i punti per performance (max 300 punti)
    final step = (_distances.length / 300).ceil().clamp(1, 100);
    
    for (int i = 0; i < _distances.length && i < _elevations.length; i += step) {
      if (_elevations[i] != null) {
        spots.add(FlSpot(_distances[i] / 1000, _elevations[i]!)); // km
      }
    }

    if (spots.isEmpty) {
      return const Center(child: Text('Nessun dato altimetrico'));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _calculateInterval(_maxElevation - _minElevation, 5),
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          ),
        ),
        titlesData: _buildTitlesData('km', 'm'),
        borderData: FlBorderData(show: false),
        lineTouchData: _buildTouchData(AppColors.success, 'm'),
        minY: (_minElevation - 20).clamp(0, double.infinity),
        maxY: _maxElevation + 20,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.success,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.success.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedChart() {
    final spots = <FlSpot>[];
    
    // Riduce i punti per performance (max 300 punti)
    final step = (_distances.length / 300).ceil().clamp(1, 100);
    
    for (int i = 0; i < _distances.length && i < _speeds.length; i += step) {
      if (_speeds[i] != null) {
        spots.add(FlSpot(_distances[i] / 1000, _speeds[i]!));
      }
    }

    if (spots.isEmpty) {
      return const Center(child: Text('Nessun dato velocità'));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _calculateInterval(_maxSpeed, 5),
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          ),
        ),
        titlesData: _buildTitlesData('km', 'km/h'),
        borderData: FlBorderData(show: false),
        lineTouchData: _buildTouchData(AppColors.info, 'km/h'),
        minY: 0,
        maxY: _maxSpeed + 2,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.info,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.info.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeartRateChart() {
    final spots = <FlSpot>[];
    
    // Riduce i punti per performance (max 300 punti)
    final step = (_distances.length / 300).ceil().clamp(1, 100);
    
    for (int i = 0; i < _distances.length && i < _heartRates.length; i += step) {
      if (_heartRates[i] != null) {
        spots.add(FlSpot(_distances[i] / 1000, _heartRates[i]!.toDouble()));
      }
    }

    if (spots.isEmpty) {
      return const Center(child: Text('Nessun dato battito cardiaco'));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          ),
        ),
        titlesData: _buildTitlesData('km', 'bpm'),
        borderData: FlBorderData(show: false),
        lineTouchData: _buildTouchData(AppColors.danger, 'bpm'),
        minY: 40,
        maxY: (_maxHeartRate + 20).toDouble(),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.danger,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.danger.withOpacity(0.4),
                  AppColors.danger.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedChart() {
    final elevationSpots = <FlSpot>[];
    final speedSpots = <FlSpot>[];
    
    // Riduce i punti per performance (max 200 punti)
    final step = (_distances.length / 200).ceil().clamp(1, 100);
    
    for (int i = 0; i < _distances.length; i += step) {
      final distKm = _distances[i] / 1000;
      
      if (i < _elevations.length && _elevations[i] != null) {
        // Normalizza elevazione (0-100%)
        final range = _maxElevation - _minElevation;
        final normalized = range > 0 
            ? ((_elevations[i]! - _minElevation) / range) * 100.0 
            : 50.0;
        elevationSpots.add(FlSpot(distKm, normalized.toDouble()));
      }
      
      if (i < _speeds.length && _speeds[i] != null) {
        // Normalizza velocità (0-100%)
        final normalized = _maxSpeed > 0 ? (_speeds[i]! / _maxSpeed) * 100.0 : 0.0;
        speedSpots.add(FlSpot(distKm, normalized.toDouble()));
      }
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: _calculateInterval(_totalDistance / 1000, 5),
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
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: 100,
        lineBarsData: [
          // Elevazione
          LineChartBarData(
            spots: elevationSpots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.success,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.success.withOpacity(0.15),
            ),
          ),
          // Velocità
          LineChartBarData(
            spots: speedSpots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.info,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  FlTitlesData _buildTitlesData(String xUnit, String yUnit) {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: _calculateInterval(_totalDistance / 1000, 5),
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
          getTitlesWidget: (value, meta) {
            return Text(
              value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            );
          },
        ),
      ),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  LineTouchData _buildTouchData(Color color, String unit) {
    return LineTouchData(
      enabled: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (spot) => Colors.white,
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((spot) {
            // Trova l'indice del punto più vicino
            final distanceKm = spot.x;
            int nearestIndex = 0;
            double minDiff = double.infinity;
            for (int i = 0; i < _distances.length; i++) {
              final diff = ((_distances[i] / 1000) - distanceKm).abs();
              if (diff < minDiff) {
                minDiff = diff;
                nearestIndex = i;
              }
            }
            
            // Notifica callback
            widget.onPointTap?.call(nearestIndex, _distances[nearestIndex]);
            
            return LineTooltipItem(
              '${spot.y.toStringAsFixed(1)} $unit\n${distanceKm.toStringAsFixed(2)} km',
              TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            );
          }).toList();
        },
      ),
      handleBuiltInTouches: true,
    );
  }

  double _calculateInterval(double range, int divisions) {
    if (range <= 0) return 1;
    final interval = range / divisions;
    // Arrotonda a un valore "bello"
    if (interval < 1) return 0.5;
    if (interval < 5) return 1;
    if (interval < 10) return 5;
    if (interval < 50) return 10;
    if (interval < 100) return 25;
    return 50;
  }

  Widget _buildStats() {
    return Row(
      children: [
        if (_selectedChart == ChartType.elevation || _selectedChart == ChartType.combined) ...[
          _StatBadge(
            icon: Icons.arrow_upward,
            label: 'Max',
            value: '${_maxElevation.toStringAsFixed(0)} m',
            color: AppColors.success,
          ),
          const SizedBox(width: 12),
          _StatBadge(
            icon: Icons.arrow_downward,
            label: 'Min',
            value: '${_minElevation.toStringAsFixed(0)} m',
            color: AppColors.success,
          ),
        ],
        if (_selectedChart == ChartType.speed || _selectedChart == ChartType.combined) ...[
          const SizedBox(width: 12),
          _StatBadge(
            icon: Icons.speed,
            label: 'Media',
            value: '${_avgSpeed.toStringAsFixed(1)} km/h',
            color: AppColors.info,
          ),
          const SizedBox(width: 12),
          _StatBadge(
            icon: Icons.flash_on,
            label: 'Max',
            value: '${_maxSpeed.toStringAsFixed(1)} km/h',
            color: AppColors.info,
          ),
        ],
        if (_selectedChart == ChartType.heartRate) ...[
          _StatBadge(
            icon: Icons.favorite,
            label: 'Media',
            value: '$_avgHeartRate bpm',
            color: AppColors.danger,
          ),
          const SizedBox(width: 12),
          _StatBadge(
            icon: Icons.favorite,
            label: 'Max',
            value: '$_maxHeartRate bpm',
            color: AppColors.danger,
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET: Chart Type Button
// ═══════════════════════════════════════════════════════════════════════════

class _ChartTypeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _ChartTypeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : AppColors.textMuted.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? color : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET: Stat Badge
// ═══════════════════════════════════════════════════════════════════════════

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 9, color: color.withOpacity(0.7)),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
