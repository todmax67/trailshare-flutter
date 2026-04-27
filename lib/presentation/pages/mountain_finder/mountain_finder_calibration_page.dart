import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/mountain_finder_settings.dart';
import '../../../core/services/peaks_dataset_service.dart';
import '../../../core/utils/mountain_projection.dart';
import '../../../data/models/mountain_peak.dart';

/// Pagina di calibrazione del FOV (Field Of View) della camera per
/// allineare i pin AR alla scena reale.
///
/// L'utente vede:
/// - Preview camera live con tutti i pin candidati nelle vicinanze
///   (fino a 8) per avere riferimenti multipli
/// - Due slider in basso: **FOV orizzontale** e **FOV verticale**
/// - Live update: muovendo gli slider i pin si riposizionano
///   istantaneamente sul viewfinder
/// - Pulsante "Predefinito" che riporta ai valori standard 60°/80°
///
/// Workflow consigliato:
/// 1. Punta verso una cima nota (es. cima dietro casa)
/// 2. Regola **FOV orizzontale** finché il pin si centra esattamente
///    sul picco reale
/// 3. Inclina su/giù: regola **FOV verticale** finché il pin segue
///    la cima quando muovi il telefono in alto/basso
class MountainFinderCalibrationPage extends StatefulWidget {
  const MountainFinderCalibrationPage({super.key});

  @override
  State<MountainFinderCalibrationPage> createState() =>
      _MountainFinderCalibrationPageState();
}

class _MountainFinderCalibrationPageState
    extends State<MountainFinderCalibrationPage> {
  CameraController? _camera;
  bool _initializing = true;
  String? _error;

  Position? _userPosition;
  double? _heading;
  double _pitchDeg = 0;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  static const double _alpha = 0.18;
  static const double _candidateRadiusKm = 60;

  // Zoom (replica di MountainFinderPage per fine-tuning anche in calibrazione)
  double _zoomLevel = 1.0;
  double _baseZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  List<MountainPeak> _candidatePeaks = const [];

  @override
  void initState() {
    super.initState();
    MountainFinderSettings().load();
    MountainFinderSettings().addListener(_onSettingsChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    MountainFinderSettings().removeListener(_onSettingsChanged);
    _positionSub?.cancel();
    _compassSub?.cancel();
    _accelSub?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    try {
      unawaited(PeaksDatasetService().ensureLoaded());

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
      );
      await _camera!.initialize();

      try {
        _minZoom = await _camera!.getMinZoomLevel();
        _maxZoom = await _camera!.getMaxZoomLevel();
        _maxZoom = _maxZoom.clamp(_minZoom, 6.0);
      } catch (_) {}

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
        await _refreshCandidates(pos);
      });

      if (_userPosition != null) {
        await _refreshCandidates(_userPosition!);
      }

      _compassSub = FlutterCompass.events?.listen((event) {
        if (!mounted) return;
        final raw = event.heading;
        if (raw == null) return;
        final normalized = raw < 0 ? raw + 360 : raw;
        final prev = _heading;
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

  Future<void> _refreshCandidates(Position pos) async {
    final ds = PeaksDatasetService();
    if (!ds.isLoaded) await ds.ensureLoaded();
    final cands = ds.findWithinRadius(
      pos.latitude,
      pos.longitude,
      radiusKm: _candidateRadiusKm,
    );
    if (!mounted) return;
    setState(() => _candidatePeaks = cands);
  }

  @override
  Widget build(BuildContext context) {
    final settings = MountainFinderSettings();

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
              _buildCameraOverlay(settings),

            _buildTopBar(),

            // Pannello calibrazione in basso
            if (!_initializing && _error == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildCalibrationPanel(settings),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraOverlay(MountainFinderSettings settings) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final pos = _userPosition;
        final heading = _heading;

        // FOV effettivo = FOV calibrato / zoom level. Stesso accorgimento
        // della MountainFinderPage cosi i pin restano coerenti durante lo
        // zoom anche in calibrazione.
        final effectiveHFov = settings.horizontalFovDeg / _zoomLevel;
        final effectiveVFov = settings.verticalFovDeg / _zoomLevel;

        // Mostriamo fino a 8 pin (più del normale 5) così l'utente ha
        // riferimenti multipli per giudicare l'allineamento.
        final projected = (pos != null && heading != null)
            ? MountainProjection.projectAll(
                peaks: _candidatePeaks,
                observerLat: pos.latitude,
                observerLng: pos.longitude,
                observerAltitudeMeters: pos.altitude,
                phoneHeadingDeg: heading,
                phonePitchDeg: _pitchDeg,
                viewport: viewport,
                maxVisible: 8,
                horizontalFovDeg: effectiveHFov,
                verticalFovDeg: effectiveVFov,
              )
            : <ProjectedPeak>[];

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: (_) {
                  _baseZoom = _zoomLevel;
                },
                onScaleUpdate: (details) {
                  if (_maxZoom <= _minZoom) return;
                  final next = (_baseZoom * details.scale)
                      .clamp(_minZoom, _maxZoom);
                  if ((next - _zoomLevel).abs() < 0.02) return;
                  _zoomLevel = next;
                  _camera?.setZoomLevel(next);
                  setState(() {});
                },
                onDoubleTap: () {
                  final target = _zoomLevel > 1.5
                      ? _minZoom
                      : (2.0).clamp(_minZoom, _maxZoom);
                  _zoomLevel = target;
                  _camera?.setZoomLevel(target);
                  setState(() {});
                },
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _camera!.value.previewSize?.height ??
                        viewport.width,
                    height: _camera!.value.previewSize?.width ??
                        viewport.height,
                    child: CameraPreview(_camera!),
                  ),
                ),
              ),
            ),
            // Reticolo centrale
            Center(
              child: SizedBox(
                width: 80,
                height: 80,
                child: CustomPaint(
                  painter: _CalibrationCrosshairPainter(),
                ),
              ),
            ),
            // Pin "lite" (solo dot + nome corto)
            for (final p in projected)
              Positioned(
                left: p.screenX - 60,
                top: p.screenY - 16,
                width: 120,
                height: 32,
                child: IgnorePointer(
                  child: _CalibrationPin(projected: p),
                ),
              ),
            // Indicatore zoom (visibile solo > 1.05x)
            if (_zoomLevel > 1.05)
              Positioned(
                top: 70,
                left: 0,
                right: 0,
                child: Center(
                  child: _CalibZoomChip(
                    level: _zoomLevel,
                    onReset: () {
                      _zoomLevel = _minZoom;
                      _camera?.setZoomLevel(_minZoom);
                      setState(() {});
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar() {
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
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: context.l10n.cancel,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.mfCalibrationTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
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
        child: Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildCalibrationPanel(MountainFinderSettings settings) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.themedBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.tune, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.mfCalibrationHelp,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Slider FOV orizzontale
          _FovSlider(
            label: context.l10n.mfCalibrationHorizontalFov,
            value: settings.horizontalFovDeg,
            min: MountainFinderSettings.minHFov,
            max: MountainFinderSettings.maxHFov,
            onChanged: (v) => settings.setHorizontalFov(v),
          ),
          const SizedBox(height: 8),
          // Slider FOV verticale
          _FovSlider(
            label: context.l10n.mfCalibrationVerticalFov,
            value: settings.verticalFovDeg,
            min: MountainFinderSettings.minVFov,
            max: MountainFinderSettings.maxVFov,
            onChanged: (v) => settings.setVerticalFov(v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => settings.reset(),
                icon: const Icon(Icons.restore, size: 18),
                label: Text(context.l10n.mfCalibrationReset),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: Text(context.l10n.mfCalibrationDone),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FovSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _FovSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ),
            Text(
              '${value.toStringAsFixed(1)}°',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) * 2).round(), // mezzo grado per step
          onChanged: onChanged,
          activeColor: AppColors.primary,
        ),
      ],
    );
  }
}

class _CalibrationCrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Cerchio centrale
    canvas.drawCircle(Offset(cx, cy), 24, paint);
    // Tick croce
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(cx - 10, cy), Offset(cx - 4, cy), tick);
    canvas.drawLine(Offset(cx + 4, cy), Offset(cx + 10, cy), tick);
    canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy - 4), tick);
    canvas.drawLine(Offset(cx, cy + 4), Offset(cx, cy + 10), tick);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pin compatto usato in calibrazione: meno informazione, più leggibile
/// per giudicare allineamento con la cima reale.
class _CalibrationPin extends StatelessWidget {
  final ProjectedPeak projected;

  const _CalibrationPin({required this.projected});

  @override
  Widget build(BuildContext context) {
    final isVolcano = projected.peak.type == 'volcano';
    final color = isVolcano ? AppColors.danger : Colors.amber;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                projected.peak.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip indicatore zoom nella pagina di calibrazione.
class _CalibZoomChip extends StatelessWidget {
  final double level;
  final VoidCallback onReset;

  const _CalibZoomChip({required this.level, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onReset,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.zoom_in, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text(
                '${level.toStringAsFixed(1)}x',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.close,
                color: Colors.white.withValues(alpha: 0.6),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
