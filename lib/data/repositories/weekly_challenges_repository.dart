import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/weekly_challenge.dart';

/// Storage per le [WeeklyChallenge] dell'utente corrente:
/// `users/{uid}/weekly_challenges/{challengeId}`.
///
/// Il challengeId corrisponde all'`isoWeekId` della settimana target, così
/// chiamate ripetute al generator non creano duplicati (upsert idempotente).
class WeeklyChallengesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection('users').doc(uid).collection('weekly_challenges');

  String? get _uid => _auth.currentUser?.uid;

  Future<WeeklyChallenge?> getCurrent() async {
    final uid = _uid;
    if (uid == null) return null;
    final id = WeekBoundaries.forNow().isoWeekId;
    try {
      final doc = await _col(uid).doc(id).get();
      if (!doc.exists || doc.data() == null) return null;
      return WeeklyChallenge.fromFirestore(doc.id, doc.data()!);
    } catch (e) {
      // permission-denied, offline o transitorio: non far crashare il
      // caller (discover carousel, post-track save, ecc.). Ritorna null
      // e lascia che chi chiama gestisca l'assenza della sfida.
      debugPrint('[WeeklyChallengesRepo] getCurrent failed: $e');
      return null;
    }
  }

  Future<WeeklyChallenge?> getById(String id) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final doc = await _col(uid).doc(id).get();
      if (!doc.exists || doc.data() == null) return null;
      return WeeklyChallenge.fromFirestore(doc.id, doc.data()!);
    } catch (e) {
      debugPrint('[WeeklyChallengesRepo] getById failed: $e');
      return null;
    }
  }

  Future<void> save(WeeklyChallenge challenge) async {
    final uid = _uid;
    if (uid == null) return;
    await _col(uid).doc(challenge.id).set(challenge.toFirestore());
    debugPrint('[WeeklyChallenges] salvata ${challenge.id} '
        '(${challenge.type.code}, target=${challenge.target}, progress=${challenge.progress})');
  }

  Future<void> updateProgress(String id, double progress, {
    WeeklyChallengeStatus? status,
    DateTime? completedAt,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _col(uid).doc(id).update({
      'progress': progress,
      if (status != null) 'status': status.name,
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt),
    });
  }

  /// Ritorna le ultime N sfide (utile per storia / calcolo media).
  Future<List<WeeklyChallenge>> getRecent({int limit = 12}) async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _col(uid)
        .orderBy('weekStart', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => WeeklyChallenge.fromFirestore(d.id, d.data()))
        .toList();
  }
}
