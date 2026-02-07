import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/elevation_processor.dart';
import '../../data/models/track.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' show min;

/// Dati di un singolo lap (chilometro)
class LapData {
  final int lapNumber;
  final Duration time;
  final double distance; // metri effettivi (può essere leggermente diverso da 1000)
  final double elevationGain;
  final double elevationLoss;
  final double avgSpeed; // km/h
  final int? avgHeartRate;
  final int startPointIndex;
  final int endPointIndex;

  const LapData({
    required this.lapNumber,
    required this.time,
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    required this.avgSpeed,
    this.avgHeartRate,
    required this.startPointIndex,
    required this.endPointIndex,
  });

  /// Passo in formato mm:ss per km
  String get paceFormatted {
    if (avgSpeed <= 0) return '--:--';
    final paceMinutes = 60 / avgSpeed;
    final mins = paceMinutes.floor();
    final secs = ((paceMinutes - mins) * 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  /// Tempo formattato mm:ss
  String get timeFormatted {
    final mins = time.inMinutes;
    final secs = time.inSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  /// Dislivello netto
  double get netElevation => elevationGain - elevationLoss;

  /// Stringa dislivello con segno
  String get elevationFormatted {
    if (netElevation > 0) {
      return '+${netElevation.toStringAsFixed(0)}m';
    } else if (netElevation < 0) {
      return '${netElevation.toStringAsFixed(0)}m';
    }
    return '0m';
  }
}

/// Widget che mostra le statistiche per ogni chilometro della traccia
class LapSplitsWidget extends StatefulWidget {
  /// Punti della traccia
  final List<TrackPoint> points;

  /// Durata totale (opzionale, per tracce senza timestamp validi)
  final Duration? totalDuration;

  /// Dati battito cardiaco (opzionale)
  /// Mappa: timestamp -> BPM
  final Map<DateTime, int>? heartRateData;

  /// Callback quando si tocca un lap (per evidenziare sulla mappa)
  final void Function(int startIndex, int endIndex)? onLapTap;

  const LapSplitsWidget({
    super.key,
    required this.points,
    this.totalDuration,
    this.heartRateData,
    this.onLapTap,
  });

  @override
  State<LapSplitsWidget> createState() => _LapSplitsWidgetState();
}

class _LapSplitsWidgetState extends State<LapSplitsWidget> {
  List<LapData> _laps = [];
  bool _isExpanded = false;
  int? _selectedLap;

  @override
  void initState() {
    super.initState();
    _calculateLaps();
  }

  @override
  void didUpdateWidget(LapSplitsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) {
      _calculateLaps();
    }
  }

  void _calculateLaps() {
    if (widget.points.length < 2) {
      _laps = [];
      return;
    }

    final laps = <LapData>[];
    double cumulativeDistance = 0;
    int lapStartIndex = 0;
    int currentLap = 1;
    
    double lapElevationGain = 0;
    double lapElevationLoss = 0;
    double lapTimeSeconds = 0;

    // Processa tutte le elevazioni con smoothing e spike removal
    final elevationProcessor = const ElevationProcessor();
    final rawElevations = widget.points.map((p) => p.elevation).toList();
    final eleResult = elevationProcessor.process(rawElevations);
    final smoothedElevations = eleResult.smoothedElevations;

    // Per il calcolo dislivello per km, usiamo l'isteresi
    // tramite un tracker dedicato per ogni lap
    double? lastSmoothedElevation;
    
    // Verifica se i timestamp sono validi
    final firstTime = widget.points.first.timestamp;
    final lastTime = widget.points.last.timestamp;
    final totalTimeDiff = lastTime.difference(firstTime);
    
    // Controlla se i punti hanno timestamp diversi
    int differentTimestamps = 0;
    for (int i = 1; i < widget.points.length && i < 10; i++) {
      if (widget.points[i].timestamp.difference(widget.points[i-1].timestamp).inMilliseconds.abs() > 100) {
        differentTimestamps++;
      }
    }
    
    final hasValidTimestamps = totalTimeDiff.inSeconds > 60 && 
                                totalTimeDiff.inHours < 100 &&
                                differentTimestamps > 3;
    
    // Controlla se i punti hanno dati di velocità
    int pointsWithSpeed = 0;
    for (final p in widget.points) {
      if (p.speed != null && p.speed! > 0.1) {
        pointsWithSpeed++;
      }
    }
    final hasSpeedData = pointsWithSpeed > widget.points.length * 0.5;
    
    debugPrint('[LapSplits] ===== CALCOLO LAPS =====');
    debugPrint('[LapSplits] Punti: ${widget.points.length}');
    debugPrint('[LapSplits] Timestamp validi: $hasValidTimestamps');
    debugPrint('[LapSplits] Punti con speed: $pointsWithSpeed (${(pointsWithSpeed * 100 / widget.points.length).toStringAsFixed(0)}%)');
    debugPrint('[LapSplits] Usa speed data: $hasSpeedData');
    debugPrint('[LapSplits] Durata totale fornita: ${widget.totalDuration}');
    
    // Calcola distanza totale per le stime
    final totalDistance = _calculateTotalDistance();
    debugPrint('[LapSplits] Distanza totale: ${totalDistance.toStringAsFixed(0)}m');

    for (int i = 1; i < widget.points.length; i++) {
      final prev = widget.points[i - 1];
      final curr = widget.points[i];

      // Calcola distanza del segmento
      final segmentDistance = const Distance().as(
        LengthUnit.Meter,
        LatLng(prev.latitude, prev.longitude),
        LatLng(curr.latitude, curr.longitude),
      );
      cumulativeDistance += segmentDistance;

      // Calcola tempo del segmento usando la velocità del punto
      if (hasSpeedData && curr.speed != null && curr.speed! > 0.1) {
        // speed è in m/s, tempo = distanza / velocità
        final segmentTime = segmentDistance / curr.speed!;
        lapTimeSeconds += segmentTime;
      } else if (hasValidTimestamps) {
        // Fallback ai timestamp
        final segmentTime = curr.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
        if (segmentTime > 0 && segmentTime < 3600) { // Max 1 ora per segmento
          lapTimeSeconds += segmentTime;
        }
      }

      // Nota: il dislivello per lap viene calcolato DOPO il loop
      // usando ElevationProcessor con isteresi (vedi sotto)

      // Ogni 1000 metri, crea un lap
      if (cumulativeDistance >= currentLap * 1000) {
        final lapDistance = 1000.0;
        
        // Calcola dislivello del lap con isteresi sulle elevazioni smoothed
        if (smoothedElevations.isNotEmpty && lapStartIndex < smoothedElevations.length) {
          final lapEndIndex = min(i, smoothedElevations.length - 1);
          final lapElevationData = smoothedElevations.sublist(lapStartIndex, lapEndIndex + 1);
          if (lapElevationData.length >= 2) {
            final lapEleResult = elevationProcessor.calculateGainLoss(lapElevationData);
            lapElevationGain = lapEleResult.gain;
            lapElevationLoss = lapEleResult.loss;
          }
        }

        // Se non abbiamo calcolato il tempo, stima dalla durata totale
        Duration lapTime;
        if (lapTimeSeconds > 0) {
          lapTime = Duration(seconds: lapTimeSeconds.round());
        } else if (widget.totalDuration != null && widget.totalDuration!.inSeconds > 0 && totalDistance > 0) {
          final ratio = lapDistance / totalDistance;
          lapTime = Duration(seconds: (widget.totalDuration!.inSeconds * ratio).round());
        } else {
          lapTime = Duration.zero;
        }

        // Calcola velocità media
        final avgSpeed = lapTime.inSeconds > 0
            ? (lapDistance / lapTime.inSeconds) * 3.6
            : 0.0;

        // Calcola HR medio (se disponibile)
        int? avgHR;
        if (widget.heartRateData != null && widget.heartRateData!.isNotEmpty) {
          avgHR = _calculateAvgHeartRate(lapStartIndex, i);
        }

        laps.add(LapData(
          lapNumber: currentLap,
          time: lapTime,
          distance: lapDistance,
          elevationGain: lapElevationGain,
          elevationLoss: lapElevationLoss,
          avgSpeed: avgSpeed,
          avgHeartRate: avgHR,
          startPointIndex: lapStartIndex,
          endPointIndex: i,
        ));
        
        debugPrint('[LapSplits] Lap $currentLap: ${lapTime.inMinutes}m${lapTime.inSeconds % 60}s, ${avgSpeed.toStringAsFixed(1)} km/h, +${lapElevationGain.toStringAsFixed(0)}m/-${lapElevationLoss.toStringAsFixed(0)}m');

        // Reset per prossimo lap
        lapStartIndex = i;
        currentLap++;
        lapElevationGain = 0;
        lapElevationLoss = 0;
        lapTimeSeconds = 0;
      }
    }

    // Ultimo lap parziale (se > 100m)
    final remainingDistance = cumulativeDistance - ((currentLap - 1) * 1000);
    if (remainingDistance > 100) {
      final lastIndex = widget.points.length - 1;

      // Calcola dislivello ultimo lap con isteresi
      if (smoothedElevations.isNotEmpty && lapStartIndex < smoothedElevations.length) {
        final lapEndIndex = min(lastIndex, smoothedElevations.length - 1);
        final lapElevationData = smoothedElevations.sublist(lapStartIndex, lapEndIndex + 1);
        if (lapElevationData.length >= 2) {
          final lapEleResult = elevationProcessor.calculateGainLoss(lapElevationData);
          lapElevationGain = lapEleResult.gain;
          lapElevationLoss = lapEleResult.loss;
        }
      }
      
      Duration lapTime;
      if (lapTimeSeconds > 0) {
        lapTime = Duration(seconds: lapTimeSeconds.round());
      } else if (widget.totalDuration != null && widget.totalDuration!.inSeconds > 0 && totalDistance > 0) {
        final ratio = remainingDistance / totalDistance;
        lapTime = Duration(seconds: (widget.totalDuration!.inSeconds * ratio).round());
      } else {
        lapTime = Duration.zero;
      }

      final avgSpeed = lapTime.inSeconds > 0
          ? (remainingDistance / lapTime.inSeconds) * 3.6
          : 0.0;

      int? avgHR;
      if (widget.heartRateData != null) {
        avgHR = _calculateAvgHeartRate(lapStartIndex, lastIndex);
      }

      laps.add(LapData(
        lapNumber: currentLap,
        time: lapTime,
        distance: remainingDistance,
        elevationGain: lapElevationGain,
        elevationLoss: lapElevationLoss,
        avgSpeed: avgSpeed,
        avgHeartRate: avgHR,
        startPointIndex: lapStartIndex,
        endPointIndex: lastIndex,
      ));
      
      debugPrint('[LapSplits] Lap $currentLap (parziale ${remainingDistance.toStringAsFixed(0)}m): ${lapTime.inMinutes}m${lapTime.inSeconds % 60}s, +${lapElevationGain.toStringAsFixed(0)}m/-${lapElevationLoss.toStringAsFixed(0)}m');
    }

    setState(() => _laps = laps);
    debugPrint('[LapSplits] Totale laps: ${_laps.length}');
  }

  double _calculateTotalDistance() {
    double total = 0;
    for (int i = 1; i < widget.points.length; i++) {
      final prev = widget.points[i - 1];
      final curr = widget.points[i];
      total += const Distance().as(
        LengthUnit.Meter,
        LatLng(prev.latitude, prev.longitude),
        LatLng(curr.latitude, curr.longitude),
      );
    }
    return total;
  }

  int? _calculateAvgHeartRate(int startIndex, int endIndex) {
    if (widget.heartRateData == null || widget.heartRateData!.isEmpty) {
      return null;
    }

    final startTime = widget.points[startIndex].timestamp;
    final endTime = widget.points[endIndex].timestamp;

    int total = 0;
    int count = 0;

    for (final entry in widget.heartRateData!.entries) {
      if (entry.key.isAfter(startTime) && entry.key.isBefore(endTime)) {
        total += entry.value;
        count++;
      }
    }

    return count > 0 ? (total / count).round() : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_laps.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.timer, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Statistiche per Km',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '${_laps.length} km',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // Contenuto espandibile
          if (_isExpanded) ...[
            const Divider(height: 1),
            
            // Header tabella
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[100],
              child: const Row(
                children: [
                  SizedBox(width: 40, child: Text('Km', style: _headerStyle)),
                  Expanded(child: Text('Passo', style: _headerStyle, textAlign: TextAlign.center)),
                  Expanded(child: Text('Vel.', style: _headerStyle, textAlign: TextAlign.center)),
                  Expanded(child: Text('Disliv.', style: _headerStyle, textAlign: TextAlign.center)),
                ],
              ),
            ),

            // Righe lap
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _laps.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final lap = _laps[index];
                final isSelected = _selectedLap == index;
                final isLastPartial = index == _laps.length - 1 && lap.distance < 900;

                return InkWell(
                  onTap: () {
                    setState(() => _selectedLap = isSelected ? null : index);
                    if (!isSelected) {
                      widget.onLapTap?.call(lap.startPointIndex, lap.endPointIndex);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: isSelected ? AppColors.primary.withOpacity(0.1) : null,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(
                            isLastPartial 
                                ? '${(lap.distance / 1000).toStringAsFixed(1)}'
                                : '${lap.lapNumber}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected ? AppColors.primary : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            lap.paceFormatted,
                            textAlign: TextAlign.center,
                            style: _valueStyle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${lap.avgSpeed.toStringAsFixed(1)}',
                            textAlign: TextAlign.center,
                            style: _valueStyle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            lap.elevationFormatted,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: lap.netElevation > 0 
                                  ? AppColors.success 
                                  : lap.netElevation < 0 
                                      ? AppColors.info 
                                      : AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Riga totale
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey[50],
              child: Row(
                children: [
                  const SizedBox(
                    width: 40,
                    child: Text('TOT', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Text(
                      _calculateAvgPace(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${_calculateAvgSpeed().toStringAsFixed(1)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _formatTotalElevation(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _totalElevationGain() > _totalElevationLoss()
                            ? AppColors.success
                            : AppColors.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Legenda
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Tocca un km per evidenziarlo sulla mappa',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTotalTime() {
    final total = _laps.fold<Duration>(
      Duration.zero,
      (sum, lap) => sum + lap.time,
    );
    final hours = total.inHours;
    final mins = total.inMinutes % 60;
    final secs = total.inSeconds % 60;
    if (hours > 0) {
      return '$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _calculateAvgPace() {
    final avgSpeed = _calculateAvgSpeed();
    if (avgSpeed <= 0) return '--:--';
    final paceMinutes = 60 / avgSpeed;
    final mins = paceMinutes.floor();
    final secs = ((paceMinutes - mins) * 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  double _calculateAvgSpeed() {
    final totalDistance = _laps.fold<double>(0, (sum, lap) => sum + lap.distance);
    final totalTime = _laps.fold<Duration>(Duration.zero, (sum, lap) => sum + lap.time);
    if (totalTime.inSeconds <= 0) return 0;
    return (totalDistance / totalTime.inSeconds) * 3.6;
  }

  double _totalElevationGain() {
    return _laps.fold<double>(0, (sum, lap) => sum + lap.elevationGain);
  }

  double _totalElevationLoss() {
    return _laps.fold<double>(0, (sum, lap) => sum + lap.elevationLoss);
  }

  String _formatTotalElevation() {
    final gain = _totalElevationGain();
    final loss = _totalElevationLoss();
    return '+${gain.toStringAsFixed(0)}/-${loss.toStringAsFixed(0)}m';
  }

  static const _headerStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    color: AppColors.textMuted,
  );

  static const _valueStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
}
