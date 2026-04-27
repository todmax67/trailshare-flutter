import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/peaks_dataset_service.dart';
import '../../../core/utils/mountain_projection.dart';
import '../../../data/models/mountain_peak.dart';

/// **Mountain Finder AR** — punta il telefono e riconosci le cime.
///
/// **Step 2 (v2.0.0)**: math di proiezione AR completa.
/// I pin sono posizionati correttamente sopra le cime nella camera live
/// usando bearing (bussola) + pitch (accelerometro) + altitudine cima.
///
/// In Step 3 il dataset hardcoded sarà sostituito da quello OSM completo
/// (~12k cime italiane) caricato come asset bundled.
class MountainFinderPage extends StatefulWidget {
  const MountainFinderPage({super.key});

  @override
  State<MountainFinderPage> createState() => _MountainFinderPageState();
}

class _MountainFinderPageState extends State<MountainFinderPage> {
  CameraController? _camera;
  bool _initializing = true;
  String? _error;

  // Sensor state
  Position? _userPosition;
  double? _heading; // 0..360, 0 = Nord (smoothed)
  double _pitchDeg = 0; // -90..+90, 0 = orizzonte (smoothed)

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // Smoothing low-pass alpha (più basso = più fluido ma più lento)
  static const double _alpha = 0.18;

  List<ProjectedPeak> _visiblePeaks = const [];

  /// Cime candidate (entro 60 km dalla posizione utente). Aggiornata quando
  /// la posizione si sposta significativamente. Tipicamente ~50-300 cime,
  /// quindi `projectAll` su questo subset è praticamente gratis.
  List<MountainPeak> _candidatePeaks = const [];

  /// Ultima posizione usata per calcolare le candidate. Quando l'utente si
  /// sposta più di 5 km ricomputiamo il subset (evitiamo lavoro inutile
  /// per piccoli aggiornamenti GPS).
  Position? _lastCandidatePosition;
  static const double _candidateRefreshThresholdMeters = 5000;
  static const double _candidateRadiusKm = 60;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _accelSub?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // Pre-carica il dataset OSM (in parallelo con camera/GPS).
      unawaited(PeaksDatasetService().ensureLoaded());

      // Camera
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _initializing = false;
          _error = context.l10n.mfCameraNotAvailable;
        });
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _camera = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _camera!.initialize();

      // GPS — prima posizione + stream.
      try {
        _userPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {}
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen((pos) async {
        if (!mounted) return;
        setState(() => _userPosition = pos);
        await _refreshCandidatePeaksIfNeeded(pos);
      });

      if (_userPosition != null) {
        await _refreshCandidatePeaksIfNeeded(_userPosition!);
      }

      // Compass: smoothing low-pass per evitare jitter delle label.
      _compassSub = FlutterCompass.events?.listen((event) {
        if (!mounted) return;
        final raw = event.heading;
        if (raw == null) return;
        final normalized = raw < 0 ? raw + 360 : raw;
        final prev = _heading;
        // Gestisci wraparound 359°→0°
        double smoothed;
        if (prev == null) {
          smoothed = normalized;
        } else {
          double delta = normalized - prev;
          if (delta > 180) delta -= 360;
          if (delta < -180) delta += 360;
          smoothed = (prev + _alpha * delta + 360) % 360;
        }
        setState(() => _heading = smoothed);
      });

      // Accelerometer: pitch del telefono (smoothed).
      _accelSub = accelerometerEventStream().listen((event) {
        if (!mounted) return;
        final rawPitch = MountainProjection.pitchFromAccelerometer(
          event.x,
          event.y,
          event.z,
        );
        final smoothed = _pitchDeg + _alpha * (rawPitch - _pitchDeg);
        setState(() => _pitchDeg = smoothed);
      });

      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = context.l10n.errorWithDetails(e.toString());
      });
    }
  }

  /// Aggiorna [_candidatePeaks] interrogando il dataset OSM con la
  /// posizione data, ma solo se l'utente si è spostato più di
  /// [_candidateRefreshThresholdMeters] dall'ultimo aggiornamento.
  Future<void> _refreshCandidatePeaksIfNeeded(Position pos) async {
    final last = _lastCandidatePosition;
    if (last != null) {
      final moved = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (moved < _candidateRefreshThresholdMeters &&
          _candidatePeaks.isNotEmpty) {
        return;
      }
    }

    final ds = PeaksDatasetService();
    if (!ds.isLoaded) {
      await ds.ensureLoaded();
    }
    final candidates = ds.findWithinRadius(
      pos.latitude,
      pos.longitude,
      radiusKm: _candidateRadiusKm,
    );
    if (!mounted) return;
    setState(() {
      _candidatePeaks = candidates.isEmpty
          // Fallback ai peak iconici se il dataset è vuoto / offline
          ? famousItalianPeaks
          : candidates;
      _lastCandidatePosition = pos;
    });
    debugPrint('[MountainFinder] candidate peaks aggiornate: '
        '${_candidatePeaks.length} entro ${_candidateRadiusKm}km');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_initializing)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (_error != null)
              _buildError(_error!)
            else if (_camera != null && _camera!.value.isInitialized)
              _buildCameraWithOverlay()
            else
              const SizedBox.shrink(),

            // HUD top
            _buildTopHUD(),

            // Card info in basso (X cime visibili)
            if (!_initializing && _error == null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _buildInfoCard(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraWithOverlay() {
    // LayoutBuilder fornisce le dimensioni reali del viewport e ricalcoliamo
    // la proiezione ogni volta che cambia (rotation, etc.).
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final pos = _userPosition;
        final heading = _heading;

        // Ricalcola sincrono con la dimensione corrente. L'output viene
        // applicato in setState dal sensor listener; qui semplicemente
        // ri-proiettiamo in tempo reale per ridurre latenza.
        final projected = (pos != null && heading != null)
            ? MountainProjection.projectAll(
                peaks: _candidatePeaks,
                observerLat: pos.latitude,
                observerLng: pos.longitude,
                observerAltitudeMeters: pos.altitude,
                phoneHeadingDeg: heading,
                phonePitchDeg: _pitchDeg,
                viewport: viewport,
                maxVisible: 5,
              )
            : <ProjectedPeak>[];

        // Riallinea il count per la info card al prossimo frame.
        if (projected.length != _visiblePeaks.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && projected.length != _visiblePeaks.length) {
              setState(() => _visiblePeaks = projected);
            }
          });
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview "fill" (nasconde le bande nere).
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _camera!.value.previewSize?.height ?? viewport.width,
                  height: _camera!.value.previewSize?.width ?? viewport.height,
                  child: CameraPreview(_camera!),
                ),
              ),
            ),

            // Reticolo centrale (mirino).
            const Center(
              child: _Crosshair(),
            ),

            // Pin AR per le cime visibili.
            for (final p in projected)
              Positioned(
                left: p.screenX - 80,
                top: p.screenY - 50,
                width: 160,
                height: 100,
                child: _PeakPin(projected: p, viewport: viewport),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTopHUD() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Row(
        children: [
          Material(
            color: Colors.black.withValues(alpha: 0.5),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: context.l10n.cancel,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.terrain, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.mfTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Bearing live + pitch (debug).
                  Text(
                    _heading != null
                        ? '${_heading!.toStringAsFixed(0)}° · ${_pitchDeg.toStringAsFixed(0)}°'
                        : '—°',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 56, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _initializing = true;
                  _error = null;
                });
                _bootstrap();
              },
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final count = _visiblePeaks.length;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.themedBorder),
      ),
      child: Row(
        children: [
          Icon(
            count > 0 ? Icons.check_circle : Icons.search,
            size: 18,
            color: count > 0 ? AppColors.success : context.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 0
                  ? context.l10n.mfNoPeaksInView
                  : context.l10n.mfPeaksInView(count),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ),
          if (_userPosition != null)
            Text(
              '${(_userPosition!.altitude).toStringAsFixed(0)} m',
              style: TextStyle(
                fontSize: 12,
                color: context.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

/// Mirino centrale per aiutare l'utente ad allineare lo sguardo.
class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: CustomPaint(
        painter: _CrosshairPainter(),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Cerchio sottile
    canvas.drawCircle(Offset(cx, cy), 18, paint);

    // 4 tick a croce
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(cx - 6, cy), Offset(cx + 6, cy), tick);
    canvas.drawLine(Offset(cx, cy - 6), Offset(cx, cy + 6), tick);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pin di una cima nel viewport AR.
class _PeakPin extends StatelessWidget {
  final ProjectedPeak projected;
  final Size viewport;

  const _PeakPin({required this.projected, required this.viewport});

  @override
  Widget build(BuildContext context) {
    final centered = projected.isCentered(viewport);
    final isVolcano = projected.peak.type == 'volcano';
    final accent =
        isVolcano ? AppColors.danger : (centered ? AppColors.warning : Colors.white);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Label compatta
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: centered ? 0.85 : 0.6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: accent.withValues(alpha: 0.7),
              width: centered ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                projected.peak.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: centered ? 13 : 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                _subtitle(projected),
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Pin punto + linea
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _subtitle(ProjectedPeak p) {
    final ele = p.peak.elevation;
    final dist = p.distanceMeters / 1000;
    final distStr =
        dist < 10 ? dist.toStringAsFixed(1) : dist.toStringAsFixed(0);
    if (ele == null) return '$distStr km';
    return '${ele.round()} m · $distStr km';
  }
}
