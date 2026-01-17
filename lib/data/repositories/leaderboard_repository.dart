import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repository per la Leaderboard
class LeaderboardRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Ottiene la classifica settimanale tra utenti seguiti
  /// 
  /// Calcola in tempo reale basandosi sulle tracce della settimana corrente
  Future<LeaderboardData> getWeeklyLeaderboard() async {
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

      // 3. Per ogni utente, calcola stats settimanali
      final List<LeaderboardEntry> entries = [];

      for (final userId in allUserIds) {
        final entry = await _calculateUserWeeklyStats(userId, weekStartDate);
        if (entry != null) {
          entries.add(entry);
        }
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
      print('[LeaderboardRepo] Errore: $e');
      return LeaderboardData(entries: [], currentUserRank: null);
    }
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

      // Ottieni tracce della settimana
      final tracksSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('tracks')
          .where('recordedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
          .get();

      double weeklyDistance = 0;
      double weeklyElevation = 0;
      int weeklyTracks = 0;
      int weeklyXp = 0;

      for (final doc in tracksSnapshot.docs) {
        final data = doc.data();
        weeklyDistance += (data['distance'] as num?)?.toDouble() ?? 0;
        weeklyElevation += (data['elevationGain'] as num?)?.toDouble() ?? 0;
        weeklyTracks++;
        
        // Calcola XP guadagnati (semplificato)
        // 1 XP per 100m di distanza + 1 XP per 10m di dislivello
        weeklyXp += ((data['distance'] as num?)?.toDouble() ?? 0) ~/ 100;
        weeklyXp += ((data['elevationGain'] as num?)?.toDouble() ?? 0) ~/ 10;
      }

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
      print('[LeaderboardRepo] Errore calcolo stats per $userId: $e');
      return null;
    }
  }

  /// Ottiene la classifica precalcolata (se disponibile)
  /// Fallback al calcolo in tempo reale se non esiste
  Future<LeaderboardData> getPrecomputedLeaderboard() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return LeaderboardData(entries: [], currentUserRank: null);
    }

    try {
      final leaderboardDoc = await _firestore
          .collection('leaderboards')
          .doc(user.uid)
          .get();

      if (!leaderboardDoc.exists) {
        // Fallback al calcolo in tempo reale
        return getWeeklyLeaderboard();
      }

      final data = leaderboardDoc.data()!;
      final leaderboardList = data['userLeaderboard'] as List? ?? [];

      final entries = leaderboardList.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value as Map<String, dynamic>;
        
        return LeaderboardEntry(
          userId: item['userId'] ?? '',
          username: item['username'] ?? 'Utente',
          avatarUrl: item['avatarUrl'],
          level: (item['level'] as num?)?.toInt() ?? 1,
          totalXp: (item['xp'] as num?)?.toInt() ?? 0,
          weeklyXp: (item['xp'] as num?)?.toInt() ?? 0,
          weeklyDistance: (item['distance'] as num?)?.toDouble() ?? 0,
          weeklyElevation: (item['elevation'] as num?)?.toDouble() ?? 0,
          weeklyTracks: (item['tracks'] as num?)?.toInt() ?? 0,
          rank: index + 1,
        );
      }).toList();

      // Trova rank utente corrente
      int? currentUserRank;
      for (final entry in entries) {
        if (entry.userId == user.uid) {
          currentUserRank = entry.rank;
          break;
        }
      }

      return LeaderboardData(
        entries: entries,
        currentUserRank: currentUserRank,
      );
    } catch (e) {
      print('[LeaderboardRepo] Errore leaderboard precalcolata: $e');
      return getWeeklyLeaderboard();
    }
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
