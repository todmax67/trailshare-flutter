import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/elevation_processor.dart';
import '../../../data/models/track.dart';

/// Pagina admin per ricalcolare le statistiche di tutte le tracce
/// dai punti GPS salvati in Firestore.
///
/// Usa ElevationProcessor (stesso di LapSplitsWidget) per garantire
/// coerenza tra dati riassuntivi e stats per km.
class RecalculateStatsPage extends StatefulWidget {
  const RecalculateStatsPage({super.key});

  @override
  State<RecalculateStatsPage> createState() => _RecalculateStatsPageState();
}

class _RecalculateStatsPageState extends State<RecalculateStatsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isRunning = false;
  final List<_RecalcResult> _results = [];
  int _totalTracks = 0;
  int _processedTracks = 0;
  int _fixedTracks = 0;
  int _skippedTracks = 0;
  int _errorTracks = 0;
  String _currentTrack = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ricalcolo Statistiche'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header con spiegazione e pulsante
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.info),
                    SizedBox(width: 8),
                    Text(
                      'Ricalcolo Stats Tracce',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.info,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ricalcola distanza, dislivello, quota min/max direttamente '
                  'dai punti GPS salvati.\n'
                  'Usa ElevationProcessor (filtro mediano + smoothing + isteresi 4m) '
                  '— stesso algoritmo usato nelle stats per km.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),

                // Progress
                if (_isRunning || _processedTracks > 0) ...[
                  LinearProgressIndicator(
                    value: _totalTracks > 0
                        ? _processedTracks / _totalTracks
                        : null,
                    backgroundColor: Colors.grey[200],
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRunning
                        ? '$_processedTracks/$_totalTracks - $_currentTrack'
                        : 'Completato: $_fixedTracks corrette, $_skippedTracks ok, $_errorTracks errori',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                ],

                // Pulsanti
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isRunning
                            ? null
                            : () => _recalculate(onlyMyTracks: true),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Le mie tracce'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isRunning
                            ? null
                            : () => _recalculate(onlyMyTracks: false),
                        icon: const Icon(Icons.admin_panel_settings, size: 18),
                        label: const Text('Tutti gli utenti'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Risultati
          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: Text(
                      'Premi un pulsante per avviare il ricalcolo',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final r = _results[index];
                      return _buildResultCard(r);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(_RecalcResult r) {
    final IconData icon;
    final Color color;

    switch (r.status) {
      case _RecalcStatus.fixed:
        icon = Icons.check_circle;
        color = AppColors.success;
        break;
      case _RecalcStatus.skipped:
        icon = Icons.remove_circle_outline;
        color = Colors.grey;
        break;
      case _RecalcStatus.error:
        icon = Icons.error;
        color = AppColors.danger;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color, size: 28),
        title: Text(
          r.trackName,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: r.details != null
            ? Text(
                r.details!,
                style: TextStyle(fontSize: 11, color: color),
                maxLines: 2,
              )
            : null,
        dense: true,
      ),
    );
  }

  Future<void> _recalculate({required bool onlyMyTracks}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma ricalcolo'),
        content: Text(
          onlyMyTracks
              ? 'Ricalcolare le statistiche di tutte le TUE tracce dai punti GPS?'
              : 'Ricalcolare le statistiche di TUTTI gli utenti? Operazione pesante.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary),
            child:
                const Text('Avvia', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isRunning = true;
      _results.clear();
      _processedTracks = 0;
      _fixedTracks = 0;
      _skippedTracks = 0;
      _errorTracks = 0;
      _totalTracks = 0;
    });

    try {
      if (onlyMyTracks) {
        await _recalculateForUser(user.uid);
      } else {
        final usersSnapshot = await _firestore.collection('users').get();
        for (final userDoc in usersSnapshot.docs) {
          await _recalculateForUser(userDoc.id);
        }
      }
    } catch (e) {
      debugPrint('[Recalc] Errore globale: $e');
    }

    setState(() => _isRunning = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ Completato: $_fixedTracks corrette, $_skippedTracks ok, $_errorTracks errori'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _recalculateForUser(String userId) async {
    try {
      final tracksSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('tracks')
          .get();

      setState(() => _totalTracks += tracksSnapshot.docs.length);

      for (final trackDoc in tracksSnapshot.docs) {
        try {
          final data = trackDoc.data();
          final trackName = data['name']?.toString() ?? 'Senza nome';
          final activityType = data['activityType']?.toString() ?? 'trekking';

          setState(() {
            _currentTrack = trackName;
            _processedTracks++;
          });

          // Leggi punti GPS
          final pointsData = data['points'];
          if (pointsData == null ||
              pointsData is! List ||
              (pointsData).isEmpty) {
            _addResult(
                _RecalcStatus.skipped, trackName, 'Nessun punto GPS');
            continue;
          }

          // Parsa i punti — stessa logica di _trackFromFirestore in TracksRepository
          final points = <TrackPoint>[];
          for (var p in pointsData) {
            try {
              if (p is Map) {
                final lat = _toDouble(p['latitude'] ?? p['lat']);
                final lng =
                    _toDouble(p['longitude'] ?? p['lng'] ?? p['lon']);
                final ele =
                    _toDouble(p['altitude'] ?? p['ele'] ?? p['elevation']);

                if (lat != null && lng != null) {
                  DateTime timestamp = DateTime.now();
                  if (p['timestamp'] is int) {
                    timestamp = DateTime.fromMillisecondsSinceEpoch(
                        p['timestamp']);
                  } else if (p['timestamp'] is String) {
                    timestamp =
                        DateTime.tryParse(p['timestamp']) ?? DateTime.now();
                  } else if (p['time'] is String) {
                    timestamp =
                        DateTime.tryParse(p['time']) ?? DateTime.now();
                  }

                  points.add(TrackPoint(
                    latitude: lat,
                    longitude: lng,
                    elevation: ele,
                    timestamp: timestamp,
                    speed: _toDouble(p['speed']),
                  ));
                }
              }
            } catch (_) {}
          }

          if (points.length < 2) {
            _addResult(_RecalcStatus.skipped, trackName,
                'Meno di 2 punti (${points.length})');
            continue;
          }

          // ═══════════════════════════════════════════════════════
          // RICALCOLO con ElevationProcessor
          // (stesso usato da LapSplitsWidget → numeri coerenti)
          // ═══════════════════════════════════════════════════════

          // 1. Calcola distanza dai punti originali (precisa)
          double distance = 0;
          for (int i = 1; i < points.length; i++) {
            distance += points[i - 1].distanceTo(points[i]);
          }

          // 2. Calcola elevazione con ElevationProcessor
          //    Usa la factory per attività per soglie ottimali
          final elevationProcessor = ElevationProcessor.forActivity(activityType);
          final rawElevations = points.map((p) => p.elevation).toList();
          final eleResult = elevationProcessor.process(rawElevations);

          debugPrint('[Recalc] ${points.length} punti ($activityType) → '
              'D:${(distance / 1000).toStringAsFixed(1)}km '
              'E+:${eleResult.elevationGain.toStringAsFixed(0)}m '
              'E-:${eleResult.elevationLoss.toStringAsFixed(0)}m '
              'Max:${eleResult.maxElevation.toStringAsFixed(0)}m');

          // 3. Leggi stats attuali per il log confronto
          final oldDistance = _toDouble(data['distance']) ?? 0;
          final oldElevGain = _toDouble(data['elevationGain']) ?? 0;
          final oldElevLoss = _toDouble(data['elevationLoss']) ?? 0;
          final oldMaxAlt =
              _toDouble(data['maxAltitude'] ?? data['maxElevation']) ?? 0;

          // 4. Aggiorna SEMPRE Firestore
          await trackDoc.reference.update({
            'distance': distance,
            'elevationGain': eleResult.elevationGain,
            'elevationLoss': eleResult.elevationLoss,
            'maxAltitude': eleResult.maxElevation,
            'minAltitude': eleResult.minElevation,
          });

          final details =
              'D: ${(oldDistance / 1000).toStringAsFixed(1)}→${(distance / 1000).toStringAsFixed(1)}km | '
              'E+: ${oldElevGain.toStringAsFixed(0)}→${eleResult.elevationGain.toStringAsFixed(0)}m | '
              'E-: ${oldElevLoss.toStringAsFixed(0)}→${eleResult.elevationLoss.toStringAsFixed(0)}m | '
              'Max: ${oldMaxAlt.toStringAsFixed(0)}→${eleResult.maxElevation.toStringAsFixed(0)}m';

          _addResult(_RecalcStatus.fixed, trackName, details);
        } catch (e) {
          _addResult(_RecalcStatus.error, _currentTrack, e.toString());
        }

        // Piccola pausa per non sovraccaricare Firestore
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } catch (e) {
      debugPrint('[Recalc] Errore utente $userId: $e');
    }
  }

  void _addResult(_RecalcStatus status, String name, String? details) {
    setState(() {
      switch (status) {
        case _RecalcStatus.fixed:
          _fixedTracks++;
          break;
        case _RecalcStatus.skipped:
          _skippedTracks++;
          break;
        case _RecalcStatus.error:
          _errorTracks++;
          break;
      }
      _results.add(_RecalcResult(
          status: status, trackName: name, details: details));
    });
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

enum _RecalcStatus { fixed, skipped, error }

class _RecalcResult {
  final _RecalcStatus status;
  final String trackName;
  final String? details;

  const _RecalcResult({
    required this.status,
    required this.trackName,
    this.details,
  });
}
