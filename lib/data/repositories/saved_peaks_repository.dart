import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/mountain_peak.dart';

/// Repository per le **cime salvate** dell'utente — collezione personale
/// di vette riconosciute con il Mountain Finder che l'utente vuole
/// ricordare ("le cime fatte" o "da fare").
///
/// Storage: `users/{uid}/saved_peaks/{peakId}` con i campi del
/// [MountainPeak] + `savedAt` timestamp.
///
/// Differente dalla `WishlistRepository` che è per i percorsi (track):
/// le cime sono entità geografiche fisse (no track GPS associato),
/// quindi un proprio storage dedicato.
class SavedPeaksRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>>? _userPeaksCol() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('saved_peaks');
  }

  /// True se la cima è già nella lista personale.
  Future<bool> isSaved(String peakId) async {
    final col = _userPeaksCol();
    if (col == null) return false;
    try {
      final doc = await col.doc(peakId).get();
      return doc.exists;
    } catch (e) {
      debugPrint('[SavedPeaks] isSaved error: $e');
      return false;
    }
  }

  /// Toggle: aggiunge se non esiste, rimuove altrimenti.
  /// Ritorna true se ora la cima è SALVATA, false se è stata rimossa.
  /// In caso di errore lancia.
  Future<bool> toggle(MountainPeak peak) async {
    final col = _userPeaksCol();
    if (col == null) {
      throw StateError('User not authenticated');
    }
    final docRef = col.doc(peak.id);
    final exists = (await docRef.get()).exists;
    if (exists) {
      await docRef.delete();
      debugPrint('[SavedPeaks] removed ${peak.name}');
      return false;
    }
    await docRef.set({
      ...peak.toJson(),
      'savedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('[SavedPeaks] saved ${peak.name}');
    return true;
  }

  /// Lista completa delle cime salvate, ordinata per data salvataggio
  /// decrescente.
  Future<List<MountainPeak>> getAll({int limit = 200}) async {
    final col = _userPeaksCol();
    if (col == null) return const [];
    try {
      final snap = await col
          .orderBy('savedAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs
          .map((d) => MountainPeak.fromJson(d.data()))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[SavedPeaks] getAll error: $e');
      return const [];
    }
  }

  /// Stream della collezione (per UI reattiva).
  Stream<List<MountainPeak>> watchAll() {
    final col = _userPeaksCol();
    if (col == null) return Stream.value(const []);
    return col
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => MountainPeak.fromJson(d.data()))
            .toList(growable: false));
  }
}
