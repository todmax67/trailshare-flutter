import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/badge_family.dart';
import '../../data/models/track.dart';

/// Servizio che calcola lo stato di TUTTE le famiglie di badge per
/// l'utente corrente (Garmin-style).
///
/// Sostituisce la vecchia logica binary unlocked/locked di
/// GamificationService.checkAndUnlockBadges con un sistema multi-tier:
/// - 11 famiglie (totalDistance, totalElevation, totalTracks, streak,
///   followers, cheersReceived, trailRunner, cyclist, mountainBiker,
///   skiTourer, peakConquered)
/// - 4 tier per famiglia (Bronze, Silver, Gold, Platinum)
/// - 44 badge totali possibili
///
/// Persistenza: un doc per tier sbloccato su `users/{uid}/badges/{id}`
/// con `id = "${family.wireName}_${tier.wireName}"`. La data di sblocco
/// è il primo evaluate che ha rilevato il superamento della soglia.
/// I doc legacy (es. `hiker_50km`) sono preservati e mappati alla nuova
/// famiglia/tier via [LegacyBadgeMapping].
class BadgeEvaluatorService {
  BadgeEvaluatorService._();
  static final BadgeEvaluatorService _instance = BadgeEvaluatorService._();
  factory BadgeEvaluatorService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Calcola lo stato di tutte le famiglie. Carica metriche
  /// dall'utente e dai badge già sbloccati, computa progress per
  /// ciascuna famiglia, e ritorna la lista ordinata.
  ///
  /// I caller possono usare il flag [evaluateNewUnlocks] per
  /// scrivere su Firestore i badge tier non ancora persistiti (es.
  /// chiamare a `BadgesPage.initState` o post-track-save).
  Future<List<BadgeProgress>> getAllProgress({
    bool evaluateNewUnlocks = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return const [];

    final stats = await _computeUserStats(user.uid);
    final unlockedMap = await _loadUnlocked(user.uid);

    final List<BadgeProgress> result = [];
    for (final family in GameBadgeFamily.values) {
      final value = stats.valueFor(family);
      final progress = BadgeProgress.compute(
        family: family,
        currentValue: value,
        unlockedAt: unlockedMap[family],
      );
      result.add(progress);

      // Persisti i nuovi tier raggiunti che non erano già sbloccati.
      if (evaluateNewUnlocks && progress.currentTier != null) {
        await _persistNewlyUnlocked(
          uid: user.uid,
          progress: progress,
        );
      }
    }
    return result;
  }

  /// Carica le metriche aggregate dell'utente. Ignora le tracce
  /// `isPlanned=true` (pianificate dal Planner ORS, non realmente
  /// svolte) per coerenza col fix dashboard/leaderboard.
  Future<_UserStats> _computeUserStats(String uid) async {
    // 1) Profilo (followers)
    int followers = 0;
    try {
      final pdoc =
          await _firestore.collection('user_profiles').doc(uid).get();
      final p = pdoc.data();
      followers = (p?['followers'] as List?)?.length ?? 0;
    } catch (e) {
      debugPrint('[BadgeEvaluator] profile load error: $e');
    }

    // 2) Tracce: aggrega totali per family. Filtro isPlanned.
    double totalDistance = 0; // metri
    double totalElevation = 0;
    int totalTracks = 0;
    double trailRunningKm = 0;
    double cyclingKm = 0;
    double mtbKm = 0;
    int skiTourerSessions = 0;
    final activeDays = <String>{}; // YYYY-MM-DD per streak

    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('tracks')
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['isPlanned'] == true) continue;
        totalTracks += 1;
        final dist = (d['distance'] as num?)?.toDouble() ?? 0;
        final eleG = (d['elevationGain'] as num?)?.toDouble() ?? 0;
        totalDistance += dist;
        totalElevation += eleG;

        final at = (d['activityType']?.toString() ?? '').toLowerCase();
        final km = dist / 1000;
        if (_isTrailRunning(at)) trailRunningKm += km;
        if (_isCycling(at)) cyclingKm += km;
        if (_isMtb(at)) mtbKm += km;
        if (_isSki(at)) skiTourerSessions += 1;

        final dateStr = _extractDateKey(d);
        if (dateStr != null) activeDays.add(dateStr);
      }
    } catch (e) {
      debugPrint('[BadgeEvaluator] tracks load error: $e');
    }

    // 3) Cheers ricevuti: somma dei `cheerCount` sulle published_tracks
    //    dell'utente. Più semplice del fetch di ogni doc cheers.
    int cheers = 0;
    try {
      final pubSnap = await _firestore
          .collection('published_tracks')
          .where('originalOwnerId', isEqualTo: uid)
          .get();
      for (final p in pubSnap.docs) {
        cheers += ((p.data()['cheerCount'] as num?)?.toInt() ?? 0);
      }
    } catch (e) {
      debugPrint('[BadgeEvaluator] cheers load error: $e');
    }

    // 4) Cime salvate (Mountain Finder): leggi count da saved_peaks.
    int peaks = 0;
    try {
      final peaksSnap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('saved_peaks')
          .count()
          .get();
      peaks = peaksSnap.count ?? 0;
    } catch (e) {
      debugPrint('[BadgeEvaluator] peaks load error: $e');
    }

    // 5) Streak: max sequenza consecutiva di giorni con almeno una
    //    traccia, fino ad oggi. Lo calcoliamo qui in-memory ordinando
    //    activeDays e cercando run più lunga che termini oggi-1
    //    (oggi può non aver registrato ancora).
    final streak = _computeStreak(activeDays);

    return _UserStats(
      totalDistanceKm: totalDistance / 1000,
      totalElevationM: totalElevation,
      totalTracks: totalTracks,
      streakDays: streak,
      followers: followers,
      cheersReceived: cheers,
      trailRunningKm: trailRunningKm,
      cyclingKm: cyclingKm,
      mtbKm: mtbKm,
      skiTourerSessions: skiTourerSessions,
      peakConquered: peaks,
    );
  }

  /// Streak = run più lunga di giorni consecutivi che include oggi
  /// (o ieri, per dare grace di 1 giorno alla giornata di evaluation).
  int _computeStreak(Set<String> activeDays) {
    if (activeDays.isEmpty) return 0;
    final today = DateTime.now();
    DateTime cursor = today;
    // Se non hai registrato oggi, parti da ieri per non azzerare la
    // streak quando arrivi alle 8:00 prima di uscire.
    final todayKey = _dateKey(today);
    if (!activeDays.contains(todayKey)) {
      cursor = today.subtract(const Duration(days: 1));
    }
    int count = 0;
    while (activeDays.contains(_dateKey(cursor))) {
      count += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String? _extractDateKey(Map<String, dynamic> trackData) {
    final ra = trackData['recordedAt'];
    DateTime? d;
    if (ra is Timestamp) d = ra.toDate();
    if (ra is String) d = DateTime.tryParse(ra);
    if (d == null) {
      final ca = trackData['createdAt'];
      if (ca is Timestamp) d = ca.toDate();
      if (ca is String) d = DateTime.tryParse(ca);
    }
    return d == null ? null : _dateKey(d);
  }

  bool _isTrailRunning(String at) =>
      at == ActivityType.running.name ||
      at == ActivityType.trailRunning.name ||
      at == 'running' ||
      at == 'trail_running' ||
      at == 'trailrunning';
  bool _isCycling(String at) =>
      at == ActivityType.cycling.name ||
      at == ActivityType.gravelBiking.name ||
      at == ActivityType.eBike.name ||
      at == 'cycling' ||
      at == 'gravel_biking' ||
      at == 'e_bike';
  bool _isMtb(String at) =>
      at == ActivityType.mountainBiking.name ||
      at == ActivityType.eMountainBike.name ||
      at == 'mountainbike' ||
      at == 'mtb' ||
      at == 'mountain_biking';
  bool _isSki(String at) =>
      at == ActivityType.skiTouring.name ||
      at == ActivityType.snowshoeing.name ||
      at == 'ski_touring' ||
      at == 'snowshoeing';

  /// Carica i badge sbloccati dell'utente, inclusi i legacy ID
  /// mappati alle famiglie nuove via [LegacyBadgeMapping].
  /// Ritorna `Map<family, Map<tier, DateTime>>`.
  Future<Map<GameBadgeFamily, Map<GameBadgeTier, DateTime>>> _loadUnlocked(
      String uid) async {
    final result = <GameBadgeFamily, Map<GameBadgeTier, DateTime>>{};
    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('badges')
          .get();
      for (final doc in snap.docs) {
        final id = doc.id;
        final data = doc.data();
        final unlockedAt = (data['unlockedAt'] is Timestamp)
            ? (data['unlockedAt'] as Timestamp).toDate()
            : DateTime.now();

        // Nuovo formato: family_tier (es. totalDistance_bronze)
        final parts = id.split('_');
        if (parts.length >= 2) {
          final tier = GameBadgeTier.fromWire(parts.last);
          final familyStr = parts.sublist(0, parts.length - 1).join('_');
          final family = GameBadgeFamily.fromWire(familyStr);
          if (family != null && tier != null) {
            (result[family] ??= {})[tier] = unlockedAt;
            continue;
          }
        }
        // Legacy: mappa via LegacyBadgeMapping.
        final legacy = LegacyBadgeMapping.lookup(id);
        if (legacy != null) {
          (result[legacy.family] ??= {})[legacy.tier] = unlockedAt;
        }
      }
    } catch (e) {
      debugPrint('[BadgeEvaluator] unlocked load error: $e');
    }
    return result;
  }

  /// Scrive su Firestore i tier raggiunti ma non ancora persistiti.
  /// Idempotente via doc id deterministico.
  Future<void> _persistNewlyUnlocked({
    required String uid,
    required BadgeProgress progress,
  }) async {
    if (progress.currentTier == null) return;
    for (var i = 0; i <= progress.currentTier!.index; i++) {
      final tier = GameBadgeTier.values[i];
      if (progress.unlockedAtFor(tier) != null) continue; // già unlocked
      final id = progress.family.badgeId(tier);
      try {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('badges')
            .doc(id)
            .set({
          'family': progress.family.wireName,
          'tier': tier.wireName,
          'unlockedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('[BadgeEvaluator] sbloccato $id');
      } catch (e) {
        debugPrint('[BadgeEvaluator] persist $id error: $e');
      }
    }
  }
}

class _UserStats {
  final double totalDistanceKm;
  final double totalElevationM;
  final int totalTracks;
  final int streakDays;
  final int followers;
  final int cheersReceived;
  final double trailRunningKm;
  final double cyclingKm;
  final double mtbKm;
  final int skiTourerSessions;
  final int peakConquered;

  const _UserStats({
    required this.totalDistanceKm,
    required this.totalElevationM,
    required this.totalTracks,
    required this.streakDays,
    required this.followers,
    required this.cheersReceived,
    required this.trailRunningKm,
    required this.cyclingKm,
    required this.mtbKm,
    required this.skiTourerSessions,
    required this.peakConquered,
  });

  double valueFor(GameBadgeFamily f) {
    switch (f) {
      case GameBadgeFamily.totalDistance:
        return totalDistanceKm;
      case GameBadgeFamily.totalElevation:
        return totalElevationM;
      case GameBadgeFamily.totalTracks:
        return totalTracks.toDouble();
      case GameBadgeFamily.streak:
        return streakDays.toDouble();
      case GameBadgeFamily.followers:
        return followers.toDouble();
      case GameBadgeFamily.cheersReceived:
        return cheersReceived.toDouble();
      case GameBadgeFamily.trailRunner:
        return trailRunningKm;
      case GameBadgeFamily.cyclist:
        return cyclingKm;
      case GameBadgeFamily.mountainBiker:
        return mtbKm;
      case GameBadgeFamily.skiTourer:
        return skiTourerSessions.toDouble();
      case GameBadgeFamily.peakConquered:
        return peakConquered.toDouble();
    }
  }
}
