import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/mountain_finder_settings.dart';
import '../../../core/services/peaks_dataset_service.dart';
import '../../../core/services/pro_gate_service.dart';
import '../../../core/utils/mountain_photo_renderer.dart';
import '../../../core/utils/mountain_projection.dart';
import '../../../data/models/mountain_peak.dart';
import '../../widgets/app_snackbar.dart';
import 'mountain_finder_calibration_page.dart';
import 'mountain_photo_result_page.dart';

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

  // Smoothing low-pass adattivo: alpha basso (0.06) quando il telefono
  // e' fermo → pin "ancorati", stabili. Alpha alto (0.30) quando si
  // ruota rapidamente → pin reattivi. Lerp lineare in mezzo.
  static const double _alphaMin = 0.06;
  static const double _alphaMax = 0.30;
  static const double _rateForMaxAlpha = 30.0; // °/s per alpha max
  DateTime? _lastHeadingTime;
  DateTime? _lastPitchTime;
  double _lastRawPitch = 0;

  double _adaptiveAlpha(double ratePerSec) {
    final t = (ratePerSec / _rateForMaxAlpha).clamp(0.0, 1.0);
    return _alphaMin + t * (_alphaMax - _alphaMin);
  }

  List<ProjectedPeak> _visiblePeaks = const [];

  // Zoom camera: lo zoom effettivo cambia il FOV. A 2x zoom il FOV si
  // dimezza, quindi i pin vanno riposizionati di conseguenza.
  double _zoomLevel = 1.0;
  double _baseZoom = 1.0; // Snapshot allo start del pinch
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  /// Cime candidate (entro 60 km dalla posizione utente). Aggiornata quando
  /// la posizione si sposta significativamente. Tipicamente ~50-300 cime,
  /// quindi `projectAll` su questo subset è praticamente gratis.
  List<MountainPeak> _candidatePeaks = const [];

  /// Ultima posizione usata per calcolare le candidate. Quando l'utente si
  /// sposta più di 5 km ricomputiamo il subset (evitiamo lavoro inutile
  /// per piccoli aggiornamenti GPS).
  Position? _lastCandidatePosition;
  static const double _candidateRefreshThresholdMeters = 5000;

  /// True durante la cattura+annotazione foto (overlay loader).
  bool _processingCapture = false;

  @override
  void initState() {
    super.initState();
    // Il service e' un ChangeNotifier: ascoltiamo cosi i pin si
    // ri-proiettano in tempo reale durante la calibrazione.
    MountainFinderSettings().load();
    MountainFinderSettings().addListener(_onSettingsChanged);
    // Pro gate: serve a sapere se mostrare lo shutter sbloccato o
    // l'upsell paywall.
    ProGateService().load();
    ProGateService().addListener(_onProChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    MountainFinderSettings().removeListener(_onSettingsChanged);
    ProGateService().removeListener(_onProChanged);
    _positionSub?.cancel();
    _compassSub?.cancel();
    _accelSub?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  void _onProChanged() {
    if (mounted) setState(() {});
  }

  /// Settings precedenti per detection del cambio distanza (che richiede
  /// un re-fetch delle candidate, mentre il FOV no).
  double _lastSeenDistanceKm = MountainFinderSettings.defaultDistanceKm;

  void _onSettingsChanged() {
    if (!mounted) return;
    final newDist = MountainFinderSettings().maxDistanceKmValue;
    if ((newDist - _lastSeenDistanceKm).abs() > 0.5) {
      _lastSeenDistanceKm = newDist;
      // La distanza è cambiata: rifetcha le candidate dal dataset.
      final pos = _userPosition;
      if (pos != null) {
        _refreshCandidatePeaksIfNeeded(pos, force: true);
      }
    }
    setState(() {});
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

      // Zoom range: tipicamente 1x → 8/10x sui dispositivi moderni.
      try {
        _minZoom = await _camera!.getMinZoomLevel();
        _maxZoom = await _camera!.getMaxZoomLevel();
        // Cap pratico: oltre 6x la qualita' digitale e' troppo bassa.
        _maxZoom = _maxZoom.clamp(_minZoom, 6.0);
      } catch (_) {
        // Su alcuni device il plugin non espone questi metodi: lasciamo
        // i default (1.0, 1.0) che disabilitano il pinch-to-zoom.
      }

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

      // Compass: smoothing low-pass ADATTIVO. Quando il telefono e'
      // fermo i pin si "ancorano" alle cime (alpha basso = molto smooth);
      // quando ruoti rapidamente, i pin seguono senza lag (alpha alto).
      _compassSub = FlutterCompass.events?.listen((event) {
        if (!mounted) return;
        final raw = event.heading;
        if (raw == null) return;
        final normalized = raw < 0 ? raw + 360 : raw;
        final now = DateTime.now();
        final prev = _heading;
        if (prev == null) {
          _heading = normalized;
          _lastHeadingTime = now;
          setState(() {});
          return;
        }
        // Gestisci wraparound 359°→0°
        double delta = normalized - prev;
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        // Calcola la velocità angolare per alpha adattivo
        final dt = _lastHeadingTime == null
            ? 0.05
            : (now.difference(_lastHeadingTime!).inMilliseconds / 1000.0)
                .clamp(0.01, 0.5);
        final rate = (delta / dt).abs();
        final alpha = _adaptiveAlpha(rate);
        final smoothed = (prev + alpha * delta + 360) % 360;
        _lastHeadingTime = now;
        setState(() => _heading = smoothed);
      });

      // Accelerometer: pitch del telefono con smoothing adattivo.
      _accelSub = accelerometerEventStream().listen((event) {
        if (!mounted) return;
        final rawPitch = MountainProjection.pitchFromAccelerometer(
          event.x,
          event.y,
          event.z,
        );
        final now = DateTime.now();
        final dt = _lastPitchTime == null
            ? 0.05
            : (now.difference(_lastPitchTime!).inMilliseconds / 1000.0)
                .clamp(0.01, 0.5);
        final rate = ((rawPitch - _lastRawPitch) / dt).abs();
        final alpha = _adaptiveAlpha(rate);
        final smoothed = _pitchDeg + alpha * (rawPitch - _pitchDeg);
        _lastRawPitch = rawPitch;
        _lastPitchTime = now;
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

  /// Costruisce il layer dei pin AR con algoritmo anti-collisione: le
  /// label vengono impilate verticalmente quando le cime sono allineate
  /// sullo stesso bearing. Il "dot" resta sempre alla posizione reale
  /// della cima, una sottile linea connette label e dot quando sono
  /// distanziati.
  List<Widget> _buildPinLayer(List<ProjectedPeak> projected) {
    if (projected.isEmpty) return const [];

    final layouts = _layoutPins(projected);

    return [
      // Linee connettrici (sotto tutto, non assorbono tap).
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _PinLinesPainter(layouts),
          ),
        ),
      ),
      // Dot punto fisso alla posizione reale della cima.
      for (var i = 0; i < layouts.length; i++)
        AnimatedPositioned(
          key: ValueKey('dot_${layouts[i].peak.peak.id}'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          left: layouts[i].dotX - 6,
          top: layouts[i].dotY - 6,
          width: 12,
          height: 12,
          child: IgnorePointer(
            child: _PeakDot(
              isVolcano: layouts[i].peak.peak.type == 'volcano',
              isCentered: i == 0,
            ),
          ),
        ),
      // Label box (separabile dal dot, può essere offset verticalmente).
      for (var i = 0; i < layouts.length; i++)
        _AnimatedPeakLabel(
          key: ValueKey('label_${layouts[i].peak.peak.id}'),
          layout: layouts[i],
          rank: i,
          viewport: Size.zero, // viewport non più necessario per centratura
          isCentered: i == 0,
          onTap: () => _showPeakDetail(layouts[i].peak),
        ),
    ];
  }

  /// Algoritmo di layout: spinge verso l'alto le label che collidono
  /// con quelle già piazzate. Iterativo con safety counter per evitare
  /// loop infiniti su casi pathological.
  List<_PinLayout> _layoutPins(List<ProjectedPeak> peaks) {
    // Costanti di dimensione label coerenti con _AnimatedPeakLabel.
    const labelHalfWidth = 88.0; // metà larghezza label box (176/2)
    const labelHeight = 56.0; // altezza label box
    const gap = 6.0;
    const defaultLabelOffsetY = 42.0; // label centrata sopra il dot

    final placed = <_PinLayout>[];

    for (final p in peaks) {
      double labelY = p.screenY - defaultLabelOffsetY;
      bool collides = true;
      int safety = 0;
      while (collides && safety < 30) {
        collides = false;
        for (final pl in placed) {
          final dx = (p.screenX - pl.labelX).abs();
          final dy = (labelY - pl.labelY).abs();
          // Considera collisione se i centri label sono entro la
          // bounding box reciproca con un piccolo overlap minimo.
          if (dx < (labelHalfWidth * 2 - 30) && dy < labelHeight + gap) {
            // Spostamento verso l'alto
            labelY = pl.labelY - labelHeight - gap;
            collides = true;
            break;
          }
        }
        safety++;
      }

      placed.add(_PinLayout(
        peak: p,
        dotX: p.screenX,
        dotY: p.screenY,
        labelX: p.screenX,
        labelY: labelY,
      ));
    }

    return placed;
  }

  /// Apre un bottom sheet con i dettagli completi della cima toccata.
  /// In landscape l'altezza disponibile e' ridotta: usiamo
  /// `isScrollControlled` + scroll interno cosi il contenuto resta sempre
  /// raggiungibile.
  void _showPeakDetail(ProjectedPeak p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Limitiamo l'altezza max al 90% per lasciare visibile il backdrop.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      builder: (ctx) => _PeakDetailSheet(projected: p),
    );
  }

  /// Aggiorna [_candidatePeaks] interrogando il dataset OSM con la
  /// posizione data, ma solo se l'utente si è spostato più di
  /// [_candidateRefreshThresholdMeters] dall'ultimo aggiornamento.
  Future<void> _refreshCandidatePeaksIfNeeded(Position pos,
      {bool force = false}) async {
    final last = _lastCandidatePosition;
    if (!force && last != null) {
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
    final radius = MountainFinderSettings().maxDistanceKmValue;
    final candidates = ds.findWithinRadius(
      pos.latitude,
      pos.longitude,
      radiusKm: radius,
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
        '${_candidatePeaks.length} entro ${radius}km');
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
                bottom: 96,
                child: _buildInfoCard(),
              ),

            // Shutter button (Pro): cattura foto + annota cime + apre il
            // result page con preview e share. Sotto la card info.
            if (!_initializing && _error == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(child: _buildShutterButton()),
              ),

            // Loader durante il processing post-capture
            if (_processingCapture)
              Container(
                color: Colors.black.withValues(alpha: 0.6),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.mfPhotoProcessing,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Pulsante shutter Pro. Tap → cattura foto + projecta tutte le cime
  /// candidate sull'immagine + annota e apre la result page.
  Widget _buildShutterButton() {
    final isPro = ProGateService().isPro;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _processingCapture
            ? null
            : (isPro ? _capturePhoto : _showProUpsell),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
              if (!isPro)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFFD700),
                    ),
                    child: const Icon(Icons.lock,
                        size: 12, color: Colors.black),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Stub upsell paywall: per ora solo snackbar informativa, sarà
  /// sostituito dal vero PaywallSheet con 6.B4.
  void _showProUpsell() {
    AppSnackBar.info(context, context.l10n.mfPhotoProUpsell);
  }

  /// Cattura una foto e processa l'annotazione di TUTTE le cime
  /// candidate visibili nel cono FOV (nessun limite a 5 come in live).
  Future<void> _capturePhoto() async {
    final cam = _camera;
    final pos = _userPosition;
    final heading = _heading;
    if (cam == null || pos == null || heading == null) {
      AppSnackBar.error(context, context.l10n.mfPhotoNoSensors);
      return;
    }
    setState(() => _processingCapture = true);
    try {
      final settings = MountainFinderSettings();

      // Snapshot del viewport corrente per la math di proiezione.
      final mq = MediaQuery.of(context);
      final viewport = Size(
        mq.size.width,
        mq.size.height - mq.padding.top - mq.padding.bottom,
      );

      // FOV: orientation-aware (swap H/V in landscape, vedi note in
      // _buildCameraWithOverlay). Diviso per zoom per ridurre il cono.
      final isPortrait = viewport.height >= viewport.width;
      final calibH = settings.horizontalFovDeg;
      final calibV = settings.verticalFovDeg;
      final effHFov = (isPortrait ? calibH : calibV) / _zoomLevel;
      final effVFov = (isPortrait ? calibV : calibH) / _zoomLevel;

      // Tutti i peak nel cono FOV — niente cap come in live
      // (la differenza Free vs Pro!).
      final allVisible = MountainProjection.projectAll(
        peaks: _candidatePeaks,
        observerLat: pos.latitude,
        observerLng: pos.longitude,
        observerAltitudeMeters: pos.altitude,
        phoneHeadingDeg: heading,
        phonePitchDeg: _pitchDeg,
        viewport: viewport,
        maxVisible: 9999, // illimitato
        horizontalFovDeg: effHFov,
        verticalFovDeg: effVFov,
      );

      // Cattura
      final xfile = await cam.takePicture();
      final bytes = await xfile.readAsBytes();

      // Render annotato
      final annotated = await MountainPhotoRenderer.render(
        imageBytes: bytes,
        projected: allVisible,
        originalViewport: viewport,
      );

      if (!mounted) return;
      setState(() => _processingCapture = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MountainPhotoResultPage(
            annotatedImage: annotated,
            peaks: allVisible,
          ),
        ),
      );
    } catch (e, stack) {
      debugPrint('[MountainFinder] capture error: $e\n$stack');
      if (mounted) {
        setState(() => _processingCapture = false);
        AppSnackBar.error(
            context, context.l10n.errorWithDetails(e.toString()));
      }
    }
  }

  Widget _buildCameraWithOverlay() {
    // LayoutBuilder fornisce le dimensioni reali del viewport e ricalcoliamo
    // la proiezione ogni volta che cambia (rotation, etc.).
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final pos = _userPosition;
        final heading = _heading;

        // Ricalcola sincrono con la dimensione corrente.
        final settings = MountainFinderSettings();
        // FOV effettivo: la calibrazione H/V è fatta in portrait
        // (sensor long-axis verticale). In landscape il long-axis e'
        // orizzontale: H/V vanno scambiati per applicare correttamente
        // la math di proiezione allo schermo.
        final isPortrait = viewport.height >= viewport.width;
        final calibH = settings.horizontalFovDeg;
        final calibV = settings.verticalFovDeg;
        final effectiveHFov =
            (isPortrait ? calibH : calibV) / _zoomLevel;
        final effectiveVFov =
            (isPortrait ? calibV : calibH) / _zoomLevel;
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
                horizontalFovDeg: effectiveHFov,
                verticalFovDeg: effectiveVFov,
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
            // Camera preview "fill" (nasconde le bande nere). Avvolta in
            // GestureDetector per il pinch-to-zoom.
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: (_) {
                  _baseZoom = _zoomLevel;
                },
                onScaleUpdate: (details) {
                  if (_maxZoom <= _minZoom) return; // device senza zoom
                  final next = (_baseZoom * details.scale)
                      .clamp(_minZoom, _maxZoom);
                  if ((next - _zoomLevel).abs() < 0.02) return;
                  _zoomLevel = next;
                  _camera?.setZoomLevel(next);
                  setState(() {});
                },
                onDoubleTap: () {
                  // Doppio tap: toggle 1x / 2x rapido
                  final target = _zoomLevel > 1.5
                      ? _minZoom
                      : (2.0).clamp(_minZoom, _maxZoom);
                  _zoomLevel = target;
                  _camera?.setZoomLevel(target);
                  setState(() {});
                },
                child: _buildCameraPreviewBox(viewport),
              ),
            ),

            // Reticolo centrale (mirino).
            const Center(
              child: _Crosshair(),
            ),

            // Pin AR: layout anti-collisione + linee connettrici + label
            // animate. Le label si impilano verticalmente quando le cime
            // sono allineate sullo stesso bearing per evitare overlap.
            ..._buildPinLayer(projected),

            // Indicatore zoom: visibile solo quando zoom > 1.05x.
            if (_zoomLevel > 1.05)
              Positioned(
                top: 70,
                left: 0,
                right: 0,
                child: Center(child: _ZoomChip(
                  level: _zoomLevel,
                  onReset: () {
                    _zoomLevel = _minZoom;
                    _camera?.setZoomLevel(_minZoom);
                    setState(() {});
                  },
                )),
              ),
          ],
        );
      },
    );
  }

  /// Camera preview con BoxFit.cover **orientation-aware**.
  ///
  /// Il buffer della camera è sempre nella sua orientazione native
  /// (tipicamente landscape: width > height). In **portrait** ruotiamo
  /// il box swappando width/height. In **landscape** lo lasciamo
  /// nativo. Senza questo check la preview in landscape veniva
  /// schiacciata orizzontalmente.
  Widget _buildCameraPreviewBox(Size viewport) {
    final ps = _camera!.value.previewSize;
    final bufW = ps?.width ?? viewport.width;
    final bufH = ps?.height ?? viewport.height;
    final isPortrait = viewport.height >= viewport.width;
    final boxW = isPortrait ? bufH : bufW;
    final boxH = isPortrait ? bufW : bufH;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: boxW,
        height: boxH,
        child: CameraPreview(_camera!),
      ),
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
          const SizedBox(width: 8),
          // Gear: apre la pagina di calibrazione FOV.
          // Filtro distanza
          Material(
            color: Colors.black.withValues(alpha: 0.5),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: _showDistanceFilterSheet,
              icon: const Icon(Icons.straighten, color: Colors.white),
              tooltip: context.l10n.mfDistanceFilterTitle,
            ),
          ),
          const SizedBox(width: 4),
          // Calibrazione FOV
          Material(
            color: Colors.black.withValues(alpha: 0.5),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MountainFinderCalibrationPage(),
                  ),
                );
              },
              icon: const Icon(Icons.tune, color: Colors.white),
              tooltip: context.l10n.mfCalibrationTitle,
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet con slider e preset chips per filtrare le cime
  /// per distanza dal punto di osservazione.
  void _showDistanceFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _DistanceFilterSheet(),
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
/// Pin animato di una cima nel viewport AR.
///
/// Animazioni:
/// - **AnimatedPositioned** smooth movement quando l'utente ruota il
///   telefono (200ms easeOut).
/// - **AnimatedScale** in base al ranking di centratura: la cima più
///   centrata è grande (1.0), le secondarie scalano fino a 0.78.
/// - **AnimatedOpacity**: la cima centrata è completamente opaca,
///   le altre sono leggermente trasparenti (focus visivo).
/// - **Highlight gold** quando il pin è entro il 10% dal centro
///   (utente sta puntando bene).
/// Risultato dell'algoritmo di layout anti-collisione: dot sempre alla
/// posizione reale della cima, label eventualmente offset verticalmente.
class _PinLayout {
  final ProjectedPeak peak;
  final double dotX;
  final double dotY;
  final double labelX; // X centro label
  final double labelY; // Y centro label
  const _PinLayout({
    required this.peak,
    required this.dotX,
    required this.dotY,
    required this.labelX,
    required this.labelY,
  });
}

/// Painter delle linee connettrici label↔dot. Disegnata sotto le label
/// con IgnorePointer così non intercetta tap.
class _PinLinesPainter extends CustomPainter {
  final List<_PinLayout> layouts;

  _PinLinesPainter(this.layouts);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final l in layouts) {
      // Salta linea se label e dot sono allineati (no offset).
      if ((l.labelY - l.dotY).abs() < 30) continue;
      final from = Offset(l.labelX, l.labelY + 18); // bottom della label
      final to = Offset(l.dotX, l.dotY - 5); // top del dot
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PinLinesPainter oldDelegate) =>
      oldDelegate.layouts != layouts;
}

/// Solo il dot della cima — sempre alla posizione reale, mai spostato.
class _PeakDot extends StatelessWidget {
  final bool isVolcano;
  final bool isCentered;

  const _PeakDot({required this.isVolcano, required this.isCentered});

  @override
  Widget build(BuildContext context) {
    final color = isVolcano
        ? AppColors.danger
        : (isCentered ? AppColors.warning : Colors.white);
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
          ),
          if (isCentered)
            BoxShadow(
              color: color.withValues(alpha: 0.5),
              blurRadius: 8,
              spreadRadius: 1,
            ),
        ],
      ),
    );
  }
}

/// Label box animata della cima con tap → bottom sheet dettagli.
/// Spostabile verticalmente dall'algoritmo anti-collisione.
class _AnimatedPeakLabel extends StatelessWidget {
  final _PinLayout layout;
  final int rank;
  final Size viewport;
  final bool isCentered;
  final VoidCallback onTap;

  const _AnimatedPeakLabel({
    super.key,
    required this.layout,
    required this.rank,
    required this.viewport,
    required this.isCentered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = rank == 0 ? 1.0 : (1.0 - rank * 0.07).clamp(0.78, 1.0);
    final opacity = rank == 0 ? 1.0 : (1.0 - rank * 0.06).clamp(0.74, 1.0);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      left: layout.labelX - 88,
      top: layout.labelY - 28, // centratura sulla labelY (height/2)
      width: 176,
      height: 56,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        scale: scale,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: opacity,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: _LabelBox(
              projected: layout.peak,
              isCentered: isCentered,
            ),
          ),
        ),
      ),
    );
  }
}

class _LabelBox extends StatelessWidget {
  final ProjectedPeak projected;
  final bool isCentered;

  const _LabelBox({required this.projected, required this.isCentered});

  @override
  Widget build(BuildContext context) {
    final isVolcano = projected.peak.type == 'volcano';
    final accent = isVolcano
        ? AppColors.danger
        : (isCentered ? AppColors.warning : Colors.white);

    return Center(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: isCentered ? 0.85 : 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: accent.withValues(alpha: 0.7),
            width: isCentered ? 1.5 : 1,
          ),
          boxShadow: isCentered
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
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
                fontSize: isCentered ? 15 : 14,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              _subtitle(projected),
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
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

/// Bottom sheet con i dettagli completi di una cima toccata nel viewfinder.
class _PeakDetailSheet extends StatelessWidget {
  final ProjectedPeak projected;

  const _PeakDetailSheet({required this.projected});

  @override
  Widget build(BuildContext context) {
    final p = projected.peak;
    final isVolcano = p.type == 'volcano';
    final accent = isVolcano ? AppColors.danger : AppColors.primary;

    return SingleChildScrollView(
      // Padding bottom dinamico per IME / safe-area in landscape.
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Drag handle
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
            const SizedBox(height: 16),
            // Header con icona e nome
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isVolcano
                        ? Icons.local_fire_department
                        : Icons.terrain,
                    color: accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (p.region != null && p.region!.isNotEmpty)
                        Text(
                          p.region!,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Stats grid
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.height,
                    label: context.l10n.mfDetailElevation,
                    value: p.elevation == null
                        ? '—'
                        : '${p.elevation!.round()}',
                    unit: 'm',
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    icon: Icons.straighten,
                    label: context.l10n.mfDetailDistance,
                    value:
                        (projected.distanceMeters / 1000) < 10
                            ? (projected.distanceMeters / 1000)
                                .toStringAsFixed(1)
                            : (projected.distanceMeters / 1000)
                                .toStringAsFixed(0),
                    unit: 'km',
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    icon: Icons.explore,
                    label: context.l10n.mfDetailBearing,
                    value: projected.bearingDeg.toStringAsFixed(0),
                    unit: '°',
                    color: const Color(0xFF6D4C41),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Coordinate
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.pin_drop_outlined,
                      size: 16, color: context.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                        fontFeatures:
                            const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Pulsante OSM
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openOsm(p, context),
                icon: const Icon(Icons.public),
                label: Text(context.l10n.mfDetailOpenOsm),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: accent.withValues(alpha: 0.5)),
                  foregroundColor: accent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                context.l10n.mfDetailDataSource,
                style: TextStyle(
                  fontSize: 10,
                  color: context.textMuted,
                ),
              ),
            ),
          ],
        ),
    );
  }

  Future<void> _openOsm(MountainPeak peak, BuildContext context) async {
    final url = Uri.parse(
      'https://www.openstreetmap.org/?mlat=${peak.latitude}&mlon=${peak.longitude}#map=14/${peak.latitude}/${peak.longitude}',
    );
    try {
      // externalApplication non richiede canLaunchUrl, lancia direttamente
      // un Intent VIEW: gestito sia da browser che da app OSM-compatibili.
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.mfDetailOpenError)),
        );
      }
    } catch (e) {
      debugPrint('[MountainFinder] _openOsm error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.mfDetailOpenError)),
        );
      }
    }
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: context.textMuted,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}


/// Chip che mostra lo zoom corrente. Tap per resettare a 1x.
class _ZoomChip extends StatelessWidget {
  final double level;
  final VoidCallback onReset;

  const _ZoomChip({required this.level, required this.onReset});

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

/// Bottom sheet per regolare la distanza massima delle cime mostrate.
/// Pensata per ridurre il numero di pin nel viewfinder quando si è in
/// zone dense (es. Alpi) o aumentarlo per orizzonti lontani (es. mare).
class _DistanceFilterSheet extends StatefulWidget {
  const _DistanceFilterSheet();

  @override
  State<_DistanceFilterSheet> createState() => _DistanceFilterSheetState();
}

class _DistanceFilterSheetState extends State<_DistanceFilterSheet> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = MountainFinderSettings().maxDistanceKmValue;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
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
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.straighten,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.mfDistanceFilterTitle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.mfDistanceFilterHelp,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Valore corrente
            Center(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: _value.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: ' km',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Slider
            Slider(
              value: _value.clamp(
                MountainFinderSettings.minDistanceKm,
                MountainFinderSettings.maxDistanceKm,
              ),
              min: MountainFinderSettings.minDistanceKm,
              max: MountainFinderSettings.maxDistanceKm,
              divisions: (MountainFinderSettings.maxDistanceKm -
                      MountainFinderSettings.minDistanceKm)
                  .toInt(),
              activeColor: AppColors.primary,
              onChanged: (v) {
                setState(() => _value = v);
                MountainFinderSettings().setMaxDistanceKm(v);
              },
            ),
            const SizedBox(height: 8),
            // Preset chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset
                    in MountainFinderSettings.distancePresetsKm)
                  ChoiceChip(
                    label: Text('${preset.toInt()} km'),
                    selected: (_value - preset).abs() < 0.5,
                    onSelected: (_) {
                      setState(() => _value = preset);
                      MountainFinderSettings().setMaxDistanceKm(preset);
                    },
                    selectedColor:
                        AppColors.primary.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      fontWeight: (_value - preset).abs() < 0.5
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: (_value - preset).abs() < 0.5
                          ? AppColors.primary
                          : context.textPrimary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
