import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/device_attitude_service.dart';
import '../../../core/services/mountain_finder_settings.dart';
import '../../../core/services/peaks_dataset_service.dart';
import '../../../core/services/pro_gate_service.dart';
import '../../../core/services/terrain_tile_service.dart';
import '../../../core/services/viewshed_service.dart';
import '../../../core/utils/camera_fov.dart';
import '../../../core/utils/camera_orientation.dart';
import '../../../core/utils/mountain_photo_renderer.dart';
import '../../../core/utils/mountain_projection.dart';
import '../../../data/models/mountain_peak.dart';
import '../../../data/models/osm_poi.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/osm_pois_repository.dart';
import '../../../data/repositories/saved_peaks_repository.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/paywall_sheet.dart';
import '../../widgets/skyline_overlay.dart';
import 'mountain_finder_calibration_page.dart';
import 'mountain_photo_result_page.dart';
import 'peak_map_page.dart';
import '../../../core/utils/camera_teardown.dart';

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

  /// L'inizializzazione in volo, conservata perche' la chiusura possa
  /// aspettarla: chiudere una fotocamera a meta' inizializzazione era il
  /// crash. Vedi [closeCameraSafely].
  Future<void>? _cameraInit;
  bool _initializing = true;
  String? _error;

  // Sensor state
  Position? _userPosition;

  /// Assetto corrente del telefono (terna della fotocamera + qualità della
  /// bussola). Sorgente unica: [DeviceAttitudeService], che fonde i sensori
  /// nativi e sa dove punta l'**obiettivo**, non il bordo alto del telefono.
  DeviceAttitude? _attitude;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<DeviceAttitude>? _attitudeSub;

  /// Terna congelata dall'AR lock: si continua a disegnare con questa mentre i
  /// sensori vanno avanti per conto loro.
  CameraBasis? _lockedBasis;

  /// Altezza degli occhi sopra il terreno, in metri.
  static const double _eyeHeightM = 1.7;

  /// Quota del terreno sotto l'utente secondo il DEM. È molto più affidabile
  /// dell'altitudine GPS (che su Android sbaglia di 20-50 m, cioè un grado di
  /// errore verticale a 3 km) ed è la stessa quota che usa il viewshed: senza,
  /// le due metà del sistema non concordano su dove si trova l'utente.
  double? _groundElevationM;

  /// Ultima posizione per cui abbiamo chiesto la quota del terreno.
  Position? _lastElevationPosition;

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

  /// Modalità allineamento: il trascinamento sposta le etichette invece di
  /// zoomare, così l'utente le fa combaciare con le montagne vere.
  ///
  /// Non è un ripiego per una math sbagliata: il magnetometro di uno smartphone
  /// sbaglia di qualche grado in presenza di roccia ferrosa, funivie, ferrate o
  /// custodie magnetiche, e nessuna fusione di sensori lo corregge. Tutti i
  /// concorrenti seri danno questa manopola; senza, l'unica reazione possibile
  /// a un errore è chiudere l'app.
  bool _alignMode = false;

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
  /// Esito dell'ultimo compute: serve a distinguere "non vedi cime" da "non
  /// sono riuscito a calcolarlo", che prima erano indistinguibili.
  ViewshedStatus _viewshedStatus = ViewshedStatus.ok;
  /// True quando buona parte delle cime mostrate è "non so se è nascosta":
  /// il DEM non copriva tutto il terreno in mezzo.
  bool _viewshedPatchyTerrain = false;
  /// True quando esiste un risultato valido, anche se la lista è **vuota**.
  /// Serve a distinguere "il filtro ha girato e non vedi nulla" (fondovalle
  /// chiuso: risposta legittima) da "il filtro non ha ancora girato" — che
  /// prima erano lo stesso insieme vuoto, e nel dubbio si mostravano tutte le
  /// cime con l'icona del filtro accesa.
  bool _viewshedHasResult = false;
  /// Non riprovare prima di questo istante, dopo un calcolo fallito.
  DateTime? _viewshedRetryAfter;

  /// Profilo dell'orizzonte calcolato dal DEM: angolo di elevazione massimo del
  /// terreno per ogni direzione. Disegnato sopra la camera come riferimento.
  List<double> _skylineAngles = const [];

  /// Posizione in cui il profilo è stato calcolato. Il profilo **non si disegna
  /// senza questa**: un orizzonte è valido solo da dove è stato preso, e uno
  /// vecchio non è un difetto estetico — l'utente lo vede non combaciare, entra
  /// in allineamento manuale e trascina fino a farlo coincidere, salvando un
  /// offset falso che sposta anche tutte le etichette. Lo strumento che deve
  /// dimostrare la correttezza diventerebbe la causa dell'errore.
  Position? _skylinePosition;

  /// Campo visivo del fotogramma pieno dell'obiettivo, letto dall'hardware.
  /// Null finché non risponde, o se la piattaforma non lo espone.
  ({double horizontalDeg, double verticalDeg})? _sensorFov;

  /// Ultimo campo visivo effettivo calcolato, per la diagnostica.
  CameraFov? _lastEffectiveFov;
  bool _loggedEffectiveFov = false;

  /// Mostra il profilo dell'orizzonte (preferenza persistita).
  bool get _showSkyline => MountainFinderSettings().showSkyline;

  /// True se il profilo disegnato è stato calcolato abbastanza vicino a dove
  /// siamo adesso. La verifica sta qui, in un solo punto, invece che nei vari
  /// rami che potrebbero dimenticarsi di azzerarlo: così un profilo stantio non
  /// è "un caso che non abbiamo gestito", è impossibile da disegnare.
  bool get _skylineIsCurrent {
    if (_skylineAngles.isEmpty) return false;
    final from = _skylinePosition;
    final now = _userPosition;
    if (from == null || now == null) return false;
    return Geolocator.distanceBetween(
          from.latitude, from.longitude, now.latitude, now.longitude,
        ) <
        _viewshedRefreshMeters;
  }
  /// Tier risolto una volta sola: il controllo admin è una chiamata Firestore
  /// e adesso il viewshed gira ogni 500 m invece che ogni 5 km.
  ViewshedTier? _resolvedTier;

  // ── Diagnostica di campo (solo admin) ───────────────────────────────
  /// L'allineamento AR si può giudicare solo con il telefono in mano davanti
  /// a montagne vere, e in release i log non si leggono. Questo pannello
  /// mostra a schermo cosa stanno facendo davvero i sensori. Gated su admin:
  /// è uno strumento di lavoro, non una feature.
  bool _isAdmin = false;
  bool _showDiagnostics = false;

  /// Riepilogo dell'ultimo calcolo viewshed, per il pannello.
  int _viewshedVisibleCount = 0;
  int _viewshedUncertainCount = 0;
  int _viewshedElapsedMs = 0;

  /// Distanza oltre la quale il viewshed va rifatto. In cresta l'occlusione
  /// cambia radicalmente in poche centinaia di metri.
  static const double _viewshedRefreshMeters = 500;

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
    _attitudeSub?.cancel();
    // Staccata dal campo e chiusa fuori: `dispose()` e' sincrono per
    // contratto, e chiudere la fotocamera mentre si sta ancora inizializzando
    // faceva esplodere CameraX. Vedi [closeCameraSafely].
    final camera = _camera;
    final cameraInit = _cameraInit;
    _camera = null;
    unawaited(closeCameraSafely(camera, cameraInit));
    super.dispose();
  }

  void _onProChanged() {
    if (!mounted) return;
    // Il tier è memorizzato per non interrogare Firestore ogni 500 m: se
    // l'utente compra Pro adesso, va ricalcolato o resterebbe free per tutta
    // la sessione.
    _resolvedTier = null;
    final pos = _userPosition;
    if (pos != null) {
      unawaited(_recomputeViewshedIfNeeded(pos, force: true));
    }
    setState(() {});
  }

  /// Settings precedenti per detection del cambio distanza (che richiede
  /// un re-fetch delle candidate, mentre il FOV no).
  double _lastSeenDistanceKm = MountainFinderSettings.defaultDistanceKm;

  /// Preferenza skyline all'ultimo giro, per accorgersi di quando viene accesa.
  bool _lastSeenShowSkyline = true;

  void _onSettingsChanged() {
    if (!mounted) return;
    final settings = MountainFinderSettings();

    // Accendere il profilo dell'orizzonte richiede un calcolo che non c'è:
    // ora lo skyline si produce solo se qualcuno lo disegna, quindi senza
    // questo l'interruttore sembrerebbe non fare nulla finché non ci si
    // sposta di mezzo chilometro.
    if (settings.showSkyline != _lastSeenShowSkyline) {
      _lastSeenShowSkyline = settings.showSkyline;
      final pos = _userPosition;
      if (settings.showSkyline && pos != null) {
        unawaited(_recomputeViewshedIfNeeded(pos, force: true));
      }
    }

    final newDist = MountainFinderSettings().maxDistanceKmValue;
    if ((newDist - _lastSeenDistanceKm).abs() > 0.5) {
      _lastSeenDistanceKm = newDist;
      // La distanza è cambiata: rifetcha le candidate dal dataset e rifai il
      // viewshed, che dipende dal raggio.
      final pos = _userPosition;
      if (pos != null) {
        _refreshCandidatePeaksIfNeeded(pos, force: true)
            .then((_) => _recomputeViewshedIfNeeded(pos, force: true));
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
      // Il Future viene conservato: se si esce dalla pagina adesso, la
      // chiusura deve poterlo aspettare invece di interrompere a meta'.
      _cameraInit = _camera!.initialize();
      await _cameraInit;

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

      // Campo visivo reale dell'obiettivo. Era l'ultimo numero indovinato
      // della catena: 60°x80° scritti a tavolino e mai verificati su questo
      // telefono, mentre orientamento, declinazione, quota e occlusioni sono
      // ormai tutti misurati o derivati.
      unawaited(DeviceAttitudeService().sensorFieldOfView().then((fov) {
        if (mounted && fov != null) setState(() => _sensorFov = fov);
      }));

      // **Il mirino si apre qui**, appena la fotocamera è pronta: non si aspetta
      // il GPS.
      //
      // Prima lo si mostrava in fondo, dopo il primo fix. Con la rete il fix
      // arriva in un paio di secondi e non si notava; senza rete il telefono
      // non può scaricare i dati di assistenza satellitare e ci mette decine di
      // secondi — cioè proprio in montagna, dove la funzione serve, l'utente
      // guardava uno spinner davanti a una fotocamera che era già accesa.
      // Le etichette compaiono quando arriva la posizione: è un'attesa che ha
      // senso, perché senza posizione non c'è niente da etichettare.
      if (!mounted) return;
      setState(() => _initializing = false);

      // Anche l'orientamento parte subito: non dipende dal GPS, e lasciarlo
      // dietro l'attesa della posizione teneva la bussola a "—°" e il mirino
      // immobile per tutto il tempo.
      _attitudeSub = DeviceAttitudeService().stream.listen((attitude) {
        if (!mounted || _arLocked) return;
        setState(() => _attitude = attitude);
      });

      // GPS — prima posizione + stream. Da qui in poi si lavora in sottofondo,
      // con il mirino già visibile.
      try {
        _userPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        if (mounted) setState(() {});
      } catch (_) {}
      if (!mounted) return;
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen((pos) async {
        if (!mounted) return;
        setState(() => _userPosition = pos);
        unawaited(_expireStaleAlignOffset(pos));
        unawaited(_refreshObserverElevation(pos));
        // Il dataset delle cime si ricarica ogni ~5 km (è un raggio largo),
        // il viewshed ogni 500 m: sono due cadenze diverse e vanno tenute
        // separate. Prima il secondo era annidato nel primo, quindi in pratica
        // l'elenco delle cime visibili si aggiornava solo ogni 5 km.
        await _refreshCandidatePeaksIfNeeded(pos);
        await _recomputeViewshedIfNeeded(pos);
      });

      if (_userPosition != null) {
        unawaited(_refreshObserverElevation(_userPosition!));
        await _refreshCandidatePeaksIfNeeded(_userPosition!);
        unawaited(_recomputeViewshedIfNeeded(_userPosition!));
      }
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
  /// Rettangoli dello schermo occupati dai comandi, in cui le etichette non
  /// devono finire.
  ///
  /// Senza questo l'interfaccia si disegna sopra il contenuto: in landscape la
  /// barra dei comandi e la card coprivano i nomi delle cime, cioè esattamente
  /// la cosa per cui si apre la schermata. Le zone entrano nello stesso
  /// algoritmo anti-collisione che le etichette usano fra loro, invece di
  /// essere un caso a parte.
  List<Rect> _reservedRegions(Size viewport) {
    final w = viewport.width;
    final h = viewport.height;
    final isPortrait = h >= w;
    return [
      // Barra dei comandi in alto.
      Rect.fromLTRB(0, 0, w, 62),
      if (isPortrait) ...[
        // Card informativa + pulsante di scatto, entrambi in basso.
        Rect.fromLTRB(0, h - 200, w, h),
      ] else ...[
        // Card in basso a sinistra, scatto sulla destra a metà altezza.
        Rect.fromLTRB(0, h - 110, 285, h),
        Rect.fromLTRB(w - 100, h / 2 - 50, w, h / 2 + 50),
      ],
      // Indicazione della modalità allineamento, quando è attiva.
      if (_alignMode)
        Rect.fromLTRB(w / 2 - 180, h - 250, w / 2 + 180, h - 150),
    ];
  }

  List<Widget> _buildPinLayer(List<ProjectedPeak> projected, Size viewport) {
    if (projected.isEmpty) return const [];

    // La cima più centrata è la prima della lista (projectAll ordina per
    // centratura): la evidenziamo (colore + dimensione) e le garantiamo
    // sempre un'etichetta.
    final centeredId = projected.first.peak.id;

    // Etichette decluttered: solo le cime più importanti (quota maggiore)
    // ricevono un nome; le altre restano solo come dot. Evita il muro di
    // testo quando molte cime cadono nello stesso settore.
    final labelLayouts =
        _layoutLabels(projected, centeredId, _reservedRegions(viewport));

    return [
      // Steli connettori dot → ancoraggio etichetta (sotto tutto, no tap).
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _PinLinesPainter(labelLayouts),
          ),
        ),
      ),
      // Dot per TUTTE le cime visibili (anche quelle senza etichetta).
      for (final p in projected)
        AnimatedPositioned(
          key: ValueKey('dot_${p.peak.id}'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          left: p.screenX - 5,
          top: p.screenY - 5,
          width: 10,
          height: 10,
          child: IgnorePointer(
            child: _PeakDot(
              isVolcano: p.peak.type == 'volcano',
              isCentered: p.peak.id == centeredId,
            ),
          ),
        ),
      // Etichette diagonali (stile PeakFinder): testo ruotato che sale
      // verso destra dall'ancoraggio dello stelo.
      for (final l in labelLayouts)
        _DiagonalPeakLabel(
          key: ValueKey('label_${l.peak.peak.id}'),
          layout: l,
          isCentered: l.peak.peak.id == centeredId,
          onTap: () => _showPeakDetail(l.peak),
        ),
    ];
  }

  /// Stima la lunghezza in pixel dell'etichetta (nome + meta) per la
  /// collisione. Sovrastima leggermente (è meglio scartare un'etichetta in
  /// più che lasciarne due sovrapposte). Coerente con `_DiagonalPeakLabel`.
  static double _estLabelLength(ProjectedPeak p, bool centered) {
    final nameF = centered ? 16.0 : 14.0;
    final metaF = centered ? 12.0 : 11.0;
    final meta = _peakLabelMeta(p, full: centered);
    final nameW = p.peak.name.length * nameF * 0.56;
    final metaW = meta.isEmpty ? 0.0 : 6 + meta.length * metaF * 0.56;
    return 8 + nameW + metaW + 10;
  }

  /// Selezione + layout delle etichette diagonali con **decluttering per
  /// importanza** (regola: vince la cima più alta).
  ///
  /// Le etichette condividono lo stesso angolo (-45°), quindi modelliamo
  /// ognuna come un rettangolo orientato e proiettiamo l'ancoraggio su due
  /// assi: `pu` lungo la direzione del testo, `pn` perpendicolare. Due
  /// etichette si sovrappongono solo se sono vicine in `pn` (entro l'altezza
  /// del testo) E i loro intervalli lungo `pu` si intersecano — controllo
  /// dell'ingombro REALE del testo ruotato, non solo della distanza degli
  /// ancoraggi (era il bug: nomi lunghi che si incrociavano).
  ///
  /// Si processano le cime per quota decrescente (la centrale per prima, così
  /// ha sempre l'etichetta). Ognuna prova lo stelo base; se collide, allunga
  /// lo stelo di qualche gradino per cercare una banda libera; se non la
  /// trova, **niente etichetta** (resta il dot) → nei cluster fitti
  /// sopravvivono i nomi delle vette più alte.
  List<_PinLayout> _layoutLabels(
      List<ProjectedPeak> peaks, String centeredId, List<Rect> reserved) {
    const baseStem = 22.0; // stelo minimo (px sopra il dot)
    const stemStep = 30.0; // allungamento stelo per cercare una banda libera
    const maxExtraLevels = 3; // tentativi di stelo più lungo prima di scartare
    const labelThickness = 24.0; // ingombro perpendicolare del testo (px)
    const gap = 8.0; // margine minimo lungo la direzione del testo
    const s = 0.70710678; // 1/√2 (proiezione a 45°)

    // Ordine di importanza: quota decrescente; tiebreak sulla più vicina.
    final ranked = [...peaks]
      ..sort((a, b) {
        final ea = a.peak.elevation ?? -1;
        final eb = b.peak.elevation ?? -1;
        final c = eb.compareTo(ea);
        if (c != 0) return c;
        return a.distanceMeters.compareTo(b.distanceMeters);
      });
    final ci = ranked.indexWhere((p) => p.peak.id == centeredId);
    if (ci > 0) ranked.insert(0, ranked.removeAt(ci));

    // Rettangoli orientati già piazzati: (pu inizio, pu fine, pn).
    final placed = <(double, double, double)>[];
    final result = <_PinLayout>[];

    for (final p in ranked) {
      final centered = p.peak.id == centeredId;
      final len = _estLabelLength(p, centered);
      bool ok = false;
      final diag = len * s;

      // Si prova prima sopra il punto, come sempre; se lassù non c'è posto —
      // tipicamente in landscape, dove lo schermo è basso e la barra dei
      // comandi occupa la fascia alta — si prova **sotto**, invece di
      // rinunciare al nome. Il testo resta inclinato allo stesso modo: cambia
      // solo da che parte del punto è agganciato.
      for (final below in [false, true]) {
        if (ok) break;
        double stem = baseStem;
        for (var lvl = 0; lvl <= maxExtraLevels; lvl++) {
          final ax = p.screenX;
          final ay = below ? p.screenY + stem + diag : p.screenY - stem;
          final pu = (ax - ay) * s; // coord lungo il testo
          final pn = (ax + ay) * s; // coord perpendicolare

          bool collides = false;
          // Ingombro dell'etichetta ruotata, in coordinate schermo: parte
          // dall'ancoraggio e sale verso destra a 45°.
          final labelBox = Rect.fromLTRB(
            ax,
            ay - diag - labelThickness,
            ax + diag,
            ay + 4,
          );
          for (final region in reserved) {
            if (region.overlaps(labelBox)) {
              collides = true;
              break;
            }
          }
          for (final r in placed) {
            if (collides) break;
            if ((pn - r.$3).abs() < labelThickness &&
                pu < r.$2 + gap &&
                r.$1 < pu + len + gap) {
              collides = true;
              break;
            }
          }

          if (!collides) {
            placed.add((pu, pu + len, pn));
            result.add(_PinLayout(
              peak: p,
              dotX: p.screenX,
              dotY: p.screenY,
              labelX: p.screenX,
              labelY: ay,
            ));
            ok = true;
            break;
          }
          stem += stemStep;
        }
      }
      // !ok → nessuna posizione libera né sopra né sotto: resta il dot.
      if (!ok) continue;
    }

    return result;
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
    // Raggio **dell'utente**, non del tier: qui si decide cosa l'utente vede
    // quando il filtro è spento, e il tier non c'entra. Legarlo al tier è stata
    // una regressione dello sprint precedente — un utente free con lo slider a
    // 100 km e il filtro spento perdeva tutto oltre i 20, senza spiegazione e
    // con lo slider che continuava a dire 100. Il tier limita il viewshed
    // (dove costa davvero), non l'elenco delle cime.
    final radius = MountainFinderSettings().maxDistanceKmValue;
    final candidates = ds.findWithinRadius(
      pos.latitude,
      pos.longitude,
      radiusKm: radius,
      // Con la quota dell'osservatore il taglio delle candidate premia le cime
      // che si alzano davvero nella scena, invece delle più vicine.
      observerElevationM: _observerEyeElevationM,
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
  }

  /// Aggiorna la quota del terreno sotto l'utente dal DEM, se si è spostato
  /// abbastanza da poter essere cambiata.
  /// Butta la correzione manuale se l'utente si è spostato oltre il raggio in
  /// cui era stata tarata.
  ///
  /// Serve perché quella correzione compensa il campo magnetico **locale**:
  /// misurata dentro casa, accanto a un telaio metallico, vale una decina di
  /// gradi; all'aperto uno o due. Trascinarsela dietro non è prudente, è la
  /// cosa peggiore possibile — la correzione diventa essa stessa l'errore, e
  /// per giunta con l'utente convinto di aver già allineato.
  Future<void> _expireStaleAlignOffset(Position pos) async {
    final settings = MountainFinderSettings();
    if (!settings.hasAlignOffset) return;
    final lat = settings.alignLat, lng = settings.alignLng;
    if (lat == null || lng == null) return;
    final moved = Geolocator.distanceBetween(lat, lng, pos.latitude, pos.longitude);
    if (moved < MountainFinderSettings.alignValidityMeters) return;
    await settings.resetAlignOffset();
    if (!mounted) return;
    AppSnackBar.info(context, context.l10n.mfAlignExpired);
  }

  Future<void> _refreshObserverElevation(Position pos) async {
    final last = _lastElevationPosition;
    if (last != null &&
        Geolocator.distanceBetween(
              last.latitude,
              last.longitude,
              pos.latitude,
              pos.longitude,
            ) <
            50) {
      return;
    }
    _lastElevationPosition = pos;
    // Comunichiamo la posizione alla piattaforma: ad Android serve per la
    // declinazione magnetica (che è ciò che separa il nord magnetico da quello
    // geografico, ~4° nelle Alpi).
    unawaited(DeviceAttitudeService().setLocation(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
    ));
    try {
      final ground = await TerrainTileService().groundElevationAt(
        pos.latitude,
        pos.longitude,
      );
      if (!mounted || ground == null) return;
      setState(() => _groundElevationM = ground);
    } catch (e) {
      debugPrint('[MountainFinder] quota DEM non disponibile: $e');
    }
  }

  /// Quota dell'occhio dell'osservatore, in metri.
  ///
  /// Preferisce il DEM: l'altitudine GPS sbaglia di 20-50 m su Android, e
  /// quell'errore si traduce direttamente in pin spostati in verticale.
  double get _observerEyeElevationM {
    final ground = _groundElevationM;
    if (ground != null) return ground + _eyeHeightM;
    return _userPosition?.altitude ?? 0;
  }

  /// Terna della fotocamera da usare per disegnare: quella congelata se l'AR
  /// lock è attivo, altrimenti quella corrente, in entrambi i casi corretta
  /// dall'offset manuale di allineamento.
  CameraBasis? get _currentBasis {
    final raw = _arLocked ? _lockedBasis : _attitude?.basis;
    if (raw == null) return null;
    final settings = MountainFinderSettings();
    return raw.nudged(
      deltaAzimuthDeg: settings.alignAzimuthOffsetDeg,
      deltaPitchDeg: settings.alignPitchOffsetDeg,
    );
  }

  /// Campo visivo da usare per la proiezione, in gradi (orizzontale, verticale)
  /// **riferiti allo schermo**.
  ///
  /// Se l'utente non ha regolato nulla si usa quello letto dall'obiettivo,
  /// corretto per la rotazione e per il ritaglio `BoxFit.cover` della preview —
  /// una misura, non una supposizione. Gli slider di calibrazione restano come
  /// sovrascrittura, ma da qui in poi servono a rifinire, non a indovinare.
  (double, double) _fovForViewport(Size viewport) {
    final settings = MountainFinderSettings();
    final isPortrait = viewport.height >= viewport.width;

    final sensor = _sensorFov;
    if (!settings.hasManualFov && sensor != null) {
      final preview = _camera?.value.previewSize;
      if (preview != null) {
        final measured = screenFovFromSensor(
          sensorHorizontalDeg: sensor.horizontalDeg,
          sensorVerticalDeg: sensor.verticalDeg,
          // Il buffer arriva sempre nell'orientamento nativo del sensore.
          bufferWidth: preview.width,
          bufferHeight: preview.height,
          viewportWidth: viewport.width,
          viewportHeight: viewport.height,
        );
        if (measured != null) {
          if (!_loggedEffectiveFov) {
            _loggedEffectiveFov = true;
            debugPrint('[MountainFinder] FOV schermo: '
                '${measured.horizontalDeg.toStringAsFixed(1)}×'
                '${measured.verticalDeg.toStringAsFixed(1)}° '
                '(sensore ${sensor.horizontalDeg.toStringAsFixed(1)}×'
                '${sensor.verticalDeg.toStringAsFixed(1)}°, '
                'buffer ${preview.width.toStringAsFixed(0)}×'
                '${preview.height.toStringAsFixed(0)}, '
                'viewport ${viewport.width.toStringAsFixed(0)}×'
                '${viewport.height.toStringAsFixed(0)})');
          }
          _lastEffectiveFov = measured;
          return (measured.horizontalDeg, measured.verticalDeg);
        }
      }
    }

    // Ripiego: valori di calibrazione. Sono espressi assumendo portrait, quindi
    // in landscape vanno scambiati perché descrivono gli assi dello schermo.
    final calibH = settings.horizontalFovDeg;
    final calibV = settings.verticalFovDeg;
    return isPortrait ? (calibH, calibV) : (calibV, calibH);
  }

  /// Raggio effettivo, in km: il minore fra quello scelto dall'utente e quello
  /// consentito dal tier.
  ///
  /// Le due cose erano scollegate, e ne usciva il peggio dei due mondi: le cime
  /// candidate si prendevano nel raggio dell'utente (60 km di default) mentre il
  /// viewshed girava su quello del tier (100 km per il Pro). Risultato, il
  /// raggio pieno del Pro non esisteva — nessuna cima oltre i 60 km entrava mai
  /// nell'insieme — e insieme si sprecava lavoro su un DEM più largo del
  /// necessario.
  Future<double> _effectiveRadiusKm() async {
    final tier = await _viewshedTier();
    final userKm = MountainFinderSettings().maxDistanceKmValue;
    return math.min(userKm, tier.maxRadiusKm.toDouble());
  }

  /// Tier del viewshed, risolto una volta sola per sessione: il controllo
  /// admin passa da Firestore e ora il viewshed gira ogni 500 m.
  Future<ViewshedTier> _viewshedTier() async {
    final cached = _resolvedTier;
    if (cached != null) return cached;
    // Pro sbloccato da subscription IAP attiva OPPURE admin (per permettere
    // test in development senza acquisto).
    final isPro = ProGateService().isPro;
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    if (isAdmin != _isAdmin && mounted) {
      setState(() => _isAdmin = isAdmin);
    }
    final tier = (isPro || isAdmin) ? ViewshedTier.pro : ViewshedTier.free;
    _resolvedTier = tier;
    return tier;
  }

  /// (Re)compute viewshed se la posizione è cambiata più di
  /// [_viewshedRefreshMeters], o se [force].
  Future<void> _recomputeViewshedIfNeeded(Position pos,
      {bool force = false}) async {
    // Il calcolo serve a due consumatori indipendenti: il filtro "solo cime
    // visibili" e il profilo dell'orizzonte. Legarlo solo al primo significava
    // che a filtro spento il profilo non si aggiornava mai più.
    if (!_viewshedOnly && !MountainFinderSettings().showSkyline) return;
    if (!force && _lastViewshedPosition != null) {
      final moved = Geolocator.distanceBetween(
        _lastViewshedPosition!.latitude, _lastViewshedPosition!.longitude,
        pos.latitude, pos.longitude,
      );
      if (moved < _viewshedRefreshMeters) return;
    }
    if (_computingViewshed) return; // già in corso, evita race
    if (_candidatePeaks.isEmpty) return;
    // Dopo un fallimento aspettiamo prima di riprovare: senza, un errore
    // ripetibile (offline) fa ripartire il calcolo a ogni fix GPS, cioè ogni
    // 5 metri, con decine di tile richiesti ogni volta.
    final retryAfter = _viewshedRetryAfter;
    if (!force && retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      return;
    }

    // Il flag va alzato **prima** di qualsiasi await, altrimenti non protegge
    // nulla: il primo giro attende il controllo admin su Firestore, e in quelle
    // centinaia di millisecondi ogni nuovo fix GPS supera il guard e lancia un
    // calcolo in parallelo. Succedeva davvero — due `[Viewshed] start` in fila
    // nei log del telefono, e il tempo raddoppiato.
    _computingViewshed = true;
    setState(() {});
    try {
      final tier = await _viewshedTier();
      if (!mounted) return;
      final result = await ViewshedService().computeVisible(
        observerLat: pos.latitude,
        observerLng: pos.longitude,
        candidates: _candidatePeaks,
        tier: tier,
        radiusKm: await _effectiveRadiusKm(),
        // Se l'utente ha spento il profilo dell'orizzonte non lo calcoliamo:
        // sono 720 raggi in piu' che raddoppiano il tempo del calcolo.
        computeSkyline: MountainFinderSettings().showSkyline,
      );
      if (!mounted) return;
      setState(() {
        _viewshedVisibleIds = result.visible.map((v) => v.peak.id).toSet();
        _viewshedStatus = result.status;
        _viewshedPatchyTerrain = result.hasPatchyTerrain;
        _viewshedVisibleCount = result.visible.length;
        // Aggiornato o buttato, mai conservato "per non perderlo": un profilo
        // senza la sua posizione è peggio di nessun profilo.
        if (result.skylineAngles.isNotEmpty && result.isReliable) {
          _skylineAngles = result.skylineAngles;
          _skylinePosition = pos;
        } else {
          _skylineAngles = const [];
          _skylinePosition = null;
        }
        _viewshedUncertainCount = result.uncertainCount;
        _viewshedElapsedMs = result.elapsedMs;
        _viewshedHasResult = result.isReliable;
        if (result.isReliable) {
          // Riuscito: la posizione è "consumata", si rifà fra 500 m.
          _lastViewshedPosition = pos;
          _viewshedRetryAfter = null;
        } else {
          // Fallito: non consumiamo la posizione (vogliamo riprovare anche da
          // fermi, la rete può tornare) ma imponiamo un'attesa, altrimenti si
          // riparte a ogni fix GPS.
          _viewshedRetryAfter =
              DateTime.now().add(const Duration(seconds: 30));
        }
        // Quota del terreno: la teniamo solo come ripiego. Quella del viewshed
        // viene da un DEM a zoom 10 (~110 m/pixel), mentre
        // `_refreshObserverElevation` ne prende una a zoom 12 (~30 m): se si
        // sovrascrivessero a vicenda la quota oscillerebbe fra due valori a ogni
        // ricalcolo, e i pin salterebbero in verticale.
        final ground = result.observerGroundElevationM;
        if (_groundElevationM == null && ground != null && ground.isFinite) {
          _groundElevationM = ground;
        }
      });
      debugPrint(
          '[MountainFinder] viewshed: ${result.visible.length} cime visibili '
          '(tier=${tier.label}, ${result.elapsedMs}ms, ${result.status.name})');
    } catch (e) {
      debugPrint('[MountainFinder] viewshed error: $e');
      if (mounted) {
        _viewshedRetryAfter = DateTime.now().add(const Duration(seconds: 30));
      }
    } finally {
      // In un `finally`, non in ogni ramo: un `return` anticipato per
      // `!mounted` lasciava il flag alzato per sempre, e da lì in poi nessun
      // ricalcolo sarebbe più partito.
      if (mounted) {
        setState(() => _computingViewshed = false);
      } else {
        _computingViewshed = false;
      }
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
        _viewshedStatus = ViewshedStatus.ok;
        _viewshedHasResult = false;
        _viewshedRetryAfter = null;
      }
    });
    if (wantOn) {
      await _recomputeViewshedIfNeeded(pos, force: true);
    }
  }

  /// Lista cime effettiva considerando il filtro viewshed.
  ///
  /// La condizione è "esiste un risultato", non "l'insieme non è vuoto": un
  /// fondovalle chiuso in cui davvero non si vede nessuna cima è una risposta
  /// legittima, e prima veniva scambiata per "filtro non disponibile" — l'app
  /// mostrava tutte le cime del raggio, etichettate sopra il crinale che le
  /// nasconde, con l'icona del filtro accesa e nessun avviso.
  List<MountainPeak> get _effectiveCandidatePeaks {
    if (!_viewshedOnly || !_viewshedHasResult) return _candidatePeaks;
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

            // Diagnostica di campo (solo admin, e solo se richiesta).
            if (_isAdmin && _showDiagnostics && !_initializing)
              Positioned(
                left: 8,
                top: 60,
                child: _buildDiagnosticsPanel(),
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

    // Landscape: la card va in basso a SINISTRA, non in alto a destra.
    // In orizzontale le cime stanno all'altezza dell'orizzonte, cioè a metà
    // schermo, e le etichette salgono verso destra: l'angolo in alto a destra
    // è esattamente dove finiscono i nomi delle cime più lontane. In basso a
    // sinistra non c'è quasi mai nulla da coprire.
    return [
      Positioned(
        left: 12,
        bottom: 12,
        width: 260,
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
    final basis = _currentBasis;
    if (cam == null || pos == null || basis == null) {
      AppSnackBar.error(context, context.l10n.mfPhotoNoSensors);
      return;
    }
    setState(() => _processingCapture = true);
    try {
      // Snapshot del viewport corrente per la math di proiezione.
      final mq = MediaQuery.of(context);
      final viewport = Size(
        mq.size.width,
        mq.size.height - mq.padding.top - mq.padding.bottom,
      );

      // FOV: orientation-aware (swap H/V in landscape, vedi note in
      // _buildCameraWithOverlay). Lo zoom non si applica più dividendo i
      // gradi: restringe la **tangente** del semiangolo, dentro la proiezione.
      final (effHFov, effVFov) = _fovForViewport(viewport);

      // Tutti i peak nel cono FOV — niente cap come in live
      // (la differenza Free vs Pro!).
      final allVisible = MountainProjection.projectAll(
        peaks: _effectiveCandidatePeaks,
        observerLat: pos.latitude,
        observerLng: pos.longitude,
        observerElevationMeters: _observerEyeElevationM,
        basis: basis,
        viewport: viewport,
        maxVisible: 9999, // illimitato
        horizontalFovDeg: effHFov,
        verticalFovDeg: effVFov,
        zoom: _zoomLevel,
      );

      // 6.A2 v2: anche i POI OSM (rifugi, sorgenti, ecc.) nel cono FOV.
      // Stesso math, modello diverso. Cap a 12 visualizzati per non
      // sovrastare le cime (gestito dal renderer).
      final visiblePois = MountainProjection.projectAllPois(
        pois: _candidatePois,
        observerLat: pos.latitude,
        observerLng: pos.longitude,
        observerElevationMeters: _observerEyeElevationM,
        basis: basis,
        viewport: viewport,
        maxVisible: 12,
        horizontalFovDeg: effHFov,
        verticalFovDeg: effVFov,
        zoom: _zoomLevel,
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
        final basis = _currentBasis;

        // Campo visivo riferito allo schermo: misurato dall'obiettivo se
        // possibile, altrimenti dalla calibrazione manuale.
        final (effectiveHFov, effectiveVFov) = _fovForViewport(viewport);
        final projected = (pos != null && basis != null)
            ? MountainProjection.projectAll(
                peaks: _effectiveCandidatePeaks,
                observerLat: pos.latitude,
                observerLng: pos.longitude,
                observerElevationMeters: _observerEyeElevationM,
                basis: basis,
                viewport: viewport,
                maxVisible: _maxLiveLabels,
                horizontalFovDeg: effectiveHFov,
                verticalFovDeg: effectiveVFov,
                zoom: _zoomLevel,
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
                  // In modalità allineamento il trascinamento a un dito muove
                  // le etichette; il pinch a due dita continua a zoomare, così
                  // si può ingrandire per allineare con più precisione.
                  if (_alignMode && details.pointerCount <= 1) {
                    _applyAlignDrag(details.focalPointDelta,
                        effectiveHFov, effectiveVFov, viewport);
                    return;
                  }
                  if (_maxZoom <= _minZoom) return; // device senza zoom
                  final next = (_baseZoom * details.scale)
                      .clamp(_minZoom, _maxZoom);
                  if ((next - _zoomLevel).abs() < 0.02) return;
                  _zoomLevel = next;
                  _camera?.setZoomLevel(next);
                  setState(() {});
                },
                onScaleEnd: (_) {
                  if (_alignMode) {
                    // Insieme all'offset salviamo dove è stato tarato: fuori
                    // da quel raggio non vale più.
                    unawaited(MountainFinderSettings().commitAlignOffset(
                      latitude: _userPosition?.latitude,
                      longitude: _userPosition?.longitude,
                    ));
                  }
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

            // Profilo dell'orizzonte dal DEM: sotto le etichette, sopra la
            // preview. E' il riferimento che permette di vedere a colpo d'occhio
            // se il puntamento combacia con le montagne vere.
            if (basis != null && _showSkyline && _skylineIsCurrent)
              Positioned.fill(
                child: SkylineOverlay(
                  skylineAngles: _skylineAngles,
                  basis: basis,
                  horizontalFovDeg: effectiveHFov,
                  verticalFovDeg: effectiveVFov,
                  zoom: _zoomLevel,
                ),
              ),

            // Reticolo centrale (mirino).
            const Center(
              child: _Crosshair(),
            ),

            // Pin AR: layout anti-collisione + linee connettrici + label
            // animate. Le label si impilano verticalmente quando le cime
            // sono allineate sullo stesso bearing per evitare overlap.
            ..._buildPinLayer(projected, viewport),

            // Modalità allineamento: istruzione + offset applicato. I numeri
            // sono in gradi apposta — sono la misura dell'errore residuo dei
            // sensori, non solo una regolazione estetica.
            if (_alignMode)
              Positioned(
                left: 12,
                right: 12,
                bottom: 170,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n.mfAlignHint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '↔ ${MountainFinderSettings().alignAzimuthOffsetDeg.toStringAsFixed(1)}°'
                          '   ↕ ${MountainFinderSettings().alignPitchOffsetDeg.toStringAsFixed(1)}°',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

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
            // Il chip fa anche da interruttore della diagnostica di campo per
            // gli admin: la barra è già piena, e un pulsante in più andrebbe
            // in overflow sui telefoni stretti.
            child: GestureDetector(
              onTap: _isAdmin
                  ? () => setState(() => _showDiagnostics = !_showDiagnostics)
                  : null,
              behavior: HitTestBehavior.opaque,
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
                  // Bearing live prima del titolo così rimane sempre
                  // visibile; il titolo si elide se manca spazio.
                  Flexible(
                    child: Text(
                      _currentBasis != null
                          ? '${_currentBasis!.azimuthDeg.toStringAsFixed(0)}°'
                          : '—°',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  // Bussola inaffidabile: è la causa più comune di etichette
                  // fuori posto, e finora l'informazione c'era ma non veniva
                  // mai mostrata.
                  if (_attitude?.needsCalibration ?? false) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.explore_off,
                      size: 14,
                      color: AppColors.warning,
                    ),
                  ],
                ],
              ),
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
          // Allineamento manuale: trascina le etichette sulle montagne vere.
          // Tap lungo per azzerare e tornare ai sensori nudi. Il pulsante resta
          // evidenziato finché una correzione è attiva: correggere in silenzio
          // sarebbe peggio che non correggere, perché l'utente non saprebbe di
          // stare guardando una scena spostata a mano.
          Material(
            color: _alignMode || MountainFinderSettings().hasAlignOffset
                ? AppColors.primary
                : Colors.black.withValues(alpha: 0.5),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _alignMode = !_alignMode),
              onLongPress: () async {
                await MountainFinderSettings().resetAlignOffset();
                if (mounted) {
                  AppSnackBar.info(context, context.l10n.mfAlignReset);
                }
              },
              child: Tooltip(
                message: context.l10n.mfAlignTooltip,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.open_with, color: Colors.white, size: 20),
                ),
              ),
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
              onPressed: () {
                // Senza una terna da congelare il lock spegnerebbe l'AR fino
                // allo sblocco: meglio non entrarci proprio.
                final basis = _attitude?.basis;
                if (!_arLocked && basis == null) return;
                setState(() {
                  _arLocked = !_arLocked;
                  _lockedBasis = _arLocked ? basis : null;
                });
              },
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
    final warning = _statusWarning();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.themedBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  '${_observerEyeElevationM.toStringAsFixed(0)} m',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          // Quando il filtro visibilità non ha potuto girare (offline, o DEM
          // scoperto proprio qui) l'elenco torna a essere "tutte le cime nel
          // cono": dirlo, invece di lasciar credere che siano quelle visibili.
          if (warning != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warning,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Converte un trascinamento in gradi di correzione del puntamento.
  ///
  /// La scala è quella naturale: trascinare per tutta la larghezza dello
  /// schermo sposta di un intero campo visivo, quindi le etichette seguono il
  /// dito. Diviso per lo zoom, perché a 3× lo stesso pixel vale un terzo di
  /// grado — ed è proprio zoomando che si fanno le regolazioni fini.
  void _applyAlignDrag(
    Offset delta,
    double hFovDeg,
    double vFovDeg,
    Size viewport,
  ) {
    if (viewport.width <= 0 || viewport.height <= 0) return;
    // Segni: trascinando a destra le etichette devono andare a destra. Le
    // etichette si spostano a destra quando l'azimut della camera DIMINUISCE,
    // da cui il meno; in verticale il verso è invece concorde.
    final deltaAz =
        -(delta.dx / viewport.width) * hFovDeg / _zoomLevel;
    final deltaPitch =
        (delta.dy / viewport.height) * vFovDeg / _zoomLevel;
    MountainFinderSettings()
        .nudgeAlignOffset(deltaAzDeg: deltaAz, deltaPitchDeg: deltaPitch);
  }

  /// Pannello diagnostico di campo (solo admin).
  ///
  /// L'allineamento AR si giudica solo con montagne vere davanti, e in release
  /// i log non si leggono: questo mostra a schermo cosa fanno davvero i
  /// sensori. Serve a rispondere a tre domande, in ordine:
  /// 1. la sorgente di orientamento è quella nativa o il ripiego?
  /// 2. stiamo puntando al nord geografico o a quello magnetico?
  /// 3. la quota viene dal DEM o dal GPS?
  Widget _buildDiagnosticsPanel() {
    final attitude = _attitude;
    final basis = _currentBasis;
    final ground = _groundElevationM;

    String row(String k, String v) => '$k  $v';
    final lines = <String>[
      row('sorgente',
          attitude == null
              ? '—'
              : (attitude.isNative ? 'fusione nativa' : 'RIPIEGO bussola')),
      row('nord',
          attitude == null
              ? '—'
              : (attitude.isTrueNorth ? 'geografico' : 'MAGNETICO')),
      row('bussola',
          attitude?.accuracyDeg == null
              ? 'INAFFIDABILE'
              : '±${attitude!.accuracyDeg!.toStringAsFixed(0)}°'),
      row('az/pitch/roll',
          basis == null
              ? '—'
              : '${basis.azimuthDeg.toStringAsFixed(1)}° / '
                  '${basis.pitchDeg.toStringAsFixed(1)}° / '
                  '${basis.rollDeg.toStringAsFixed(1)}°'),
      row('quota',
          ground != null
              ? 'DEM ${ground.toStringAsFixed(0)} m (+${_eyeHeightM.toStringAsFixed(1)})'
              : 'GPS ${(_userPosition?.altitude ?? 0).toStringAsFixed(0)} m'),
      row('viewshed',
          '${_viewshedStatus.name} · $_viewshedVisibleCount vis · '
              '$_viewshedUncertainCount inc · ${_viewshedElapsedMs}ms'),
      row('tier', _resolvedTier?.label ?? '—'),
      row('allineam.',
          '↔ ${MountainFinderSettings().alignAzimuthOffsetDeg.toStringAsFixed(2)}° '
              '↕ ${MountainFinderSettings().alignPitchOffsetDeg.toStringAsFixed(2)}°'),
      row('fov sensore',
          _sensorFov == null
              ? '—'
              : '${_sensorFov!.horizontalDeg.toStringAsFixed(1)}×'
                  '${_sensorFov!.verticalDeg.toStringAsFixed(1)}°'),
      row('fov schermo',
          _lastEffectiveFov == null
              ? (MountainFinderSettings().hasManualFov ? 'manuale' : '—')
              : '${_lastEffectiveFov!.horizontalDeg.toStringAsFixed(1)}×'
                  '${_lastEffectiveFov!.verticalDeg.toStringAsFixed(1)}°'
                  ' ${MountainFinderSettings().hasManualFov ? "(manuale)" : ""}'),
      row('zoom', '${_zoomLevel.toStringAsFixed(2)}x'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Text(
              l,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                height: 1.5,
                fontFamily: 'monospace',
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }

  /// Avviso da mostrare nella card, o null se è tutto a posto. In ordine di
  /// priorità: prima quello che invalida le cime mostrate, poi quello che
  /// invalida il puntamento.
  String? _statusWarning() {
    if (_viewshedOnly) {
      switch (_viewshedStatus) {
        case ViewshedStatus.demUnavailable:
          return context.l10n.mfViewshedNoTerrain;
        case ViewshedStatus.observerOutsideDem:
          return context.l10n.mfViewshedNoTerrainHere;
        case ViewshedStatus.ok:
          // Il filtro sta girando: qui il terreno lacunoso non disattiva nulla,
          // rende solo incerte alcune cime — e il messaggio deve dire questo,
          // non "mostro tutte le cime".
          if (_viewshedPatchyTerrain) {
            return context.l10n.mfViewshedPartialTerrain;
          }
          if (_viewshedHasResult && _viewshedVisibleCount == 0) {
            return context.l10n.mfViewshedNothingVisible;
          }
          break;
        case ViewshedStatus.noPeaksInRange:
          break;
      }
    }
    if (_attitude?.needsCalibration ?? false) {
      return context.l10n.mfCompassUnreliable;
    }
    return null;
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
/// Metadati cima per l'etichetta diagonale. [full] (cima selezionata) =
/// quota + distanza; altrimenti solo quota → etichetta più corta, meno
/// sovrapposizioni nei cluster. Condiviso tra rendering e stima ingombro
/// nel layout anti-collisione, così le due cose restano coerenti.
String _peakLabelMeta(ProjectedPeak p, {required bool full}) {
  final ele = p.peak.elevation;
  final dist = p.distanceMeters / 1000;
  final distStr =
      dist < 10 ? dist.toStringAsFixed(1) : dist.toStringAsFixed(0);
  if (ele == null) return full ? '$distStr km' : '';
  return full ? '${ele.round()} m · $distStr km' : '${ele.round()} m';
}

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

    final meta = _peakLabelMeta(p, full: isCentered);

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
                if (meta.isNotEmpty) ...[
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
            const Divider(height: 24),
            // Profilo dell'orizzonte: sta qui e non nella barra in alto perche'
            // e' una preferenza che si imposta una volta, non un comando che si
            // usa di continuo — e la barra e' gia' piena.
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: MountainFinderSettings().showSkyline,
              onChanged: (v) {
                setState(() {});
                MountainFinderSettings().setShowSkyline(v);
              },
              title: Text(
                context.l10n.mfSkylineTitle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              subtitle: Text(
                context.l10n.mfSkylineHelp,
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
              activeThumbColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
