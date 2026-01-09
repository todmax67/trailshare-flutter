import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/location_service.dart';
import '../../../presentation/blocs/tracking_bloc.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/track_repository.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  late final TrackingBloc _trackingBloc;
  final TrackRepository _repository = TrackRepository();
  final MapController _mapController = MapController();
  bool _followUser = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _trackingBloc = TrackingBloc(LocationService());
    _trackingBloc.addListener(_onTrackingUpdate);
  }

  void _onTrackingUpdate() {
    if (_followUser && _trackingBloc.state.points.isNotEmpty) {
      final lastPoint = _trackingBloc.state.points.last;
      _mapController.move(
        LatLng(lastPoint.latitude, lastPoint.longitude),
        _mapController.camera.zoom,
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _trackingBloc.removeListener(_onTrackingUpdate);
    _trackingBloc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _trackingBloc.state;

    return Scaffold(
      body: Stack(
        children: [
          _buildMap(state),
          if (!state.isIdle) _buildStatsHeader(state),
          _buildControls(state),
          if (state.errorMessage != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 100,
              left: 16,
              right: 16,
              child: _buildErrorBanner(state.errorMessage!),
            ),
          if (_isSaving)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Salvataggio...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap(TrackingState state) {
    final center = state.points.isNotEmpty
        ? LatLng(state.points.last.latitude, state.points.last.longitude)
        : const LatLng(45.9, 9.9);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
        minZoom: 4,
        maxZoom: 18,
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) _followUser = false;
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.trailshare.app',
        ),
        if (state.points.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: state.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                strokeWidth: 4,
                color: state.isRecording ? AppColors.trackRecording : AppColors.primary,
              ),
            ],
          ),
        if (state.points.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(state.points.first.latitude, state.points.first.longitude),
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.flag, color: Colors.white, size: 14),
                ),
              ),
              Marker(
                point: LatLng(state.points.last.latitude, state.points.last.longitude),
                width: 32,
                height: 32,
                child: Container(
                  decoration: BoxDecoration(
                    color: state.isRecording ? AppColors.trackRecording : AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: (state.isRecording ? AppColors.trackRecording : AppColors.primary).withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.navigation, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStatsHeader(TrackingState state) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          bottom: 16,
          left: 16,
          right: 16,
        ),
        decoration: BoxDecoration(
          color: state.isRecording 
              ? AppColors.trackRecording.withOpacity(0.95)
              : AppColors.warning.withOpacity(0.95),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  state.isRecording ? Icons.fiber_manual_record : Icons.pause,
                  color: Colors.white,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  state.isRecording ? 'REGISTRAZIONE' : 'IN PAUSA',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat('Distanza', '${state.stats.distanceKm.toStringAsFixed(2)} km'),
                _buildStat('Tempo', state.stats.durationFormatted),
                _buildStat('D+', '${state.stats.elevationGain.toStringAsFixed(0)} m'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat('Vel.', '${state.stats.currentSpeedKmh.toStringAsFixed(1)} km/h', small: true),
                _buildStat('Media', '${state.stats.avgSpeedKmh.toStringAsFixed(1)} km/h', small: true),
                _buildStat('Passo', state.stats.avgPace, small: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, {bool small = false}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: small ? 16 : 22),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: small ? 10 : 11),
        ),
      ],
    );
  }

  Widget _buildControls(TrackingState state) {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Column(
        children: [
          if (!state.isIdle)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FloatingActionButton.small(
                  heroTag: 'center',
                  onPressed: () {
                    _followUser = true;
                    if (state.points.isNotEmpty) {
                      final lastPoint = state.points.last;
                      _mapController.move(LatLng(lastPoint.latitude, lastPoint.longitude), 16);
                    }
                  },
                  backgroundColor: _followUser ? AppColors.primary : Colors.white,
                  child: Icon(Icons.my_location, color: _followUser ? Colors.white : AppColors.textPrimary),
                ),
              ),
            ),
          if (state.isIdle) _buildStartButton() else _buildRecordingControls(state),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return GestureDetector(
      onTap: () => _trackingBloc.startRecording(),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 20, spreadRadius: 5),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow, color: Colors.white, size: 40),
            Text('INIZIA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingControls(TrackingState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: Icons.close,
            label: 'Annulla',
            color: AppColors.textMuted,
            onTap: _showCancelDialog,
          ),
          _buildControlButton(
            icon: state.isRecording ? Icons.pause : Icons.play_arrow,
            label: state.isRecording ? 'Pausa' : 'Riprendi',
            color: AppColors.warning,
            onTap: () {
              if (state.isRecording) {
                _trackingBloc.pauseRecording();
              } else {
                _trackingBloc.resumeRecording();
              }
            },
            large: true,
          ),
          _buildControlButton(
            icon: Icons.stop,
            label: 'Salva',
            color: AppColors.danger,
            onTap: _showSaveDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool large = false,
  }) {
    final size = large ? 64.0 : 48.0;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: large ? 32 : 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annullare registrazione?'),
        content: const Text('I dati della traccia corrente verranno persi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Continua')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _trackingBloc.cancelRecording();
            },
            child: const Text('Annulla', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _showSaveDialog() async {
    // Ferma tracking e ottieni traccia
    final track = await _trackingBloc.stopRecording();
    
    if (track == null || track.points.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessun punto registrato')),
        );
      }
      return;
    }

    // Mostra dialog con anteprima
    if (!mounted) return;
    
    final nameController = TextEditingController(text: track.name);
    
    final shouldSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Salva traccia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nome traccia',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildSummaryRow('Distanza', '${track.stats.distanceKm.toStringAsFixed(2)} km'),
            _buildSummaryRow('Dislivello', '+${track.stats.elevationGain.toStringAsFixed(0)} m'),
            _buildSummaryRow('Durata', track.stats.durationFormatted),
            _buildSummaryRow('Punti GPS', '${track.points.length}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (shouldSave != true) return;

    // Salva su Firebase
    setState(() => _isSaving = true);
    
    try {
      final trackToSave = track.copyWith(name: nameController.text.trim());
      await _repository.saveTrack(trackToSave);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Traccia salvata!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
