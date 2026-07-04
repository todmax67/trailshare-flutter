import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/utils/perf_trace.dart';

/// Repository per la Leaderboard
class LeaderboardRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Ottiene la classifica settimanale tra utenti seguiti
  ///
  /// Calcola in tempo reale basandosi sulle tracce della settimana corrente
  Future<LeaderboardData> getWeeklyLeaderboard() {
    return PerfTrace.track(
      'leaderboard.getWeeklyLeaderboard',
      _getWeeklyLeaderboard,
      describe: (d) => '${d.entries.length} utenti in classifica',
    );
  }

  Future<LeaderboardData> _getWeeklyLeaderboard() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return LeaderboardData(entries: [], currentUserRank: null);
    }

    try {
      // 1. Ottieni lista utenti seguiti
      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(user.uid)
          .get();

      List<String> followingIds = [];
      if (profileDoc.exists) {
        followingIds = List<String>.from(profileDoc.data()?['following'] ?? []);
      }

      // Aggiungi l'utente corrente alla lista
      final allUserIds = [user.uid, ...followingIds];

      // 2. Calcola inizio settimana (lunedì)
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);

      // 3. FAST PATH — stats settimanali denormalizzate sui profili,
      // mantenute lato server da onTrackCreate/onTrackUpdate (reset lazy):
      // 1 query whereIn ogni 30 utenti sui doc user_profiles (leggeri),
      // NIENTE subcollection tracks — che su Android costava 23-32s per il
      // peso dei doc legacy con i points GPS inline.
      final weekId = '${weekStartDate.year}-'
          '${weekStartDate.month.toString().padLeft(2, '0')}-'
          '${weekStartDate.day.toString().padLeft(2, '0')}';
      final profiles = await PerfTrace.track(
        'leaderboard.profilesFetch',
        () => _fetchProfiles(allUserIds),
        describe: (m) => '${m.length} profili',
      );

      // Rollout-safe: se NESSUN profilo ha il campo weekly, la function non
      // è ancora deployata o il backfill non è girato → calcolo real-time
      // come prima. Se almeno uno ce l'ha, chi non ce l'ha vale zero (il
      // backfill scrive il campo a TUTTI i profili, quindi l'assenza
      // significa profilo nato dopo, senza attività).
      final denormLive =
          profiles.values.any((d) => d.containsKey('weeklyStatsWeekId'));

      final List<LeaderboardEntry> entries;
      if (denormLive) {
        entries = [
          for (final userId in allUserIds)
            if (profiles.containsKey(userId))
              _entryFromProfile(userId, profiles[userId]!, weekId),
        ];
      } else {
        entries = await _computeRealtimeLeaderboard(allUserIds, weekStartDate);
      }

      // 4. Ordina per XP (o distanza)
      entries.sort((a, b) => b.weeklyXp.compareTo(a.weeklyXp));

      // 5. Assegna rank e trova posizione utente corrente
      int? currentUserRank;
      for (int i = 0; i < entries.length; i++) {
        entries[i] = entries[i].copyWith(rank: i + 1);
        if (entries[i].userId == user.uid) {
          currentUserRank = i + 1;
        }
      }

      return LeaderboardData(
        entries: entries,
        currentUserRank: currentUserRank,
        weekStart: weekStartDate,
      );
    } catch (e) {
      debugPrint('[LeaderboardRepo] Errore: $e');
      return LeaderboardData(entries: [], currentUserRank: null);
    }
  }

  /// Fetch dei profili via whereIn sull'id documento, a batch di 30
  /// (limite Firestore). Ritorna solo i profili esistenti: gli utenti
  /// cancellati spariscono dalla classifica (prima comparivano come
  /// "Utente" a zero).
  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
      List<String> userIds) async {
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < userIds.length; i += 30) {
      final batch = userIds.skip(i).take(30).toList();
      final snap = await _firestore
          .collection('user_profiles')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      for (final doc in snap.docs) {
        out[doc.id] = doc.data();
      }
    }
    return out;
  }

  /// Entry dalla denormalizzazione server. Un weeklyStatsWeekId diverso
  /// dalla settimana corrente = nessuna attività questa settimana (reset
  /// lazy: il server azzera il bucket solo alla prossima traccia).
  LeaderboardEntry _entryFromProfile(
      String userId, Map<String, dynamic> data, String weekId) {
    final sameWeek = data['weeklyStatsWeekId'] == weekId;
    return LeaderboardEntry(
      userId: userId,
      username: data['username'] ?? data['displayName'] ?? 'Utente',
      avatarUrl: data['avatarUrl'] ?? data['photoURL'],
      level: (data['level'] as num?)?.toInt() ?? 1,
      totalXp: (data['xp'] as num?)?.toInt() ?? 0,
      weeklyXp: sameWeek ? (data['weeklyXpCurrent'] as num?)?.toInt() ?? 0 : 0,
      weeklyDistance: sameWeek
          ? (data['weeklyDistanceCurrent'] as num?)?.toDouble() ?? 0.0
          : 0.0,
      weeklyElevation: sameWeek
          ? (data['weeklyElevationCurrent'] as num?)?.toDouble() ?? 0.0
          : 0.0,
      weeklyTracks:
          sameWeek ? (data['weeklyTracksCurrent'] as num?)?.toInt() ?? 0 : 0,
      rank: 0, // Verrà assegnato dopo
    );
  }

  /// FALLBACK pre-rollout: calcolo real-time dalle tracce, in batch
  /// paralleli da 8. Usato solo finché la denormalizzazione weekly non è
  /// deployata + backfillata; poi diventa codice morto rimovibile insieme
  /// a _calculateUserWeeklyStats.
  Future<List<LeaderboardEntry>> _computeRealtimeLeaderboard(
      List<String> allUserIds, DateTime weekStartDate) async {
    final List<LeaderboardEntry> entries = [];
    const batchSize = 8;
    for (var i = 0; i < allUserIds.length; i += batchSize) {
      final batch = allUserIds.skip(i).take(batchSize);
      final results = await Future.wait(
        batch.map((userId) => _calculateUserWeeklyStats(userId, weekStartDate)),
      );
      entries.addAll(results.whereType<LeaderboardEntry>());
    }
    return entries;
  }

  /// Calcola le statistiche settimanali di un utente
  Future<LeaderboardEntry?> _calculateUserWeeklyStats(
    String userId,
    DateTime weekStart,
  ) async {
    try {
      // Ottieni profilo utente
      final profileDoc = await _firestore
          .collection('user_profiles')
          .doc(userId)
          .get();

      String username = 'Utente';
      String? avatarUrl;
      int totalXp = 0;
      int level = 1;

      if (profileDoc.exists) {
        final data = profileDoc.data()!;
        username = data['username'] ?? data['displayName'] ?? 'Utente';
        avatarUrl = data['avatarUrl'] ?? data['photoURL'];
        totalXp = (data['xp'] as num?)?.toInt() ?? 0;
        level = (data['level'] as num?)?.toInt() ?? 1;
      }

      // ⭐ FIX: carica TUTTE le tracce e filtra lato client
      // Il database ha formati data misti (Timestamp, String ISO, int milliseconds)
      // quindi .where() con Timestamp non funziona per tutte le tracce.
      // Per utente sono poche tracce, quindi è efficiente caricarle tutte.
      final allTracksSnapshot = await PerfTrace.track(
        'leaderboard.tracksFetch[$userId]',
        () => _firestore
            .collection('users')
            .doc(userId)
            .collection('tracks')
            .get(),
        describe: (s) => '${s.docs.length} doc',
      );

      debugPrint('[LeaderboardRepo] Utente $userId: ${allTracksSnapshot.docs.length} tracce totali, weekStart: $weekStart');

      double weeklyDistance = 0;
      double weeklyElevation = 0;
      int weeklyTracks = 0;
      int weeklyXp = 0;

      for (final doc in allTracksSnapshot.docs) {
        final data = doc.data();

        // ⭐ VERIDICITÀ: solo attività realmente svolte. I percorsi
        // pianificati col Planner (isPlanned=true) hanno recordedAt=null e
        // ripiegherebbero su createdAt cadendo "questa settimana" →
        // gonfierebbero la classifica. Escludili (regola canonica).
        if (data['isPlanned'] == true) continue;

        // Parsing data robusto: gestisce Timestamp, String ISO, int milliseconds
        final rawRecordedAt = data['recordedAt'];
        final rawCreatedAt = data['createdAt'];
        DateTime? trackDate = _parseDate(rawRecordedAt) ?? _parseDate(rawCreatedAt);
        
        debugPrint('[LeaderboardRepo]   Traccia ${doc.id}: recordedAt=${rawRecordedAt?.runtimeType}:$rawRecordedAt, createdAt=${rawCreatedAt?.runtimeType}:$rawCreatedAt → parsed=$trackDate');
        
        // Filtra solo tracce della settimana corrente
        if (trackDate == null || trackDate.isBefore(weekStart)) {
          debugPrint('[LeaderboardRepo]   → SKIP (fuori settimana o data null)');
          continue;
        }
        
        final dist = (data['distance'] as num?)?.toDouble() ?? 0;
        final ele = (data['elevationGain'] as num?)?.toDouble() ?? 0;
        if (dist <= 0) continue; // tracce vuote/annullate: non sono attività
        weeklyDistance += dist;
        weeklyElevation += ele;
        weeklyTracks++;
        
        // Calcola XP guadagnati (semplificato)
        // 1 XP per 100m di distanza + 1 XP per 10m di dislivello
        weeklyXp += dist ~/ 100;
        weeklyXp += ele ~/ 10;
        
        debugPrint('[LeaderboardRepo]   → INCLUSA! dist=${dist.toStringAsFixed(0)}m, ele=${ele.toStringAsFixed(0)}m');
      }
      
      debugPrint('[LeaderboardRepo] Risultato $username: $weeklyTracks tracce, ${weeklyDistance.toStringAsFixed(0)}m, +${weeklyElevation.toStringAsFixed(0)}m, $weeklyXp XP');

      return LeaderboardEntry(
        userId: userId,
        username: username,
        avatarUrl: avatarUrl,
        level: level,
        totalXp: totalXp,
        weeklyXp: weeklyXp,
        weeklyDistance: weeklyDistance,
        weeklyElevation: weeklyElevation,
        weeklyTracks: weeklyTracks,
        rank: 0, // Verrà assegnato dopo
      );
    } catch (e) {
      debugPrint('[LeaderboardRepo] Errore calcolo stats per $userId: $e');
      return null;
    }
  }

  /// Helper: parsing robusto di date Firestore (Timestamp, String ISO, int ms)
  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  /// Ottiene la classifica. Con la denormalizzazione weekly attiva
  /// (onTrackCreate/onTrackUpdate + backfill) è davvero precalcolata:
  /// _getWeeklyLeaderboard legge i soli profili e ricade sul real-time
  /// solo se i campi weekly non esistono ancora.
  Future<LeaderboardData> getPrecomputedLeaderboard() async {
    return getWeeklyLeaderboard();
  }
}

/// Dati completi della leaderboard
class LeaderboardData {
  final List<LeaderboardEntry> entries;
  final int? currentUserRank;
  final DateTime? weekStart;

  const LeaderboardData({
    required this.entries,
    required this.currentUserRank,
    this.weekStart,
  });

  bool get isEmpty => entries.isEmpty;
  int get totalParticipants => entries.length;
}

/// Entry singola della leaderboard
class LeaderboardEntry {
  final String userId;
  final String username;
  final String? avatarUrl;
  final int level;
  final int totalXp;
  final int weeklyXp;
  final double weeklyDistance;
  final double weeklyElevation;
  final int weeklyTracks;
  final int rank;

  const LeaderboardEntry({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.level,
    required this.totalXp,
    required this.weeklyXp,
    required this.weeklyDistance,
    required this.weeklyElevation,
    required this.weeklyTracks,
    required this.rank,
  });

  LeaderboardEntry copyWith({
    String? userId,
    String? username,
    String? avatarUrl,
    int? level,
    int? totalXp,
    int? weeklyXp,
    double? weeklyDistance,
    double? weeklyElevation,
    int? weeklyTracks,
    int? rank,
  }) {
    return LeaderboardEntry(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      level: level ?? this.level,
      totalXp: totalXp ?? this.totalXp,
      weeklyXp: weeklyXp ?? this.weeklyXp,
      weeklyDistance: weeklyDistance ?? this.weeklyDistance,
      weeklyElevation: weeklyElevation ?? this.weeklyElevation,
      weeklyTracks: weeklyTracks ?? this.weeklyTracks,
      rank: rank ?? this.rank,
    );
  }

  /// Iniziale per avatar placeholder
  String get initial => username.isNotEmpty ? username[0].toUpperCase() : '?';

  /// Distanza formattata
  String get distanceFormatted {
    if (weeklyDistance < 1000) return '${weeklyDistance.toStringAsFixed(0)} m';
    return '${(weeklyDistance / 1000).toStringAsFixed(1)} km';
  }

  /// Dislivello formattato
  String get elevationFormatted => '${weeklyElevation.toStringAsFixed(0)} m';
}
