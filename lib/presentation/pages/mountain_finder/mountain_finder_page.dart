import 'dart:async';
import 'dart:math' as math;

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
import '../../../core/services/viewshed_service.dart';
import '../../../core/utils/mountain_photo_renderer.dart';
import '../../../core/utils/mountain_projection.dart';
import '../../../data/models/mountain_peak.dart';
import '../../../data/models/osm_poi.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/osm_pois_repository.dart';
import '../../../data/repositories/saved_peaks_repository.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/paywall_sheet.dart';
import 'mountain_finder_calibration_page.dart';
import 'mountain_photo_result_page.dart';
import 'peak_map_page.dart';

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

  /// POI OSM candidati nello stesso raggio dei peak. Usati nell'AR
  /// Photo Mode v2 per overlayare rifugi/sorgenti/etc oltre alle cime.
  List<OsmPoi> _candidatePois = const [];

  /// Ultima posizione usata per calcolare le candidate. Quando l'utente si
  /// sposta più di 5 km ricomputiamo il subset (evitiamo lavoro inutile
  /// per piccoli aggiornamenti GPS).
  Position? _lastCandidatePosition;
  static const double _candidateRefreshThresholdMeters = 5000;

  /// Cap di etichette mostrate live nel viewfinder. Prima era 5 (solo le più
  /// centrate → effetto "riconosce solo il centro"). Col viewshed attivo la
  /// lista effettiva è già filtrata alle cime realmente visibili (≤10 free),
  /// quindi un cap alto mostra tutte le cime su tutta la larghezza schermo
  /// senza affollare. Limite di sicurezza per zone densissime / viewshed off.
  static const int _maxLiveLabels = 30;

  /// True durante la cattura+annotazione foto (overlay loader).
  bool _processingCapture = false;

  /// AR lock: quando true, ignoriamo i sensori e congeliamo la
  /// proiezione corrente per permettere all'utente di leggere le
  /// label senza muoversi. Toggle dall'icona lock nell'HUD.
  bool _arLocked = false;

  // ── Viewshed filter (default ON, esteso con Pro) ────────────────────
  /// Quando true, mostriamo solo le cime effettivamente visibili dalla
  /// posizione utente (occlusione da crinali calcolata su DEM). È il
  /// comportamento DI DEFAULT: senza, il finder elencava tutte le cime
  /// entro il raggio anche se nascoste dietro un monte. Free: raggio 20km,
  /// max 10 cime. Pro: 100km, illimitato, disk-cache. L'utente può
  /// disattivarlo dall'icona occhio per rivedere tutte le cime nel cono.
  bool _viewshedOnly = true;
  /// Set di peak.id che il viewshed considera visibili. Vuoto = nessun filtro.
  Set<String> _viewshedVisibleIds = const {};
  /// Loading flag mentre gira il compute viewshed.
  bool _computingViewshed = false;
  /// Posizione usata per l'ultimo compute (per invalidare > 500m).
  Position? _lastViewshedPosition;

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
        if (!mounted || _arLocked) return;
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
        if (!mounted || _arLocked) return;
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

    // La cima più centrata è la prima della lista (projectAll ordina per
    // centratura): la evidenziamo (colore + dimensione) ovunque finisca
    // dopo il re-ordinamento per X del layout.
    final centeredId = projected.first.peak.id;
    final layouts = _layoutPins(projected);

    return [
      // Steli connettori dot → ancoraggio etichetta (sotto tutto, no tap).
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _PinLinesPainter(layouts),
          ),
        ),
      ),
      // Dot punto fisso alla posizione reale della cima.
      for (final l in layouts)
        AnimatedPositioned(
          key: ValueKey('dot_${l.peak.peak.id}'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          left: l.dotX - 5,
          top: l.dotY - 5,
          width: 10,
          height: 10,
          child: IgnorePointer(
            child: _PeakDot(
              isVolcano: l.peak.peak.type == 'volcano',
              isCentered: l.peak.peak.id == centeredId,
            ),
          ),
        ),
      // Etichette diagonali (stile PeakFinder): testo ruotato che sale
      // verso destra dall'ancoraggio dello stelo.
      for (final l in layouts)
        _DiagonalPeakLabel(
          key: ValueKey('label_${l.peak.peak.id}'),
          layout: l,
          isCentered: l.peak.peak.id == centeredId,
          onTap: () => _showPeakDetail(l.peak),
        ),
    ];
  }

  /// Layout etichette diagonali stile PeakFinder.
  ///
  /// Ogni cima ha un dot alla posizione reale e uno **stelo verticale** che
  /// sale fino a un ancoraggio; dall'ancoraggio il nome è scritto in
  /// diagonale (verso l'alto-destra). Per evitare sovrapposizioni quando
  /// più cime sono vicine in orizzontale, allunghiamo lo stelo (stagger):
  /// le cime vicine in X ricevono ancoraggi a quote diverse, così i testi
  /// diagonali non si calpestano.
  List<_PinLayout> _layoutPins(List<ProjectedPeak> peaks) {
    const baseStem = 26.0; // lunghezza stelo minima (px sopra il dot)
    const stemStep = 30.0; // incremento per separare cime vicine
    const minDx = 52.0; // distanza X sotto la quale due ancoraggi collidono
    const maxStem = 280.0; // tetto di sicurezza

    // Ordina sinistra→destra per una lettura stabile e per dare priorità di
    // "stelo corto" alle cime già piazzate a sinistra.
    final sorted = [...peaks]..sort((a, b) => a.screenX.compareTo(b.screenX));

    final placed = <_PinLayout>[];
    for (final p in sorted) {
      double stem = baseStem;
      bool collides = true;
      int safety = 0;
      while (collides && safety < 40) {
        collides = false;
        final anchorY = p.screenY - stem;
        for (final pl in placed) {
          if ((p.screenX - pl.dotX).abs() < minDx &&
              (anchorY - pl.labelY).abs() < stemStep - 4) {
            stem += stemStep;
            if (stem > maxStem) {
              collides = false;
              break;
            }
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
        labelY: p.screenY - stem,
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

    // Carica anche i POI OSM nello stesso raggio (rifugi, sorgenti,
    // ecc.). Lazy: l'asset viene parsato la prima volta che lo serve.
    final osmRepo = OsmPoisRepository();
    if (!osmRepo.isLoaded) {
      await osmRepo.ensureLoaded();
    }
    final osmCandidates = osmRepo.findNearby(
      pos.latitude,
      pos.longitude,
      radiusMeters: radius * 1000,
    );

    if (!mounted) return;
    setState(() {
      _candidatePois = osmCandidates;
      _candidatePeaks = candidates.isEmpty
          // Fallback ai peak iconici se il dataset è vuoto / offline
          ? famousItalianPeaks
          : candidates;
      _lastCandidatePosition = pos;
    });
    debugPrint('[MountainFinder] candidate peaks aggiornate: '
        '${_candidatePeaks.length} entro ${radius}km');

    // Viewshed ON di default: ricalcola le cime visibili ad ogni refresh
    // delle candidate (ogni ~5km di spostamento), per tutti gli utenti. Il
    // tier (raggio/limite cime) resta differenziato Free vs Pro dentro
    // _recomputeViewshedIfNeeded. Pro aggiunge raggio 100km e nessun cap.
    if (_viewshedOnly) {
      unawaited(_recomputeViewshedIfNeeded(pos, force: true));
    }
  }

  /// (Re)compute viewshed se posizione è cambiata > 500m o force=true.
  Future<void> _recomputeViewshedIfNeeded(Position pos, {bool force = false}) async {
    if (!force && _lastViewshedPosition != null) {
      final moved = Geolocator.distanceBetween(
        _lastViewshedPosition!.latitude, _lastViewshedPosition!.longitude,
        pos.latitude, pos.longitude,
      );
      if (moved < 500) return;
    }
    if (_computingViewshed) return; // già in corso, evita race
    if (_candidatePeaks.isEmpty) return;

    // Pro tier sbloccato da: subscription IAP attiva OPPURE admin (per
    // permettere test in development senza acquisto).
    final isPro = ProGateService().isPro;
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    final tier = (isPro || isAdmin) ? ViewshedTier.pro : ViewshedTier.free;

    setState(() => _computingViewshed = true);
    try {
      final result = await ViewshedService().computeVisible(
        observerLat: pos.latitude,
        observerLng: pos.longitude,
        candidates: _candidatePeaks,
        tier: tier,
      );
      if (!mounted) return;
      setState(() {
        _viewshedVisibleIds = result.visible.map((v) => v.peak.id).toSet();
        _lastViewshedPosition = pos;
        _computingViewshed = false;
      });
      debugPrint(
          '[MountainFinder] viewshed: ${result.visible.length} cime visibili '
          '(tier=${tier.label}, ${result.elapsedMs}ms)');
    } catch (e) {
      debugPrint('[MountainFinder] viewshed error: $e');
      if (mounted) setState(() => _computingViewshed = false);
    }
  }

  /// Toggle del filtro "solo cime visibili". Triggera compute la prima volta.
  Future<void> _toggleViewshed() async {
    final pos = _userPosition;
    if (pos == null) {
      AppSnackBar.info(context, context.l10n.locationTimeout);
      return;
    }
    final wantOn = !_viewshedOnly;
    setState(() {
      _viewshedOnly = wantOn;
      if (!wantOn) {
        _viewshedVisibleIds = const {};
        _lastViewshedPosition = null;
      }
    });
    if (wantOn) {
      await _recomputeViewshedIfNeeded(pos, force: true);
    }
  }

  /// Lista cime effettiva considerando il filtro viewshed.
  List<MountainPeak> get _effectiveCandidatePeaks {
    if (!_viewshedOnly || _viewshedVisibleIds.isEmpty) return _candidatePeaks;
    return _candidatePeaks
        .where((p) => _viewshedVisibleIds.contains(p.id))
        .toList();
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

            // Card info + shutter: layout orientation-aware. In portrait
            // sono entrambi sotto, in landscape vanno sul lato destro
            // (info card sopra, shutter sotto) per non rubare spazio
            // verticale alla preview camera.
            if (!_initializing && _error == null)
              ..._buildBottomControls(),

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

  /// Layout dei controlli inferiori (info card + shutter button) con
  /// supporto orientation-aware: in **portrait** entrambi al centro
  /// in basso (classico camera UI). In **landscape** spostati a destra,
  /// info card in alto/centro, shutter sotto, allineati lateralmente
  /// per non rubare spazio verticale alla preview.
  List<Widget> _buildBottomControls() {
    final mq = MediaQuery.of(context);
    final isPortrait = mq.size.height >= mq.size.width;

    if (isPortrait) {
      return [
        // Info card full-width sopra lo shutter
        Positioned(
          left: 12,
          right: 12,
          bottom: 96,
          child: _buildInfoCard(),
        ),
        // Shutter centrato in basso
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: Center(child: _buildShutterButton()),
        ),
      ];
    }

    // Landscape: layout sulla colonna destra. La preview ha tutta
    // l'altezza disponibile. Right column larga ~200px.
    return [
      Positioned(
        right: 12,
        top: 70, // sotto al top HUD
        width: 200,
        child: _buildInfoCard(),
      ),
      Positioned(
        right: 16,
        bottom: 0,
        top: 0,
        child: Center(child: _buildShutterButton()),
      ),
    ];
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
    // Dead-end fix: invece di mostrare uno snackbar info che lascia
    // l'utente nel limbo, apriamo la PaywallSheet con trigger dedicato.
    // È il momento di massimo intent: l'utente ha appena toccato lo
    // shutter — è ora di proporre l'acquisto.
    showPaywallSheet(context, trigger: PaywallTrigger.photoModePro);
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
        peaks: _effectiveCandidatePeaks,
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

      // 6.A2 v2: anche i POI OSM (rifugi, sorgenti, ecc.) nel cono FOV.
      // Stesso math, modello diverso. Cap a 12 visualizzati per non
      // sovrastare le cime (gestito dal renderer).
      final visiblePois = MountainProjection.projectAllPois(
        pois: _candidatePois,
        observerLat: pos.latitude,
        observerLng: pos.longitude,
        observerAltitudeMeters: pos.altitude,
        phoneHeadingDeg: heading,
        phonePitchDeg: _pitchDeg,
        viewport: viewport,
        maxVisible: 12,
        horizontalFovDeg: effHFov,
        verticalFovDeg: effVFov,
      );

      // Cattura
      final xfile = await cam.takePicture();
      final bytes = await xfile.readAsBytes();

      // Render annotato — peak + POI con stili distinti
      final annotated = await MountainPhotoRenderer.render(
        imageBytes: bytes,
        projected: allVisible,
        pois: visiblePois,
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
            pois: visiblePois,
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
                peaks: _effectiveCandidatePeaks,
                observerLat: pos.latitude,
                observerLng: pos.longitude,
                observerAltitudeMeters: pos.altitude,
                phoneHeadingDeg: heading,
                phonePitchDeg: _pitchDeg,
                viewport: viewport,
                maxVisible: _maxLiveLabels,
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
                  // Bearing live + pitch (debug) prima del titolo così rimane
                  // sempre visibile; il titolo si elide se manca spazio.
                  Text(
                    _heading != null
                        ? '${_heading!.toStringAsFixed(0)}°'
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
          // Viewshed filter: mostra solo cime non occluse da crinali.
          // Free 20km/10 cime, Pro 100km/illimitato.
          Material(
            color: _viewshedOnly
                ? AppColors.success
                : Colors.black.withValues(alpha: 0.5),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: _computingViewshed ? null : _toggleViewshed,
              icon: _computingViewshed
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      _viewshedOnly ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white,
                    ),
              tooltip: _viewshedOnly
                  ? context.l10n.mfViewshedOnTooltip
                  : context.l10n.mfViewshedOffTooltip,
            ),
          ),
          const SizedBox(width: 4),
          // AR lock: congela il puntamento per leggere le label.
          Material(
            color: _arLocked
                ? AppColors.warning
                : Colors.black.withValues(alpha: 0.5),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () => setState(() => _arLocked = !_arLocked),
              icon: Icon(
                _arLocked ? Icons.lock : Icons.lock_open,
                color: Colors.white,
              ),
              tooltip: _arLocked
                  ? context.l10n.mfArUnlock
                  : context.l10n.mfArLock,
            ),
          ),
          const SizedBox(width: 4),
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
      // isScrollControlled + SingleChildScrollView interno permettono
      // al sheet di estendersi oltre il 50% dell'altezza in landscape
      // (dove altrimenti sforerebbe).
      isScrollControlled: true,
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
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final l in layouts) {
      // Stelo verticale dal dot all'ancoraggio dell'etichetta diagonale.
      final from = Offset(l.dotX, l.dotY - 4); // appena sopra il dot
      final to = Offset(l.labelX, l.labelY); // ancoraggio etichetta
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

/// Etichetta cima in **diagonale** (stile PeakFinder): testo ancorato in
/// cima allo stelo verticale e ruotato verso l'alto-destra. Riduce molto la
/// sovrapposizione quando si mostrano molte cime su tutta la larghezza, e dà
/// il look "professionale" delle app concorrenti. Tap → bottom sheet.
class _DiagonalPeakLabel extends StatelessWidget {
  final _PinLayout layout;
  final bool isCentered;
  final VoidCallback onTap;

  const _DiagonalPeakLabel({
    super.key,
    required this.layout,
    required this.isCentered,
    required this.onTap,
  });

  /// -45° → il testo sale verso destra (in Flutter l'angolo positivo è
  /// orario perché l'asse Y punta in basso, quindi negativo = antiorario).
  static const double _angleRad = -45 * math.pi / 180;

  static const List<Shadow> _shadows = [
    Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
    Shadow(color: Colors.black87, blurRadius: 6),
  ];

  @override
  Widget build(BuildContext context) {
    final p = layout.peak;
    final isVolcano = p.peak.type == 'volcano';
    final accent = isVolcano
        ? AppColors.danger
        : (isCentered ? AppColors.warning : Colors.white);

    final ele = p.peak.elevation;
    final dist = p.distanceMeters / 1000;
    final distStr =
        dist < 10 ? dist.toStringAsFixed(1) : dist.toStringAsFixed(0);
    final meta = ele != null ? '${ele.round()} m · $distStr km' : '$distStr km';

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      left: layout.labelX,
      top: layout.labelY,
      child: Transform.rotate(
        // Pivot in alto-sinistra = ancoraggio dello stelo: il testo parte da
        // lì e sale verso destra, indipendentemente dalla sua lunghezza.
        angle: _angleRad,
        alignment: Alignment.topLeft,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            // Stacca il testo di qualche px dall'ancoraggio dello stelo.
            padding: const EdgeInsets.only(left: 6, bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  p.peak.name,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: isCentered ? accent : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: isCentered ? 16 : 14,
                    height: 1.0,
                    shadows: _shadows,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  meta,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: isCentered ? 12 : 11,
                    height: 1.0,
                    shadows: _shadows,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet con i dettagli completi di una cima toccata nel viewfinder.
class _PeakDetailSheet extends StatefulWidget {
  final ProjectedPeak projected;

  const _PeakDetailSheet({required this.projected});

  @override
  State<_PeakDetailSheet> createState() => _PeakDetailSheetState();
}

class _PeakDetailSheetState extends State<_PeakDetailSheet> {
  final SavedPeaksRepository _savedRepo = SavedPeaksRepository();
  bool _saved = false;
  bool _loadingSave = false;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    setState(() => _loadingSave = true);
    final s = await _savedRepo.isSaved(widget.projected.peak.id);
    if (!mounted) return;
    setState(() {
      _saved = s;
      _loadingSave = false;
    });
  }

  Future<void> _toggleSave() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      final nowSaved = await _savedRepo.toggle(widget.projected.peak);
      if (!mounted) return;
      setState(() => _saved = nowSaved);
      AppSnackBar.success(
        context,
        nowSaved
            ? context.l10n.mfDetailSaveAdded
            : context.l10n.mfDetailSaveRemoved,
      );
    } catch (e) {
      debugPrint('[PeakDetail] toggle save error: $e');
      if (mounted) {
        AppSnackBar.error(context, context.l10n.mfDetailSaveError);
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  void _openOnMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PeakMapPage(peak: widget.projected.peak),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projected = widget.projected;
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
            // Salva cima + Apri mappa (riga di 2 pulsanti)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        (_toggling || _loadingSave) ? null : _toggleSave,
                    icon: _toggling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(_saved
                            ? Icons.bookmark
                            : Icons.bookmark_outline),
                    label: Text(
                      _saved
                          ? context.l10n.mfDetailSaved
                          : context.l10n.mfDetailSave,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _saved ? accent : accent.withValues(alpha: 0.85),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openOnMap,
                    icon: const Icon(Icons.map_outlined),
                    label: Text(context.l10n.mfDetailViewOnMap),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                          color: accent.withValues(alpha: 0.5)),
                      foregroundColor: accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Pulsante OSM (secondario)
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _openOsm(p, context),
                icon: const Icon(Icons.public, size: 18),
                label: Text(context.l10n.mfDetailOpenOsm),
                style: TextButton.styleFrom(
                  foregroundColor: context.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 4),
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
      // SingleChildScrollView: permette al contenuto di scrollare in
      // landscape (dove altrimenti il sheet sfora). Il sheet padre ha
      // isScrollControlled: true così può estendersi oltre il 50% h.
      child: SingleChildScrollView(
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
