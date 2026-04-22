import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Periodo temporale su cui aggregare la classifica regionale.
enum RegionalLeaderboardPeriod { allTime, monthly }

/// Metrica di ordinamento della classifica.
enum RegionalLeaderboardMetric { xp, distance }

/// Voce della classifica regionale.
class RegionalLeaderboardEntry {
  final String userId;
  final String username;
  final String? avatarUrl;
  final int level;
  final int totalXp;
  final String? region;

  /// Per il periodo [RegionalLeaderboardPeriod.monthly] è la distanza del
  /// mese in corso (metri). Per [allTime] rispecchia la somma denormalizzata
  /// se disponibile, oppure 0 se mancante.
  final double distance;

  /// Dislivello corrispondente al periodo (metri).
  final double elevation;

  /// Tracce nel periodo.
  final int tracks;

  /// Rank 1-based assegnato dal repository.
  final int rank;

  const RegionalLeaderboardEntry({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.level,
    required this.totalXp,
    this.region,
    required this.distance,
    required this.elevation,
    required this.tracks,
    required this.rank,
  });

  String get initial => username.isNotEmpty ? username[0].toUpperCase() : '?';
}

/// Repository per le classifiche regionali.
///
/// Le query lavorano su `user_profiles` che deve avere i campi:
/// - `region`: code della regione (vedi [ItalianRegions])
/// - `xp`, `level`: per il ranking all-time
/// - `monthlyDistanceCurrent`, `monthlyElevationCurrent`,
///   `monthlyTracksCurrent`, `monthlyStatsMonthId`: denormalizzati dal
///   `PostTrackSaveService` ad ogni salvataggio traccia, resettati quando
///   `monthlyStatsMonthId` non coincide col mese in corso.
class RegionalLeaderboardRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Ritorna la top N della regione richiesta.
  ///
  /// Per il periodo `monthly` la query è filtrata su
  /// `monthlyStatsMonthId == currentMonthId` così la top riflette solo il
  /// mese in corso.
  Future<List<RegionalLeaderboardEntry>> getTop({
    required String regionCode,
    RegionalLeaderboardPeriod period = RegionalLeaderboardPeriod.allTime,
    int limit = 50,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('user_profiles')
          .where('region', isEqualTo: regionCode);

      final now = DateTime.now();
      final currentMonthId =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

      switch (period) {
        case RegionalLeaderboardPeriod.allTime:
          query = query.orderBy('xp', descending: true).limit(limit);
          break;
        case RegionalLeaderboardPeriod.monthly:
          // Filtriamo al mese corrente per evitare di vedere dati stantii
          // di utenti che non registrano dal mese scorso.
          query = query
              .where('monthlyStatsMonthId', isEqualTo: currentMonthId)
              .orderBy('monthlyDistanceCurrent', descending: true)
              .limit(limit);
          break;
      }

      final snap = await query.get();
      debugPrint('[RegionalLeaderboard] region=$regionCode period=${period.name} '
          'risultati=${snap.docs.length}');

      return List.generate(snap.docs.length, (i) {
        final d = snap.docs[i].data();
        return RegionalLeaderboardEntry(
          userId: snap.docs[i].id,
          username: d['username']?.toString() ??
              d['displayName']?.toString() ??
              'Utente',
          avatarUrl: d['avatarUrl']?.toString() ?? d['photoURL']?.toString(),
          level: (d['level'] as num?)?.toInt() ?? 1,
          totalXp: (d['xp'] as num?)?.toInt() ?? 0,
          region: d['region']?.toString(),
          distance: period == RegionalLeaderboardPeriod.monthly
              ? ((d['monthlyDistanceCurrent'] as num?)?.toDouble() ?? 0)
              : ((d['totalDistance'] as num?)?.toDouble() ?? 0),
          elevation: period == RegionalLeaderboardPeriod.monthly
              ? ((d['monthlyElevationCurrent'] as num?)?.toDouble() ?? 0)
              : ((d['totalElevation'] as num?)?.toDouble() ?? 0),
          tracks: period == RegionalLeaderboardPeriod.monthly
              ? ((d['monthlyTracksCurrent'] as num?)?.toInt() ?? 0)
              : ((d['totalTracks'] as num?)?.toInt() ?? 0),
          rank: i + 1,
        );
      });
    } catch (e) {
      debugPrint('[RegionalLeaderboard] errore: $e');
      return const [];
    }
  }

  /// Posizione di un utente specifico nella classifica (rank 1-based) o
  /// null se l'utente non è in top o non è in quella regione.
  ///
  /// Versione semplificata: esegue la stessa query e cerca l'uid nella lista.
  /// Per una vera classifica con posizione "fuori-top" servirebbe una
  /// count query filtrata su `xp > currentUserXp`.
  Future<int?> getRankOfUser({
    required String regionCode,
    required String userId,
    RegionalLeaderboardPeriod period = RegionalLeaderboardPeriod.allTime,
    int limit = 100,
  }) async {
    final top = await getTop(
      regionCode: regionCode,
      period: period,
      limit: limit,
    );
    for (final e in top) {
      if (e.userId == userId) return e.rank;
    }
    return null;
  }
}
