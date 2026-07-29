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
    // STEP 1: XP per la traccia — SOLO display, NON scrive
    // L'XP è assegnato UNA SOLA volta lato server (Cloud Function
    // onTrackCreate), per TUTTE le sorgenti (registrazione + import device).
    // Qui non scriviamo più XP (eliminato il doppio conteggio client+server):
    // calcoliamo i valori da mostrare con la STESSA formula del server e
    // rileviamo l'eventuale level-up rileggendo il profilo.
    // ═══════════════════════════════════════════════════════════════
    try {
      xpGranted = _gamification.previewServerXpForTrack(
        distanceMeters: distanceMeters,
        elevationGain: elevationGain,
      );
      // Level-up best-effort: diamo un attimo al trigger server, poi
      // confrontiamo il livello prima/dopo questa traccia.
      await Future.delayed(const Duration(milliseconds: 1200));
      final profileDoc =
          await _firestore.collection('user_profiles').doc(user.uid).get();
      final xpAfter = (profileDoc.data()?['xp'] as num?)?.toInt() ?? 0;
      final levelAfter = _gamification.calculateLevel(xpAfter);
      final levelBefore =
          _gamification.calculateLevel((xpAfter - xpGranted).clamp(0, xpAfter));
      leveledUp = levelAfter > levelBefore;
      newLevel = leveledUp ? levelAfter : null;
      debugPrint(
          '[PostTrackSave] ✅ XP (server): +$xpGranted, livello $levelAfter${leveledUp ? ' 🎉 LEVEL UP!' : ''}');
    } catch (e) {
      debugPrint('[PostTrackSave] ❌ Errore stima XP/level-up: $e');
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
      // VERIDICITÀ: i totali badge devono escludere i percorsi pianificati
      // col Planner (isPlanned=true), che non sono attività svolte. Firestore
      // non sa fare 'isPlanned != true OR isNull' in una query sola, ma
      // possiamo calcolare TUTTO e sottrarre la sola quota planner:
      // `isPlanned == true` matcha solo le planner (niente problema coi
      // documenti vecchi che hanno il campo mancante). Due aggregate sono
      // OOM-safe (non scaricano i GPS points) e a costo trascurabile.
      final tracksRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('tracks');
      final aggAll = await tracksRef
          .aggregate(count(), sum('distance'), sum('elevationGain'))
          .get();
      final aggPlanned = await tracksRef
          .where('isPlanned', isEqualTo: true)
          .aggregate(count(), sum('distance'), sum('elevationGain'))
          .get();
      final int totalTracks = (aggAll.count ?? 0) - (aggPlanned.count ?? 0);
      final double totalDistance =
          ((aggAll.getSum('distance') ?? 0) - (aggPlanned.getSum('distance') ?? 0))
              .toDouble();
      final double totalElevation = ((aggAll.getSum('elevationGain') ?? 0) -
              (aggPlanned.getSum('elevationGain') ?? 0))
          .toDouble();

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

        if (attempts.isNotEmpty) {
          // Il profilo si legge UNA volta, non a ogni giro. Stava dentro il
          // ciclo: finche' i passaggi erano al massimo uno per segmento la
          // differenza non si vedeva, ma con le ripetute il ciclo gira fino
          // a venti volte per segmento e rileggere lo stesso documento venti
          // volte e' solo attesa in piu' fra l'arrivo e il riepilogo.
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

          // I giri si raggruppano per segmento: le classifiche e i primati si
          // ragionano una volta per segmento, non una volta per giro.
          final giriPerSegmento = <String, List<SegmentMatchAttempt>>{};
          for (final a in attempts) {
            giriPerSegmento.putIfAbsent(a.segment.id, () => []).add(a);
          }

          for (final giri in giriPerSegmento.values) {
            final seg = giri.first.segment;

            // Letti una volta per segmento, PRIMA di scrivere: sono il
            // "com'era prima di oggi". Rileggendoli dentro il ciclo dei giri
            // il secondo giro si sarebbe confrontato col primo appena
            // scritto, e ogni ripetuta in progressione avrebbe annunciato un
            // nuovo record.
            final topBefore = await _segmentsRepo.getTopEffort(seg.id);
            final pbBefore = await _segmentsRepo.getUserBestEffort(seg.id, user.uid);

            // TUTTI i passaggi, non solo i primati.
            //
            // Prima qui c'era `if (isNewPB)`, per "evitare clutter" in
            // classifica. Ma la classifica ora tiene da sola un tempo a testa
            // (getLeaderboard deduplica per utente), mentre scartare i giri
            // piu' lenti buttava via proprio il dato che serve in un
            // allenamento a ripetute: se stai calando giro dopo giro lo si
            // vede solo avendoli tutti.
            for (final attempt in giri) {
              final effort = SegmentEffort(
                id: '',
                userId: user.uid,
                username: username,
                avatarUrl: avatarUrl,
                trackId: trackId,
                durationSeconds: attempt.durationSeconds,
                distance: seg.distance,
                averageSpeedKmh: attempt.averageSpeedKmh,
                // L'ora in cui si e' TAGLIATO IL TRAGUARDO, letta dalla
                // traccia. DateTime.now() era l'ora del salvataggio:
                // sbagliata su una traccia sincronizzata dall'orologio a
                // fine giornata, e uguale per tutti i giri dell'uscita.
                completedAt: track.points[attempt.endIdx].timestamp,
                // Niente trackStartIdx: e' un indice sui punti a piena
                // risoluzione, mentre il server legge la traccia decimata a
                // mille punti e ne calcolerebbe un altro. Vedi il commento
                // sul campo in segment.dart.
                passIndex: attempt.passIndex,
              );
              await _segmentsRepo.saveEffort(seg.id, effort);
            }

            // UN risultato per segmento, col migliore dei giri: e' quello che
            // si confronta col passato ed e' quello che si annuncia.
            final migliore = giri.reduce(
                (a, b) => a.durationSeconds <= b.durationSeconds ? a : b);

            segmentResults.add(SegmentMatchResult(
              segment: seg,
              durationSeconds: migliore.durationSeconds,
              distance: seg.distance,
              isNewRecord: topBefore == null ||
                  migliore.durationSeconds < topBefore.durationSeconds,
              isNewPB: pbBefore == null ||
                  migliore.durationSeconds < pbBefore.durationSeconds,
              previousPBSeconds: pbBefore?.durationSeconds,
              passCount: giri.length,
            ));
          }
        }
        debugPrint('[PostTrackSave] 🏁 Segmenti: ${segmentResults.length}, '
            'passaggi totali: ${attempts.length}');
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

    // STEP 6 (stats mensili/all-time per le classifiche regionali) è ora
    // gestito SERVER-SIDE dalla Cloud Function onTrackCreate — vedi il
    // commento lì: il set() client toccava chiavi mai whitelistate nelle
    // rules e veniva sempre respinto (il monthly regional leaderboard non ha
    // mai funzionato per un utente reale). Rimosso il write client-side
    // duplicato/rotto insieme al metodo _updateMonthlyDenormalizedStats.

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
