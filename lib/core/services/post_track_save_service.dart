import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'gamification_service.dart';
import 'challenges_service.dart';
import 'segment_matching_service.dart';
import '../../data/models/segment.dart';
import '../../data/models/track.dart';
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
      // Calcola totali utente da tutte le tracce
      final tracksSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('tracks')
          .get();

      double totalDistance = 0;
      double totalElevation = 0;
      int totalTracks = tracksSnapshot.docs.length;

      for (final doc in tracksSnapshot.docs) {
        final data = doc.data();
        totalDistance += (data['distance'] as num?)?.toDouble() ?? 0;
        totalElevation += (data['elevationGain'] as num?)?.toDouble() ?? 0;
      }

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
            await showLevelUpDialog(
              context,
              newLevel: newLevel,
              totalXp: totalXp,
            );
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

    debugPrint('[PostTrackSave] ═══════════════════════════════════════');

    return PostTrackSaveResult(
      xpGranted: xpGranted,
      leveledUp: leveledUp,
      newLevel: newLevel,
      newBadges: newBadges,
      segmentResults: segmentResults,
    );
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

  const PostTrackSaveResult({
    this.xpGranted = 0,
    this.leveledUp = false,
    this.newLevel,
    this.newBadges = const [],
    this.segmentResults = const [],
  });
}
