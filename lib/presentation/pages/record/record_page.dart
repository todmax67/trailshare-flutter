import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/location_service.dart';
import '../../../presentation/blocs/tracking_bloc.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../../widgets/live_track_button.dart';
import '../../widgets/heart_rate_widget.dart';
import '../../../core/services/feature_tips.dart';
import '../../../core/services/track_photos_service.dart';
import '../../widgets/photo_gallery_widget.dart';
import '../../../core/services/recording_persistence_service.dart';
import '../../../core/services/live_track_service.dart';
import 'package:battery_plus/battery_plus.dart';
import 'dart:async';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> with WidgetsBindingObserver {
  late final TrackingBloc _trackingBloc;
  final TracksRepository _repository = TracksRepository();
  final MapController _mapController = MapController();
  final RecordingPersistenceService _persistence = RecordingPersistenceService.instance;
  
  bool _followUser = true;
  bool _isSaving = false;
  bool _isRestoringState = false;
  
  final TrackPhotosService _photosService = TrackPhotosService();
  final List<TrackPhoto> _photos = [];
  ActivityType _selectedActivity = ActivityType.trekking;
  
  // Battery monitoring
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;
  bool _lowBatteryWarningShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _trackingBloc = TrackingBloc(LocationService());
    _trackingBloc.addListener(_onTrackingUpdate);
    _checkForBackup();
    _startBatteryMonitoring();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) AppTips.showFirstTrackTip(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('[RecordPage] AppLifecycleState: $state');
    if (state == AppLifecycleState.inactive || 
        state == AppLifecycleState.paused || 
        state == AppLifecycleState.detached) {
      _saveStateToBackup();
    }
  }

  Future<void> _saveStateToBackup() async {
    final state = _trackingBloc.state;
    if (state.isIdle || state.points.isEmpty) return;
    
    debugPrint('[RecordPage] Salvataggio backup: ${state.points.length} punti, ${_photos.length} foto');
    
    final backup = RecordingBackup(
      points: state.points,
      startTime: state.startTime ?? DateTime.now(),
      pausedDuration: state.pausedDuration,
      activityType: state.activityType,
      photos: _photos.map((p) => PhotoBackup(
        localPath: p.localPath, latitude: p.latitude,
        longitude: p.longitude, elevation: p.elevation, timestamp: p.timestamp,
      )).toList(),
    );
    await _persistence.saveState(backup);
  }

  Future<void> _checkForBackup() async {
    final hasBackup = await _persistence.hasBackup();
    if (!hasBackup) return;
    
    final backup = await _persistence.loadState();
    if (backup == null || backup.points.isEmpty) {
      await _persistence.clearState();
      return;
    }
    
    final age = DateTime.now().difference(backup.lastSaveTime);
    if (age.inHours > 24) {
      await _persistence.clearState();
      return;
    }
    
    if (!mounted) return;
    
    final shouldRestore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(children: [Icon(Icons.restore, color: AppColors.warning), SizedBox(width: 8), Text('Registrazione trovata')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('È stata trovata una registrazione non salvata:'),
            const SizedBox(height: 12),
            _buildBackupInfo(backup),
            const SizedBox(height: 12),
            const Text('Vuoi recuperarla?', style: TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Elimina')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Recupera'),
          ),
        ],
      ),
    );
    
    if (shouldRestore == true) await _restoreFromBackup(backup);
    else await _persistence.clearState();
  }

  Widget _buildBackupInfo(RecordingBackup backup) {
    double distance = 0;
    for (int i = 1; i < backup.points.length; i++) {
      distance += backup.points[i - 1].distanceTo(backup.points[i]);
    }
    final duration = backup.lastSaveTime.difference(backup.startTime) - backup.pausedDuration;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📍 ${backup.points.length} punti GPS'),
          Text('📏 ${(distance / 1000).toStringAsFixed(2)} km'),
          Text('⏱️ ${duration.inHours > 0 ? "${duration.inHours}h ${duration.inMinutes.remainder(60)}m" : "${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s"}'),
          if (backup.photos.isNotEmpty) Text('📸 ${backup.photos.length} foto'),
        ],
      ),
    );
  }

  Future<void> _restoreFromBackup(RecordingBackup backup) async {
    setState(() => _isRestoringState = true);
    try {
      for (final photoBackup in backup.photos) {
        final file = File(photoBackup.localPath);
        if (await file.exists()) {
          _photos.add(TrackPhoto(
            localPath: photoBackup.localPath, latitude: photoBackup.latitude,
            longitude: photoBackup.longitude, elevation: photoBackup.elevation, timestamp: photoBackup.timestamp,
          ));
        }
      }
      await _trackingBloc.restoreFromBackup(
        points: backup.points, startTime: backup.startTime,
        pausedDuration: backup.pausedDuration, activityType: backup.activityType,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Recuperati ${backup.points.length} punti GPS'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger));
    } finally {
      setState(() => _isRestoringState = false);
    }
  }

  void _onTrackingUpdate() {
    if (_followUser && _trackingBloc.state.points.isNotEmpty) {
      final lastPoint = _trackingBloc.state.points.last;
      _mapController.move(LatLng(lastPoint.latitude, lastPoint.longitude), _mapController.camera.zoom);
    }
    final state = _trackingBloc.state;
    if (!state.isIdle && state.points.length % 5 == 0) _saveStateToBackup();
    setState(() {});
  }

  void _startBatteryMonitoring() {
    _batterySubscription = _battery.onBatteryStateChanged.listen((_) async {
      await _checkBatteryLevel();
    });
    // Check iniziale
    _checkBatteryLevel();
  }

  Future<void> _checkBatteryLevel() async {
    if (!mounted) return;
    final state = _trackingBloc.state;
    if (state.isIdle) return; // Non in registrazione
    
    try {
      final level = await _battery.batteryLevel;
      debugPrint('[RecordPage] Batteria: $level%');
      
      // Warning a 15%
      if (level <= 15 && !_lowBatteryWarningShown) {
        _lowBatteryWarningShown = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Batteria bassa! La traccia verrà salvata automaticamente al 5%'),
              backgroundColor: AppColors.warning,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
      
      // Salvataggio automatico a 5%
      if (level <= 5 && state.points.isNotEmpty) {
        debugPrint('[RecordPage] Batteria critica! Salvataggio automatico...');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔋 Batteria critica! Salvataggio traccia in corso...'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
        await _autoSaveTrack();
      }
    } catch (e) {
      debugPrint('[RecordPage] Errore check batteria: $e');
    }
  }

  Future<void> _autoSaveTrack() async {
    if (_isSaving) return;
    
    final state = _trackingBloc.state;
    if (state.isIdle || state.points.isEmpty) return;
    
    setState(() => _isSaving = true);
    
    try {
      final track = await _trackingBloc.stopRecording();
      if (track == null) return;
      
      final now = DateTime.now();
      final activityName = track.activityType.displayName;
      final trackToSave = track.copyWith(name: '$activityName ${now.day}/${now.month}/${now.year} (auto-salvato)');
      
      await _repository.saveTrack(trackToSave);
      await _trackingBloc.stopForegroundService();
      await _persistence.clearState();
      await LiveTrackService().stop();
      _photos.clear();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Traccia salvata automaticamente!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      debugPrint('[RecordPage] Errore auto-save: $e');
      // Almeno salva il backup
      await _saveStateToBackup();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _trackingBloc.removeListener(_onTrackingUpdate);
    _batterySubscription?.cancel();
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
          if (_photos.isNotEmpty || !state.isIdle)
            Positioned(bottom: 180, left: 0, right: 0,
              child: PhotoGalleryWidget(photos: _photos, isRecording: !state.isIdle, onAddPhoto: state.isIdle ? null : _showPhotoOptions, onDeletePhoto: _deletePhoto),
            ),
          if (!state.isIdle) _buildStatsHeader(state),
          _buildControls(state),
          if (state.errorMessage != null)
            Positioned(top: MediaQuery.of(context).padding.top + 100, left: 16, right: 16, child: _buildErrorBanner(state.errorMessage!)),
          if (_isSaving) Container(color: Colors.black54, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(color: Colors.white), const SizedBox(height: 16),
            const Text('Salvataggio traccia...', style: TextStyle(color: Colors.white)),
            if (_photos.isNotEmpty) Text('Upload di ${_photos.length} foto...', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
          if (_isRestoringState) Container(color: Colors.black54, child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Colors.white), SizedBox(height: 16),
            Text('Ripristino registrazione...', style: TextStyle(color: Colors.white)),
          ])),
        ],
      ),
      floatingActionButton: !state.isIdle && state.isRecording
          ? AddPhotoButton(onTakePhoto: _takePhoto, onPickFromGallery: _pickPhotos) : null,
    );
  }

  Future<void> _takePhoto() async {
    final state = _trackingBloc.state;
    if (state.points.isEmpty) { _showSnackBar('GPS non disponibile', isError: true); return; }
    await _saveStateToBackup();
    final lastPoint = state.points.last;
    final photo = await _photosService.takePhoto(latitude: lastPoint.latitude, longitude: lastPoint.longitude, elevation: lastPoint.elevation);
    if (!mounted) return;
    if (photo != null) { setState(() => _photos.add(photo)); _showSnackBar('📸 Foto aggiunta!'); await _saveStateToBackup(); }
  }

  Future<void> _pickPhotos() async {
    final state = _trackingBloc.state;
    TrackPoint? lastPoint; if (state.points.isNotEmpty) lastPoint = state.points.last;
    await _saveStateToBackup();
    final photos = await _photosService.pickFromGallery(latitude: lastPoint?.latitude, longitude: lastPoint?.longitude, elevation: lastPoint?.elevation);
    if (!mounted) return;
    if (photos.isNotEmpty) { setState(() => _photos.addAll(photos)); _showSnackBar('📸 ${photos.length} foto aggiunte!'); await _saveStateToBackup(); }
  }

  void _deletePhoto(int index) { setState(() => _photos.removeAt(index)); _showSnackBar('Foto eliminata'); _saveStateToBackup(); }

  void _showPhotoOptions() {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.camera_alt, color: AppColors.primary), title: const Text('Scatta foto'), onTap: () { Navigator.pop(context); _takePhoto(); }),
      ListTile(leading: const Icon(Icons.photo_library, color: AppColors.info), title: const Text('Scegli dalla galleria'), onTap: () { Navigator.pop(context); _pickPhotos(); }),
    ])));
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? AppColors.danger : AppColors.success, duration: const Duration(seconds: 2)));
  }

  void _showCancelDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Annullare registrazione?'),
      content: Text(_photos.isEmpty ? 'I dati della traccia corrente verranno persi.' : 'I dati della traccia e le ${_photos.length} foto verranno persi.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Continua')),
        TextButton(onPressed: () { Navigator.pop(context); setState(() => _photos.clear()); _trackingBloc.cancelRecording(); _persistence.clearState(); LiveTrackService().stop(); },
          child: const Text('Annulla', style: TextStyle(color: AppColors.danger))),
      ],
    ));
  }

  void _showSaveDialog() async {
    // 1. Prima PAUSA per mostrare il dialog con i dati ancora disponibili
    _trackingBloc.pauseRecording();
    
    final state = _trackingBloc.state;
    if (state.points.isEmpty) {
      await _trackingBloc.cancelRecording();
      await _trackingBloc.stopForegroundService();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nessun punto registrato')));
      return;
    }
    if (!mounted) return;
    
    // 2. Genera nome default con tipo attività e data
    final now = DateTime.now();
    final activityName = state.activityType.displayName;
    final defaultName = '$activityName del ${now.day}/${now.month}/${now.year}';
    final nameController = TextEditingController(text: defaultName);
    
    // 3. Mostra dialog di conferma (lo stato è in pausa, non perso)
    final shouldSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Salva traccia'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome traccia', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          _buildSummaryRow('Distanza', '${state.stats.distanceKm.toStringAsFixed(2)} km'),
          _buildSummaryRow('Dislivello', '+${state.stats.elevationGain.toStringAsFixed(0)} m'),
          _buildSummaryRow('Durata', state.stats.durationFormatted),
          _buildSummaryRow('Punti GPS', '${state.points.length}'),
          if (_photos.isNotEmpty) _buildSummaryRow('Foto', '${_photos.length}'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white), child: const Text('Salva')),
        ],
      ),
    );
    
    // 4. Se annullato, riprendi la registrazione
    if (shouldSave != true) {
      _trackingBloc.resumeRecording();
      return;
    }

    // 5. Ora ferma definitivamente e salva
    setState(() => _isSaving = true);
    try {
      final track = await _trackingBloc.stopRecording();
      if (track == null) throw Exception('Errore nel fermare la registrazione');
      
      final trackToSave = track.copyWith(name: nameController.text.trim());
      final trackId = await _repository.saveTrack(trackToSave);
      
      if (_photos.isNotEmpty) {
        final result = await _photosService.uploadPhotos(photos: _photos, trackId: trackId, onProgress: (c, t) => debugPrint('[RecordPage] Upload foto $c/$t'));
        if (result.uploaded.isNotEmpty) {
          final photoMetadata = result.uploaded.map((p) => TrackPhotoMetadata(url: p.url, latitude: p.latitude, longitude: p.longitude, elevation: p.elevation, timestamp: p.timestamp)).toList();
          await _repository.updateTrackPhotos(trackId, photoMetadata);
        }
        if (result.hasFailures && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${result.failed.length} foto non caricate'), backgroundColor: AppColors.warning));
        }
      }
      
      await _trackingBloc.stopForegroundService();
      await _persistence.clearState();
      await LiveTrackService().stop();
      _photos.clear();
      
      if (mounted) {
        _showCompletionDialog(trackToSave);
      }
    } catch (e) {
      debugPrint('[RecordPage] Errore salvataggio: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildSummaryRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: AppColors.textSecondary)), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]));
  Widget _buildErrorBanner(String message) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.error_outline, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text(message, style: const TextStyle(color: Colors.white)))]));

  Widget _buildMap(TrackingState state) {
    final center = state.points.isNotEmpty ? LatLng(state.points.last.latitude, state.points.last.longitude) : const LatLng(45.9, 9.9);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: center, initialZoom: 16, minZoom: 4, maxZoom: 18, onPositionChanged: (position, hasGesture) { if (hasGesture) _followUser = false; }),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.trailshare.app'),
        if (state.points.length >= 2) PolylineLayer(polylines: [Polyline(points: state.points.map((p) => LatLng(p.latitude, p.longitude)).toList(), strokeWidth: 4, color: state.isRecording ? AppColors.trackRecording : AppColors.primary)]),
        if (state.points.isNotEmpty) MarkerLayer(markers: [
          Marker(point: LatLng(state.points.first.latitude, state.points.first.longitude), width: 24, height: 24, child: Container(decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: const Icon(Icons.flag, color: Colors.white, size: 14))),
          Marker(point: LatLng(state.points.last.latitude, state.points.last.longitude), width: 32, height: 32, child: Container(decoration: BoxDecoration(color: state.isRecording ? AppColors.trackRecording : AppColors.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: (state.isRecording ? AppColors.trackRecording : AppColors.primary).withOpacity(0.4), blurRadius: 8, spreadRadius: 2)]), child: const Icon(Icons.navigation, color: Colors.white, size: 18))),
        ]),
      ],
    );
  }

  Widget _buildStatsHeader(TrackingState state) {
    return Positioned(top: 0, left: 0, right: 0, child: Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 16, left: 16, right: 16),
      decoration: BoxDecoration(color: state.isRecording ? AppColors.trackRecording.withOpacity(0.95) : AppColors.warning.withOpacity(0.95), borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const SizedBox(width: 60),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(state.isRecording ? Icons.fiber_manual_record : Icons.pause, color: Colors.white, size: 12),
            const SizedBox(width: 4),
            Text(state.isRecording ? 'REGISTRAZIONE' : 'IN PAUSA', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ]),
          const HeartRateWidget(), // ❤️ HEART RATE
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _buildStat('Distanza', '${state.stats.distanceKm.toStringAsFixed(2)} km'),
          _buildStat('Tempo', state.stats.durationFormatted),
          _buildStat('D+', '${state.stats.elevationGain.toStringAsFixed(0)} m'),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _buildStat('Vel.', '${(state.stats.currentSpeed * 3.6).toStringAsFixed(1)} km/h', small: true),
          _buildStat('Media', '${(state.stats.avgSpeed * 3.6).toStringAsFixed(1)} km/h', small: true),
          _buildStat('Passo', _formatPace(state.stats.avgSpeed), small: true),
        ]),
      ]),
    ));
  }

  Widget _buildStat(String label, String value, {bool small = false}) => Column(children: [Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: small ? 16 : 22)), Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: small ? 10 : 11))]);
  String _formatPace(double avgSpeed) { if (avgSpeed <= 0) return '--:--'; final paceSeconds = 1000 / avgSpeed; final minutes = (paceSeconds / 60).floor(); final seconds = (paceSeconds % 60).floor(); return '$minutes:${seconds.toString().padLeft(2, '0')}'; }

  Widget _buildControls(TrackingState state) {
    return Positioned(bottom: 24, left: 16, right: 16, child: Column(children: [
      if (!state.isIdle) Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(bottom: 16), child: FloatingActionButton.small(heroTag: 'center', onPressed: () { _followUser = true; if (state.points.isNotEmpty) _mapController.move(LatLng(state.points.last.latitude, state.points.last.longitude), 16); }, backgroundColor: _followUser ? AppColors.primary : Colors.white, child: Icon(Icons.my_location, color: _followUser ? Colors.white : AppColors.textPrimary)))),
      if (state.isIdle) _buildStartButton() else _buildRecordingControls(state),
    ]));
  }

  Widget _buildStartButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Selettore tipo attività (tap per aprire bottom sheet)
        GestureDetector(
          onTap: _showActivityPicker,
          child: Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_selectedActivity.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(
                  _selectedActivity.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF1A2E1A),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.expand_more, size: 20, color: Colors.grey[600]),
              ],
            ),
          ),
        ),
        // Pulsante INIZIA
        GestureDetector(
          onTap: () => _trackingBloc.startRecording(activityType: _selectedActivity),
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 20, spreadRadius: 5)],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                Text(
                  _selectedActivity.displayName.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- BOTTOM SHEET per selezionare attività ---

  void _showActivityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ActivityPickerSheet(
        selected: _selectedActivity,
        onSelected: (type) {
          setState(() => _selectedActivity = type);
          Navigator.pop(context);
        },
      ),
    );
  }


  Widget _buildRecordingControls(TrackingState state) => Column(mainAxisSize: MainAxisSize.min, children: [
    const Padding(padding: EdgeInsets.only(bottom: 12), child: LiveTrackButton()),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _buildControlButton(icon: Icons.close, label: 'Annulla', color: AppColors.textMuted, onTap: _showCancelDialog),
      _buildControlButton(icon: state.isRecording ? Icons.pause : Icons.play_arrow, label: state.isRecording ? 'Pausa' : 'Riprendi', color: AppColors.warning, onTap: () { if (state.isRecording) _trackingBloc.pauseRecording(); else _trackingBloc.resumeRecording(); }, large: true),
      _buildControlButton(icon: Icons.stop, label: 'Salva', color: AppColors.danger, onTap: _showSaveDialog),
    ])),
  ]);

  Widget _buildControlButton({required IconData icon, required String label, required Color color, required VoidCallback onTap, bool large = false}) {
    final size = large ? 64.0 : 48.0;
    return GestureDetector(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: size, height: size, decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle), child: Icon(icon, color: color, size: large ? 32 : 24)), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500))]));
  }

  void _showCompletionDialog(Track track) {
    final km = (track.stats.distance / 1000).toStringAsFixed(1);
    final elev = track.stats.elevationGain.toStringAsFixed(0);
    final h = track.stats.duration.inHours;
    final m = track.stats.duration.inMinutes % 60;
    final duration = h > 0 ? '${h}h ${m}m' : '${m} min';

    // Messaggi motivazionali casuali
    final messages = [
      'Ottimo lavoro! 💪',
      'Grande escursione! 🏔️',
      'Fantastico percorso! 🥾',
      'Che avventura! 🌟',
      'Sei un vero esploratore! 🧭',
      'Trail completato! 🎯',
      'Complimenti, continua così! 🔥',
    ];
    final message = messages[DateTime.now().millisecond % messages.length];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn('🏃', km, 'km'),
                Container(width: 1, height: 40, color: Colors.grey[300]),
                _buildStatColumn('⬆️', elev, 'm D+'),
                Container(width: 1, height: 40, color: Colors.grey[300]),
                _buildStatColumn('⏱️', duration, ''),
              ],
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Continua', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (label.isNotEmpty)
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}
class _ActivityPickerSheet extends StatelessWidget {
  final ActivityType selected;
  final ValueChanged<ActivityType> onSelected;

  const _ActivityPickerSheet({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Raggruppa per categoria
    final grouped = <String, List<ActivityType>>{};
    for (final type in ActivityType.values) {
      grouped.putIfAbsent(type.category, () => []).add(type);
    }

    // Icona categoria
    String categoryIcon(String cat) {
      switch (cat) {
        case 'A piedi':
          return '🚶';
        case 'In bicicletta':
          return '🚴';
        case 'Sport invernali':
          return '❄️';
        default:
          return '🏃';
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Titolo
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'Scegli attività',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2E1A),
              ),
            ),
          ),

          // Lista categorie + sport
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: grouped.entries.map((entry) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header categoria
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8, left: 4),
                      child: Row(
                        children: [
                          Text(categoryIcon(entry.key), style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[600],
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Grid di sport
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: entry.value.map((type) {
                        final isSelected = type == selected;
                        return GestureDetector(
                          onTap: () => onSelected(type),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFF5F7F2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF388E3C)
                                    : const Color(0xFFE0E4DA),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(type.icon, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 6),
                                Text(
                                  type.displayName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? Colors.white : const Color(0xFF1A2E1A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
