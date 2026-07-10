import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Integrazione Suunto Cloud API: l'utente collega il suo account Suunto
/// e gli allenamenti (GPS + battito, via FIT) arrivano in TrailShare
/// automaticamente via webhook server-side.
///
/// Clone di [PolarService]: il flow OAuth apre il browser sulla Cloud
/// Function `suuntoAuthStart` (con `state=<uid>`) — client_id solo nei
/// secrets server. Lo scambio code→token avviene in `suuntoCallback`,
/// che salva l'integrazione e torna al deep link
/// `trailshare://suunto/connected`.
class SuuntoService {
  /// URL della Cloud Function `suuntoAuthStart` (region europe-west3).
  static const String _authStartUrl =
      'https://europe-west3-trailshare-5334b.cloudfunctions.net/suuntoAuthStart';

  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('integrations')
        .doc('suunto');
  }

  /// Stream sullo stato di connessione (doc users/{uid}/integrations/suunto).
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

  /// Apre il browser per autorizzare TrailShare sull'account Suunto.
  Future<bool> connect() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('[Suunto] connect: utente non loggato');
      return false;
    }
    final uri =
        Uri.parse(_authStartUrl).replace(queryParameters: {'state': uid});
    debugPrint('[Suunto] launching: $uri');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
      debugPrint('[Suunto] externalApplication false, fallback platformDefault');
    } catch (e) {
      debugPrint('[Suunto] externalApplication errore $e, fallback');
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      debugPrint('[Suunto] anche platformDefault è fallito: $e');
      return false;
    }
  }

  Future<bool> disconnect() async {
    try {
      await _functions.httpsCallable('suuntoDisconnect').call();
      return true;
    } catch (e) {
      debugPrint('[Suunto] disconnect errore: $e');
      return false;
    }
  }

  /// Import manuale degli ultimi [limit] allenamenti (recupero storico/test).
  /// Ritorna il numero di tracce importate, o -1 su errore.
  Future<int> importRecent({int limit = 10}) async {
    try {
      final res = await _functions
          .httpsCallable('suuntoImportRecent')
          .call({'limit': limit});
      final data = Map<String, dynamic>.from(res.data as Map);
      return (data['imported'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[Suunto] importRecent errore: $e');
      return -1;
    }
  }
}
