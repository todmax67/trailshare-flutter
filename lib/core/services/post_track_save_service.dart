import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'badge_evaluator_service.dart';
import 'gamification_service.dart';
import 'challenges_service.dart';
import 'segment_matching_service.dart';
import 'weekly_challenges_service.dart';
import '../extensions/l10n_extension.dart';
import '../../data/models/segment.dart';
import '../../data/models/track.dart';
import '../../data/models/weekly_challenge.dart';
import '../../data/repositories/groups_repository.dart';
import '../../data/repositories/segments_repository.dart';
import '../../presentation/widgets/level_up_dialog.dart';
import '../../presentation/widgets/segment_results_dialog.dart';
import '../../presentation/widgets/xp_snack_bar.dart';

/// Servizio centralizzato per gestire tutte le azioni post-salvataggio traccia.
///
/// Dopo ogni salvataggio traccia (manuale, auto-save, navigazione),
/// questo servizio si occupa di:
/// 1. Assegnare XP per la traccia completata
/// 2. Controllare e sbloccare badge maturati
/// 3. Aggiornare il progresso delle sfide attive
/// 4. Mostrare notifiche e dialogs all'utente
///
/// Utilizzo:
/// ```dart
/// await PostTrackSaveService.handleTrackSaved(
///   context: context,
///   distanceMeters: track.stats.distance,
///   elevationGain: track.stats.elevationGain,
///   durationSeconds: track.stats.duration.inSeconds,
/// );
/// ```
class PostTrackSaveService {
  static final GamificationService _gamification = GamificationService();
  static final ChallengesService _challenges = ChallengesService();
  static final SegmentsRepository _segmentsRepo = SegmentsRepository();
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Gestisce tutte le azioni post-salvataggio traccia.
  ///
  /// [context] - BuildContext per mostrare dialogs/snackbar (opzionale)
  /// [distanceMeters] - Distanza della traccia in metri
  /// [elevationGain] - Dislivello positivo in metri
  /// [durationSeconds] - Durata in secondi
  /// [showDialogs] - Se mostrare dialogs level-up/badge (default true)
  static Future<PostTrackSaveResult> handleTrackSaved({
    BuildContext? context,
    required double distanceMeters,
    required double elevationGain,
    required int durationSeconds,
    bool showDialogs = true,
    Track? track,
    String? trackId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[PostTrackSave] Utente non loggato, skip');
      return const PostTrackSaveResult();
    }

    debugPrint('[PostTrackSave] ═══════════════════════════════════════');
    debugPrint('[PostTrackSave] Traccia salvata: ${(distanceMeters / 1000).toStringAsFixed(1)}km, +${elevationGain.toStringAsFixed(0)}m, ${durationSeconds}s');

    int xpGranted = 0;
    bool leveledUp = false;
    int? newLevel;
    List<GameBadge> newBadges = [];
    List<SegmentMatchResult> segmentResults = [];

    // ═══════════════════════════════════════════════════════════════
    // STEP 1: Assegna XP per la traccia
    // ═══════════════════════════════════════════════════════════════
    try {
      // Controlla se è la prima traccia
      final tracksCount = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('tracks')
          .count()
          .get();
      final isFirstTrack = (tracksCount.count ?? 0) <= 1;

      final xpResult = await _gamification.grantXpForTrack(
        distanceMeters: distanceMeters,
        elevationGain: elevationGain,
        duration: Duration(seconds: durationSeconds),
        isFirstTrack: isFirstTrack,
      );

      if (xpResult.success) {
        xpGranted = xpResult.xpGranted ?? 0;
        leveledUp = xpResult.leveledUp;
        newLevel = xpResult.newLevel;
        debugPrint('[PostTrackSave] ✅ XP: +$xpGranted (totale: ${xpResult.totalXp})${leveledUp ? ' 🎉 LEVEL UP → $newLevel!' : ''}');
      } else {
        debugPrint('[PostTrackSave] ⚠️ XP errore: ${xpResult.error}');
      }
    } catch (e) {
      debugPrint('[PostTrackSave] ❌ Errore XP: $e');
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 2: Controlla e sblocca badge
    // ═══════════════════════════════════════════════════════════════
    try {
      // Calcola totali utente via SERVER-SIDE aggregation.
      // CRITICO: il loop precedente scaricava ogni traccia con i GPS
      // points embedded (24MB+ su utenti con storico) → OutOfMemory
      // sul thread Firestore proprio al post-save di una traccia,
      // crashando l'app nel flow più critico.
      //
      // TRADE-OFF: l'aggregation include anche le tracce pianificate
      // (planner ORS) nei totali badge — Firestore non supporta
      // 'isPlanned != true OR isNull' in una sola query e split + sum
      // raddoppia il costo. Il bias è minimo (utenti tipici hanno
      // pochissime planned tracks) e infinitamente preferibile a un
      // crash. La precisione si recupera col fix vero (split sub-
      // collection track_points, già in backlog).
      final tracksRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('tracks');
      final agg = await tracksRef
          .aggregate(
            count(),
            sum('distance'),
            sum('elevationGain'),
          )
          .get();
      final int totalTracks = agg.count ?? 0;
      final double totalDistance =
          (agg.getSum('distance') ?? 0).toDouble();
      final double totalElevation =
          (agg.getSum('elevationGain') ?? 0).toDouble();

      // Ottieni followers
      int followersCount = 0;
      int cheersReceived = 0;

      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();

      if (profileDoc.exists) {
        final profileData = profileDoc.data()!;
        final followers = profileData['followers'] as List?;
        followersCount = followers?.length ?? 0;
      }

      // Conta cheers ricevuti
      final publishedSnapshot = await _firestore
          .collection('published_tracks')
          .where('originalOwnerId', isEqualTo: user.uid)
          .get();

      for (final doc in publishedSnapshot.docs) {
        final data = doc.data();
        // `cheerCount` è la fonte autorevole (Cloud Function). Il vecchio
        // `cheersCount` client è deprecato; teniamo il max come fallback per i
        // doc storici non ancora riallineati.
        final c1 = (data['cheerCount'] as num?)?.toInt() ?? 0;
        final c2 = (data['cheersCount'] as num?)?.toInt() ?? 0;
        cheersReceived += c1 > c2 ? c1 : c2;
      }

      debugPrint('[PostTrackSave] Totali: $totalTracks tracce, ${totalDistance.toStringAsFixed(0)}m, +${totalElevation.toStringAsFixed(0)}m, $followersCount followers, $cheersReceived cheers');

      // Sblocca badge maturati
      newBadges = await _gamification.checkAndUnlockBadges(
        totalDistance: totalDistance,
        totalElevation: totalElevation,
        totalTracks: totalTracks,
        followersCount: followersCount,
        cheersReceived: cheersReceived,
        currentStreak: 0, // TODO: calcolare streak giorni consecutivi
      );

      if (newBadges.isNotEmpty) {
        debugPrint('[PostTrackSave] 🏅 Nuovi badge: ${newBadges.map((b) => b.name).join(', ')}');
      }

      // Sistema badge Garmin-style (Epic refactor): popola in parallelo
      // i tier multi-livello (totalDistance_bronze..platinum, ecc.).
      // Best-effort, non blocca il flow se errore.
      try {
        await BadgeEvaluatorService().getAllProgress();
      } catch (e) {
        debugPrint('[PostTrackSave] BadgeEvaluator error: $e');
      }
    } catch (e) {
      debugPrint('[PostTrackSave] ❌ Errore badge: $e');
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 3: Aggiorna progresso sfide attive
    // ═══════════════════════════════════════════════════════════════
    try {
      await _challenges.updateProgress(
        distanceMeters: distanceMeters,
        elevationGain: elevationGain,
        tracksCount: 1,
      );
      debugPrint('[PostTrackSave] ✅ Sfide aggiornate');
    } catch (e) {
      debugPrint('[PostTrackSave] ❌ Errore sfide: $e');
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 4: Matching segmenti cronometrati
    // ═══════════════════════════════════════════════════════════════
    if (track != null && trackId != null) {
      try {
        final segments = await _segmentsRepo.getAllSegments();
        final attempts = SegmentMatchingService.match(track, segments);

        for (final attempt in attempts) {
          // Ricava username/avatar denormalizzati
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

          // Top assoluto e PB precedenti
          final topBefore = await _segmentsRepo.getTopEffort(attempt.segment.id);
          final pbBefore = await _segmentsRepo.getUserBestEffort(attempt.segment.id, user.uid);

          final isNewRecord = topBefore == null ||
              attempt.durationSeconds < topBefore.durationSeconds;
          final isNewPB = pbBefore == null ||
              attempt.durationSeconds < pbBefore.durationSeconds;

          // Salva l'effort solo se PB (evita clutter)
          if (isNewPB) {
            final effort = SegmentEffort(
              id: '',
              userId: user.uid,
              username: username,
              avatarUrl: avatarUrl,
              trackId: trackId,
              durationSeconds: attempt.durationSeconds,
              distance: attempt.segment.distance,
              averageSpeedKmh: attempt.averageSpeedKmh,
              completedAt: DateTime.now(),
            );
            await _segmentsRepo.saveEffort(attempt.segment.id, effort);
          }

          segmentResults.add(SegmentMatchResult(
            segment: attempt.segment,
            durationSeconds: attempt.durationSeconds,
            distance: attempt.segment.distance,
            isNewRecord: isNewRecord,
            isNewPB: isNewPB,
            previousPBSeconds: pbBefore?.durationSeconds,
          ));
        }
        debugPrint('[PostTrackSave] 🏁 Segmenti completati: ${segmentResults.length}');
      } catch (e) {
        debugPrint('[PostTrackSave] ❌ Errore segmenti: $e');
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 5: Mostra notifiche UI
    // ═══════════════════════════════════════════════════════════════
    if (showDialogs && context != null && context.mounted) {
      try {
        // Snackbar XP
        if (xpGranted > 0) {
          XpSnackBar.show(context, xpGained: xpGranted, reason: 'track_completed');
        }

        // Dialog level-up
        if (leveledUp && newLevel != null) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (context.mounted) {
            final totalXp = await _getCurrentXp(user.uid);
            if (context.mounted) {
              await showLevelUpDialog(
                context,
                newLevel: newLevel,
                totalXp: totalXp,
              );
            }
          }
        }

        // Dialog badge sbloccati
        for (final badge in newBadges) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (context.mounted) {
            await showBadgeUnlockedDialog(context, badge);
          }
        }

        // Dialog segmenti completati
        if (segmentResults.isNotEmpty && context.mounted) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (context.mounted) {
            await showSegmentResultsDialog(context, segmentResults);
          }
        }
      } catch (e) {
        debugPrint('[PostTrackSave] ⚠️ Errore UI dialogs: $e');
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 6: Denormalizza stats mensili sul profilo utente
    // (usate dalle classifiche regionali — 3.3)
    // ═══════════════════════════════════════════════════════════════
    try {
      await _updateMonthlyDenormalizedStats(
        userId: user.uid,
        distance: distanceMeters,
        elevation: elevationGain,
      );
    } catch (e) {
      debugPrint('[PostTrackSave] ⚠️ Errore stats mensili: $e');
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 5: Aggiorna progresso sfida settimanale personale
    // ═══════════════════════════════════════════════════════════════
    WeeklyChallenge? weeklyChallengeCompleted;
    if (track != null) {
      try {
        final before = WeeklyChallengesService().cached;
        final after = await WeeklyChallengesService().onTrackSaved(track);
        if (after != null &&
            after.isCompleted &&
            (before == null || !before.isCompleted)) {
          weeklyChallengeCompleted = after;
          debugPrint('[PostTrackSave] 🏆 Sfida settimanale completata! +${after.xpReward} XP');
        }
      } catch (e) {
        debugPrint('[PostTrackSave] ⚠️ Errore weekly challenge: $e');
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 5.b: Aggiorna sfide di gruppo (Epic 3.2)
    // Best-effort: per ogni gruppo dell'utente, somma il contributo
    // della traccia alle sfide attive (distance/elevation/tracks/streak).
    // La Cloud Function `onChallengeStandingUpdated` controlla
    // eventuale completamento target e notifica i partecipanti.
    // ═══════════════════════════════════════════════════════════════
    if (track != null) {
      try {
        await GroupsRepository().autoUpdateGroupChallengesForTrack(
          trackDate: track.recordedAt ?? track.createdAt,
          distanceMeters: distanceMeters,
          elevationGain: elevationGain,
        );
      } catch (e) {
        debugPrint('[PostTrackSave] ⚠️ Errore group challenges: $e');
      }
    }

    // Dialog di celebrazione sfida (post-tutti gli altri dialogs).
    if (weeklyChallengeCompleted != null &&
        showDialogs &&
        context != null &&
        context.mounted) {
      try {
        await _showChallengeCompletedDialog(context, weeklyChallengeCompleted);
      } catch (e) {
        debugPrint('[PostTrackSave] ⚠️ Errore dialog sfida: $e');
      }
    }

    debugPrint('[PostTrackSave] ═══════════════════════════════════════');

    return PostTrackSaveResult(
      xpGranted: xpGranted,
      leveledUp: leveledUp,
      newLevel: newLevel,
      newBadges: newBadges,
      segmentResults: segmentResults,
      weeklyChallengeCompleted: weeklyChallengeCompleted,
    );
  }

  static Future<void> _showChallengeCompletedDialog(
    BuildContext context,
    WeeklyChallenge c,
  ) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.emoji_events, size: 48, color: Color(0xFFFFA726)),
        title: Text(ctx.l10n.weeklyChallengeCompletedDialogTitle),
        content: Text(ctx.l10n.weeklyChallengeCompletedDialogBody(c.xpReward)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.gotItAction),
          ),
        ],
      ),
    );
  }

  /// Denormalizza sul documento `user_profiles/{uid}` i contatori mensili
  /// usati dalle classifiche regionali (3.3).
  ///
  /// Campi aggiornati:
  /// - `monthlyStatsMonthId`: `yyyy-MM` del mese in corso.
  /// - `monthlyDistanceCurrent`, `monthlyElevationCurrent`,
  ///   `monthlyTracksCurrent`: somma del mese in corso.
  /// - `totalDistance`, `totalElevation`, `totalTracks`: totali all-time
  ///   incrementali.
  ///
  /// Se il mese è cambiato rispetto al valore salvato, i contatori mensili
  /// vengono resettati ai valori della traccia corrente prima dell'increment.
  /// Usa una transaction per evitare race condition tra tracce vicine.
  static Future<void> _updateMonthlyDenormalizedStats({
    required String userId,
    required double distance,
    required double elevation,
  }) async {
    final now = DateTime.now();
    final currentMonthId =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

    final profileRef =
        _firestore.collection('user_profiles').doc(userId);

    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(profileRef);
      final data = snap.data() ?? {};
      final storedMonthId = data['monthlyStatsMonthId']?.toString();

      final bool sameMonth = storedMonthId == currentMonthId;
      final double prevDist = sameMonth
          ? ((data['monthlyDistanceCurrent'] as num?)?.toDouble() ?? 0)
          : 0;
      final double prevEle = sameMonth
          ? ((data['monthlyElevationCurrent'] as num?)?.toDouble() ?? 0)
          : 0;
      final int prevTracks = sameMonth
          ? ((data['monthlyTracksCurrent'] as num?)?.toInt() ?? 0)
          : 0;

      final double newMonthDist = prevDist + distance;
      final double newMonthEle = prevEle + elevation;
      final int newMonthTracks = prevTracks + 1;

      // Totali all-time: sempre incrementali, anche se il mese cambia.
      final double totalDist =
          ((data['totalDistance'] as num?)?.toDouble() ?? 0) + distance;
      final double totalEle =
          ((data['totalElevation'] as num?)?.toDouble() ?? 0) + elevation;
      final int totalTracks =
          ((data['totalTracks'] as num?)?.toInt() ?? 0) + 1;

      transaction.set(
        profileRef,
        {
          'monthlyStatsMonthId': currentMonthId,
          'monthlyDistanceCurrent': newMonthDist,
          'monthlyElevationCurrent': newMonthEle,
          'monthlyTracksCurrent': newMonthTracks,
          'totalDistance': totalDist,
          'totalElevation': totalEle,
          'totalTracks': totalTracks,
          'lastTrackAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
    debugPrint('[PostTrackSave] ✅ Stats mensili aggiornate ($currentMonthId): '
        '+${(distance / 1000).toStringAsFixed(1)}km, +${elevation.toStringAsFixed(0)}m');
  }

  /// Ottiene XP corrente per dialogs
  static Future<int> _getCurrentXp(String userId) async {
    try {
      final doc = await _firestore.collection('user_profiles').doc(userId).get();
      return (doc.data()?['xp'] as num?)?.toInt() ?? 0;
    } catch (e) {
      return 0;
    }
  }
}

/// Risultato delle azioni post-salvataggio
class PostTrackSaveResult {
  final int xpGranted;
  final bool leveledUp;
  final int? newLevel;
  final List<GameBadge> newBadges;
  final List<SegmentMatchResult> segmentResults;

  /// Non-null se la sfida settimanale è stata completata con questa
  /// traccia. Contiene la challenge in stato `completed`.
  final WeeklyChallenge? weeklyChallengeCompleted;

  const PostTrackSaveResult({
    this.xpGranted = 0,
    this.leveledUp = false,
    this.newLevel,
    this.newBadges = const [],
    this.segmentResults = const [],
    this.weeklyChallengeCompleted,
  });
}
