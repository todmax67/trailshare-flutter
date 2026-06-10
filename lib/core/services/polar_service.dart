import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Integrazione Polar AccessLink: l'utente collega il suo account Polar Flow
/// e gli allenamenti (GPS + battito) arrivano in TrailShare automaticamente
/// via webhook server-side.
///
/// Il flow OAuth apre il browser sulla Cloud Function `polarAuthStart`
/// (con `state=<uid>`): è lei a redirigere su flow.polar.com con il
/// client_id, che così resta SOLO nei secrets server (a differenza di
/// Strava, nessun id nell'app). Lo scambio code→token avviene in
/// `polarCallback`, che salva l'integrazione e torna al deep link
/// `trailshare://polar/connected`.
class PolarService {
  /// URL della Cloud Function `polarAuthStart` (region europe-west3).
  static const String _authStartUrl =
      'https://europe-west3-trailshare-5334b.cloudfunctions.net/polarAuthStart';

  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('integrations')
        .doc('polar');
  }

  /// Stream sullo stato di connessione (doc users/{uid}/integrations/polar).
  Stream<bool> connectedStream() {
    final doc = _doc;
    if (doc == null) return Stream.value(false);
    return doc
        .snapshots()
        .map((s) => s.exists && (s.data()?['accessToken'] != null));
  }

  Future<bool> isConnected() async {
    final doc = _doc;
    if (doc == null) return false;
    final snap = await doc.get();
    return snap.exists && (snap.data()?['accessToken'] != null);
  }

  Future<void> setImportEnabled(bool enabled) async {
    await _doc?.set({'importEnabled': enabled}, SetOptions(merge: true));
  }

  Future<bool> isImportEnabled() async {
    final doc = _doc;
    if (doc == null) return false;
    final snap = await doc.get();
    return snap.exists && snap.data()?['importEnabled'] != false;
  }

  /// Apre il browser per autorizzare TrailShare su Polar Flow.
  Future<bool> connect() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('[Polar] connect: utente non loggato');
      return false;
    }
    final uri =
        Uri.parse(_authStartUrl).replace(queryParameters: {'state': uid});
    debugPrint('[Polar] launching: $uri');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
      debugPrint('[Polar] externalApplication false, fallback platformDefault');
    } catch (e) {
      debugPrint('[Polar] externalApplication errore $e, fallback');
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      debugPrint('[Polar] anche platformDefault è fallito: $e');
      return false;
    }
  }

  Future<bool> disconnect() async {
    try {
      await _functions.httpsCallable('polarDisconnect').call();
      return true;
    } catch (e) {
      debugPrint('[Polar] disconnect errore: $e');
      return false;
    }
  }
}
