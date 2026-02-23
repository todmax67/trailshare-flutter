import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../../../core/services/offline_tile_provider.dart';

/// Pagina per seguire una traccia in tempo reale
///
/// Funzionalità:
/// - Mappa fullscreen con traccia e posizione live GPS
/// - Barra stats: distanza percorsa, restante, dislivello, off-trail
/// - Avviso deviazione (>50m dalla traccia) con vibrazione
/// - Mini grafico elevazione con indicatore posizione
/// - Cambio stile mappa (Standard, Topo, Satellite)
/// - Centra su utente / centra su traccia
/// - Funziona in background (usa Geolocator stream)
class TrailFollowPage extends StatefulWidget {
  /// Punti completi della traccia da seguire
  final List<TrackPoint> trailPoints;

  /// Nome del sentiero
  final String trailName;

  /// Distanza totale in metri (opzionale, calcolata se non fornita)
  final double? totalDistance;

  /// Dislivello positivo in metri (opzionale)
  final double? totalElevationGain;

  const TrailFollowPage({
    super.key,
    required this.trailPoints,
    required this.trailName,
    this.totalDistance,
    this.totalElevationGain,
  });

  @override
  State<TrailFollowPage> createState() => _TrailFollowPageState();
}

class _TrailFollowPageState extends State<TrailFollowPage> {
  final MapController _mapController = MapController();
  final Distance _distCalc = const Distance();

  // GPS
  StreamSubscription<Position>? _positionSub;
  LatLng? _userPosition;
  double? _userHeading;
  bool _isGpsActive = false;
  String? _gpsError;

  // Stato navigazione
  int _nearestPointIndex = 0;
  double _distanceFromTrail = 0; // metri dalla traccia
  double _distanceCovered = 0; // metri percorsi lungo la traccia
  double _distanceRemaining = 0;
  double _elevationGainRemaining = 0;
  double _currentElevation = 0;
  bool _isOffTrail = false;
  bool _hasReachedEnd = false;

  // Dati traccia pre-calcolati
  late List<LatLng> _trailLatLngs;
  late List<double> _cumulativeDistances;
  late double _totalDistance;
  late double _totalElevationGain;

  // UI
  bool _followUser = true; // auto-centra su utente
  int _currentMapStyle = 0;
  final List<(String name, String url)> _mapStyles = [
    ('Standard', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
    ('Topo', 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png'),
    ('Satellite', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'),
  ];

  // Off-trail
  static const double _offTrailThreshold = 50.0; // metri
  static const double _severeOffTrailThreshold = 150.0;
  DateTime? _lastVibration;

  // 🔊 Audio alert
  final AudioPlayer _alertPlayer = AudioPlayer();
  bool _soundEnabled = true;
  String? _beepFilePath;
  String? _severeBeepFilePath;

  // ⏺ Registrazione traccia
  final TracksRepository _tracksRepo = TracksRepository();
  bool _isRecording = false;
  List<TrackPoint> _recordedPoints = [];
  DateTime? _recordingStartTime;
  Timer? _recDurationTimer;
  Duration _recordingDuration = Duration.zero;
  bool _isSavingTrack = false;

  @override
  void initState() {
    super.initState();
    _precalculateTrailData();
    _prepareAlertSounds();
    _startGps();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _alertPlayer.dispose();
    _recDurationTimer?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO ALERT - Genera beep WAV in memoria (nessun file esterno necessario)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Prepara i file audio di allarme (generati programmaticamente)
  Future<void> _prepareAlertSounds() async {
    try {
      final dir = await getTemporaryDirectory();

      // Beep normale: 880Hz, 400ms (fuori traccia >50m)
      final beepFile = File('${dir.path}/trail_alert.wav');
      await beepFile.writeAsBytes(_generateBeepWav(frequency: 880, durationMs: 400));
      _beepFilePath = beepFile.path;

      // Beep severo: 1200Hz, 600ms, più forte (fuori traccia >150m)
      final severeFile = File('${dir.path}/trail_alert_severe.wav');
      await severeFile.writeAsBytes(_generateBeepWav(frequency: 1200, durationMs: 600));
      _severeBeepFilePath = severeFile.path;

      debugPrint('[TrailFollow] 🔊 Alert sounds pronti');
    } catch (e) {
      debugPrint('[TrailFollow] Errore preparazione suoni: $e');
    }
  }

  /// Genera un file WAV con un tono sinusoidale puro
  Uint8List _generateBeepWav({
    required int frequency,
    required int durationMs,
    int sampleRate = 44100,
    double volume = 0.8,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final dataSize = numSamples * 2; // 16-bit mono
    final buffer = ByteData(44 + dataSize);

    // ── WAV Header ──
    // "RIFF"
    buffer.setUint8(0, 0x52);
    buffer.setUint8(1, 0x49);
    buffer.setUint8(2, 0x46);
    buffer.setUint8(3, 0x46);
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    // "WAVE"
    buffer.setUint8(8, 0x57);
    buffer.setUint8(9, 0x41);
    buffer.setUint8(10, 0x56);
    buffer.setUint8(11, 0x45);
    // "fmt "
    buffer.setUint8(12, 0x66);
    buffer.setUint8(13, 0x6D);
    buffer.setUint8(14, 0x74);
    buffer.setUint8(15, 0x20);
    buffer.setUint32(16, 16, Endian.little); // chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM format
    buffer.setUint16(22, 1, Endian.little); // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buffer.setUint16(32, 2, Endian.little); // block align
    buffer.setUint16(34, 16, Endian.little); // bits per sample
    // "data"
    buffer.setUint8(36, 0x64);
    buffer.setUint8(37, 0x61);
    buffer.setUint8(38, 0x74);
    buffer.setUint8(39, 0x61);
    buffer.setUint32(40, dataSize, Endian.little);

    // ── Genera onda sinusoidale con fade in/out ──
    final fadeFrames = (sampleRate * 0.02).round(); // 20ms fade
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double envelope = volume;

      // Fade in
      if (i < fadeFrames) {
        envelope *= i / fadeFrames;
      }
      // Fade out
      if (i > numSamples - fadeFrames) {
        envelope *= (numSamples - i) / fadeFrames;
      }

      final sample =
          (math.sin(2 * math.pi * frequency * t) * 32767 * envelope)
              .round()
              .clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRECALCOLO DATI TRACCIA
  // ═══════════════════════════════════════════════════════════════════════════

  void _precalculateTrailData() {
    _trailLatLngs = widget.trailPoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    // Distanze cumulative
    _cumulativeDistances = [0.0];
    for (int i = 1; i < _trailLatLngs.length; i++) {
      final d = _distCalc.as(
        LengthUnit.Meter,
        _trailLatLngs[i - 1],
        _trailLatLngs[i],
      );
      _cumulativeDistances.add(_cumulativeDistances.last + d);
    }

    _totalDistance =
        widget.totalDistance ?? _cumulativeDistances.last;

    // Dislivello positivo
    if (widget.totalElevationGain != null) {
      _totalElevationGain = widget.totalElevationGain!;
    } else {
      double gain = 0;
      for (int i = 1; i < widget.trailPoints.length; i++) {
        final prev = widget.trailPoints[i - 1].elevation;
        final curr = widget.trailPoints[i].elevation;
        if (prev != null && curr != null && curr > prev) {
          gain += curr - prev;
        }
      }
      _totalElevationGain = gain;
    }

    _distanceRemaining = _totalDistance;
    _elevationGainRemaining = _totalElevationGain;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GPS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _startGps() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _gpsError = 'GPS disattivato');
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          setState(() => _gpsError = 'Permesso GPS negato');
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() => _gpsError = 'Permesso GPS negato permanentemente');
        return;
      }

      // Prima posizione
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        _onNewPosition(pos);
      } catch (_) {}

      // Stream continuo
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen(
        _onNewPosition,
        onError: (e) {
          debugPrint('[TrailFollow] GPS error: $e');
          if (mounted) setState(() => _gpsError = 'Errore GPS');
        },
      );

      setState(() {
        _isGpsActive = true;
        _gpsError = null;
      });
    } catch (e) {
      setState(() => _gpsError = 'Errore: $e');
    }
  }

  void _onNewPosition(Position pos) {
    if (!mounted) return;

    // ⏺ Se in registrazione, salva il punto
    if (_isRecording) {
      _recordedPoints.add(TrackPoint(
        latitude: pos.latitude,
        longitude: pos.longitude,
        elevation: pos.altitude > 0 ? pos.altitude : null,
        timestamp: pos.timestamp ?? DateTime.now(),
        speed: pos.speed > 0 ? pos.speed : null,
        accuracy: pos.accuracy,
        heading: pos.heading > 0 ? pos.heading : null,
      ));
    }

    final userPos = LatLng(pos.latitude, pos.longitude);

    // Trova punto più vicino sulla traccia
    double minDist = double.infinity;
    int nearestIdx = 0;

    for (int i = 0; i < _trailLatLngs.length; i++) {
      final d = _distCalc.as(LengthUnit.Meter, userPos, _trailLatLngs[i]);
      if (d < minDist) {
        minDist = d;
        nearestIdx = i;
      }
    }

    // Calcola distanza percorsa e restante
    final covered = _cumulativeDistances[nearestIdx];
    final remaining = _totalDistance - covered;

    // Calcola dislivello restante
    double elevGainRemaining = 0;
    for (int i = nearestIdx + 1; i < widget.trailPoints.length; i++) {
      final prev = widget.trailPoints[i - 1].elevation;
      final curr = widget.trailPoints[i].elevation;
      if (prev != null && curr != null && curr > prev) {
        elevGainRemaining += curr - prev;
      }
    }

    // Elevazione corrente (dal punto più vicino sulla traccia)
    final currentEle = widget.trailPoints[nearestIdx].elevation ?? 0;

    // Check deviazione
    final wasOffTrail = _isOffTrail;
    final isNowOffTrail = minDist > _offTrailThreshold;

    // Alert se appena deviato (suono normale)
    if (isNowOffTrail && !wasOffTrail) {
      _triggerAlert(severe: false);
    }
    // Alert periodico se molto lontano (suono severo)
    if (minDist > _severeOffTrailThreshold) {
      final now = DateTime.now();
      if (_lastVibration == null ||
          now.difference(_lastVibration!) > const Duration(seconds: 15)) {
        _triggerAlert(severe: true);
        _lastVibration = now;
      }
    }

    // Check arrivo
    final hasReached = nearestIdx >= _trailLatLngs.length - 3 && minDist < 50;

    setState(() {
      _userPosition = userPos;
      _userHeading = pos.heading > 0 ? pos.heading : null;
      _nearestPointIndex = nearestIdx;
      _distanceFromTrail = minDist;
      _distanceCovered = covered;
      _distanceRemaining = remaining.clamp(0, _totalDistance);
      _elevationGainRemaining = elevGainRemaining;
      _currentElevation = currentEle;
      _isOffTrail = isNowOffTrail;
      _hasReachedEnd = hasReached;
      _gpsError = null;
    });

    // Auto-centra
    if (_followUser) {
      _mapController.move(userPos, _mapController.camera.zoom);
    }
  }

  /// Vibrazione + suono di allarme
  void _triggerAlert({required bool severe}) {
    // Vibrazione sempre
    HapticFeedback.heavyImpact();

    // Suono solo se abilitato
    if (_soundEnabled) {
      _playAlertSound(severe: severe);
    }
  }

  /// Riproduce il beep di allarme
  Future<void> _playAlertSound({required bool severe}) async {
    try {
      final filePath = severe ? _severeBeepFilePath : _beepFilePath;
      if (filePath == null) return;

      await _alertPlayer.stop();
      await _alertPlayer.setVolume(severe ? 1.0 : 0.7);
      await _alertPlayer.play(DeviceFileSource(filePath));

      // Se severo, ripeti il beep dopo 300ms per più urgenza
      if (severe) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          await _alertPlayer.play(DeviceFileSource(filePath));
        }
      }
    } catch (e) {
      debugPrint('[TrailFollow] Errore riproduzione alert: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ⏺ REGISTRAZIONE TRACCIA
  // ═══════════════════════════════════════════════════════════════════════════

  void _toggleRecording() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _recordedPoints = [];
      _recordingStartTime = DateTime.now();
      _recordingDuration = Duration.zero;
    });

    // Timer per aggiornare la durata visualizzata
    _recDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRecording && _recordingStartTime != null) {
        setState(() {
          _recordingDuration = DateTime.now().difference(_recordingStartTime!);
        });
      }
    });

    HapticFeedback.mediumImpact();
    debugPrint('[TrailFollow] ⏺ Registrazione avviata');
  }

  Future<void> _stopRecording() async {
    _recDurationTimer?.cancel();

    if (_recordedPoints.length < 2) {
      setState(() {
        _isRecording = false;
        _recordedPoints = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Troppo pochi punti per salvare')),
        );
      }
      return;
    }

    setState(() => _isRecording = false);
    HapticFeedback.mediumImpact();

    // Mostra dialog salvataggio
    if (mounted) {
      await _showSaveDialog();
    }
  }

  Future<void> _showSaveDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Devi essere loggato per salvare')),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SaveRecordingDialog(
        trailName: widget.trailName,
        pointsCount: _recordedPoints.length,
        duration: _recordingDuration,
        distance: _calculateRecordedDistance(),
      ),
    );

    if (result == null) {
      // Utente ha annullato - chiedi se scartare
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Scartare registrazione?'),
          content: Text('Hai registrato ${_recordedPoints.length} punti. Vuoi scartarli?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, salva'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Scarta', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      );
      if (discard != true && mounted) {
        await _showSaveDialog(); // Riapri dialog
      }
      return;
    }

    // Salva la traccia
    await _saveRecordedTrack(
      name: result['name'] as String,
      activityType: result['activityType'] as ActivityType,
    );
  }

  Future<void> _saveRecordedTrack({
    required String name,
    required ActivityType activityType,
  }) async {
    setState(() => _isSavingTrack = true);

    try {
      final stats = _calculateRecordedStats();
      final track = Track(
        name: name,
        points: _recordedPoints,
        activityType: activityType,
        recordedAt: _recordingStartTime,
        createdAt: DateTime.now(),
        stats: stats,
      );

      final trackId = await _tracksRepo.saveTrack(track);
      debugPrint('[TrailFollow] ✅ Traccia salvata: $trackId (${_recordedPoints.length} punti)');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Traccia "$name" salvata! (${_recordedPoints.length} punti)'),
            backgroundColor: AppColors.success,
          ),
        );
      }

      _recordedPoints = [];
    } catch (e) {
      debugPrint('[TrailFollow] ❌ Errore salvataggio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore salvataggio: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingTrack = false);
    }
  }

  double _calculateRecordedDistance() {
    double dist = 0;
    for (int i = 1; i < _recordedPoints.length; i++) {
      final prev = LatLng(_recordedPoints[i - 1].latitude, _recordedPoints[i - 1].longitude);
      final curr = LatLng(_recordedPoints[i].latitude, _recordedPoints[i].longitude);
      dist += _distCalc.as(LengthUnit.Meter, prev, curr);
    }
    return dist;
  }

  TrackStats _calculateRecordedStats() {
    final distance = _calculateRecordedDistance();
    double elevGain = 0, elevLoss = 0;
    double maxEle = double.negativeInfinity, minEle = double.infinity;
    double maxSpeed = 0;

    for (int i = 1; i < _recordedPoints.length; i++) {
      final prev = _recordedPoints[i - 1];
      final curr = _recordedPoints[i];

      if (curr.elevation != null) {
        if (curr.elevation! > maxEle) maxEle = curr.elevation!;
        if (curr.elevation! < minEle) minEle = curr.elevation!;
        if (prev.elevation != null) {
          final diff = curr.elevation! - prev.elevation!;
          if (diff > 2) elevGain += diff;
          if (diff < -2) elevLoss += diff.abs();
        }
      }
      if (curr.speed != null && curr.speed! > maxSpeed) {
        maxSpeed = curr.speed!;
      }
    }

    final avgSpeed = _recordingDuration.inSeconds > 0
        ? distance / _recordingDuration.inSeconds
        : 0.0;

    return TrackStats(
      distance: distance,
      elevationGain: elevGain,
      elevationLoss: elevLoss,
      maxElevation: maxEle.isFinite ? maxEle : 0,
      minElevation: minEle.isFinite ? minEle : 0,
      duration: _recordingDuration,
      movingTime: _recordingDuration,
      avgSpeed: avgSpeed,
      maxSpeed: maxSpeed,
    );
  }

  String _formatRecDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Mappa
          _buildMap(),

          // Barra superiore con nome e pulsante indietro
          _buildTopBar(),

          // Avviso deviazione
          if (_isOffTrail) _buildOffTrailWarning(),

          // Avviso arrivo
          if (_hasReachedEnd) _buildArrivalBanner(),

          // Errore GPS
          if (_gpsError != null) _buildGpsError(),

          // Controlli mappa (destra)
          _buildMapControls(),

          // ⏺ Pulsante registrazione (sinistra)
          _buildRecButton(),

          // Stats panel (basso)
          _buildStatsPanel(),

          // Overlay salvataggio
          if (_isSavingTrack)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Salvataggio traccia...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final (center, zoom) = _calculateInitialView();

    // Colore traccia: segmenti percorsi vs restanti
    final coveredPoints = _trailLatLngs.sublist(0, _nearestPointIndex + 1);
    final remainingPoints =
        _trailLatLngs.sublist(_nearestPointIndex);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _userPosition ?? center,
        initialZoom: _userPosition != null ? 16.0 : zoom,
        onPositionChanged: (pos, hasGesture) {
          // Se l'utente muove la mappa manualmente, disattiva auto-centra
          if (hasGesture) {
            setState(() => _followUser = false);
          }
        },
      ),
      children: [
        // Tile layer
        TileLayer(
          urlTemplate: _mapStyles[_currentMapStyle].$2,
          subdomains: _currentMapStyle == 1 ? const ['a', 'b', 'c'] : const [],
          userAgentPackageName: 'com.trailshare.app',
          tileProvider: OfflineFallbackTileProvider(),
        ),

        // Traccia percorsa (grigia)
        if (coveredPoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: coveredPoints,
                strokeWidth: 5,
                color: Colors.grey.shade400,
              ),
            ],
          ),

        // Traccia restante (blu)
        if (remainingPoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: remainingPoints,
                strokeWidth: 5,
                color: AppColors.info,
              ),
            ],
          ),

        // Markers
        MarkerLayer(
          markers: [
            // Start
            Marker(
              point: _trailLatLngs.first,
              width: 28,
              height: 28,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
              ),
            ),

            // End
            Marker(
              point: _trailLatLngs.last,
              width: 28,
              height: 28,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.flag, color: Colors.white, size: 14),
              ),
            ),

            // Punto più vicino sulla traccia (proiezione)
            if (_userPosition != null && _nearestPointIndex < _trailLatLngs.length)
              Marker(
                point: _trailLatLngs[_nearestPointIndex],
                width: 16,
                height: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),

            // Utente
            if (_userPosition != null)
              Marker(
                point: _userPosition!,
                width: 36,
                height: 36,
                child: Transform.rotate(
                  angle: (_userHeading ?? 0) * math.pi / 180,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isOffTrail ? AppColors.danger : Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: (_isOffTrail ? AppColors.danger : Colors.blue)
                              .withOpacity(0.4),
                          blurRadius: 12,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.navigation, color: Colors.white, size: 18),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _showExitConfirm(),
              child: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.trailName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _isGpsActive ? 'Navigazione attiva' : 'In attesa del GPS...',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isGpsActive ? AppColors.success : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // 🔊 Toggle suono alert
            GestureDetector(
              onTap: () {
                setState(() => _soundEnabled = !_soundEnabled);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_soundEnabled
                        ? '🔊 Allarme sonoro attivato'
                        : '🔇 Allarme sonoro disattivato'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  _soundEnabled ? Icons.volume_up : Icons.volume_off,
                  color: _soundEnabled ? AppColors.primary : AppColors.textMuted,
                  size: 22,
                ),
              ),
            ),
            // Indicatore GPS
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _isGpsActive
                    ? (_isOffTrail ? AppColors.danger : AppColors.success)
                    : AppColors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffTrailWarning() {
    final isSevere = _distanceFromTrail > _severeOffTrailThreshold;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSevere ? AppColors.danger : AppColors.warning,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (isSevere ? AppColors.danger : AppColors.warning)
                  .withOpacity(0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isSevere ? Icons.warning_amber : Icons.near_me_disabled,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isSevere
                    ? 'Sei a ${_distanceFromTrail.toStringAsFixed(0)}m dalla traccia!'
                    : 'Fuori traccia (${_distanceFromTrail.toStringAsFixed(0)}m)',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrivalBanner() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.success,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withOpacity(0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sei arrivato alla fine del sentiero! 🎉',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsError() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.gps_off, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _gpsError!,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            GestureDetector(
              onTap: _startGps,
              child: const Icon(Icons.refresh, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecButton() {
    return Positioned(
      left: 12,
      bottom: 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsante REC
          GestureDetector(
            onTap: _toggleRecording,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _isRecording ? AppColors.danger : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? AppColors.danger : Colors.black)
                        .withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: _isRecording ? 2 : 0,
                  ),
                ],
              ),
              child: _isRecording
                  ? const Icon(Icons.stop, color: Colors.white, size: 28)
                  : const Icon(Icons.fiber_manual_record, color: AppColors.danger, size: 28),
            ),
          ),

          // Timer e contatore punti (visibile solo durante registrazione)
          if (_isRecording) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.danger.withOpacity(0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatRecDuration(_recordingDuration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    '${_recordedPoints.length} pt',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      right: 12,
      bottom: 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stile mappa
          _MapBtn(
            icon: Icons.layers,
            onTap: () {
              setState(() {
                _currentMapStyle =
                    (_currentMapStyle + 1) % _mapStyles.length;
              });
            },
            tooltip: _mapStyles[_currentMapStyle].$1,
          ),
          const SizedBox(height: 8),
          // Centra su traccia
          _MapBtn(
            icon: Icons.crop_free,
            onTap: _centerOnTrail,
            tooltip: 'Vedi tutta la traccia',
          ),
          const SizedBox(height: 8),
          // Centra su utente (evidenziato se follow attivo)
          _MapBtn(
            icon: Icons.my_location,
            onTap: _centerOnUser,
            highlighted: _followUser,
            tooltip: 'Centra su di me',
          ),
        ],
      ),
    );
  }

  Widget _buildStatsPanel() {
    final progressPercent =
        _totalDistance > 0 ? (_distanceCovered / _totalDistance).clamp(0.0, 1.0) : 0.0;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Barra progresso
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(progressPercent * 100).toStringAsFixed(0)}% completato',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          _formatDistance(_distanceCovered),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressPercent,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isOffTrail ? AppColors.danger : AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Stats grid
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: [
                    _StatTile(
                      icon: Icons.straighten,
                      value: _formatDistance(_distanceRemaining),
                      label: 'Restante',
                      color: AppColors.primary,
                    ),
                    _StatTile(
                      icon: Icons.trending_up,
                      value: '+${_elevationGainRemaining.toStringAsFixed(0)}m',
                      label: 'Salita',
                      color: AppColors.success,
                    ),
                    _StatTile(
                      icon: Icons.terrain,
                      value: '${_currentElevation.toStringAsFixed(0)}m',
                      label: 'Quota',
                      color: AppColors.info,
                    ),
                    _StatTile(
                      icon: _isOffTrail ? Icons.warning_amber : Icons.near_me,
                      value: '${_distanceFromTrail.toStringAsFixed(0)}m',
                      label: 'Dalla traccia',
                      color: _isOffTrail ? AppColors.danger : AppColors.textMuted,
                    ),
                  ],
                ),
              ),

              // Mini profilo elevazione
              _buildMiniElevation(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniElevation() {
    final elevations = widget.trailPoints
        .map((p) => p.elevation)
        .toList();
    
    if (elevations.every((e) => e == null)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        height: 50,
        child: CustomPaint(
          size: const Size(double.infinity, 50),
          painter: _MiniElevationPainter(
            elevations: elevations,
            progressIndex: _nearestPointIndex,
            totalPoints: widget.trailPoints.length,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AZIONI
  // ═══════════════════════════════════════════════════════════════════════════

  void _centerOnUser() {
    if (_userPosition != null) {
      _mapController.move(_userPosition!, 17);
    }
    setState(() => _followUser = true);
  }

  void _centerOnTrail() {
    final (center, zoom) = _calculateInitialView();
    _mapController.move(center, zoom);
    setState(() => _followUser = false);
  }

  Future<void> _showExitConfirm() async {
    // Se sta registrando, prima ferma e salva
    if (_isRecording) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Registrazione attiva'),
          content: Text(
            'Hai registrato ${_recordedPoints.length} punti in ${_formatRecDuration(_recordingDuration)}.\n'
            'Cosa vuoi fare?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'continue'),
              child: const Text('Continua'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'save_exit'),
              child: const Text('Salva ed esci'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard_exit'),
              child: const Text('Scarta ed esci', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      );

      if (action == 'save_exit' && mounted) {
        _recDurationTimer?.cancel();
        setState(() => _isRecording = false);
        await _showSaveDialog();
        if (mounted) Navigator.pop(context);
      } else if (action == 'discard_exit' && mounted) {
        _recDurationTimer?.cancel();
        setState(() {
          _isRecording = false;
          _recordedPoints = [];
        });
        Navigator.pop(context);
      }
      // 'continue' → non fa niente, torna alla navigazione
      return;
    }

    // Nessuna registrazione attiva → conferma semplice
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Interrompere navigazione?'),
        content: const Text('Vuoi smettere di seguire questa traccia?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continua'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    if (exit == true && mounted) Navigator.pop(context);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITÀ
  // ═══════════════════════════════════════════════════════════════════════════

  (LatLng, double) _calculateInitialView() {
    if (_trailLatLngs.isEmpty) return (const LatLng(45.0, 9.0), 10.0);

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in _trailLatLngs) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final maxDiff = math.max(maxLat - minLat, maxLng - minLng);

    double zoom = 14.0;
    if (maxDiff > 0.5) zoom = 10;
    else if (maxDiff > 0.2) zoom = 11;
    else if (maxDiff > 0.1) zoom = 12;
    else if (maxDiff > 0.05) zoom = 13;

    return (center, zoom);
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET: Stat tile nel pannello basso
// ═══════════════════════════════════════════════════════════════════════════

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET: Map button
// ═══════════════════════════════════════════════════════════════════════════

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool highlighted;

  const _MapBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: highlighted ? AppColors.primary : Colors.white,
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              color: highlighted ? Colors.white : AppColors.primary,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAINTER: Mini profilo elevazione con indicatore posizione
// ═══════════════════════════════════════════════════════════════════════════

class _MiniElevationPainter extends CustomPainter {
  final List<double?> elevations;
  final int progressIndex;
  final int totalPoints;

  _MiniElevationPainter({
    required this.elevations,
    required this.progressIndex,
    required this.totalPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (elevations.isEmpty || totalPoints == 0) return;

    // Trova min/max
    double minEle = double.infinity, maxEle = double.negativeInfinity;
    for (final e in elevations) {
      if (e == null) continue;
      if (e < minEle) minEle = e;
      if (e > maxEle) maxEle = e;
    }
    if (minEle == double.infinity) return;

    final range = (maxEle - minEle).clamp(10.0, double.infinity);
    final w = size.width;
    final h = size.height;

    // Path area
    final path = Path();
    final coveredPath = Path();
    bool started = false;
    bool coveredStarted = false;

    for (int i = 0; i < elevations.length; i++) {
      final e = elevations[i];
      if (e == null) continue;

      final x = (i / (elevations.length - 1)) * w;
      final y = h - ((e - minEle) / range) * (h - 4) - 2;

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }

      // Parte percorsa
      if (i <= progressIndex) {
        if (!coveredStarted) {
          coveredPath.moveTo(x, y);
          coveredStarted = true;
        } else {
          coveredPath.lineTo(x, y);
        }
      }
    }

    // Disegna area completa (grigia chiara)
    final areaPath = Path.from(path);
    areaPath.lineTo(w, h);
    areaPath.lineTo(0, h);
    areaPath.close();

    canvas.drawPath(
      areaPath,
      Paint()..color = Colors.grey.shade200,
    );

    // Linea traccia completa (grigia)
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Linea percorsa (primary)
    if (coveredStarted) {
      canvas.drawPath(
        coveredPath,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    // Indicatore posizione corrente
    if (progressIndex >= 0 && progressIndex < elevations.length) {
      final e = elevations[progressIndex];
      if (e != null) {
        final px = (progressIndex / (elevations.length - 1)) * w;
        final py = h - ((e - minEle) / range) * (h - 4) - 2;

        // Linea verticale
        canvas.drawLine(
          Offset(px, 0),
          Offset(px, h),
          Paint()
            ..color = AppColors.primary.withOpacity(0.3)
            ..strokeWidth = 1,
        );

        // Punto
        canvas.drawCircle(
          Offset(px, py),
          4,
          Paint()..color = AppColors.primary,
        );
        canvas.drawCircle(
          Offset(px, py),
          4,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiniElevationPainter old) {
    return old.progressIndex != progressIndex;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DIALOG: Salva registrazione
// ═══════════════════════════════════════════════════════════════════════════

class _SaveRecordingDialog extends StatefulWidget {
  final String trailName;
  final int pointsCount;
  final Duration duration;
  final double distance;

  const _SaveRecordingDialog({
    required this.trailName,
    required this.pointsCount,
    required this.duration,
    required this.distance,
  });

  @override
  State<_SaveRecordingDialog> createState() => _SaveRecordingDialogState();
}

class _SaveRecordingDialogState extends State<_SaveRecordingDialog> {
  late TextEditingController _nameController;
  ActivityType _activityType = ActivityType.trekking;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final months = ['Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu',
                    'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic'];
    _nameController = TextEditingController(
      text: '${widget.trailName} - ${now.day} ${months[now.month - 1]} ${now.year}',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.save, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Salva traccia'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Riepilogo
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MiniStat(
                    label: 'Distanza',
                    value: '${(widget.distance / 1000).toStringAsFixed(1)} km',
                  ),
                  _MiniStat(
                    label: 'Durata',
                    value: _formatDuration(widget.duration),
                  ),
                  _MiniStat(
                    label: 'Punti',
                    value: '${widget.pointsCount}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Nome traccia
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome traccia',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit),
              ),
            ),
            const SizedBox(height: 16),

            // Tipo attività
            const Text('Tipo attività', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ActivityType.values.map((type) {
                final selected = type == _activityType;
                return ChoiceChip(
                  label: Text('${type.icon} ${type.displayName}'),
                  selected: selected,
                  onSelected: (v) {
                    if (v) setState(() => _activityType = type);
                  },
                  selectedColor: AppColors.primary.withOpacity(0.2),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Annulla'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (_nameController.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'name': _nameController.text.trim(),
              'activityType': _activityType,
            });
          },
          icon: const Icon(Icons.save, size: 18),
          label: const Text('Salva'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
      ],
    );
  }
}
