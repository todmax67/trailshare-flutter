import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/emergency_contact.dart';
import '../../data/repositories/emergency_contacts_repository.dart';
import 'live_track_service.dart';
import 'lifeline_alert_service.dart';

/// Bozza di messaggio Lifeline pronta per essere inviata via `url_launcher`.
///
/// Contiene il testo già sostituito e i canali disponibili (telefono/email)
/// per il contatto, così la UI può offrire i pulsanti giusti (SMS, WhatsApp,
/// Email). Il send effettivo lo fa il chiamante — Opzione A: l'utente
/// conferma l'invio nell'app nativa.
class LifelineMessageDraft {
  final EmergencyContact contact;

  /// Testo pre-compilato già renderizzato (placeholder sostituiti).
  final String text;

  /// Link personalizzato con token univoco per questo contatto.
  final String link;

  const LifelineMessageDraft({
    required this.contact,
    required this.text,
    required this.link,
  });
}

/// Eventi pubblicati da [LifelineService] per aggiornare la UI (banner
/// "Lifeline attiva", SOS, stato inattività).
class LifelineState {
  final bool isActive;
  final int contactsCount;
  final String? sessionId;

  /// True quando è stata rilevata inattività >= [inactivityThreshold]
  /// e il servizio sta chiedendo conferma locale all'utente prima di
  /// notificare i contatti. La UI deve mostrare il dialog "Tutto bene?".
  final bool needsInactivityConfirmation;

  /// Timestamp di quando è stata rilevata l'inattività. La UI usa questo
  /// per calcolare il countdown visivo prima dell'auto-alert.
  final DateTime? inactivityDetectedAt;

  const LifelineState({
    required this.isActive,
    required this.contactsCount,
    this.sessionId,
    this.needsInactivityConfirmation = false,
    this.inactivityDetectedAt,
  });

  LifelineState copyWith({
    bool? isActive,
    int? contactsCount,
    String? sessionId,
    bool? needsInactivityConfirmation,
    DateTime? inactivityDetectedAt,
  }) {
    return LifelineState(
      isActive: isActive ?? this.isActive,
      contactsCount: contactsCount ?? this.contactsCount,
      sessionId: sessionId ?? this.sessionId,
      needsInactivityConfirmation:
          needsInactivityConfirmation ?? this.needsInactivityConfirmation,
      inactivityDetectedAt:
          inactivityDetectedAt ?? this.inactivityDetectedAt,
    );
  }

  static const LifelineState off =
      LifelineState(isActive: false, contactsCount: 0);
}

/// Servizio orchestratore della feature Lifeline.
///
/// **Non** sostituisce [LiveTrackService]: ci si appoggia per creare la
/// sessione live. Sopra aggiunge:
/// - invio messaggi iniziali personalizzati ai contatti d'emergenza
/// - token di accesso univoci per contatto con audit
/// - gestione stato (per banner UI + notifica inattività)
/// - messaggio "arrivato in sicurezza" opzionale al stop
///
/// Il ciclo di vita è legato a una sola registrazione: `start` → `stop`.
/// Singleton per comodità (analogo a LiveTrackService).
class LifelineService {
  LifelineService._();
  static final LifelineService _i = LifelineService._();
  factory LifelineService() => _i;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LiveTrackService _liveTrack = LiveTrackService();

  final _stateCtrl = StreamController<LifelineState>.broadcast();
  Stream<LifelineState> get stateStream => _stateCtrl.stream;

  LifelineState _state = LifelineState.off;
  LifelineState get state => _state;

  // ── Detection inattività ─────────────────────────────────────────────
  /// Soglia di inattività: se l'utente non si muove > [_movementThreshold]
  /// per questo lasso di tempo, viene richiesto un check locale.
  /// 30 minuti è lo standard per escursionismo (copre soste legittime per
  /// pranzo / pausa foto senza falsi positivi).
  static const Duration inactivityThreshold = Duration(minutes: 30);

  /// Distanza sotto la quale consideriamo l'utente "fermo".
  /// 20 m filtra il rumore GPS tipico mentre si pianzia fermi.
  static const double _movementThreshold = 20.0;

  /// Finestra di risposta locale prima di notificare i contatti.
  static const Duration responseWindow = Duration(minutes: 5);

  // Elenco di ultime posizioni utente (usate dall'inactivity check).
  LatLng? _lastSignificantPosition;
  DateTime? _lastMovementTime;
  Timer? _inactivityCheckTimer;
  Timer? _autoAlertTimer;

  /// Contatti e parametri memorizzati al start, usati per generare gli
  /// alert di inattività/SOS senza dover ri-raccogliere dati.
  List<EmergencyContact> _contacts = const [];
  String _userName = '';
  String _activityName = '';
  String? _referenceName;
  String? _customTemplate;

  /// Avvia Lifeline.
  ///
  /// Flusso:
  /// 1. Avvia sessione LiveTrack silent (senza dialog di share).
  /// 2. Genera un token univoco per ogni contatto e lo salva in
  ///    `live_sessions/{sid}/access_tokens/{token}`.
  /// 3. Renderizza il messaggio (template utente o default) per ciascuno.
  /// 4. Ritorna la lista di [LifelineMessageDraft] che la UI dovrà
  ///    inviare uno-a-uno via `url_launcher` (SMS/WhatsApp/email).
  ///
  /// Se [contacts] è vuoto ritorna lista vuota e non avvia nulla (caller
  /// deve prevenire questo caso).
  Future<List<LifelineMessageDraft>> start({
    required List<EmergencyContact> contacts,
    required String userName,
    required String activityName,
    String? referenceName,
    required String? customTemplate,
  }) async {
    if (contacts.isEmpty) {
      debugPrint('[Lifeline] start abort: no contacts');
      return [];
    }
    if (_state.isActive) {
      debugPrint('[Lifeline] già attiva — ignore start');
      return [];
    }

    // 1. Avvia sessione live silent
    final ok = await _liveTrack.startSilent(userName: userName);
    if (!ok || _liveTrack.sessionId == null) {
      debugPrint('[Lifeline] errore startSilent LiveTrack');
      return [];
    }
    final sessionId = _liveTrack.sessionId!;

    final template = (customTemplate != null && customTemplate.trim().isNotEmpty)
        ? customTemplate
        : EmergencyContactsRepository.defaultMessageTemplate;

    // 2+3. Per ogni contatto: token + draft messaggio
    final drafts = <LifelineMessageDraft>[];
    for (final c in contacts) {
      final token = _generateToken();
      // Salva token Firestore (audit-friendly)
      try {
        await _firestore
            .collection('live_sessions')
            .doc(sessionId)
            .collection('access_tokens')
            .doc(token)
            .set({
          'contactId': c.id,
          'contactName': c.name,
          'createdAt': FieldValue.serverTimestamp(),
          'accessCount': 0,
        });
      } catch (e) {
        debugPrint('[Lifeline] errore salvataggio token ${c.name}: $e');
        // Continuiamo lo stesso: il link funzionerà meno strettamente,
        // l'utente non deve restare bloccato.
      }

      final link = 'https://trailshare.app/live?id=$sessionId&token=$token';
      final text = EmergencyContactsRepository.renderTemplate(
        template: template,
        contactName: c.name,
        activityName: activityName,
        referenceName: referenceName,
        link: link,
      );

      drafts.add(LifelineMessageDraft(contact: c, text: text, link: link));
    }

    // Memorizza parametri per poter generare alert successivi.
    _contacts = contacts;
    _userName = userName;
    _activityName = activityName;
    _referenceName = referenceName;
    _customTemplate = customTemplate;

    // Reset detection inattività.
    _lastSignificantPosition = null;
    _lastMovementTime = DateTime.now();
    _startInactivityWatcher();

    _state = LifelineState(
      isActive: true,
      contactsCount: contacts.length,
      sessionId: sessionId,
    );
    _stateCtrl.add(_state);
    debugPrint('[Lifeline] avviata: sessionId=$sessionId contacts=${contacts.length}');

    return drafts;
  }

  /// Chiamato dal TrackingBloc ad ogni nuovo punto GPS durante la
  /// registrazione. Aggiorna `_lastMovementTime` solo se lo spostamento
  /// supera la soglia di rumore ([_movementThreshold]).
  ///
  /// Questa è la sola fonte di verità per capire se l'utente si è
  /// davvero mosso (il timer della batteria/GPS può ricevere punti anche
  /// da utente fermo, qui li filtriamo).
  void onPosition(double lat, double lng) {
    if (!_state.isActive) return;
    final p = LatLng(lat, lng);
    final last = _lastSignificantPosition;
    if (last == null) {
      _lastSignificantPosition = p;
      _lastMovementTime = DateTime.now();
      return;
    }
    final dist = const Distance().as(LengthUnit.Meter, last, p);
    if (dist >= _movementThreshold) {
      _lastSignificantPosition = p;
      _lastMovementTime = DateTime.now();
      // Se stavamo mostrando l'alert di inattività e l'utente si è
      // rimesso in moto, dismissiamo automaticamente.
      if (_state.needsInactivityConfirmation) {
        debugPrint('[Lifeline] Movimento rilevato → auto-dismiss inactivity');
        dismissInactivityAlert();
      }
    }
  }

  /// Avvia il check periodico (ogni 30s) che confronta tempo trascorso
  /// dall'ultimo movimento con la soglia [inactivityThreshold].
  void _startInactivityWatcher() {
    _inactivityCheckTimer?.cancel();
    _inactivityCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkInactivity();
    });
  }

  void _checkInactivity() {
    if (!_state.isActive) return;
    if (_state.needsInactivityConfirmation) return; // già in attesa risposta
    final last = _lastMovementTime;
    if (last == null) return;
    final elapsed = DateTime.now().difference(last);
    if (elapsed >= inactivityThreshold) {
      debugPrint('[Lifeline] Inattività rilevata: ${elapsed.inMinutes} min');
      _state = _state.copyWith(
        needsInactivityConfirmation: true,
        inactivityDetectedAt: DateTime.now(),
      );
      _stateCtrl.add(_state);

      // Sveglia il telefono anche in standby: notifica MAX priority +
      // vibrazione + suono. Indispensabile se l'utente è incosciente o
      // il telefono è in tasca: senza questo il dialog in-app si vede
      // solo a schermo acceso.
      LifelineAlertService().fireInactivityAlert();

      // Avvia timer per auto-fire alert se l'utente non risponde entro
      // la response window. Se l'utente tappa un bottone sul dialog
      // dismissInactivityAlert() cancella questo timer.
      _autoAlertTimer?.cancel();
      _autoAlertTimer = Timer(responseWindow, _triggerAutoAlert);
    }
  }

  /// L'utente ha risposto al check e tutto va bene: reset detection e
  /// cancella il timer di auto-alert + notifica di sistema.
  void dismissInactivityAlert() {
    _autoAlertTimer?.cancel();
    _autoAlertTimer = null;
    _lastMovementTime = DateTime.now(); // reset finestra
    // Ferma vibrazione e rimuovi notifica sistema
    LifelineAlertService().dismiss();
    if (_state.needsInactivityConfirmation) {
      _state = _state.copyWith(
        needsInactivityConfirmation: false,
        inactivityDetectedAt: null,
      );
      _stateCtrl.add(_state);
    }
  }

  /// L'utente non ha risposto al check entro [responseWindow]: prepara
  /// e ritorna i draft "⚠️ Inattività" per i contatti. La UI dovrà
  /// aprire il dialog invii per farli partire.
  ///
  /// Se la UI non è in primo piano (app in background) la detection
  /// del non-risposta avviene comunque (Timer), ma l'invio effettivo
  /// dei draft richiede interazione utente (Opzione A). In v1.8 questo
  /// sarà sostituito da push automatiche a contatti TrailShare + SMS
  /// via Cloud Function.
  void _triggerAutoAlert() {
    if (!_state.needsInactivityConfirmation) return; // utente ha risposto
    debugPrint('[Lifeline] No response → auto-alert contatti');
    // Lo stato resta needsInactivityConfirmation=true ma viene emesso
    // un evento specifico per distinguere "in attesa risposta" da
    // "timer scaduto → inviare ORA". La UI gestisce la distinzione
    // internamente (countdown arriva a 0 → mostra draft dialog).
    // Qui ci limitiamo a NON cambiare stato: la UI quando il suo
    // countdown arriva a 0 chiama prepareInactivityDrafts().
  }

  /// Costruisce i messaggi di alert "⚠️ Inattività" per tutti i contatti.
  /// Riusa i token esistenti della sessione LiveTrack. Chiamato dalla
  /// UI quando il countdown 5 min arriva a 0 senza risposta, oppure
  /// manualmente dall'utente via pulsante SOS (vedi [triggerManualSos]).
  Future<List<LifelineMessageDraft>> prepareInactivityDrafts() async {
    final sid = _state.sessionId;
    if (sid == null) return [];
    return _prepareAlertDrafts(
      sid: sid,
      prefix: '⚠️ ATTENZIONE — TrailShare',
      body:
          '$_userName è fermo da ${inactivityThreshold.inMinutes} minuti durante $_activityName e non ha risposto al check. Posizione live:',
    );
  }

  /// Costruisce i messaggi di SOS manuale.
  Future<List<LifelineMessageDraft>> prepareSosDrafts() async {
    final sid = _state.sessionId;
    if (sid == null) return [];
    return _prepareAlertDrafts(
      sid: sid,
      prefix: '🆘 SOS — TrailShare',
      body:
          '$_userName ha attivato un SOS durante $_activityName e ha bisogno di aiuto. Posizione live:',
    );
  }

  Future<List<LifelineMessageDraft>> _prepareAlertDrafts({
    required String sid,
    required String prefix,
    required String body,
  }) async {
    final drafts = <LifelineMessageDraft>[];
    try {
      final tokensSnap = await _firestore
          .collection('live_sessions')
          .doc(sid)
          .collection('access_tokens')
          .get();

      if (tokensSnap.docs.isEmpty) {
        debugPrint('[Lifeline] _prepareAlertDrafts: nessun token trovato');
        return [];
      }

      for (final c in _contacts) {
        // Cerca il token per questo contatto; fallback al primo token
        // se il matching specifico non trova nulla (non dovrebbe mai
        // succedere ma teniamo il link utilizzabile).
        String tokenId;
        final matching = tokensSnap.docs.where(
          (d) => d.data()['contactId'] == c.id,
        );
        if (matching.isNotEmpty) {
          tokenId = matching.first.id;
        } else {
          tokenId = tokensSnap.docs.first.id;
          debugPrint(
              '[Lifeline] Token non trovato per contatto ${c.name}, uso fallback');
        }

        final link = 'https://trailshare.app/live?id=$sid&token=$tokenId';
        drafts.add(LifelineMessageDraft(
          contact: c,
          link: link,
          text: '$prefix\n\n$body $link\n\nContattalo o chiama il 112.',
        ));
      }
    } catch (e) {
      debugPrint('[Lifeline] Errore _prepareAlertDrafts: $e');
    }
    return drafts;
  }

  /// Ferma Lifeline.
  ///
  /// Se [sendSafeArrival] è true, ritorna anche una lista di
  /// [LifelineMessageDraft] "Sono arrivato/a al sicuro" che la UI può
  /// proporre di inviare. Altrimenti lista vuota.
  Future<List<LifelineMessageDraft>> stop({
    required List<EmergencyContact> contacts,
    required String userName,
    bool sendSafeArrival = false,
  }) async {
    if (!_state.isActive) return [];

    final sessionId = _state.sessionId;
    List<LifelineMessageDraft> drafts = [];

    // Prepara messaggi safe-arrival se richiesto (ANCORA con token esistenti:
    // link resta utile per mostrare il tracciato completo come prova)
    if (sendSafeArrival && sessionId != null) {
      try {
        final tokensSnap = await _firestore
            .collection('live_sessions')
            .doc(sessionId)
            .collection('access_tokens')
            .get();
        if (tokensSnap.docs.isNotEmpty) {
          for (final c in contacts) {
            String tokenId;
            final matching = tokensSnap.docs.where(
              (d) => d.data()['contactId'] == c.id,
            );
            tokenId = matching.isNotEmpty
                ? matching.first.id
                : tokensSnap.docs.first.id;
            final link =
                'https://trailshare.app/live?id=$sessionId&token=$tokenId';
            drafts.add(LifelineMessageDraft(
              contact: c,
              link: link,
              text: '✅ Lifeline TrailShare — Ciao ${c.name}, sono $userName. '
                  'Sono rientrato/a in sicurezza dall\'attività. '
                  'Puoi rivedere il percorso qui: $link',
            ));
          }
        }
      } catch (e) {
        debugPrint('[Lifeline] errore preparazione safe-arrival: $e');
      }
    }

    // Ferma timer inattività
    _inactivityCheckTimer?.cancel();
    _inactivityCheckTimer = null;
    _autoAlertTimer?.cancel();
    _autoAlertTimer = null;
    _lastSignificantPosition = null;
    _lastMovementTime = null;
    // Rimuove eventuale notifica di allarme ancora attiva
    LifelineAlertService().dismiss();

    // Ferma LiveTrack (chiude la sessione su Firestore)
    await _liveTrack.stop();

    _state = LifelineState.off;
    _stateCtrl.add(_state);
    debugPrint('[Lifeline] fermata');

    return drafts;
  }

  /// Chiamato durante la registrazione: inoltra al LiveTrackService se
  /// Lifeline è attiva. (Oggi RecordPage chiama già LiveTrackService,
  /// quindi questo è usato solo quando si vuole un entry point unificato.)
  Future<void> updatePosition(double lat, double lng) async {
    if (!_state.isActive) return;
    await _liveTrack.updatePosition(lat, lng);
  }

  /// Genera un token crittograficamente robusto (24 byte base-36).
  /// Entropia ~124 bit — non brute-forzabile.
  String _generateToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(24, (_) => rnd.nextInt(256));
    // base36 compatto
    final n = BigInt.parse(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
    return n.toRadixString(36);
  }

  void dispose() {
    _stateCtrl.close();
  }
}
