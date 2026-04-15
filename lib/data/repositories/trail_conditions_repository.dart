import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/trail_condition.dart';

/// Repository per le segnalazioni di condizione sentiero.
///
/// Firestore schema:
/// ```
/// /trail_conditions/{trailId}/reports/{reportId}
/// ```
class TrailConditionsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _reportsCollection(String trailId) =>
      _firestore.collection('trail_conditions').doc(trailId).collection('reports');

  /// Tutte le segnalazioni di un sentiero, ordinate dalla più recente.
  Future<List<TrailCondition>> getReportsForTrail(
    String trailId, {
    int limit = 20,
  }) async {
    try {
      final snap = await _reportsCollection(trailId)
          .orderBy('reportedAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => TrailCondition.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint('[TrailConditions] Errore getReportsForTrail: $e');
      return [];
    }
  }

  /// L'ultima segnalazione del sentiero (o null se nessuna).
  Future<TrailCondition?> getLatestReport(String trailId) async {
    try {
      final snap = await _reportsCollection(trailId)
          .orderBy('reportedAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return TrailCondition.fromFirestore(snap.docs.first);
    } catch (e) {
      debugPrint('[TrailConditions] Errore getLatestReport: $e');
      return null;
    }
  }

  /// Crea una nuova segnalazione. Denormalizza username/avatar dal profilo.
  /// Ritorna il `TrailCondition` creato o `null` se errore.
  Future<TrailCondition?> createReport({
    required String trailId,
    required TrailConditionStatus status,
    String note = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[TrailConditions] Utente non loggato');
      return null;
    }

    try {
      // Leggi profilo per denormalizzare
      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();
      final profileData = profileDoc.data() ?? {};
      final username = (profileData['username'] as String?) ??
          user.displayName ??
          user.email?.split('@').first ??
          'Utente';
      final avatarUrl = (profileData['avatarUrl'] as String?) ?? user.photoURL;

      final docRef = _reportsCollection(trailId).doc();
      final report = TrailCondition(
        id: docRef.id,
        userId: user.uid,
        username: username,
        avatarUrl: avatarUrl,
        status: status,
        note: note.trim(),
        reportedAt: DateTime.now(),
      );

      await docRef.set(report.toFirestoreCreate());
      debugPrint('[TrailConditions] Report creato ${docRef.id} per trail $trailId');
      return report;
    } catch (e) {
      debugPrint('[TrailConditions] Errore createReport: $e');
      return null;
    }
  }

  /// Elimina una segnalazione. Check ownership lato client (le rules lo fanno comunque).
  Future<bool> deleteReport(String trailId, String reportId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      await _reportsCollection(trailId).doc(reportId).delete();
      return true;
    } catch (e) {
      debugPrint('[TrailConditions] Errore deleteReport: $e');
      return false;
    }
  }
}
