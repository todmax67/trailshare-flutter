import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Integrazione Strava: OAuth + upload one-shot a fine attività.
///
/// I client_id/client_secret vivono lato Cloud Functions (mai nell'app).
/// Il flow OAuth apre il browser su strava.com/oauth/authorize con
/// `state=<uid>`; lo scambio code→token avviene nella function
/// `stravaCallback`, che redirige all'app via deep link
/// `trailshare://strava/connected`.
class StravaService {
  StravaService._();
  static final StravaService _instance = StravaService._();
  factory StravaService() => _instance;

  static const String _stravaClientId = String.fromEnvironment(
    'STRAVA_CLIENT_ID',
    defaultValue: '',
  );

  /// URL della Cloud Function `stravaCallback` (region europe-west3).
  /// Va aggiornato quando crei l'app Strava: il dominio deve combaciare con
  /// "Authorization Callback Domain" sul portale developer Strava.
  static const String _callbackUrl =
      'https://europe-west3-trailshare-5334b.cloudfunctions.net/stravaCallback';

  static const String _scopes = 'read,activity:write,activity:read_all';

  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  /// Stream sullo stato di connessione (doc users/{uid}/integrations/strava).
  Stream<bool> connectedStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('integrations').doc('strava')
        .snapshots()
        .map((s) => s.exists && (s.data()?['accessToken'] != null));
  }

  Future<bool> isConnected() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final snap = await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('integrations').doc('strava').get();
    return snap.exists && (snap.data()?['accessToken'] != null);
  }

  Future<bool> isAutoUploadEnabled() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final snap = await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('integrations').doc('strava').get();
    if (!snap.exists) return false;
    return snap.data()?['autoUploadEnabled'] == true;
  }

  Future<void> setAutoUploadEnabled(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('integrations').doc('strava')
        .set({'autoUploadEnabled': enabled}, SetOptions(merge: true));
  }

  Future<void> setImportFromStravaEnabled(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('integrations').doc('strava')
        .set({'importFromStravaEnabled': enabled}, SetOptions(merge: true));
  }

  /// Apre il browser su Strava per autorizzare l'app.
  /// Il client_id deve essere passato a build-time:
  /// `flutter build/run --dart-define=STRAVA_CLIENT_ID=12345`.
  Future<bool> connect() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('[Strava] connect: utente non loggato');
      return false;
    }
    if (_stravaClientId.isEmpty) {
      debugPrint('[Strava] connect: STRAVA_CLIENT_ID mancante (--dart-define)');
      return false;
    }

    final uri = Uri.parse('https://www.strava.com/oauth/authorize').replace(
      queryParameters: {
        'client_id': _stravaClientId,
        'redirect_uri': _callbackUrl,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': _scopes,
        'state': uid,
      },
    );
    debugPrint('[Strava] launching: $uri');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> disconnect() async {
    try {
      await _functions.httpsCallable('stravaDisconnect').call();
      return true;
    } catch (e) {
      debugPrint('[Strava] disconnect errore: $e');
      return false;
    }
  }

  /// Carica una traccia su Strava. Idempotente lato server (controlla
  /// `stravaActivityId` sul track doc). Ritorna `stravaActivityId` se ok.
  Future<String?> uploadTrack(String trackId) async {
    try {
      final res = await _functions
          .httpsCallable('stravaUploadActivity')
          .call({'trackId': trackId});
      final data = res.data as Map?;
      if (data == null) return null;
      if (data['ok'] == true) {
        return data['stravaActivityId']?.toString();
      }
      debugPrint('[Strava] upload non completato: ${data['status']} '
          'err=${data['error']}');
      return null;
    } catch (e) {
      debugPrint('[Strava] upload errore: $e');
      return null;
    }
  }

  /// Da chiamare a fine "Salva attività" se sync abilitato. Fire-and-forget.
  Future<void> uploadTrackIfEnabled(String trackId) async {
    if (!await isAutoUploadEnabled()) return;
    if (!await isConnected()) return;
    final id = await uploadTrack(trackId);
    debugPrint('[Strava] auto-upload track=$trackId result=$id');
  }
}
