/// Telemetria del salvataggio tracce.
///
/// Nasce dal ticket del 2026-07-26 (utente che non trovava due trek): non
/// avevamo **nessun** modo di sapere quanto spesso un salvataggio fallisce o
/// resta solo locale. `debugPrint` non esiste nelle build release, quindi in
/// produzione eravamo ciechi.
///
/// Ogni tentativo di salvataggio scrive un doc piccolo in `save_diagnostics`.
/// Firestore invece di Firebase Analytics per tre motivi: i dati sono
/// interrogabili **subito** (Analytics ritarda fino a 24h e per le query serve
/// l'export BigQuery), li leggiamo con gli script di supporto che già usiamo,
/// e al volume attuale (~2-3 tracce/giorno) il costo è rumore di fondo.
///
/// Regola d'oro: questa classe non deve **mai** far fallire un salvataggio.
/// Ogni metodo inghiotte le proprie eccezioni ed è fire-and-forget.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'network_status.dart';

/// Esito di un tentativo di salvataggio.
enum SaveOutcome {
  /// L'utente ha confermato il salvataggio: inizio della scrittura.
  started,

  /// Il commit è stato confermato dal server.
  confirmedServer,

  /// Commit andato in timeout: la traccia è nella coda locale di Firestore e
  /// sincronizzerà da sola. NON è una perdita di dati, ma è lo stato in cui
  /// l'utente può non vedere la traccia nelle liste.
  localOnly,

  /// Il salvataggio è fallito con un'eccezione.
  failed,
}

class SaveDiagnosticsService {
  SaveDiagnosticsService._();
  static final SaveDiagnosticsService instance = SaveDiagnosticsService._();

  static const String _collection = 'save_diagnostics';

  String? _appVersion;

  Future<String> _version() async {
    if (_appVersion != null) return _appVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = 'unknown';
    }
    return _appVersion!;
  }

  String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name; // android / iOS / macOS...
  }

  /// Registra un evento del funnel di salvataggio.
  ///
  /// [attemptId] correla `started` con il suo esito: generalo una volta per
  /// tentativo (es. dall'ID della traccia, o da un timestamp) e passalo a
  /// entrambe le chiamate.
  ///
  /// Fire-and-forget: non attendere il Future se sei nel percorso critico del
  /// salvataggio.
  Future<void> record(
    SaveOutcome outcome, {
    required String attemptId,
    int? pointsCount,
    double? distanceMeters,
    int? durationSeconds,
    String? activityType,
    String? trackId,
    Object? error,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      // Senza utente non c'è nulla da diagnosticare (e le rules rifiuterebbero).
      if (uid == null) return;

      final data = <String, dynamic>{
        'userId': uid,
        'event': outcome.name,
        'attemptId': attemptId,
        'at': FieldValue.serverTimestamp(),
        // Timestamp client: sopravvive anche se il doc resta in coda offline,
        // dove `at` sarebbe null (è esattamente il caso che vogliamo misurare).
        // In UTC: senza fuso, confrontare eventi di utenti in paesi diversi
        // darebbe ordinamenti falsati.
        'atClient': DateTime.now().toUtc().toIso8601String(),
        'platform': _platform,
        'appVersion': await _version(),
        'online': NetworkStatus.instance.isOnline,
        if (pointsCount != null) 'pointsCount': pointsCount,
        if (distanceMeters != null) 'distance': distanceMeters,
        if (durationSeconds != null) 'duration': durationSeconds,
        if (activityType != null) 'activityType': activityType,
        if (trackId != null) 'trackId': trackId,
        if (error != null) 'error': _truncate(error.toString()),
      };

      // Nessun await sul commit: se siamo offline resta in coda e sincronizza
      // da sola, come la traccia. Attenderlo bloccherebbe il salvataggio.
      //
      // `catchError` NON è ridondante col try/catch qui attorno: quello
      // intercetta solo gli errori sincroni, mentre un rifiuto delle rules
      // arriva dopo, quando il Future fallisce. Senza gestore finirebbe in
      // `PlatformDispatcher.onError` (main.dart), che marca **fatal: true** —
      // cioè un problema di telemetria si travestirebbe da crash dell'app e
      // affosserebbe il crash-free rate.
      FirebaseFirestore.instance
          .collection(_collection)
          .add(data)
          .catchError((Object e) {
        debugPrint('[SaveDiagnostics] Scrittura rifiutata: $e');
        // Ritorno fittizio: il tipo di add() lo richiede, il valore non serve.
        return FirebaseFirestore.instance.collection(_collection).doc();
      });

      // Crashlytics: breadcrumb sempre, non-fatal solo sugli esiti anomali —
      // così in console vediamo il contesto delle registrazioni problematiche.
      // Il plugin non ha implementazione web: su web ci fermiamo al doc
      // Firestore (e comunque la registrazione tracce è mobile-only).
      if (kIsWeb) return;
      final crash = FirebaseCrashlytics.instance;
      crash.log('save:${outcome.name} attempt=$attemptId '
          'points=${pointsCount ?? '?'} online=${NetworkStatus.instance.isOnline}');
      if (outcome == SaveOutcome.failed) {
        await crash.recordError(
          error ?? 'save failed (no exception)',
          StackTrace.current,
          reason: 'Salvataggio traccia fallito',
          information: [
            'attemptId=$attemptId',
            'points=${pointsCount ?? '?'}',
            'platform=$_platform',
          ],
          fatal: false,
        );
      }
    } catch (e) {
      // Diagnostica rotta = problema di diagnostica, non dell'utente.
      debugPrint('[SaveDiagnostics] Errore registrazione evento: $e');
    }
  }

  /// Genera un ID di tentativo da correlare fra `started` e il suo esito.
  String newAttemptId() =>
      '${FirebaseAuth.instance.currentUser?.uid ?? 'anon'}_'
      '${DateTime.now().millisecondsSinceEpoch}';

  /// Manda a Crashlytics un errore che il codice ha già gestito e che
  /// altrimenti finirebbe solo in un `debugPrint` (invisibile in release).
  /// Non entra nel funnel: serve a non perdere i fallimenti dei passaggi
  /// intorno al salvataggio (upload foto, sync Health, Strava).
  Future<void> recordHandledError(
    Object error,
    StackTrace? stack, {
    required String reason,
  }) async {
    if (kIsWeb) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack ?? StackTrace.current,
        reason: reason,
        fatal: false,
      );
    } catch (e) {
      debugPrint('[SaveDiagnostics] Errore invio non-fatal: $e');
    }
  }

  String _truncate(String s) => s.length <= 500 ? s : '${s.substring(0, 500)}…';
}
