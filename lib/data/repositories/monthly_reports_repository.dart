import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/monthly_report.dart';

/// Storage per i [MonthlyReport] dell'utente corrente:
/// `users/{uid}/monthly_reports/{yyyy-MM}`.
///
/// Il doc id corrisponde all'`yearMonthId` del mese target (es. "2026-04"),
/// quindi chiamate ripetute al generator sono upsert idempotenti.
class MonthlyReportsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection('users').doc(uid).collection('monthly_reports');

  String? get _uid => _auth.currentUser?.uid;

  /// Ritorna il report con l'id dato (es. "2026-04"), oppure null se non esiste.
  Future<MonthlyReport?> getById(String id) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final doc = await _col(uid).doc(id).get();
      if (!doc.exists || doc.data() == null) return null;
      return MonthlyReport.fromFirestore(doc.id, doc.data()!);
    } catch (e) {
      debugPrint('[MonthlyReports] getById error: $e');
      return null;
    }
  }

  Future<MonthlyReport?> getCurrent() async {
    return getById(MonthBoundaries.forNow().yearMonthId);
  }

  Future<MonthlyReport?> getPrevious() async {
    return getById(MonthBoundaries.forNow().previous().yearMonthId);
  }

  /// Upsert del report.
  Future<void> save(MonthlyReport report) async {
    final uid = _uid;
    if (uid == null) return;
    await _col(uid).doc(report.id).set(report.toFirestore());
    debugPrint('[MonthlyReports] salvato ${report.id} '
        '(tracks=${report.trackCount}, km=${(report.distance / 1000).toStringAsFixed(1)})');
  }

  /// Ultimi N report in ordine cronologico decrescente.
  Future<List<MonthlyReport>> getRecent({int limit = 12}) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final snap = await _col(uid)
          .orderBy('monthStart', descending: true)
          .limit(limit)
          .get();
      return snap.docs
          .map((d) => MonthlyReport.fromFirestore(d.id, d.data()))
          .toList();
    } catch (e) {
      debugPrint('[MonthlyReports] getRecent error: $e');
      return [];
    }
  }
}
