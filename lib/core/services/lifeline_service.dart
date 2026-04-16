import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../data/models/emergency_contact.dart';
import '../../data/repositories/emergency_contacts_repository.dart';
import 'live_track_service.dart';

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
  const LifelineState({
    required this.isActive,
    required this.contactsCount,
    this.sessionId,
  });

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

    _state = LifelineState(
      isActive: true,
      contactsCount: contacts.length,
      sessionId: sessionId,
    );
    _stateCtrl.add(_state);
    debugPrint('[Lifeline] avviata: sessionId=$sessionId contacts=${contacts.length}');

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
        for (final c in contacts) {
          final tokenDoc = tokensSnap.docs.firstWhere(
            (d) => d.data()['contactId'] == c.id,
            orElse: () => tokensSnap.docs.isNotEmpty
                ? tokensSnap.docs.first
                : throw StateError('no tokens'),
          );
          final link = 'https://trailshare.app/live?id=$sessionId&token=${tokenDoc.id}';
          drafts.add(LifelineMessageDraft(
            contact: c,
            link: link,
            text:
                '✅ Lifeline TrailShare — Ciao ${c.name}, sono $userName. '
                'Sono rientrato/a in sicurezza dall\'attività. '
                'Puoi rivedere il percorso qui: $link',
          ));
        }
      } catch (e) {
        debugPrint('[Lifeline] errore preparazione safe-arrival: $e');
      }
    }

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
