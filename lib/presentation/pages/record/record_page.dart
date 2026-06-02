import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/services/location_service.dart';
import '../../../presentation/blocs/tracking_bloc.dart';
import '../../../core/services/post_track_save_service.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../../widgets/live_track_button.dart';
import '../../widgets/heart_rate_widget.dart';
import '../../../core/services/feature_tips.dart';
import '../../../core/services/heading_service.dart';
import '../../../core/services/hud_prefs_service.dart';
import '../../../core/utils/eta_estimator.dart';
import '../../../core/services/recording_status_service.dart';
import '../../widgets/map_heading_toggle.dart';
import '../../widgets/map_layer_button.dart';
import '../../../core/constants/map_styles.dart';
import '../../../core/services/map_style_prefs.dart';
import '../../widgets/map_overlays.dart';
import '../../../core/services/track_photos_service.dart';
import '../../widgets/photo_gallery_widget.dart';
import '../../../core/services/recording_persistence_service.dart';
import '../../../core/services/live_track_service.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../../../core/services/health_service.dart';
import '../../../core/services/strava_service.dart';
import '../../../core/services/offline_tile_provider.dart';
import '../../../core/services/voice_guidance_service.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/services/lifeline_service.dart';
import '../../../core/config/app_config.dart';
import '../../../data/models/navigation_step.dart';
import '../../../data/models/recording_reference.dart';
import '../../widgets/pre_start_preview_sheet.dart';
import '../mountain_finder/mountain_finder_page.dart';
import '../settings/emergency_contacts_page.dart';
import '../../../data/models/emergency_contact.dart';
import '../../../data/repositories/emergency_contacts_repository.dart';
import '../../widgets/poi_editor_sheet.dart';
import '../../../data/models/trail_poi.dart';
import '../../../data/repositories/poi_repository.dart';
import '../../../core/services/poi_voice_prefs.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/extensions/theme_colors_extension.dart';

class RecordPage extends StatefulWidget {
  /// Traccia di riferimento opzionale. Quando passata, la registrazione si
  /// avvia automaticamente e sulla mappa compare la polyline guida.
  ///
  /// - `reference.isPlanner` + `reference.hasTurnByTurn` → guida vocale
  ///   turn-by-turn + rilevamento arrivo
  /// - `reference.isTrail` → alert sonori off-trail + rilevamento arrivo
  ///
  /// Se `null` la pagina funziona in modalità standalone come sempre.
  final RecordingReference? reference;

  /// Tipo di attività iniziale. Usato principalmente in modalità guidata
  /// (quando non c'è lo schermo idle che permette di sceglierlo).
  final ActivityType? initialActivityType;

  const RecordPage({
    super.key,
    this.reference,
    this.initialActivityType,
  });

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> with WidgetsBindingObserver {
  late final TrackingBloc _trackingBloc;
  final TracksRepository _repository = TracksRepository();
  final MapController _mapController = MapController();
  final RecordingPersistenceService _persistence = RecordingPersistenceService.instance;
  
  bool _followUser = true;
  int _currentMapStyle = MapStylePrefs().index;
  bool _isSaving = false;
  bool _isRestoringState = false;
  bool _showRecTutorial = false;
  
  final TrackPhotosService _photosService = TrackPhotosService();
  final List<TrackPhoto> _photos = [];
  ActivityType _selectedActivity = ActivityType.trekking;
  
  // Battery monitoring
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;
  bool _lowBatteryWarningShown = false;
  bool _batterySaverSuggestionShown = false;
  bool _batterySaverOn = false;
  LatLng? _userPosition;

  // Quick stats per schermata idle
  Track? _lastTrack;
  double _weeklyDistanceKm = 0;
  double _weeklyElevation = 0;
  int _weeklyTracks = 0;

  // ── Modalità "guidata" (reference != null) ──────────────────────────────
  VoiceGuidanceService? _voice;
  int _refUserIndex = 0;
  NavigationStep? _refCurrentStep;
  NavigationStep? _refNextStep;
  double _refDistanceToNextTurn = 0;
  double _refRemainingDistance = 0;
  double _refDistanceFromTrail = 0;
  bool _refOffTrail = false;
  bool _refArrived = false;
  /// Epic 4.1 — ETA dinamico ricalcolato ad ogni update guidato sulla
  /// base della velocità corrente reale (non più solo Naismith pre-start).
  Duration? _refDynamicEta;
  DateTime? _refLastOffTrailAnnouncement;
  final Set<String> _refSpokenThresholds = {};
  bool _refAutoStartRequested = false;

  /// 4.1 — Pre-start preview: quando in modalità guidata, mostra al volo
  /// distanza/dislivello/ETA prima di avviare la registrazione, così
  /// l'utente può decidere se ha tempo. Una volta tappato "Inizia" la
  /// flag diventa false e la registrazione parte normalmente.
  bool _showPreStartPreview = true;

  // ── POI voice announcement (guided) ─────────────────────────────────
  /// POI associati al reference (trail o track) caricati al start della
  /// modalità guidata. Filtrati solo "announceable" secondo le pref.
  List<TrailPoi> _guidedPois = const [];
  /// Set<"poiId_threshold"> dei POI già annunciati per evitare ripetizioni.
  final Set<String> _poiAnnouncedThresholds = {};

  // ── Re-routing off-trail ────────────────────────────────────────────
  /// Quando l'utente esce dal percorso, segniamo l'istante. Se dopo 30s
  /// è ancora fuori, scatta il re-routing automatico.
  DateTime? _offTrailSince;
  bool _rerouting = false;
  /// Polyline di rientro (calcolata via ORS o fallback linea retta).
  List<LatLng>? _rerouteBackPolyline;
  /// True se la polyline è un fallback bussola (non un path calcolato).
  bool _rerouteIsFallback = false;
  RoutingService? _routingSvc;

  bool get _isGuided => widget.reference != null;

  // ── Lifeline ────────────────────────────────────────────────────────
  final EmergencyContactsRepository _contactsRepo = EmergencyContactsRepository();
  final LifelineService _lifeline = LifelineService();
  List<EmergencyContact> _emergencyContacts = const [];
  String? _lifelineTemplate;
  bool _lifelineToggleOn = false; // intent utente (toggle nel pulsante start)
  bool _lifelineActive = false;   // effettivamente attiva durante recording

  // ── UX overlay compatto ─────────────────────────────────────────────
  /// Se true lo stats header mostra tutti i 6 valori; se false solo i
  /// primi 3 (distanza, tempo, D+) su una riga singola. Tap sullo header
  /// alterna i due stati.
  bool _statsExpanded = false;
  /// Analogo per la card unificata guida+lifeline.
  bool _overlayExpanded = false;

  /// 1.D4 — Auto-hide HUD dopo N secondi di inattività. Quando false lo
  /// stats header si nasconde (AnimatedOpacity 0 + IgnorePointer), e
  /// resta solo un chip mini in alto a sinistra come "shortcut" per
  /// rimostrarlo. Tap mappa, tap chip, o cambio stato recording lo
  /// riattivano.
  bool _hudVisible = true;
  Timer? _hudHideTimer;
  bool _lastIsRecording = false;
  bool _lastIsPaused = false;
  bool _lastIsIdle = true;

  StreamSubscription<LifelineState>? _lifelineSub;
  bool _inactivityDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _trackingBloc = TrackingBloc(LocationService());
    _trackingBloc.addListener(_onTrackingUpdate);
    // Ruota la mappa secondo heading (se l'utente ha attivato heading-up).
    HeadingService().addListener(_onHeadingChanged);
    HeadingService().loadPreference();
    if (widget.initialActivityType != null) {
      _selectedActivity = widget.initialActivityType!;
    }
    if (_isGuided) {
      _initGuidedMode();
    } else {
      _checkForBackup();
    }
    _startBatteryMonitoring();
    _initUserPosition();
    _loadQuickStats();
    _loadLifelineConfig();
    _subscribeLifelineEvents();
    if (!_isGuided) _checkFirstRecordTutorial();
  }

  /// Se l'utente non ha mai visto il tutorial di primo avvio, lo segnala
  /// per essere mostrato come overlay sopra il pulsante REC.
  Future<void> _checkFirstRecordTutorial() async {
    final shown = await FeatureTipsService().isTipShown(AppTips.firstTrack);
    if (!mounted || shown) return;
    // Piccolo delay per dare tempo al layout di assestarsi.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _showRecTutorial = true);
  }

  Future<void> _dismissRecTutorial() async {
    if (!_showRecTutorial) return;
    setState(() => _showRecTutorial = false);
    await FeatureTipsService().markTipShown(AppTips.firstTrack);
  }

  /// Modalità guidata: pre-carica POI + voce + servizio routing, ma NON
  /// avvia automaticamente la registrazione. L'avvio reale è demandato a
  /// [_startGuidedRecording] chiamato dal pulsante "Inizia" nel
  /// [PreStartPreviewSheet] (4.1).
  ///
  /// NON fa check backup perché ci si aspetta che l'utente abbia appena
  /// avviato il follow e la pagina entri subito in registrazione.
  Future<void> _initGuidedMode() async {
    final ref = widget.reference!;
    debugPrint('[RecordPage] Modalità guidata: ${ref.source.name} - ${ref.name}');

    // Servizio routing per re-route automatico off-trail (1.4).
    _routingSvc = RoutingService(proxyBaseUrl: AppConfig.orsProxyBaseUrl);

    // Carica POI del trail/track di riferimento + preferenze voce.
    // Non blocca l'avvio (fire-and-forget).
    unawaited(_loadGuidedPois());

    // Inizializza TTS in anticipo così, quando l'utente tappa "Inizia",
    // possiamo parlare immediatamente senza freeze percepibile.
    _voice = VoiceGuidanceService();
    await _voice!.init();
  }

  /// Chiamato quando l'utente tappa "Inizia" nel pre-start preview sheet.
  /// Avvia Lifeline (se richiesto), la registrazione e l'eventuale
  /// messaggio vocale di benvenuto.
  Future<void> _startGuidedRecording() async {
    if (_refAutoStartRequested) return;
    final ref = widget.reference!;

    // ─── Lifeline: attivazione opzionale prima dello start ────────────
    // Replica della logica di [_onStartPressed] ma adattata al flusso
    // guidato. Se l'utente ha tappato il toggle Lifeline e ha contatti
    // configurati, mostriamo disclaimer (al primo uso) e avviamo il
    // servizio prima di partire con la registrazione.
    if (_lifelineToggleOn && _emergencyContacts.isNotEmpty) {
      final accepted = await _ensureLifelineDisclaimerAccepted();
      if (!accepted) return; // utente ha rifiutato: non parte nulla
      try {
        final userName = FirebaseAuth.instance.currentUser?.displayName ??
            FirebaseAuth.instance.currentUser?.email ??
            'Utente TrailShare';
        final drafts = await _lifeline.start(
          contacts: _emergencyContacts,
          userName: userName,
          activityName: _selectedActivity.displayName,
          referenceName: ref.name,
          customTemplate: _lifelineTemplate,
        );
        _lifelineActive = drafts.isNotEmpty;
        if (drafts.isNotEmpty && mounted) {
          await _showLifelineDraftsDialog(drafts);
        }
      } catch (e) {
        debugPrint('[RecordPage] Errore avvio Lifeline (guided): $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.lifelineCannotStart(e.toString())),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _showPreStartPreview = false;
      _refAutoStartRequested = true;
    });

    // Messaggio vocale di benvenuto (solo per planner con turn-by-turn).
    if (_voice != null) {
      if (ref.isPlanner && ref.hasTurnByTurn) {
        final next = ref.steps.length > 1 ? ref.steps[1] : null;
        final welcome = next != null
            ? 'Registrazione avviata. Prima manovra: ${next.maneuver.italianAction.toLowerCase()}'
            : 'Registrazione avviata lungo il percorso pianificato';
        unawaited(_voice!.speak(welcome));
      } else {
        unawaited(_voice!.speak('Registrazione avviata. Seguo la traccia ${ref.name}.'));
      }
    }

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _trackingBloc.startRecording(activityType: _selectedActivity);
    });
  }

  /// Subscribe a `LifelineService.stateStream` per mostrare il dialog
  /// di inattività quando il servizio lo richiede.
  void _subscribeLifelineEvents() {
    _lifelineSub?.cancel();
    _lifelineSub = _lifeline.stateStream.listen((s) {
      if (!mounted) return;
      if (s.needsInactivityConfirmation && !_inactivityDialogShown) {
        _inactivityDialogShown = true;
        _showInactivityConfirmationDialog();
      } else if (!s.needsInactivityConfirmation) {
        _inactivityDialogShown = false;
      }
    });
  }

  /// Carica contatti emergenza + template Lifeline dell'utente.
  /// Non blocca il flusso se fallisce: Lifeline resta semplicemente
  /// non disponibile (toggle nascosto).
  Future<void> _loadLifelineConfig() async {
    try {
      final contacts = await _contactsRepo.getContacts();
      final template = await _contactsRepo.getMessageTemplate();
      if (!mounted) return;
      setState(() {
        _emergencyContacts = contacts;
        _lifelineTemplate = template;
      });
    } catch (e) {
      debugPrint('[RecordPage] Errore load lifeline: $e');
    }
  }

  /// Centra la mappa sulla posizione utente all'avvio
  Future<void> _initUserPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (!mounted) return;
      setState(() {
        _userPosition = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_userPosition!, 16);
    } catch (e) {
      debugPrint('[RecordPage] Errore posizione iniziale: $e');
    }
  }

  /// Carica statistiche rapide per la schermata idle
  Future<void> _loadQuickStats() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      // Ultima traccia
      final result = await _repository.getMyTracksPaginated(limit: 1);
      if (result.tracks.isNotEmpty && mounted) {
        setState(() => _lastTrack = result.tracks.first);
      }

      // Stats settimanali
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final weekStart = DateTime(monday.year, monday.month, monday.day);

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tracks')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
          .get();

      if (!mounted) return;

      double dist = 0;
      double elev = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        dist += (data['distance'] as num?)?.toDouble() ?? 0;
        elev += (data['elevationGain'] as num?)?.toDouble() ?? 0;
      }

      setState(() {
        _weeklyDistanceKm = dist / 1000;
        _weeklyElevation = elev;
        _weeklyTracks = snapshot.docs.length;
      });
    } catch (e) {
      debugPrint('[RecordPage] Errore quick stats: $e');
    }
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
        title: Row(children: [const Icon(Icons.restore, color: AppColors.warning), const SizedBox(width: 8), Text(context.l10n.recordingFound)]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.unsavedRecordingFound),
            const SizedBox(height: 12),
            _buildBackupInfo(backup),
            const SizedBox(height: 12),
            Text(context.l10n.wantToRecover, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.deleteLabel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: Text(context.l10n.recover),
          ),
        ],
      ),
    );
    
    if (shouldRestore == true) {
      await _restoreFromBackup(backup);
    } else {
      await _persistence.clearState();
    }
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
          Text(context.l10n.gpsPointsCount(backup.points.length)),
          Text('📏 ${(distance / 1000).toStringAsFixed(2)} km'),
          Text('⏱️ ${duration.inHours > 0 ? "${duration.inHours}h ${duration.inMinutes.remainder(60)}m" : "${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s"}'),
          if (backup.photos.isNotEmpty) Text(context.l10n.photosCount(backup.photos.length)),
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
          SnackBar(content: Text(context.l10n.recoveredGpsPoints(backup.points.length)), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.errorWithDetails(e.toString())), backgroundColor: AppColors.danger));
    } finally {
      setState(() => _isRestoringState = false);
    }
  }

  void _onHeadingChanged() {
    if (!mounted) return;
    final service = HeadingService();
    if (!service.isHeadingUp) {
      // Se l'utente ha appena disattivato heading-up, riporta a nord.
      if (_mapController.camera.rotation != 0) {
        _mapController.rotate(0);
      }
      return;
    }
    final h = service.currentHeading;
    if (h == null) return;
    // flutter_map ruota il viewport: per avere "heading in alto" bisogna
    // ruotare di -heading (senso antiorario rispetto al nord fisico).
    _mapController.rotate(-h);
  }

  /// Stato precedente per detection delle transizioni (usato da 4.3).
  bool _wasAutoPaused = false;

  void _onTrackingUpdate() {
    if (_followUser && _trackingBloc.state.points.isNotEmpty) {
      final lastPoint = _trackingBloc.state.points.last;
      _mapController.move(LatLng(lastPoint.latitude, lastPoint.longitude), _mapController.camera.zoom);
      // Aggiorna la sorgente GPS del HeadingService (usa velocita + heading
      // del punto appena registrato; il service fa low-pass + fallback
      // bussola internamente).
      HeadingService().updateFromSpeedAndHeading(
        speed: lastPoint.speed,
        heading: lastPoint.heading,
      );
    }
    final state = _trackingBloc.state;
    if (!state.isIdle && state.points.length % 5 == 0) _saveStateToBackup();
    if (_isGuided && state.points.isNotEmpty) {
      _updateGuidedState(state.points.last);
    }
    // Mirror lo stato macro nel servizio globale così il bottom nav button
    // può animarsi (pulsare quando recording, pausa statica quando paused).
    if (state.isRecording) {
      RecordingStatusService().markRecording();
    } else if (state.isPaused) {
      RecordingStatusService().markPaused();
    } else {
      RecordingStatusService().markIdle();
    }

    // 4.3 — Notifica utente quando l'auto-pausa scatta o si auto-risolve.
    final isAutoNow = _trackingBloc.isAutoPaused;
    if (isAutoNow && !_wasAutoPaused) {
      _showSnackBar(context.l10n.autoPauseTriggered);
    } else if (!isAutoNow && _wasAutoPaused && state.isRecording) {
      _showSnackBar(context.l10n.autoPauseResumed);
    }
    _wasAutoPaused = isAutoNow;

    // 1.D4 — su cambio stato recording (start, pause, resume, idle) rimostra
    // l'HUD: l'utente deve confermare visivamente la transizione.
    if (state.isRecording != _lastIsRecording ||
        state.isPaused != _lastIsPaused ||
        state.isIdle != _lastIsIdle) {
      _lastIsRecording = state.isRecording;
      _lastIsPaused = state.isPaused;
      _lastIsIdle = state.isIdle;
      _bumpHudActivity();
    }

    setState(() {});
  }

  /// Aggiorna stato guidato: avanza indice sulla polyline di riferimento,
  /// calcola distanza residua, distanza dal trail, step corrente (se planner)
  /// e gestisce alert/voice.
  void _updateGuidedState(TrackPoint p) {
    final ref = widget.reference;
    if (ref == null || _refArrived) return;
    if (ref.polyline.length < 2) return;

    final user = LatLng(p.latitude, p.longitude);

    // Indice utente sul polyline (monotono crescente)
    final newIndex = NavigationService.findNearestPointIndex(
      ref.polyline,
      user,
      minIndex: _refUserIndex,
    );

    // Distanza residua totale
    final remaining =
        NavigationService.remainingDistanceTotal(ref.polyline, newIndex, user);

    // Distanza dal percorso
    final distFromRoute =
        NavigationService.distanceToPolyline(ref.polyline, user);
    final offTrail = distFromRoute > 50;

    // Step corrente (solo se planner con turn-by-turn)
    NavigationStep? curStep;
    NavigationStep? nextStep;
    double distToTurn = 0;
    if (ref.hasTurnByTurn) {
      curStep = NavigationService.currentStep(ref.steps, newIndex);
      nextStep = NavigationService.nextStep(ref.steps, curStep);
      if (curStep != null) {
        distToTurn = NavigationService.remainingDistanceInStep(
            ref.polyline, newIndex, user, curStep);
      }
    }

    _refUserIndex = newIndex;
    _refCurrentStep = curStep;
    _refNextStep = nextStep;
    _refDistanceToNextTurn = distToTurn;
    _refRemainingDistance = remaining;
    _refDistanceFromTrail = distFromRoute;
    final wasOffTrail = _refOffTrail;
    _refOffTrail = offTrail;

    // Epic 4.1 — ETA dinamico basato su velocità corrente.
    // Stima del dislivello residuo: proporzionale alla quota di
    // percorso ancora da fare (totalEle × remaining/total). È
    // un'approssimazione, ma evita di scorrere tutto il profilo ad
    // ogni update.
    {
      final totalDist = ref.totalDistance ?? 0;
      final totalEle = ref.totalElevationGain ?? 0;
      final remainingEle = (totalDist > 0)
          ? totalEle * (remaining / totalDist).clamp(0.0, 1.0)
          : 0.0;
      // Velocità corrente in km/h da m/s dell'ultimo punto GPS.
      final rawSpeed = p.speed;
      final speedMs = (rawSpeed != null && rawSpeed.isFinite && rawSpeed >= 0)
          ? rawSpeed
          : 0.0;
      final speedKmh = speedMs * 3.6;
      _refDynamicEta = EtaEstimator.estimateDynamic(
        remainingDistanceMeters: remaining,
        remainingElevationGainMeters: remainingEle,
        activityType: _selectedActivity,
        currentSpeedKmh: speedKmh,
      );
    }

    // 1.D4 — riapri l'HUD sui trigger guida critici (off-trail, arrivo)
    if (offTrail != wasOffTrail) _bumpHudActivity();

    // Arrivo → trigger save dialog automatico
    if (remaining < 30 && !_refArrived) {
      _refArrived = true;
      _bumpHudActivity();
      _voice?.speak('Sei arrivato a destinazione. Salvataggio registrazione.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isSaving) _showSaveDialog();
      });
      return;
    }

    // Gestione off-trail: tracciamento tempo + re-routing automatico
    if (offTrail) {
      final now = DateTime.now();
      _offTrailSince ??= now;
      // Alert vocale (debounce 10s)
      if (_refLastOffTrailAnnouncement == null ||
          now.difference(_refLastOffTrailAnnouncement!).inSeconds > 10) {
        _voice?.speak('Attenzione, sei fuori percorso');
        _refLastOffTrailAnnouncement = now;
      }
      // Re-routing: se fuori da >30s e non ho ancora un piano di rientro
      final offElapsed = now.difference(_offTrailSince!);
      if (offElapsed.inSeconds >= 30 &&
          !_rerouting &&
          _rerouteBackPolyline == null) {
        _triggerReroute(user, ref);
      }
      return;
    } else {
      // Rientrato nel percorso: reset stato re-routing
      if (_rerouteBackPolyline != null || _offTrailSince != null) {
        _voice?.speak('Sei rientrato nel percorso');
        _rerouteBackPolyline = null;
        _rerouteIsFallback = false;
        _offTrailSince = null;
      }
    }

    // Voice turn-by-turn (solo planner)
    if (curStep != null) {
      final step = curStep; // non-null locale per flow analysis
      void trySpeak(double threshold, String key) {
        final lookup = '${step.index}_$key';
        if (distToTurn <= threshold && !_refSpokenThresholds.contains(lookup)) {
          _refSpokenThresholds.add(lookup);
          _voice?.speak(step.maneuver.instructionWithDistance(distToTurn));
        }
      }

      if (distToTurn > 500) {
        _refSpokenThresholds
            .removeWhere((k) => k.startsWith('${step.index}_'));
      } else {
        trySpeak(500, '500');
        if (distToTurn <= 200) trySpeak(200, '200');
        if (distToTurn <= 50) trySpeak(50, '50');
      }
    }

    // Annunci POI prossimi (water/shelter/danger/food/viewpoint)
    _maybeAnnouncePois(user);
  }

  /// Scan dei POI caricati e annuncio alle soglie 500/200/50 m.
  /// Ogni POI × soglia è annunciato una sola volta (tracked in
  /// _poiAnnouncedThresholds).
  void _maybeAnnouncePois(LatLng user) {
    if (_guidedPois.isEmpty) return;
    const dist = Distance();
    for (final poi in _guidedPois) {
      final d = dist.as(LengthUnit.Meter, user,
          LatLng(poi.latitude, poi.longitude));
      // Soglia scegliamo in base alla distanza (prima più grande che matcha)
      int? threshold;
      if (d <= 50) {
        threshold = 50;
      } else if (d <= 200) {
        threshold = 200;
      } else if (d <= 500) {
        threshold = 500;
      }
      if (threshold == null) continue;

      final key = '${poi.id}_$threshold';
      if (_poiAnnouncedThresholds.contains(key)) continue;
      // Assicura che non siano stati annunciati i livelli superiori già (es.
      // se salta direttamente a <50m significa che l'utente è arrivato
      // velocemente — marchiamo anche 500 e 200 per coerenza)
      _poiAnnouncedThresholds.add(key);
      if (threshold == 50) {
        _poiAnnouncedThresholds.add('${poi.id}_200');
        _poiAnnouncedThresholds.add('${poi.id}_500');
      } else if (threshold == 200) {
        _poiAnnouncedThresholds.add('${poi.id}_500');
      }

      _speakPoiAnnouncement(poi, threshold, d.round());
    }
  }

  void _speakPoiAnnouncement(TrailPoi poi, int threshold, int distMeters) {
    final typeName = poi.type.displayName.toLowerCase();
    String phrase;
    if (threshold == 500) {
      phrase = 'Tra circa 500 metri, $typeName: ${poi.title}';
    } else if (threshold == 200) {
      phrase = 'Tra 200 metri, $typeName: ${poi.title}';
    } else {
      phrase = '$typeName ${poi.title} raggiunta';
    }
    _voice?.speak(phrase);
    debugPrint('[RecordPage] POI voice: $phrase (${distMeters}m)');
  }

  void _startBatteryMonitoring() {
    _batterySubscription = _battery.onBatteryStateChanged.listen((_) async {
      await _checkBatteryLevel();
    });
    // Check iniziale
    unawaited(_checkBatteryLevel());
  }

  Future<void> _checkBatteryLevel() async {
    if (!mounted) return;
    final state = _trackingBloc.state;
    if (state.isIdle) return; // Non in registrazione
    
    try {
      final level = await _battery.batteryLevel;
      debugPrint('[RecordPage] Batteria: $level%');
      
      // Suggerimento battery saver a 30% (se non già attivo)
      if (level <= 30 && !_batterySaverOn && !_batterySaverSuggestionShown) {
        _batterySaverSuggestionShown = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Batteria al 30%. Attivare il risparmio energetico?',
              ),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'Attiva',
                textColor: Colors.white,
                onPressed: () => _toggleBatterySaver(true),
              ),
            ),
          );
        }
      }

      // Warning a 15%
      if (level <= 15 && !_lowBatteryWarningShown) {
        _lowBatteryWarningShown = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.lowBatteryWarning),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
      
      // Salvataggio automatico a 5%
      if (level <= 5 && state.points.isNotEmpty) {
        debugPrint('[RecordPage] Batteria critica! Salvataggio automatico...');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.criticalBatteryWarning),
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
      if (!mounted) return;
      final trackToSave = track.copyWith(name: '$activityName ${now.day}/${now.month}/${now.year} ${context.l10n.autoSaved}');
      
      await _repository.saveTrack(trackToSave);
      await _trackingBloc.stopForegroundService();
      await _persistence.clearState();
      await LiveTrackService().stop();
      _photos.clear();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.trackAutoSaved), backgroundColor: AppColors.success),
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
    HeadingService().removeListener(_onHeadingChanged);
    // Alla chiusura della pagina ripristina north-up per evitare che altre
    // mappe (Discover, Community) si aprano ruotate.
    if (_mapController.camera.rotation != 0) {
      _mapController.rotate(0);
    }
    _batterySubscription?.cancel();
    _lifelineSub?.cancel();
    _hudHideTimer?.cancel();
    _voice?.dispose();
    _trackingBloc.dispose();
    super.dispose();
  }

  // ─── 1.D4 Auto-hide HUD helpers ─────────────────────────────────────
  /// Re-mostra l'HUD e (re)avvia il timer di auto-hide. Da chiamare su
  /// ogni "interazione" significativa:
  /// - gesture sulla mappa (pan/zoom)
  /// - tap sul chip mini
  /// - cambio stato recording (start/pause/resume/arrivo)
  /// - eventi guida (off-trail, arrivato)
  void _bumpHudActivity() {
    if (!HudPrefsService().enabled) {
      // Se l'utente ha disattivato l'auto-hide nelle settings, l'HUD
      // resta sempre visibile.
      if (!_hudVisible && mounted) setState(() => _hudVisible = true);
      return;
    }
    final state = _trackingBloc.state;
    if (state.isIdle) return; // HUD non esiste in idle
    if (!_hudVisible && mounted) {
      setState(() => _hudVisible = true);
    }
    _hudHideTimer?.cancel();
    _hudHideTimer = Timer(
      Duration(seconds: HudPrefsService().seconds),
      _hideHudIfRecording,
    );
  }

  void _hideHudIfRecording() {
    if (!mounted) return;
    final state = _trackingBloc.state;
    // Non nasconde mai in pausa o off-trail: lo stato deve restare ben
    // visibile (l'utente potrebbe non essersi accorto della pausa).
    if (!state.isRecording) return;
    if (_refOffTrail || _refArrived) return;
    setState(() => _hudVisible = false);
  }

  /// Banner informativo per modalità guidata in versione compatta con
  /// tap-to-expand. Include chip Lifeline se attiva (merge con il vecchio
  /// banner Lifeline separato).
  ///
  /// Stati:
  /// - Normale: 1 riga con icona + nome trail + chip attività + voce + chip
  ///   lifeline (se attiva) + chevron expand
  /// - Espanso (tap): +1 riga con prossima manovra o progress
  /// - Off-trail: sempre espanso + banner rosso (priorità sicurezza)
  Widget _buildGuidedBanner() {
    final ref = widget.reference!;
    final state = _trackingBloc.state;

    // Posizione: sotto lo stats header (compact ~55px, expanded ~160px)
    final headerHeight = _statsExpanded ? 160.0 : 55.0;
    final topOffset = state.isIdle
        ? MediaQuery.of(context).padding.top + 12
        : MediaQuery.of(context).padding.top + headerHeight + 8;

    // Auto-expand quando serve attenzione: off-trail (sicurezza) o
    // manovra imminente (<300m da una svolta).
    final imminentTurn = ref.hasTurnByTurn &&
        _refCurrentStep != null &&
        _refDistanceToNextTurn > 0 &&
        _refDistanceToNextTurn < 300;
    final expanded = _overlayExpanded || _refOffTrail || imminentTurn;

    return Positioned(
      top: topOffset,
      left: 12,
      right: 12,
      child: GestureDetector(
        onTap: _refOffTrail
            ? null
            : () => setState(() => _overlayExpanded = !_overlayExpanded),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          color: _refOffTrail ? AppColors.danger : Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Riga compatta sempre visibile
                _buildGuidedCompactRow(ref),
                // Se expanded: contenuto dinamico
                if (expanded) ...[
                  const SizedBox(height: 6),
                  if (_refOffTrail)
                    _buildGuidedOffTrailRow()
                  else if (ref.hasTurnByTurn && _refCurrentStep != null)
                    _buildGuidedTurnRow()
                  else
                    _buildGuidedProgressRow(),
                ],
                // Chip Lifeline (piccola, in fondo) se attiva
                if (_lifelineActive) ...[
                  const SizedBox(height: 6),
                  _buildLifelineChipInline(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Riga singola compatta: icona + nome + chip attività + voce + chevron.
  Widget _buildGuidedCompactRow(RecordingReference ref) {
    final textColor = _refOffTrail ? Colors.white : context.textPrimary;
    final accent = _refOffTrail ? Colors.white : AppColors.info;

    return Row(
      children: [
        Icon(
          ref.isPlanner ? Icons.navigation : Icons.route,
          size: 18,
          color: accent,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            // Se off-trail e non espanso: mostra l'alert in riga
            _refOffTrail
                ? 'Fuori percorso · ${_refDistanceFromTrail.round()} m'
                : ref.name,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Chip attività (tap per cambiarla)
        InkWell(
          onTap: _showActivityPickerGuided,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: _refOffTrail
                  ? Colors.white.withValues(alpha: 0.2)
                  : AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_selectedActivity.icon,
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 3),
                Text(
                  _selectedActivity.displayName,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accent),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Toggle voce
        InkWell(
          onTap: () {
            setState(() {
              if (_voice != null) _voice!.enabled = !_voice!.enabled;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              (_voice?.enabled ?? true) ? Icons.volume_up : Icons.volume_off,
              size: 18,
              color: accent,
            ),
          ),
        ),
        // Chevron expand (solo se non off-trail: off-trail è sempre expanded)
        if (!_refOffTrail)
          Icon(
            _overlayExpanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: accent,
          ),
      ],
    );
  }

  /// Chip in-line dentro il banner guidato quando Lifeline è attiva.
  /// Tap → riapre il dialog invio messaggi.
  Widget _buildLifelineChipInline() {
    return InkWell(
      onTap: _resendDrafts,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _refOffTrail
              ? Colors.white.withValues(alpha: 0.15)
              : AppColors.info.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield,
                size: 13, color: _refOffTrail ? Colors.white : AppColors.info),
            const SizedBox(width: 4),
            Text(
              'Lifeline · ${_emergencyContacts.length} contatti',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _refOffTrail ? Colors.white : AppColors.info,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Re-invia',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.underline,
                color: _refOffTrail ? Colors.white : AppColors.info,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidedOffTrailRow() {
    return Row(
      children: [
        const Icon(Icons.warning_amber, color: Colors.white, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sei fuori percorso',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                '${_refDistanceFromTrail.round()} m dalla traccia',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuidedTurnRow() {
    final step = _refCurrentStep!;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(step.maneuver.icon, size: 28, color: AppColors.info),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.maneuver.italianAction,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Tra ${_formatDistanceMeters(_refDistanceToNextTurn)}',
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                'Residuo: ${_formatDistanceMeters(_refRemainingDistance)}',
                style: TextStyle(fontSize: 11, color: context.textMuted),
              ),
              if (_refNextStep != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Poi ${_refNextStep!.maneuver.italianAction.toLowerCase()}',
                  style: TextStyle(fontSize: 11, color: context.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuidedProgressRow() {
    // Epic 4.1 — ETA dinamico + orario d'arrivo se disponibile.
    final eta = _refDynamicEta;
    String? etaValue;
    String? etaLabel;
    if (eta != null && eta > Duration.zero) {
      etaValue = EtaEstimator.formatArrivalClock(DateTime.now(), eta);
      etaLabel = 'Arrivo • ${EtaEstimator.formatCompact(eta)}';
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _guidedStat(
          Icons.straighten,
          _formatDistanceMeters(_refRemainingDistance),
          'Residuo',
        ),
        _guidedStat(
          Icons.near_me,
          '${_refDistanceFromTrail.round()} m',
          'Dal percorso',
        ),
        if (etaValue != null && etaLabel != null)
          _guidedStat(Icons.schedule, etaValue, etaLabel),
      ],
    );
  }

  Widget _guidedStat(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: context.textMuted),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        Text(label, style: TextStyle(fontSize: 10, color: context.textMuted)),
      ],
    );
  }

  String _formatDistanceMeters(double m) {
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  /// Carica i POI associati al trail/track di riferimento e le preferenze
  /// utente sulla voce. Solo POI di tipo "announceable" (per preferenza
  /// utente, default su tipi critici) vengono mantenuti.
  ///
  /// Il reference può essere:
  /// - `isPlanner`: nessun trailId/trackId, POI non caricati
  /// - `isTrail`: cerca POI con relatedTrailId = id del trail (non
  ///   abbiamo l'id nel RecordingReference, skippato per MVP)
  ///
  /// NOTA: RecordingReference attualmente non espone trailId/trackId —
  /// implementato in questo step solo per community track dove abbiamo
  /// il nome del riferimento come hint. Sarà esteso quando aggiungeremo
  /// i campi id al reference.
  Future<void> _loadGuidedPois() async {
    final ref = widget.reference;
    if (ref == null) return;

    // Pre-carica preferenze voce
    await PoiVoicePrefs().load();

    // MVP: cerchiamo POI a raggio ampio intorno al centro della polyline
    // di riferimento, filtrando poi sul tipo in base alle preferenze.
    if (ref.polyline.isEmpty) return;
    final center = ref.polyline[ref.polyline.length ~/ 2];

    final repo = PoiRepository();
    final pois = await repo.getPoisNear(
      centerLat: center.latitude,
      centerLng: center.longitude,
      radiusMeters: 15000, // 15km raggio per copertura sicura
      limit: 200,
    );

    if (!mounted) return;
    // Tieni solo quelli che l'utente vuole annunciati
    final filtered = pois
        .where((p) => PoiVoicePrefs().isAnnounceableSync(p.type))
        .toList();
    setState(() => _guidedPois = filtered);
    debugPrint(
        '[RecordPage] Guided POI caricati: ${pois.length}, announceable: ${filtered.length}');
  }

  /// Avvia re-routing automatico dal punto utente al punto più vicino
  /// sulla polyline di riferimento. Se ORS fallisce, fallback bussola +
  /// linea retta (opzione A concordata).
  Future<void> _triggerReroute(LatLng user, RecordingReference ref) async {
    if (_rerouting) return;
    _rerouting = true;
    debugPrint('[RecordPage] Trigger re-routing');
    _voice?.speak('Calcolo il percorso di rientro');

    // Trova il punto più vicino sulla polyline di riferimento
    int nearestIdx = 0;
    double nearestDist = double.infinity;
    for (var i = 0; i < ref.polyline.length; i++) {
      final d = const Distance().as(LengthUnit.Meter, user, ref.polyline[i]);
      if (d < nearestDist) {
        nearestDist = d;
        nearestIdx = i;
      }
    }
    final target = ref.polyline[nearestIdx];

    // Mappa activity → profilo ORS (solo hiking/cycling supportati)
    final profile = _isCyclingActivity(_selectedActivity)
        ? RoutingProfile.cycling
        : RoutingProfile.hiking;

    List<LatLng>? routeBack;
    try {
      final result = await _routingSvc?.calculateRoute(
        [user, target],
        profile: profile,
      );
      if (result != null && result.points.length >= 2) {
        routeBack = result.points.map((p) => p.latLng).toList();
      }
    } catch (e) {
      debugPrint('[RecordPage] Errore reroute ORS: $e');
    }

    if (!mounted) {
      _rerouting = false;
      return;
    }

    if (routeBack != null) {
      // Successo ORS
      setState(() {
        _rerouteBackPolyline = routeBack;
        _rerouteIsFallback = false;
        _rerouting = false;
      });
      _voice?.speak('Segui la linea arancione per tornare al percorso');
    } else {
      // Fallback opzione A: linea retta + direzione bussola
      final compass = _compassDirection(user, target);
      setState(() {
        _rerouteBackPolyline = [user, target];
        _rerouteIsFallback = true;
        _rerouting = false;
      });
      _voice?.speak(
        'Impossibile calcolare il rientro. Il punto più vicino è a ${nearestDist.round()} metri in direzione $compass',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rotta di rientro non disponibile. Direzione $compass, distanza ${nearestDist.round()} m',
            ),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Mappa ActivityType → profilo ORS. ORS supporta solo hiking/cycling,
  /// quindi raggruppiamo: tutte le bici → cycling, resto → hiking.
  bool _isCyclingActivity(ActivityType t) {
    return t == ActivityType.cycling ||
        t == ActivityType.mountainBiking ||
        t == ActivityType.gravelBiking ||
        t == ActivityType.eBike ||
        t == ActivityType.eMountainBike;
  }

  /// Ritorna direzione cardinale (N/NE/E/...) da [from] a [to].
  String _compassDirection(LatLng from, LatLng to) {
    final dLng = (to.longitude - from.longitude) *
        math.cos((from.latitude + to.latitude) / 2 * math.pi / 180);
    final dLat = to.latitude - from.latitude;
    // Bearing in gradi 0-360 (0 = Nord)
    double bearing = (math.atan2(dLng, dLat) * 180 / math.pi) % 360;
    if (bearing < 0) bearing += 360;
    const labels = [
      'Nord',
      'Nord-Est',
      'Est',
      'Sud-Est',
      'Sud',
      'Sud-Ovest',
      'Ovest',
      'Nord-Ovest',
    ];
    final idx = ((bearing + 22.5) % 360 / 45).floor();
    return labels[idx];
  }

  /// Attiva/disattiva la modalità battery saver durante la registrazione.
  /// Riduce frequenza GPS (10s vs 2s) e precisione (medium vs best), con
  /// un risparmio batteria stimato del 30-40%. Il tracking non si ferma,
  /// il service si riavvia con le nuove settings (piccolo gap).
  Future<void> _toggleBatterySaver([bool? force]) async {
    final next = force ?? !_batterySaverOn;
    await LocationService().setBatterySaverMode(next);
    if (!mounted) return;
    setState(() => _batterySaverOn = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next
            ? 'Risparmio energetico attivato'
            : 'Risparmio energetico disattivato'),
        backgroundColor: next ? AppColors.success : context.textMuted,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 6.1 — Pulsante per aprire il Mountain Finder AR. Disponibile sia in
  /// idle (per esplorare le cime intorno) sia durante registrazione.
  Widget _buildMountainFinderButton() {
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: Colors.white,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MountainFinderPage()),
          );
        },
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.terrain,
            color: Color(0xFF6D4C41),
            size: 22,
          ),
        ),
      ),
    );
  }

  /// Chip battery saver: posizionato in basso-sinistra durante recording.
  Widget _buildBatterySaverButton() {
    return Positioned(
      left: 12,
      bottom: 180, // sopra controls panel
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(20),
        color: _batterySaverOn
            ? AppColors.success
            : Colors.white.withValues(alpha: 0.95),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _toggleBatterySaver(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _batterySaverOn
                      ? Icons.battery_saver
                      : Icons.battery_std_outlined,
                  size: 16,
                  color: _batterySaverOn
                      ? Colors.white
                      : context.textPrimary,
                ),
                const SizedBox(width: 5),
                Text(
                  _batterySaverOn ? 'Risparmio' : 'Eco',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _batterySaverOn
                        ? Colors.white
                        : context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pulsante SOS sempre accessibile durante la registrazione.
  ///
  /// UX pensata per emergenza: grande, rosso, in alto a destra (dove
  /// l'utente lo trova anche sotto stress). Long-press 1.5s per
  /// attivarlo (evita tap accidentali con l'indice mentre cammina/
  /// corre). Tap breve mostra un hint.
  /// Calcola l'offset verticale a cui posizionare i controlli top-right
  /// (SOS + compass toggle): sotto stats header + banner vari.
  double _topRightControlsOffset() {
    double topOffset = MediaQuery.of(context).padding.top;
    topOffset += _statsExpanded ? 165.0 : 60.0;
    if (_isGuided) {
      final guidedExpanded = _overlayExpanded || _refOffTrail;
      final lifelineExtra = _lifelineActive ? 28.0 : 0.0;
      topOffset += (guidedExpanded ? 150.0 : 55.0) + lifelineExtra + 8;
    } else if (_lifelineActive) {
      topOffset += 38.0 + 8;
    } else {
      topOffset += 8;
    }
    return topOffset;
  }

  Widget _buildSosButton() {
    return Positioned(
      top: _topRightControlsOffset(),
      right: 8,
      child: _SosFab(
        onTriggered: _handleSosActivated,
        onShortTap: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tieni premuto 1,5 secondi per attivare SOS'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  /// Chiamato quando l'utente ha completato il long-press sul SOS.
  /// Mostra dialog di scelta tra "manda SOS contatti" / "chiama 112" /
  /// "annulla". Vibra per conferma.
  Future<void> _handleSosActivated() async {
    HapticFeedback.heavyImpact();
    if (!mounted) return;

    final choice = await showDialog<_SosChoice>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.danger,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber, color: Colors.white, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'SOS attivato',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _lifelineActive
                  ? 'Hai ${_emergencyContacts.length} contatti configurati.\nCome vuoi procedere?'
                  : 'Lifeline non è attiva.\nPuoi solo chiamare il 112.',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.4),
            ),
          ],
        ),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_lifelineActive)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, _SosChoice.sendAlert),
                    icon: const Icon(Icons.shield),
                    label: const Text('Manda SOS ai contatti'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.danger,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              if (_lifelineActive) const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, _SosChoice.call112),
                  icon: const Icon(Icons.phone),
                  label: const Text('Chiama 112'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, _SosChoice.cancel),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(context.l10n.cancel,
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (!mounted) return;
    switch (choice) {
      case _SosChoice.sendAlert:
        await _sendAlert(sosExplicit: true);
        break;
      case _SosChoice.call112:
        await _call112();
        break;
      case _SosChoice.cancel:
      case null:
        break;
    }
  }

  Future<void> _call112() async {
    final uri = Uri.parse('tel:112');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.callCannotOpen),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      debugPrint('[RecordPage] Errore chiamata 112: $e');
    }
  }

  /// Pulsante di chiusura per modalità guidata. Se la registrazione è in
  /// corso, mostra conferma per evitare uscite accidentali.
  Widget _buildGuidedCloseButton(TrackingState state) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 8,
      child: Material(
        color: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () async {
            // Se sta registrando (o è in pausa con dati), conferma.
            final hasActiveData = !state.isIdle && state.points.isNotEmpty;
            if (hasActiveData) {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Uscire dalla registrazione?'),
                  content: const Text(
                    'La registrazione in corso andrà persa se non la salvi. '
                    'Vuoi davvero uscire?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(context.l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      child: const Text('Esci'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              // Cancella registrazione per non lasciare stato zombie.
              await _trackingBloc.cancelRecording();
              await _persistence.clearState();
              await LiveTrackService().stop();
            }
            if (!mounted) return;
            Navigator.of(context).pop();
          },
          child: Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.close, color: context.textPrimary, size: 24),
          ),
        ),
      ),
    );
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
          // 1.D4 — stats header con auto-hide. Quando _hudVisible è false
          // fade-out (250ms) + IgnorePointer; un chip mini in alto a
          // sinistra resta cliccabile per riportarlo on.
          //
          // IMPORTANTE: il Positioned deve essere il figlio DIRETTO dello
          // Stack; AnimatedOpacity/IgnorePointer intermedi rompono il
          // parentData (StackParentData) e crashano in release con
          // 'ParentData is not a subtype of StackParentData'.
          if (!state.isIdle)
            Positioned(
              top: 0, left: 0, right: 0,
              child: AnimatedOpacity(
                opacity: _hudVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_hudVisible,
                  child: _buildStatsHeader(state),
                ),
              ),
            ),
          if (!state.isIdle && !_hudVisible) _buildHudReshowChip(state),
          // Banner guidato: solo durante registrazione attiva.
          // A registrazione ferma (idle) nasconderlo così l'utente vede la
          // schermata idle pulita e può uscire dalla pagina.
          if (_isGuided && !state.isIdle) _buildGuidedBanner(),
          // Lifeline banner separato SOLO quando non siamo in modalità guidata
          // (altrimenti l'info Lifeline è inclusa nel guided banner come chip).
          if (_lifelineActive && !_isGuided && !state.isIdle)
            _buildLifelineActiveBanner(),
          if (state.isIdle && !_isGuided) _buildIdleOverlay(),
          // Pulsante chiudi: solo in modalità guidata (la pagina è stata
          // aperta via Navigator.push, quindi non c'è un bottom nav che
          // permetta di tornare indietro come nello standalone).
          if (_isGuided) _buildGuidedCloseButton(state),
          // SOS button: sempre visibile durante registrazione.
          // Long-press 1.5s per attivarlo (evita tap accidentali).
          if (!state.isIdle) _buildSosButton(),
          // Battery saver toggle: sempre visibile durante registrazione.
          if (!state.isIdle) _buildBatterySaverButton(),
          // Compass toggle (north-up / heading-up): posizionato subito
          // sotto il SOS button. Quando SOS non e' visibile (state.isIdle)
          // il compass resta nello stesso posto, l'allineamento col SOS
          // button rimane quando si avvia la registrazione.
          Positioned(
            // SOS size = 56 + 10 gap
            top: _topRightControlsOffset() + 66,
            right: 12,
            child: const MapHeadingToggle(),
          ),
          // 6.1 — Mountain Finder AR (v2.0.0): pulsante per puntare il
          // telefono e riconoscere le cime. Posizionato sotto il toggle
          // bussola (bussola = 56 + 8 gap = 64 da SOS+66).
          Positioned(
            top: _topRightControlsOffset() + 66 + 64,
            right: 12,
            child: _buildMountainFinderButton(),
          ),
          // Selettore stile mappa (uniforme col resto dell'app: stili Pro
          // con gating). Sotto il Mountain Finder.
          Positioned(
            top: _topRightControlsOffset() + 66 + 64 + 64,
            right: 12,
            child: MapLayerButton(
              currentIndex: _currentMapStyle,
              onChanged: (i) => setState(() => _currentMapStyle = i),
            ),
          ),
          // Scrim sotto i controlli: protegge leggibilita del bottone REC
          // (e di eventuali toast) su tile mappa ad alta luminosita.
          const Positioned(
            left: 0, right: 0, bottom: 0,
            child: MapScrimGradient(
              direction: ScrimDirection.bottom,
              height: 140,
              maxOpacity: 0.35,
            ),
          ),
          _buildControls(state),
          if (state.errorMessage != null)
            Positioned(top: MediaQuery.of(context).padding.top + 100, left: 16, right: 16, child: _buildErrorBanner(_localizeError(state.errorMessage!))),
          if (_isSaving) Container(color: Colors.black54, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(color: Colors.white), const SizedBox(height: 16),
            Text(context.l10n.savingTrack, style: const TextStyle(color: Colors.white)),
            if (_photos.isNotEmpty) Text(context.l10n.uploadingPhotos(_photos.length), style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
          if (_isRestoringState) Container(color: Colors.black54, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(color: Colors.white), const SizedBox(height: 16),
            Text(context.l10n.restoringRecording, style: const TextStyle(color: Colors.white)),
          ])),
          // Tutorial primo record: overlay con freccia che indica il REC.
          if (_showRecTutorial && state.isIdle && !_isGuided) _buildRecTutorialOverlay(),

          // 4.1 — Pre-start preview overlay: visibile solo in modalità
          // guidata, prima dell'avvio della registrazione. Include toggle
          // Lifeline per non perdere la possibilità di attivarlo.
          if (_isGuided && _showPreStartPreview && state.isIdle)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: PreStartPreviewSheet(
                reference: widget.reference!,
                activityType: _selectedActivity,
                lifelineEnabled: _lifelineToggleOn,
                hasLifelineContacts: _emergencyContacts.isNotEmpty,
                contactsCount: _emergencyContacts.length,
                onLifelineToggle: () => setState(
                    () => _lifelineToggleOn = !_lifelineToggleOn),
                onLifelineSetup: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EmergencyContactsPage(),
                    ),
                  );
                  if (mounted) await _loadLifelineConfig();
                },
                onStart: _startGuidedRecording,
                onCancel: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    setState(() => _showPreStartPreview = false);
                  }
                },
              ),
            ),
        ],
      ),
      floatingActionButton: !state.isIdle && state.isRecording
          ? AddPhotoButton(onTakePhoto: _takePhoto, onPickFromGallery: _pickPhotos, onAddPoi: _addPoiHere) : null,
    );
  }

  Future<void> _takePhoto() async {
    final state = _trackingBloc.state;
    if (state.points.isEmpty) { _showSnackBar(context.l10n.gpsNotAvailable, isError: true); return; }
    await _saveStateToBackup();
    final lastPoint = state.points.last;
    final photo = await _photosService.takePhoto(latitude: lastPoint.latitude, longitude: lastPoint.longitude, elevation: lastPoint.elevation);
    if (!mounted) return;
    if (photo != null) { setState(() => _photos.add(photo)); _showSnackBar(context.l10n.photoAdded); await _saveStateToBackup(); }
  }

  Future<void> _pickPhotos() async {
    final state = _trackingBloc.state;
    TrackPoint? lastPoint; if (state.points.isNotEmpty) lastPoint = state.points.last;
    await _saveStateToBackup();
    final photos = await _photosService.pickFromGallery(latitude: lastPoint?.latitude, longitude: lastPoint?.longitude, elevation: lastPoint?.elevation);
    if (!mounted) return;
    if (photos.isNotEmpty) { setState(() => _photos.addAll(photos)); _showSnackBar(context.l10n.photosAdded(photos.length)); await _saveStateToBackup(); }
  }

  Future<void> _deletePhoto(int index) async { setState(() => _photos.removeAt(index)); _showSnackBar(context.l10n.photoDeleted); await _saveStateToBackup(); }

  void _showPhotoOptions() {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.camera_alt, color: AppColors.primary), title: Text(context.l10n.takePhoto), onTap: () { Navigator.pop(context); _takePhoto(); }),
      ListTile(leading: const Icon(Icons.photo_library, color: AppColors.info), title: Text(context.l10n.pickFromGallery), onTap: () { Navigator.pop(context); _pickPhotos(); }),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.place, color: AppColors.success),
        title: const Text('Aggiungi POI qui'),
        subtitle: const Text('Fontana, panorama, pericolo...', style: TextStyle(fontSize: 11)),
        onTap: () { Navigator.pop(context); _addPoiHere(); },
      ),
    ])));
  }

  /// Apre il bottom sheet di creazione POI con la posizione GPS attuale.
  /// Se stiamo seguendo una track community, associa il POI alla track
  /// (relatedTrackId) così diventa visibile come POI di quella traccia.
  Future<void> _addPoiHere() async {
    final state = _trackingBloc.state;
    if (state.points.isEmpty) {
      _showSnackBar('GPS non ancora disponibile', isError: true);
      return;
    }
    final lastPoint = state.points.last;
    // Se siamo in modalità guidata e il riferimento è una community track
    // (non un trail OSM), associo il POI alla track. Al momento non ho un
    // id persistente per il trail OSM dalla reference, lo aggiungerò in
    // uno step successivo.
    String? relatedTrackId;
    // TrackId è disponibile solo dopo save; durante recording non c'è.
    // Il POI verrà creato come "globale" (visibile in base alla posizione)
    // con possibilità di linkarlo alla track dopo il salvataggio.
    final poi = await showPoiEditorSheet(
      context,
      latitude: lastPoint.latitude,
      longitude: lastPoint.longitude,
      elevation: lastPoint.elevation,
      relatedTrackId: relatedTrackId,
    );
    if (poi != null && mounted) {
      _showSnackBar('POI "${poi.title}" aggiunto');
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? AppColors.danger : AppColors.success, duration: const Duration(seconds: 2)));
  }

  void _showCancelDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text(context.l10n.cancelRecording),
      content: Text(_photos.isEmpty ? context.l10n.trackDataWillBeLost : context.l10n.trackAndPhotosWillBeLost(_photos.length)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.continueBtn)),
        TextButton(onPressed: () async { Navigator.pop(context); setState(() => _photos.clear()); await _trackingBloc.cancelRecording(); await _persistence.clearState(); await LiveTrackService().stop(); await _stopLifelineIfActive(askSafeArrival: false); },
          child: Text(context.l10n.cancel, style: const TextStyle(color: AppColors.danger))),
      ],
    ));
  }

  void _showSaveDialog() async {
    // 1. Prima PAUSA per mostrare il dialog con i dati ancora disponibili
    await _trackingBloc.pauseRecording();
    
    final state = _trackingBloc.state;
    if (state.points.isEmpty) {
      await _trackingBloc.cancelRecording();
      await _trackingBloc.stopForegroundService();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.noPointsRecorded)));
      return;
    }
    if (!mounted) return;
    
    // 2. Genera nome default con tipo attività e data
    final now = DateTime.now();
    final activityName = state.activityType.displayName;
    final defaultName = '$activityName del ${now.day}/${now.month}/${now.year}';
    final nameController = TextEditingController(text: defaultName);

    // Pre-check Strava: solo se connesso mostriamo lo switch nel dialog.
    // ⚠️ CRITICO: questi sono .get() Firestore che su segnale DEBOLE
    // (es. auto in valle) possono bloccarsi a lungo aspettando il
    // server → il dialog di salvataggio non appariva mai e il bottone
    // Salva sembrava morto. Avvolgiamo in un timeout: se non rispondono
    // entro 3s procediamo SENZA lo switch Strava (il salvataggio della
    // traccia è prioritario e funziona offline).
    bool stravaConnected = false;
    bool uploadToStrava = false;
    try {
      final stravaService = StravaService();
      stravaConnected = await stravaService
          .isConnected()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (stravaConnected) {
        uploadToStrava = await stravaService
            .isAutoUploadEnabled()
            .timeout(const Duration(seconds: 3), onTimeout: () => false);
      }
    } catch (e) {
      debugPrint('[RecordPage] Strava pre-check fallito/timeout: $e');
    }
    if (!mounted) return;

    // 3. Mostra dialog di conferma (lo stato è in pausa, non perso)
    final shouldSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(context.l10n.saveTrackTitle),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: nameController, decoration: InputDecoration(labelText: context.l10n.trackName, border: const OutlineInputBorder())),
            const SizedBox(height: 16),
            _buildSummaryRow(context.l10n.distanceLabel, '${state.stats.distanceKm.toStringAsFixed(2)} km'),
            _buildSummaryRow(context.l10n.elevationLabel, '+${state.stats.elevationGain.toStringAsFixed(0)} m'),
            _buildSummaryRow(context.l10n.durationStatLabel, state.stats.durationFormatted),
            _buildSummaryRow(context.l10n.gpsPoints, '${state.points.length}'),
            if (_photos.isNotEmpty) _buildSummaryRow(context.l10n.photosLabel, '${_photos.length}'),
            if (stravaConnected) ...[
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                secondary: const Icon(Icons.directions_run, color: Color(0xFFFC4C02)),
                title: Text(context.l10n.stravaUploadTitle),
                value: uploadToStrava,
                onChanged: (v) => setStateDialog(() => uploadToStrava = v),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white), child: Text(context.l10n.save)),
          ],
        ),
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
      if (track == null) {
        if (!mounted) throw Exception('Stop recording error');
        throw Exception(context.l10n.stopRecordingError);
      }
      
      final trackToSave = track.copyWith(name: nameController.text.trim());
      final trackId = await _repository.saveTrack(trackToSave);
      
      if (_photos.isNotEmpty) {
        final result = await _photosService.uploadPhotos(photos: _photos, trackId: trackId, onProgress: (c, t) => debugPrint('[RecordPage] Upload foto $c/$t'));
        if (result.uploaded.isNotEmpty) {
          final photoMetadata = result.uploaded.map((p) => TrackPhotoMetadata(url: p.url, latitude: p.latitude, longitude: p.longitude, elevation: p.elevation, timestamp: p.timestamp)).toList();
          await _repository.updateTrackPhotos(trackId, photoMetadata);
        }
        if (result.hasFailures && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.photosNotUploaded(result.failed.length)), backgroundColor: AppColors.warning));
        }
      }

      // Sync con Apple Health / Health Connect
      HealthService().saveTrackAsWorkout(trackToSave).catchError((e) {
        debugPrint('[RecordPage] Errore sync Health: $e');
        return false;
      });

      // Upload su Strava (fire-and-forget). Lo switch nel save dialog ha
      // priorità sulla preferenza globale autoUploadEnabled per questa
      // singola attività.
      if (uploadToStrava) {
        StravaService().uploadTrack(trackId).catchError((e) {
          debugPrint('[RecordPage] Errore upload Strava: $e');
          return null;
        });
      }

      /// ❤️ Recupera battito cardiaco da Health Connect/Apple Health
      // Attende 15 secondi per dare tempo al wearable di sincronizzare
      () async {
        try {
          debugPrint('[RecordPage] ❤️ Attesa 15s per sync wearable...');
          await Future.delayed(const Duration(seconds: 15));
          final healthService = HealthService();
          final startTime = trackToSave.createdAt;
          final endTime = startTime.add(trackToSave.stats.duration);
          
          final hrData = await healthService.getHeartRateForTimeRange(
            start: startTime,
            end: endTime,
          );
          
          if (hrData.isNotEmpty) {
            await _repository.updateTrackHeartRate(trackId, hrData);
            debugPrint('[RecordPage] ❤️ ${hrData.length} campioni HR salvati sulla traccia');
          } else {
            debugPrint('[RecordPage] ❤️ Nessun dato HR trovato per questo intervallo');
          }

          // 🔥 Recupera calorie reali
          final calories = await healthService.getCaloriesForTimeRange(
            start: startTime,
            end: endTime,
          );
          if (calories != null) {
            await _repository.updateTrackField(trackId, 'healthCalories', calories);
            debugPrint('[RecordPage] 🔥 Calorie reali: ${calories.round()} kcal');
          }
          // 👣 Recupera passi
          final steps = await healthService.getStepsForTimeRange(
            start: startTime,
            end: endTime,
          );
          if (steps != null) {
            await _repository.updateTrackField(trackId, 'healthSteps', steps);
            debugPrint('[RecordPage] 👣 Passi: $steps');
          }
        } catch (e) {
          debugPrint('[RecordPage] ❤️ Errore recupero HR: $e');
        }
      }();
      
      await _trackingBloc.stopForegroundService();
      await _persistence.clearState();
      await LiveTrackService().stop();
      _photos.clear();

      // Stop Lifeline con eventuale prompt "arrivato in sicurezza"
      await _stopLifelineIfActive(askSafeArrival: true);

      // Post-save: XP, badge, sfide, segmenti cronometrati
      if (mounted) {
        await PostTrackSaveService.handleTrackSaved(
          context: context,
          distanceMeters: trackToSave.stats.distance,
          elevationGain: trackToSave.stats.elevationGain,
          durationSeconds: trackToSave.stats.duration.inSeconds,
          track: trackToSave,
          trackId: trackId,
        );
      }

      if (mounted) {
        await _showCompletionDialog(trackToSave);
      }

      // In modalità guidata la pagina è stata aperta via Navigator.push dal
      // Planner o da un trail detail: dopo il salvataggio completato torna
      // alla pagina precedente invece di lasciare l'utente bloccato in idle.
      if (mounted && _isGuided) {
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      debugPrint('[RecordPage] Errore salvataggio: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.errorWithDetails(e.toString())), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _localizeError(String code) {
    switch (code) {
      case 'gps_access_error': return context.l10n.gpsAccessError;
      case 'gps_resume_error': return context.l10n.gpsResumeError;
      default: return code;
    }
  }

  Widget _buildSummaryRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(color: context.textSecondary)), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]));
  Widget _buildErrorBanner(String message) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.error_outline, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text(message, style: const TextStyle(color: Colors.white)))]));

  Widget _buildMap(TrackingState state) {
    final center = state.points.isNotEmpty ? LatLng(state.points.last.latitude, state.points.last.longitude) : (_userPosition ?? const LatLng(45.9, 9.9));
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: center, initialZoom: 16, minZoom: 4, maxZoom: 18, onPositionChanged: (position, hasGesture) { if (hasGesture) { _followUser = false; _bumpHudActivity(); } }),
      children: [
        TileLayer(
          urlTemplate: mapStyles[_currentMapStyle.clamp(0, mapStyles.length - 1)].urlTemplate,
          subdomains: mapStyles[_currentMapStyle.clamp(0, mapStyles.length - 1)].subdomains,
          userAgentPackageName: 'com.trailshare.app',
          tileProvider: OfflineFallbackTileProvider(),
          tileBuilder: mapStyles[_currentMapStyle.clamp(0, mapStyles.length - 1)].tileColorFilter != null
              ? (context, tileWidget, tile) => ColorFiltered(
                    colorFilter: mapStyles[_currentMapStyle.clamp(0, mapStyles.length - 1)].tileColorFilter!,
                    child: tileWidget,
                  )
              : null,
        ),
        // Polyline di riferimento (sotto la traccia utente) quando in modalità guidata
        if (_isGuided && widget.reference!.polyline.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: widget.reference!.polyline,
              strokeWidth: 5,
              color: AppColors.info.withValues(alpha: 0.7),
              pattern: StrokePattern.dashed(segments: const [10, 6]),
            ),
          ]),
        // Polyline arancione di rientro quando off-trail + re-route attivo
        if (_isGuided && _rerouteBackPolyline != null)
          PolylineLayer(polylines: [
            Polyline(
              points: _rerouteBackPolyline!,
              strokeWidth: 6,
              color: Colors.orange,
              // Fallback (linea retta) distingue con pattern diverso
              pattern: _rerouteIsFallback
                  ? StrokePattern.dotted()
                  : StrokePattern.solid(),
            ),
          ]),
        if (state.points.length >= 2) PolylineLayer(polylines: [Polyline(points: state.points.map((p) => LatLng(p.latitude, p.longitude)).toList(), strokeWidth: 4, color: state.isRecording ? AppColors.trackRecording : AppColors.primary)]),
        if (state.points.isNotEmpty) MarkerLayer(markers: [
          Marker(point: LatLng(state.points.first.latitude, state.points.first.longitude), width: 24, height: 24, child: Container(decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: const Icon(Icons.flag, color: Colors.white, size: 14))),
          Marker(
            point: LatLng(state.points.last.latitude, state.points.last.longitude),
            width: 32, height: 32,
            child: ListenableBuilder(
              listenable: HeadingService(),
              builder: (_, _) {
                final h = HeadingService().currentHeading ?? 0;
                return Container(
                  decoration: BoxDecoration(
                    color: state.isRecording ? AppColors.trackRecording : AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: (state.isRecording ? AppColors.trackRecording : AppColors.primary).withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 2)],
                  ),
                  child: Transform.rotate(
                    angle: h * math.pi / 180,
                    child: const Icon(Icons.navigation, color: Colors.white, size: 18),
                  ),
                );
              },
            ),
          ),
        ]),
        // Marker posizione utente (solo quando idle)
        if (state.isIdle && _userPosition != null)
          MarkerLayer(markers: [
            Marker(
              point: _userPosition!,
              width: 24,
              height: 24,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 2),
                  ],
                ),
              ),
            ),
          ]),
      ],
    );
  }

  /// Header stats con modalità compatta (default) ed espansa.
  /// - Compatto: pulse + 3 valori primari in una riga + HR + chevron
  /// - Espanso: come prima (2 righe con tutti i 6 valori)
  /// Tap sull'header alterna i due stati.
  Widget _buildStatsHeader(TrackingState state) {
    final bg = state.isRecording
        ? AppColors.trackRecording.withValues(alpha: 0.95)
        : AppColors.warning.withValues(alpha: 0.95);
    // NB: il Positioned (top/left/right) è applicato dal chiamante
    // (vedi `build`) — qui ritorniamo solo il contenuto, così questo
    // widget può essere wrappato in AnimatedOpacity/IgnorePointer
    // senza rompere StackParentData.
    return GestureDetector(
      onTap: () {
        setState(() => _statsExpanded = !_statsExpanded);
        _bumpHudActivity();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 6,
          bottom: _statsExpanded ? 14 : 8,
          left: 12,
          right: 12,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: _statsExpanded
            ? _buildStatsExpanded(state)
            : _buildStatsCompact(state),
      ),
    );
  }

  /// 1.D4 — Chip mini visualizzato in alto a sinistra quando lo stats
  /// HUD è in auto-hide. Mostra solo distanza+pulse, tap → rimostra
  /// l'HUD per altri N secondi.
  Widget _buildHudReshowChip(TrackingState state) {
    final isRec = state.isRecording;
    final accent = isRec ? AppColors.trackRecording : AppColors.warning;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      child: GestureDetector(
        onTap: _bumpHudActivity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRec ? Icons.fiber_manual_record : Icons.pause,
                color: Colors.white,
                size: 10,
              ),
              const SizedBox(width: 6),
              Text(
                '${state.stats.distanceKm.toStringAsFixed(2)} km',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCompact(TrackingState state) {
    return Row(
      children: [
        // Spazio per il pulsante X (chiudi) quando in modalità guidata
        SizedBox(width: _isGuided ? 44 : 8),
        // Pulse dot + REC/PAUSA
        Icon(
          state.isRecording ? Icons.fiber_manual_record : Icons.pause,
          color: Colors.white,
          size: 11,
        ),
        const SizedBox(width: 8),
        // Stats in riga
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _miniStat(state.stats.distanceKm.toStringAsFixed(2), 'km'),
              _miniStat(state.stats.durationFormatted, 'h/m'),
              _miniStat(state.stats.elevationGain.toStringAsFixed(0), 'D+'),
            ],
          ),
        ),
        const SizedBox(width: 6),
        const HeartRateWidget(),
        const SizedBox(width: 4),
        const Icon(Icons.expand_more, size: 18, color: Colors.white70),
      ],
    );
  }

  Widget _buildStatsExpanded(TrackingState state) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(width: 60),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                state.isRecording
                    ? Icons.fiber_manual_record
                    : Icons.pause,
                color: Colors.white,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                state.isRecording
                    ? context.l10n.recording
                    : context.l10n.paused,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: const [
              HeartRateWidget(),
              SizedBox(width: 4),
              Icon(Icons.expand_less, size: 18, color: Colors.white70),
            ]),
          ],
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _buildStat(context.l10n.distanceLabel,
              '${state.stats.distanceKm.toStringAsFixed(2)} km'),
          _buildStat(context.l10n.timeLabel, state.stats.durationFormatted),
          _buildStat('D+',
              '${state.stats.elevationGain.toStringAsFixed(0)} m'),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _buildStat(context.l10n.speedLabel,
              '${(state.stats.currentSpeed * 3.6).toStringAsFixed(1)} km/h',
              small: true),
          _buildStat(context.l10n.avgSpeedLabel,
              '${(state.stats.avgSpeed * 3.6).toStringAsFixed(1)} km/h',
              small: true),
          _buildStat(context.l10n.paceLabel,
              _formatPace(state.stats.avgSpeed),
              small: true),
        ]),
      ],
    );
  }

  Widget _miniStat(String value, String unit) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1),
        ),
        const SizedBox(width: 3),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            unit,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8), fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value, {bool small = false}) => Column(children: [Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: small ? 16 : 22)), Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: small ? 10 : 11))]);
  String _formatPace(double avgSpeed) { if (avgSpeed <= 0) return '--:--'; final paceSeconds = 1000 / avgSpeed; final minutes = (paceSeconds / 60).floor(); final seconds = (paceSeconds % 60).floor(); return '$minutes:${seconds.toString().padLeft(2, '0')}'; }

  /// Overlay per schermata idle: stats settimanali + ultima attività
  Widget _buildIdleOverlay() {
    final colorScheme = Theme.of(context).colorScheme;
    final hasWeeklyData = _weeklyTracks > 0;
    final hasLastTrack = _lastTrack != null;

    if (!hasWeeklyData && !hasLastTrack) return const SizedBox.shrink();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 12,
      right: 12,
      child: Column(
        children: [
          // Stats settimanali
          if (hasWeeklyData)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
              ),
              // Row con FittedBox per resistere a schermi stretti /
              // accessibility font: se non entra, scala tutto insieme.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.thisWeek,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 14),
                    _buildMiniStat(
                        '📏', '${_weeklyDistanceKm.toStringAsFixed(1)} km'),
                    const SizedBox(width: 12),
                    _buildMiniStat(
                        '⬆️', '+${_weeklyElevation.toStringAsFixed(0)} m'),
                    const SizedBox(width: 12),
                    _buildMiniStat('🗺️', '$_weeklyTracks'),
                  ],
                ),
              ),
            ),

          // Ultima attività
          if (hasLastTrack) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(_lastTrack!.activityType.icon, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _lastTrack!.name,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_lastTrack!.stats.distanceKm.toStringAsFixed(1)} km · +${_lastTrack!.stats.elevationGain.toStringAsFixed(0)} m · ${_lastTrack!.stats.durationFormatted}',
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatTrackDate(_lastTrack!.createdAt),
                    style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniStat(String emoji, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
      ],
    );
  }

  String _formatTrackDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return context.l10n.today;
    if (diff.inDays == 1) return context.l10n.yesterday;
    return '${date.day}/${date.month}';
  }

  /// Overlay mostrato al primo ingresso in RecordPage: backdrop semi-trasparente
  /// + card informativa che spiega il pulsante REC + freccia giù + "Ho capito".
  Widget _buildRecTutorialOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _dismissRecTutorial,
        child: Container(
          color: Colors.black.withValues(alpha: 0.65),
          child: SafeArea(
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE07B4C).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.play_arrow_rounded, color: Color(0xFFE07B4C), size: 32),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.l10n.recTutorialTitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                context.l10n.recTutorialBody,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _dismissRecTutorial,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    context.l10n.recTutorialGotIt,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Freccia che punta verso il pulsante REC (in basso al centro).
                Positioned(
                  bottom: 160,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Icon(Icons.keyboard_double_arrow_down,
                          color: Colors.white.withValues(alpha: 0.9), size: 48),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(TrackingState state) {
    return Positioned(bottom: 24, left: 16, right: 16, child: Column(children: [
      if (!state.isIdle) Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(bottom: 16), child: FloatingActionButton.small(heroTag: 'center', onPressed: () { _followUser = true; if (state.points.isNotEmpty) _mapController.move(LatLng(state.points.last.latitude, state.points.last.longitude), 16); }, backgroundColor: _followUser ? AppColors.primary : Colors.white, child: Icon(Icons.my_location, color: _followUser ? Colors.white : context.textPrimary)))),
      if (state.isIdle) _buildStartButton() else _buildRecordingControls(state),
    ]));
  }

  Widget _buildStartButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle Lifeline (visibile solo se contatti configurati)
        if (_emergencyContacts.isNotEmpty) _buildLifelineToggle(),
        // Selettore tipo attività (tap per aprire bottom sheet)
        GestureDetector(
          onTap: _showActivityPicker,
          child: Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, spreadRadius: 2)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_selectedActivity.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(
                  _selectedActivity.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.expand_more, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        // Pulsante INIZIA
        GestureDetector(
          onTap: _onStartPressed,
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE07B4C),
                  Color(0xFFC4683F),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                Text(
                  _selectedActivity.displayName.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // LIFELINE
  // ════════════════════════════════════════════════════════════════════

  Widget _buildLifelineToggle() {
    return GestureDetector(
      onTap: () => setState(() => _lifelineToggleOn = !_lifelineToggleOn),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _lifelineToggleOn
              ? AppColors.info.withValues(alpha: 0.95)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _lifelineToggleOn
                ? AppColors.info
                : AppColors.info.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _lifelineToggleOn ? Icons.shield : Icons.shield_outlined,
              size: 16,
              color: _lifelineToggleOn ? Colors.white : AppColors.info,
            ),
            const SizedBox(width: 6),
            Text(
              _lifelineToggleOn
                  ? 'Lifeline attivo · ${_emergencyContacts.length} contatti'
                  : 'Lifeline',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _lifelineToggleOn ? Colors.white : AppColors.info,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const String _lifelineDisclaimerKey = 'lifeline_disclaimer_accepted_v1';

  /// Mostra il disclaimer Lifeline al primo utilizzo. Ritorna true se
  /// l'utente accetta, false se rifiuta. Dopo l'accettazione il flag è
  /// memorizzato in SharedPreferences e il disclaimer non viene più
  /// ripetuto (incrementare la versione del key per forzare riaccettazione
  /// quando cambieranno i termini).
  Future<bool> _ensureLifelineDisclaimerAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_lifelineDisclaimerKey) == true) return true;
    if (!mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _LifelineDisclaimerDialog(),
    );

    if (accepted == true) {
      await prefs.setBool(_lifelineDisclaimerKey, true);
      return true;
    }
    return false;
  }

  /// Handler del tap sul bottone START. Gestisce l'avvio Lifeline
  /// (se il toggle è attivo) prima di avviare la registrazione.
  /// Verifica che l'app sia esente dall'ottimizzazione batteria. Senza
  /// questa esenzione, Android (specie su OEM aggressivi: Xiaomi, Oppo,
  /// Samsung, Huawei) UCCIDE l'app/foreground service durante le pause
  /// lunghe → la registrazione si interrompe, si crea un buco nella
  /// traccia e Lifeline smette di aggiornare. Bug critico riscontrato
  /// sul campo (pausa caffè al Curò → app killata).
  ///
  /// Prompt una volta sola finché non concesso (flag SharedPreferences
  /// per non insistere se l'utente rifiuta consapevolmente).
  Future<void> _ensureBatteryOptimizationExemption() async {
    try {
      final ignoring =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (ignoring) return;

      final prefs = await SharedPreferences.getInstance();
      const key = 'battery_opt_prompt_dismissed';
      if (prefs.getBool(key) == true) return;
      if (!mounted) return;

      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Registrazione affidabile'),
          content: const Text(
            'Per non perdere la traccia durante le pause (caffè, pranzo, '
            'soste lunghe), Android deve poter tenere attiva la '
            'registrazione in background.\n\n'
            'Senza questa autorizzazione il sistema può chiudere l\'app '
            'durante le soste e interrompere il tracciamento.\n\n'
            'Vuoi consentirlo? (consigliato)',
          ),
          actions: [
            TextButton(
              onPressed: () {
                prefs.setBool(key, true);
                Navigator.pop(ctx, false);
              },
              child: const Text('Non ora'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Consenti'),
            ),
          ],
        ),
      );
      if (go == true) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (e) {
      debugPrint('[RecordPage] battery opt check error: $e');
    }
  }

  Future<void> _onStartPressed() async {
    // CRITICO: prima di registrare, assicura l'esenzione batteria così
    // il sistema non uccide l'app durante le pause (bug del Curò).
    await _ensureBatteryOptimizationExemption();

    // Se Lifeline richiesto: disclaimer al primo utilizzo + avvio
    if (_lifelineToggleOn && _emergencyContacts.isNotEmpty) {
      final accepted = await _ensureLifelineDisclaimerAccepted();
      if (!accepted) return; // utente ha rifiutato: non parte nulla
      try {
        final userName = FirebaseAuth.instance.currentUser?.displayName ??
            FirebaseAuth.instance.currentUser?.email ??
            'Utente TrailShare';
        final drafts = await _lifeline.start(
          contacts: _emergencyContacts,
          userName: userName,
          activityName: _selectedActivity.displayName,
          referenceName: widget.reference?.name,
          customTemplate: _lifelineTemplate,
        );
        _lifelineActive = drafts.isNotEmpty;
        if (drafts.isNotEmpty && mounted) {
          await _showLifelineDraftsDialog(drafts);
        }
      } catch (e) {
        debugPrint('[RecordPage] Errore avvio Lifeline: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.lifelineCannotStart(e.toString())),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      }
    }
    await _trackingBloc.startRecording(activityType: _selectedActivity);
  }

  /// Mostra un dialog con la lista dei messaggi da inviare ai contatti.
  /// L'utente tappa "Invia a X" per aprire l'app SMS (o WhatsApp / email)
  /// pre-compilata. Opzione A concordata: l'utente conferma ogni invio.
  Future<void> _showLifelineDraftsDialog(
      List<LifelineMessageDraft> drafts) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: const [
          Icon(Icons.shield, color: AppColors.info),
          SizedBox(width: 8),
          Text('Notifica contatti'),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Invia il link di tracking ai tuoi contatti:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...drafts.map((d) => _buildDraftRow(d)),
              const SizedBox(height: 8),
              Text(
                'Puoi saltare e inviarli più tardi dal banner Lifeline.',
                style: TextStyle(fontSize: 11, color: context.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fatto'),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftRow(LifelineMessageDraft draft) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.info.withValues(alpha: 0.15),
            child: Text(
              draft.contact.name.isNotEmpty
                  ? draft.contact.name[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.info,
                  fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(draft.contact.name)),
          if (draft.contact.phone != null && draft.contact.phone!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.sms, size: 20, color: AppColors.info),
              tooltip: 'SMS',
              onPressed: () => _sendDraft(draft, viaSms: true),
            ),
          if (draft.contact.phone != null && draft.contact.phone!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.chat, size: 20, color: Colors.green),
              tooltip: 'WhatsApp',
              onPressed: () => _sendDraft(draft, viaWhatsApp: true),
            ),
          if (draft.contact.email != null && draft.contact.email!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.email_outlined, size: 20),
              tooltip: 'Email',
              onPressed: () => _sendDraft(draft, viaEmail: true),
            ),
        ],
      ),
    );
  }

  Future<void> _sendDraft(
    LifelineMessageDraft draft, {
    bool viaSms = false,
    bool viaWhatsApp = false,
    bool viaEmail = false,
  }) async {
    Uri? uri;
    if (viaSms && draft.contact.phone != null) {
      final phone = draft.contact.phone!.replaceAll(' ', '');
      uri = Uri.parse('sms:$phone?body=${Uri.encodeComponent(draft.text)}');
    } else if (viaWhatsApp && draft.contact.phone != null) {
      final phone = draft.contact.phone!
          .replaceAll(' ', '')
          .replaceAll('+', '')
          .replaceAll('-', '');
      uri = Uri.parse(
          'https://wa.me/$phone?text=${Uri.encodeComponent(draft.text)}');
    } else if (viaEmail && draft.contact.email != null) {
      uri = Uri.parse(
        'mailto:${draft.contact.email}?subject=${Uri.encodeComponent("🛡️ Lifeline TrailShare")}&body=${Uri.encodeComponent(draft.text)}',
      );
    }
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.noAppAvailable)),
        );
      }
    } catch (e) {
      debugPrint('[Lifeline] Errore launchUrl: $e');
    }
  }

  /// Banner compatto "Lifeline attiva" quando non si è in modalità guidata
  /// (altrimenti è già integrato nel banner guida come chip inline).
  ///
  /// Posizionato subito sotto lo stats header, altezza minima per non
  /// rubare spazio alla mappa.
  Widget _buildLifelineActiveBanner() {
    final headerHeight = _statsExpanded ? 160.0 : 55.0;
    final topOffset = MediaQuery.of(context).padding.top + headerHeight + 8;
    return Positioned(
      top: topOffset,
      left: 12,
      right: 12,
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(10),
        color: AppColors.info,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _resendDrafts,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.shield, color: Colors.white, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Lifeline · ${_emergencyContacts.length} contatti',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                const Text(
                  'Re-invia',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 10.5,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rigenera i draft e riapre il dialog per reinviare a contatti.
  /// I token esistenti restano validi — questo serve solo a mostrare di
  /// nuovo i pulsanti SMS/WhatsApp senza ripartire la sessione.
  /// Dialog di conferma 2-step quando Lifeline rileva inattività >30 min.
  /// L'utente ha 3 opzioni + un countdown di 5 min: se non risponde, parte
  /// l'alert automatico ai contatti.
  Future<void> _showInactivityConfirmationDialog() async {
    if (!mounted) return;
    final result = await showDialog<_InactivityResponse>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InactivityDialog(
        responseWindow: LifelineService.responseWindow,
      ),
    );

    _inactivityDialogShown = false;

    if (!mounted) return;
    switch (result) {
      case _InactivityResponse.ok:
      case null:
      // Null = dismiss imprevisto → trattiamo come OK per sicurezza
      // (l'utente non ha tappato SOS, ipotizziamo stia bene).
        _lifeline.dismissInactivityAlert();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Check superato, registrazione continua'),
            backgroundColor: AppColors.success,
          ),
        );
        break;
      case _InactivityResponse.stopAndSave:
        _lifeline.dismissInactivityAlert();
        _showSaveDialog();
        break;
      case _InactivityResponse.sendAlert:
        // Utente ha esplicitamente tappato SOS → usa testo "🆘 SOS"
        await _sendAlert(sosExplicit: true);
        break;
      case _InactivityResponse.timeout:
        // Countdown scaduto senza risposta → "⚠️ Inattività"
        await _sendAlert(sosExplicit: false);
        break;
    }
  }

  /// Costruisce e mostra i draft di alert ai contatti.
  /// [sosExplicit] determina il tipo di messaggio.
  Future<void> _sendAlert({required bool sosExplicit}) async {
    debugPrint('[RecordPage] Invio alert, sos=$sosExplicit');
    final drafts = sosExplicit
        ? await _lifeline.prepareSosDrafts()
        : await _lifeline.prepareInactivityDrafts();
    if (!mounted) return;
    debugPrint('[RecordPage] Drafts preparati: ${drafts.length}');
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Errore preparazione messaggi alert. Controlla i log.',
          ),
          backgroundColor: AppColors.danger,
          duration: Duration(seconds: 6),
        ),
      );
      return;
    }
    // Reset lo stato Lifeline (l'utente ora DEVE inviare i drafts, poi
    // può decidere se continuare o stoppare).
    _lifeline.dismissInactivityAlert();
    await _showLifelineDraftsDialog(drafts);
  }

  /// Ferma Lifeline se attivo. Se [askSafeArrival] chiede all'utente se
  /// vuole mandare un messaggio "sono arrivato/a al sicuro" ai contatti.
  Future<void> _stopLifelineIfActive({bool askSafeArrival = false}) async {
    if (!_lifelineActive) return;
    bool wantSafeArrival = false;
    if (askSafeArrival && mounted) {
      wantSafeArrival = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Lifeline terminata'),
              content: const Text(
                'Vuoi notificare ai tuoi contatti che sei arrivato/a in sicurezza?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No, grazie'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Invia conferma'),
                ),
              ],
            ),
          ) ??
          false;
    }
    final userName = FirebaseAuth.instance.currentUser?.displayName ??
        FirebaseAuth.instance.currentUser?.email ??
        'Utente TrailShare';
    final drafts = await _lifeline.stop(
      contacts: _emergencyContacts,
      userName: userName,
      sendSafeArrival: wantSafeArrival,
    );
    _lifelineActive = false;
    if (drafts.isNotEmpty && mounted) {
      await _showLifelineDraftsDialog(drafts);
    }
    if (mounted) setState(() {});
  }

  Future<void> _resendDrafts() async {
    final sid = _lifeline.state.sessionId;
    if (sid == null) return;
    // Ricarichiamo i token esistenti per ricomporre i draft
    try {
      final tokensSnap = await FirebaseFirestore.instance
          .collection('live_sessions')
          .doc(sid)
          .collection('access_tokens')
          .get();
      final template = _lifelineTemplate ??
          EmergencyContactsRepository.defaultMessageTemplate;
      if (tokensSnap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Nessun token trovato per questa sessione. Riavvia Lifeline.')),
          );
        }
        return;
      }
      final drafts = <LifelineMessageDraft>[];
      for (final c in _emergencyContacts) {
        String tokenId;
        final matching = tokensSnap.docs.where(
          (d) => d.data()['contactId'] == c.id,
        );
        tokenId = matching.isNotEmpty
            ? matching.first.id
            : tokensSnap.docs.first.id;
        final link = 'https://trailshare.app/live?id=$sid&token=$tokenId';
        drafts.add(LifelineMessageDraft(
          contact: c,
          link: link,
          text: EmergencyContactsRepository.renderTemplate(
            template: template,
            contactName: c.name,
            activityName: _selectedActivity.displayName,
            referenceName: widget.reference?.name,
            link: link,
          ),
        ));
      }
      if (mounted) await _showLifelineDraftsDialog(drafts);
    } catch (e) {
      debugPrint('[Lifeline] Errore resend: $e');
    }
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

  /// Variante del picker usata in modalità guidata: aggiorna anche il
  /// TrackingBloc così l'attività viene salvata correttamente sulla traccia
  /// in registrazione (altrimenti resterebbe quella passata al start).
  void _showActivityPickerGuided() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ActivityPickerSheet(
        selected: _selectedActivity,
        onSelected: (type) {
          setState(() => _selectedActivity = type);
          _trackingBloc.setActivityType(type);
          Navigator.pop(context);
        },
      ),
    );
  }


  Widget _buildRecordingControls(TrackingState state) => Column(mainAxisSize: MainAxisSize.min, children: [
    const Padding(padding: EdgeInsets.only(bottom: 12), child: LiveTrackButton()),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, spreadRadius: 2)]), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _buildControlButton(icon: Icons.close, label: context.l10n.cancelLabel, color: context.textMuted, onTap: _showCancelDialog),
      _buildControlButton(icon: state.isRecording ? Icons.pause : Icons.play_arrow, label: state.isRecording ? context.l10n.pauseLabel : context.l10n.resumeLabel, color: AppColors.warning, onTap: () { if (state.isRecording) {
        _trackingBloc.pauseRecording();
      } else {
        _trackingBloc.resumeRecording();
      } }, large: true),
      _buildControlButton(icon: Icons.stop, label: context.l10n.saveLabel, color: AppColors.danger, onTap: _showSaveDialog),
    ])),
  ]);

  Widget _buildControlButton({required IconData icon, required String label, required Color color, required VoidCallback onTap, bool large = false}) {
    final size = large ? 64.0 : 48.0;
    return GestureDetector(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: size, height: size, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(icon, color: color, size: large ? 32 : 24)), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500))]));
  }

  Future<void> _showCompletionDialog(Track track) async {
    final km = (track.stats.distance / 1000).toStringAsFixed(1);
    final elev = track.stats.elevationGain.toStringAsFixed(0);
    final h = track.stats.duration.inHours;
    final m = track.stats.duration.inMinutes % 60;
    final duration = h > 0 ? '${h}h ${m}m' : '$m min';

    // Messaggi motivazionali casuali
    final messages = [
      context.l10n.motivational1,
      context.l10n.motivational2,
      context.l10n.motivational3,
      context.l10n.motivational4,
      context.l10n.motivational5,
      context.l10n.motivational6,
      context.l10n.motivational7,
    ];
    final message = messages[DateTime.now().millisecond % messages.length];

    await showDialog<void>(
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
                color: AppColors.success.withValues(alpha: 0.1),
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
                _buildStatColumn('⬆️', elev, context.l10n.metersDPlus),
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
              child: Text(context.l10n.continueBtn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Titolo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              context.l10n.chooseActivity,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
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
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF388E3C)
                                    : Theme.of(context).colorScheme.outlineVariant,
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
                                    color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
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

/// Scelta fatta nel dialog SOS attivato.
enum _SosChoice { sendAlert, call112, cancel }

/// Disclaimer legale + UX al primo utilizzo di Lifeline.
///
/// Obiettivo: spiegare chiaramente all'utente COSA FA e cosa NON FA
/// Lifeline per evitare aspettative irrealistiche (e relativi rischi
/// legali per l'autore dell'app). L'utente deve barrare la checkbox
/// "Ho capito" per abilitare il pulsante "Continua".
class _LifelineDisclaimerDialog extends StatefulWidget {
  const _LifelineDisclaimerDialog();

  @override
  State<_LifelineDisclaimerDialog> createState() =>
      _LifelineDisclaimerDialogState();
}

class _LifelineDisclaimerDialogState
    extends State<_LifelineDisclaimerDialog> {
  bool _ack = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.info, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(context.l10n.lifelineHowItWorks)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lifeline è uno strumento di sicurezza aggiuntivo, non un servizio di soccorso ufficiale.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _bulletRow('✓', 'Invia un link di posizione live ai tuoi contatti di fiducia'),
            _bulletRow('✓', 'Rileva inattività prolungata e ti chiede una conferma'),
            _bulletRow('✓', 'Permette di inviare SOS manuale ai contatti + chiamata 112'),
            const SizedBox(height: 12),
            const Text(
              'IMPORTANTE — Lifeline NON:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 6),
            _bulletRow('✗', 'contatta direttamente il Soccorso Alpino o altri servizi di emergenza'),
            _bulletRow('✗', 'funziona senza copertura di rete cellulare o dati'),
            _bulletRow('✗', 'garantisce la consegna dei messaggi se il telefono è spento, scarico o non raggiungibile'),
            _bulletRow('✗', 'sostituisce dispositivi satellitari di emergenza (es. Garmin inReach, SPOT)'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'In aree remote, in alta montagna o in condizioni estreme, '
                'porta sempre con te un dispositivo satellitare di emergenza '
                'e comunica il percorso al Soccorso Alpino tramite GeoResQ '
                '(app ufficiale CNSAS).',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _ack,
              onChanged: (v) => setState(() => _ack = v ?? false),
              title: const Text(
                'Ho capito i limiti di Lifeline',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _ack ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.info,
            foregroundColor: Colors.white,
          ),
          child: const Text('Ho capito, continua'),
        ),
      ],
    );
  }

  Widget _bulletRow(String bullet, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bullet,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: bullet == '✓' ? AppColors.success : AppColors.danger,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsante SOS con long-press 1.5s.
///
/// Mostra un progress ring che si riempie mentre l'utente tiene premuto.
/// Al completamento chiama [onTriggered] (caller può vibrare/aprire dialog).
/// Tap breve → [onShortTap] (per hint).
class _SosFab extends StatefulWidget {
  final VoidCallback onTriggered;
  final VoidCallback onShortTap;
  const _SosFab({required this.onTriggered, required this.onShortTap});

  @override
  State<_SosFab> createState() => _SosFabState();
}

class _SosFabState extends State<_SosFab>
    with SingleTickerProviderStateMixin {
  static const Duration _holdDuration = Duration(milliseconds: 1500);
  late AnimationController _ctrl;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _holdDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && _pressed) {
          widget.onTriggered();
          _pressed = false;
          _ctrl.reset();
        }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onPressDown() {
    _pressed = true;
    HapticFeedback.lightImpact();
    _ctrl.forward(from: 0);
  }

  void _onPressUp() {
    final wasCompleted = _ctrl.status == AnimationStatus.completed;
    _pressed = false;
    if (_ctrl.status == AnimationStatus.forward) {
      final progress = _ctrl.value;
      _ctrl.reset();
      if (progress < 0.15) {
        widget.onShortTap();
      }
    } else if (!wasCompleted) {
      _ctrl.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    return Listener(
      onPointerDown: (_) => _onPressDown(),
      onPointerUp: (_) => _onPressUp(),
      onPointerCancel: (_) => _onPressUp(),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Progress ring durante il long-press
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) {
                if (_ctrl.value == 0) return const SizedBox.shrink();
                return SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(
                    value: _ctrl.value,
                    strokeWidth: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                );
              },
            ),
            // Pulsante
            Container(
              width: size - 10,
              height: size - 10,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.danger.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Risultato del dialog di conferma inattività Lifeline.
enum _InactivityResponse {
  /// "Sono OK, continuo la registrazione"
  ok,
  /// "Sono OK, ferma e salva"
  stopAndSave,
  /// "Manda SOS adesso"
  sendAlert,
  /// Countdown scaduto senza risposta → auto-alert
  timeout,
}

/// Dialog bloccante con countdown visivo che chiede all'utente di
/// confermare lo stato dopo inattività prolungata. Progettato per essere
/// molto visibile (titolo grande, pulsanti grandi, suono/vibrazione se
/// possibile) così se il telefono è in tasca si fa sentire.
class _InactivityDialog extends StatefulWidget {
  final Duration responseWindow;
  const _InactivityDialog({required this.responseWindow});

  @override
  State<_InactivityDialog> createState() => _InactivityDialogState();
}

class _InactivityDialogState extends State<_InactivityDialog> {
  late Duration _remaining;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _remaining = widget.responseWindow;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining -= const Duration(seconds: 1);
        if (_remaining <= Duration.zero) {
          _ticker?.cancel();
          Navigator.of(context).pop(_InactivityResponse.timeout);
        }
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatCountdown() {
    final m = _remaining.inMinutes;
    final s = _remaining.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final pct = _remaining.inMilliseconds /
        widget.responseWindow.inMilliseconds;

    return AlertDialog(
      backgroundColor: AppColors.warning,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: const [
          Icon(Icons.notifications_active, color: Colors.white, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tutto bene?',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sei fermo da più di 30 minuti.\nConferma che va tutto bene.',
            style: TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 14),
          // Countdown + progress bar
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  'Allarme automatico tra ${_formatCountdown()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, _InactivityResponse.ok),
                icon: const Icon(Icons.check),
                label: Text(context.l10n.imOkContinue),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pop(context, _InactivityResponse.stopAndSave),
                icon: const Icon(Icons.stop, color: Colors.white),
                label: Text(context.l10n.imOkSaveStop,
                    style: const TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    Navigator.pop(context, _InactivityResponse.sendAlert),
                icon: const Icon(Icons.warning_amber),
                label: const Text('MANDA SOS ADESSO'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
