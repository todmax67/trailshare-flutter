import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Gestisce il codice di abbinamento tra l'utente e la watch app TrailShare per
/// Garmin (Connect IQ). Il codice si genera qui, si incolla nelle impostazioni
/// dell'app Connect IQ (via Garmin Connect Mobile) e l'orologio lo invia al
/// posto dello userId → la Cloud Function risolve l'utente in sicurezza.
class GarminPairingService {
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  /// Token attualmente attivo (se già generato), letto da Firestore.
  Future<String?> currentToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return snap.data()?['garminPairingToken'] as String?;
    } catch (e) {
      debugPrint('[GarminPairing] currentToken error: $e');
      return null;
    }
  }

  /// Genera (o rigenera) il codice di abbinamento. Ritorna il token.
  Future<String?> createPairing() async {
    try {
      final res = await _functions.httpsCallable('createGarminPairing').call();
      return (res.data as Map?)?['token'] as String?;
    } catch (e) {
      debugPrint('[GarminPairing] createPairing error: $e');
      return null;
    }
  }

  /// Revoca il codice corrente (l'orologio non potrà più inviare).
  Future<bool> revoke() async {
    try {
      await _functions.httpsCallable('revokeGarminPairing').call();
      return true;
    } catch (e) {
      debugPrint('[GarminPairing] revoke error: $e');
      return false;
    }
  }
}
