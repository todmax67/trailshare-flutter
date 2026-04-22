import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/track.dart';
import '../../data/models/weekly_challenge.dart';
import '../../data/repositories/tracks_repository.dart';
import '../../data/repositories/weekly_challenges_repository.dart';
import 'gamification_service.dart';

/// Orchestrator delle [WeeklyChallenge] personali.
///
/// Responsabilità:
/// 1. **Generator**: al primo ingresso in una settimana nuova crea una
///    sfida personalizzata basata sulla storia dell'utente (ultime 8
///    settimane di tracce).
/// 2. **Progress tracking**: quando l'utente salva una traccia, aggiorna il
///    progresso della sfida corrente se coerente con il tipo (distance,
///    elevation, tracks, duration).
/// 3. **Completion**: se `progress >= target`, passa lo stato a `completed`,
///    registra `completedAt` e dà XP via [GamificationService].
///
/// Usato da:
/// - [DashboardPage] per mostrare la card della sfida.
/// - [PostTrackSaveService] per alimentare il progresso.
/// - [DiscoveryPromptsRegistry] per suggerire all'utente di aprire la
///   dashboard quando c'è una sfida nuova / vicina al completamento.
class WeeklyChallengesService {
  WeeklyChallengesService._();
  static final WeeklyChallengesService _instance = WeeklyChallengesService._();
  factory WeeklyChallengesService() => _instance;

  final _repo = WeeklyChallengesRepository();
  final _tracksRepo = TracksRepository();
  final _gamification = GamificationService();

  /// Cache in-memory del valore corrente, aggiornata da [ensureCurrent] e
  /// dalle chiamate che modificano il progresso.
  WeeklyChallenge? _cached;

  WeeklyChallenge? get cached => _cached;

  /// Garantisce che esista una sfida per la settimana corrente.
  /// Se non esiste, la genera calcolando il target dalle ultime 8 settimane.
  Future<WeeklyChallenge?> ensureCurrent() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final existing = await _repo.getCurrent();
    if (existing != null) {
      _cached = existing;
      return existing;
    }

    // Non esiste: genera.
    final generated = await _generateForCurrentWeek(user.uid);
    if (generated == null) return null;
    await _repo.save(generated);
    _cached = generated;
    debugPrint('[WeeklyChallenges] generata nuova sfida: ${generated.type.code} '
        'target=${generated.target.toStringAsFixed(0)}');
    return generated;
  }

  /// Chiamato quando una nuova traccia viene salvata. Se esiste una sfida
  /// attiva per la settimana corrente e la metrica corrisponde al tipo della
  /// sfida, aggiorna il progresso e controlla il completion.
  ///
  /// Ritorna la sfida aggiornata (o null se nessuna sfida attiva).
  Future<WeeklyChallenge?> onTrackSaved(Track track) async {
    final challenge = await ensureCurrent();
    if (challenge == null || !challenge.isActive) return challenge;

    // Una traccia contribuisce alla sfida se appartiene alla settimana
    // corrente della sfida (typical: recordedAt ∈ [weekStart, weekEnd]).
    final trackDate = track.recordedAt ?? track.createdAt;
    if (trackDate.isBefore(challenge.weekStart) ||
        trackDate.isAfter(challenge.weekEnd)) {
      return challenge;
    }

    double delta = 0;
    switch (challenge.type) {
      case WeeklyChallengeType.distance:
        delta = track.stats.distance; // metri
        break;
      case WeeklyChallengeType.elevation:
        delta = track.stats.elevationGain; // metri
        break;
      case WeeklyChallengeType.tracks:
        delta = 1; // conteggio
        break;
      case WeeklyChallengeType.duration:
        delta = track.stats.movingTime.inSeconds.toDouble();
        if (delta <= 0) delta = track.stats.duration.inSeconds.toDouble();
        break;
    }

    if (delta <= 0) return challenge;

    final newProgress = challenge.progress + delta;
    final completed = newProgress >= challenge.target;
    final updated = challenge.copyWith(
      progress: newProgress,
      status: completed
          ? WeeklyChallengeStatus.completed
          : WeeklyChallengeStatus.active,
      completedAt: completed ? DateTime.now() : null,
    );
    await _repo.updateProgress(
      challenge.id,
      newProgress,
      status: completed ? WeeklyChallengeStatus.completed : null,
      completedAt: completed ? DateTime.now() : null,
    );
    _cached = updated;

    if (completed) {
      // Premio XP. Bloccante dalla transazione gamification ma veloce.
      await _gamification.grantXp(
        reason: 'weekly_challenge',
        amount: updated.xpReward,
        details: 'Sfida settimanale ${updated.type.code} completata',
      );
      debugPrint('[WeeklyChallenges] completata! XP +${updated.xpReward}');
    }

    return updated;
  }

  // ─── Generator ─────────────────────────────────────────────────────────

  /// Ritorna una sfida plausibile basata sulle ultime 8 settimane di tracce
  /// dell'utente. Se l'utente non ha ancora tracce abbastanza, sceglie
  /// target prudenti "entry-level" per non demoralizzare.
  Future<WeeklyChallenge?> _generateForCurrentWeek(String uid) async {
    final boundaries = WeekBoundaries.forNow();
    final id = boundaries.isoWeekId;

    final now = DateTime.now();
    final eightWeeksAgo = now.subtract(const Duration(days: 56));
    final tracks = await _tracksRepo.getMyTracks();
    final recent = tracks.where((t) {
      final d = t.recordedAt ?? t.createdAt;
      return d.isAfter(eightWeeksAgo) && d.isBefore(now);
    }).toList();

    // Medie settimanali.
    final weeks = 8;
    final avgDistancePerWeek = recent.fold<double>(0, (s, t) => s + t.stats.distance) / weeks;
    final avgElevationPerWeek = recent.fold<double>(0, (s, t) => s + t.stats.elevationGain) / weeks;
    final avgTracksPerWeek = recent.length / weeks;
    final avgDurationPerWeek = recent.fold<double>(
      0,
      (s, t) {
        final secs = t.stats.movingTime.inSeconds > 0
            ? t.stats.movingTime.inSeconds
            : t.stats.duration.inSeconds;
        return s + secs;
      },
    ) / weeks;

    // Rotazione tipo in base alla settimana: cicla tra i 4 tipi così l'utente
    // affronta varie dimensioni. Se l'utente ha storia = 0, forza tracks (più
    // ingaggiante per nuovi user: "registra 2 tracce").
    final hasHistory = recent.isNotEmpty;
    const cycle = [
      WeeklyChallengeType.distance,
      WeeklyChallengeType.tracks,
      WeeklyChallengeType.elevation,
      WeeklyChallengeType.duration,
    ];
    final weekOrdinal = now.difference(DateTime(now.year, 1, 1)).inDays ~/ 7;
    final type = hasHistory
        ? cycle[weekOrdinal % cycle.length]
        : WeeklyChallengeType.tracks;

    // Stretch: target = avg * 1.15 (arrotondato), min ragionevole.
    double target;
    int xp;
    switch (type) {
      case WeeklyChallengeType.distance:
        // Round to nearest 1 km. Min 10 km.
        final km = math.max(10.0, (avgDistancePerWeek * 1.15 / 1000).ceilToDouble());
        target = km * 1000;
        xp = (km * 2).round().clamp(30, 200);
        break;
      case WeeklyChallengeType.elevation:
        // Round to nearest 100m. Min 500m.
        final dplus = math.max(500.0, ((avgElevationPerWeek * 1.15) / 100).ceil() * 100.0);
        target = dplus;
        xp = (dplus / 20).round().clamp(30, 200);
        break;
      case WeeklyChallengeType.tracks:
        // Integer, min 2, max 6. Puntiamo sempre +1 rispetto alla media.
        final count = (avgTracksPerWeek + 1).ceil().clamp(2, 6);
        target = count.toDouble();
        xp = (count * 20).clamp(40, 150);
        break;
      case WeeklyChallengeType.duration:
        // Round to 30 min. Min 2h.
        final mins = math.max(120.0, (avgDurationPerWeek * 1.15 / 60 / 30).ceil() * 30.0);
        target = mins * 60;
        xp = (mins / 10).round().clamp(30, 200);
        break;
    }

    return WeeklyChallenge(
      id: id,
      userId: uid,
      type: type,
      target: target,
      progress: 0,
      weekStart: boundaries.start,
      weekEnd: boundaries.end,
      status: WeeklyChallengeStatus.active,
      xpReward: xp,
      createdAt: DateTime.now(),
    );
  }
}
