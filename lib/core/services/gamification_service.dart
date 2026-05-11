import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Servizio Gamification
/// 
/// Gestisce il sistema di punti esperienza (XP), livelli e badge.
class GamificationService {
  static final GamificationService _instance = GamificationService._internal();
  factory GamificationService() => _instance;
  GamificationService._internal();

  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============================================
  // CONFIGURAZIONE XP
  // ============================================
  
  static const Map<String, int> xpRewards = {
    'track_completed': 50,
    'km_hiked': 10,
    'elevation_100m': 15,
    'first_track': 100,
    'streak_day': 25,
    'track_published': 30,
    'cheers_received': 5,
    'new_follower': 10,
    'challenge_completed': 200,
  };

  static const List<int> levelThresholds = [
    0, 100, 300, 600, 1000, 1500, 2200, 3000, 4000, 5200,
    6600, 8200, 10000, 12000, 14500, 17500, 21000, 25000, 30000, 36000,
  ];

  static const Map<int, String> levelNames = {
    1: 'Principiante',
    2: 'Escursionista',
    3: 'Camminatore',
    4: 'Esploratore',
    5: 'Avventuriero',
    6: 'Pioniere',
    7: 'Scopritore',
    8: 'Veterano',
    9: 'Maestro',
    10: 'Esperto',
    11: 'Guida',
    12: 'Ranger',
    13: 'Alpinista',
    14: 'Conquistatore',
    15: 'Leggenda',
    16: 'Elite',
    17: 'Campione',
    18: 'Eroe',
    19: 'Mito',
    20: 'Immortale',
  };

  // ============================================
  // CALCOLO LIVELLO
  // ============================================

  int calculateLevel(int totalXp) {
    for (int i = levelThresholds.length - 1; i >= 0; i--) {
      if (totalXp >= levelThresholds[i]) {
        return i + 1;
      }
    }
    return 1;
  }

  LevelInfo calculateLevelInfo(int totalXp) {
    final level = calculateLevel(totalXp);
    final currentThreshold = levelThresholds[level - 1];
    final nextThreshold = level < levelThresholds.length 
        ? levelThresholds[level] 
        : levelThresholds.last + 10000;
    
    final xpInCurrentLevel = totalXp - currentThreshold;
    final xpNeededForNext = nextThreshold - currentThreshold;
    final progress = (xpInCurrentLevel / xpNeededForNext * 100).clamp(0.0, 100.0);

    return LevelInfo(
      level: level,
      totalXp: totalXp,
      currentLevelXp: xpInCurrentLevel,
      xpForNextLevel: xpNeededForNext,
      progress: progress,
      levelName: levelNames[level] ?? 'Livello $level',
      nextLevelXp: nextThreshold - totalXp,
    );
  }

  // ============================================
  // GESTIONE XP
  // ============================================

  /// Ricalcola XP totale dell'utente dalle tracce esistenti (escluse
  /// pianificate). Idempotente: se l'XP corrente è già >= calcolato,
  /// non fa nulla. Usato come backfill one-shot dopo il fix rules
  /// (commit 'fix(rules): xp/level affectedKeys whitelist') per
  /// recuperare l'XP perso negli ultimi mesi quando ogni grantXp
  /// veniva silently rejected dalle rules.
  ///
  /// Formula coerente con `grantXpForTrack`:
  ///   per ogni track: 50 + (km × 10) + (D+/100 × 15)
  ///   + 100 XP bonus first_track
  ///
  /// Ritorna l'XP totale ricalcolato (anche se nessun update è avvenuto).
  Future<int> recomputeXpFromTracks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;
    try {
      final tracksSnap = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('tracks')
          .get();
      int totalXp = 0;
      int realTracks = 0;
      for (final doc in tracksSnap.docs) {
        final d = doc.data();
        if (d['isPlanned'] == true) continue;
        realTracks += 1;
        final dist = (d['distance'] as num?)?.toDouble() ?? 0;
        final ele = (d['elevationGain'] as num?)?.toDouble() ?? 0;
        totalXp += xpRewards['track_completed']!;
        totalXp += ((dist / 1000) * xpRewards['km_hiked']!).toInt();
        totalXp += ((ele / 100) * xpRewards['elevation_100m']!).toInt();
      }
      if (realTracks > 0) {
        totalXp += xpRewards['first_track']!;
      }

      // Aggiunge XP da cheers ricevuti + tracce pubblicate.
      try {
        final pubSnap = await _firestore
            .collection('published_tracks')
            .where('originalOwnerId', isEqualTo: user.uid)
            .get();
        int totalCheers = 0;
        for (final p in pubSnap.docs) {
          totalCheers += ((p.data()['cheerCount'] as num?)?.toInt() ?? 0);
          totalXp += xpRewards['track_published']!;
        }
        totalXp += totalCheers * xpRewards['cheers_received']!;
      } catch (_) {}

      final profileRef = _firestore.collection('user_profiles').doc(user.uid);
      final currentDoc = await profileRef.get();
      final currentXp =
          (currentDoc.data()?['xp'] as num?)?.toInt() ?? 0;
      // Non sovrascrivere se già più alto (utente potrebbe avere XP da
      // grants non-track come follower, ecc.).
      if (totalXp <= currentXp) {
        debugPrint(
            '[Gamification] recomputeXp: $currentXp già >= $totalXp, skip');
        return currentXp;
      }
      final level = calculateLevel(totalXp);
      await profileRef.set({
        'xp': totalXp,
        'level': level,
        'lastXpGrant': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint(
          '[Gamification] recomputeXp: backfill $currentXp → $totalXp (livello $level)');
      return totalXp;
    } catch (e) {
      debugPrint('[Gamification] recomputeXp error: $e');
      return 0;
    }
  }

  Future<XpRewardResult> grantXp({
    required String reason,
    required int amount,
    String? details,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return XpRewardResult(success: false, error: 'Utente non loggato');
    }

    try {
      final profileRef = _firestore.collection('user_profiles').doc(user.uid);
      
      int newTotalXp = 0;
      int oldLevel = 1;
      int newLevel = 1;
      bool leveledUp = false;

      await _firestore.runTransaction((transaction) async {
        final profileDoc = await transaction.get(profileRef);
        
        int currentXp = 0;
        if (profileDoc.exists) {
          currentXp = (profileDoc.data()?['xp'] as num?)?.toInt() ?? 0;
          oldLevel = (profileDoc.data()?['level'] as num?)?.toInt() ?? 1;
        }

        newTotalXp = currentXp + amount;
        newLevel = calculateLevel(newTotalXp);
        leveledUp = newLevel > oldLevel;

        transaction.set(profileRef, {
          'xp': newTotalXp,
          'level': newLevel,
          'lastXpGrant': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      // Salva nella history XP
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('xp_history')
          .add({
        'amount': amount,
        'reason': reason,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
        'totalXp': newTotalXp,
      });

      return XpRewardResult(
        success: true,
        xpGranted: amount,
        totalXp: newTotalXp,
        leveledUp: leveledUp,
        newLevel: leveledUp ? newLevel : null,
      );
    } catch (e) {
      debugPrint('[Gamification] Errore grant XP: $e');
      return XpRewardResult(success: false, error: e.toString());
    }
  }

  Future<XpRewardResult> grantXpForTrack({
    required double distanceMeters,
    required double elevationGain,
    required Duration duration,
    bool isFirstTrack = false,
  }) async {
    int totalXp = xpRewards['track_completed']!;
    
    final kmHiked = distanceMeters / 1000;
    totalXp += (kmHiked * xpRewards['km_hiked']!).toInt();
    
    final elevation100m = elevationGain / 100;
    totalXp += (elevation100m * xpRewards['elevation_100m']!).toInt();
    
    if (isFirstTrack) {
      totalXp += xpRewards['first_track']!;
    }

    final details = 'Distanza: ${kmHiked.toStringAsFixed(1)}km, '
        'Dislivello: ${elevationGain.toStringAsFixed(0)}m';

    return grantXp(
      reason: 'track_completed',
      amount: totalXp,
      details: details,
    );
  }

  Future<XpRewardResult> grantXpForCheers() {
    return grantXp(
      reason: 'cheers_received',
      amount: xpRewards['cheers_received']!,
    );
  }

  Future<XpRewardResult> grantXpForNewFollower() {
    return grantXp(
      reason: 'new_follower',
      amount: xpRewards['new_follower']!,
    );
  }

  Future<XpRewardResult> grantXpForPublishedTrack() {
    return grantXp(
      reason: 'track_published',
      amount: xpRewards['track_published']!,
    );
  }

  // ============================================
  // BADGES
  // ============================================

  static final List<GameBadge> availableBadges = [
    GameBadge(
      id: 'first_steps',
      name: 'Primi Passi',
      description: 'Completa la tua prima traccia',
      icon: '👟',
      category: GameBadgeCategory.milestone,
      requirement: 'Completa 1 traccia',
    ),
    GameBadge(
      id: 'hiker_10km',
      name: 'Camminatore',
      description: 'Percorri 10 km in totale',
      icon: '🚶',
      category: GameBadgeCategory.distance,
      requirement: '10 km totali',
    ),
    GameBadge(
      id: 'hiker_50km',
      name: 'Escursionista',
      description: 'Percorri 50 km in totale',
      icon: '🥾',
      category: GameBadgeCategory.distance,
      requirement: '50 km totali',
    ),
    GameBadge(
      id: 'hiker_100km',
      name: 'Maratoneta',
      description: 'Percorri 100 km in totale',
      icon: '🏃',
      category: GameBadgeCategory.distance,
      requirement: '100 km totali',
    ),
    GameBadge(
      id: 'hiker_500km',
      name: 'Ultra Runner',
      description: 'Percorri 500 km in totale',
      icon: '🦅',
      category: GameBadgeCategory.distance,
      requirement: '500 km totali',
    ),
    GameBadge(
      id: 'climber_1000m',
      name: 'Scalatore',
      description: 'Accumula 1000m di dislivello',
      icon: '⛰️',
      category: GameBadgeCategory.elevation,
      requirement: '1000m D+ totali',
    ),
    GameBadge(
      id: 'climber_5000m',
      name: 'Alpinista',
      description: 'Accumula 5000m di dislivello',
      icon: '🏔️',
      category: GameBadgeCategory.elevation,
      requirement: '5000m D+ totali',
    ),
    GameBadge(
      id: 'climber_10000m',
      name: 'Conquistatore',
      description: 'Accumula 10000m di dislivello',
      icon: '🗻',
      category: GameBadgeCategory.elevation,
      requirement: '10000m D+ totali',
    ),
    GameBadge(
      id: 'social_5_followers',
      name: 'Influencer',
      description: 'Raggiungi 5 follower',
      icon: '👥',
      category: GameBadgeCategory.social,
      requirement: '5 follower',
    ),
    GameBadge(
      id: 'social_50_cheers',
      name: 'Popolare',
      description: 'Ricevi 50 cheers',
      icon: '🎉',
      category: GameBadgeCategory.social,
      requirement: '50 cheers ricevuti',
    ),
    GameBadge(
      id: 'streak_3',
      name: 'Costante',
      description: 'Tracce per 3 giorni consecutivi',
      icon: '🔥',
      category: GameBadgeCategory.streak,
      requirement: '3 giorni streak',
    ),
    GameBadge(
      id: 'streak_7',
      name: 'Dedito',
      description: 'Tracce per 7 giorni consecutivi',
      icon: '💪',
      category: GameBadgeCategory.streak,
      requirement: '7 giorni streak',
    ),
    GameBadge(
      id: 'streak_30',
      name: 'Inarrestabile',
      description: 'Tracce per 30 giorni consecutivi',
      icon: '🌟',
      category: GameBadgeCategory.streak,
      requirement: '30 giorni streak',
    ),
  ];

  Future<List<UnlockedBadge>> getUnlockedBadges(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('badges')
          .orderBy('unlockedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        final badge = availableBadges.firstWhere(
          (b) => b.id == doc.id,
          orElse: () => GameBadge(
            id: doc.id,
            name: data['name'] ?? 'Badge',
            description: '',
            icon: '🏅',
            category: GameBadgeCategory.milestone,
          ),
        );
        
        return UnlockedBadge(
          badge: badge,
          unlockedAt: (data['unlockedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[Gamification] Errore get badges: $e');
      return [];
    }
  }

  Future<bool> unlockBadge(String badgeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final badge = availableBadges.firstWhere((b) => b.id == badgeId);
      
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('badges')
          .doc(badgeId)
          .set({
        'name': badge.name,
        'unlockedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('[Gamification] Errore unlock badge: $e');
      return false;
    }
  }

  Future<List<GameBadge>> checkAndUnlockBadges({
    required double totalDistance,
    required double totalElevation,
    required int totalTracks,
    required int followersCount,
    required int cheersReceived,
    required int currentStreak,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final unlockedBadges = await getUnlockedBadges(user.uid);
    final unlockedIds = unlockedBadges.map((b) => b.badge.id).toSet();
    final newBadges = <GameBadge>[];

    // Controllo badge distanza
    if (!unlockedIds.contains('first_steps') && totalTracks >= 1) {
      if (await unlockBadge('first_steps')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'first_steps'));
      }
    }
    if (!unlockedIds.contains('hiker_10km') && totalDistance >= 10000) {
      if (await unlockBadge('hiker_10km')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'hiker_10km'));
      }
    }
    if (!unlockedIds.contains('hiker_50km') && totalDistance >= 50000) {
      if (await unlockBadge('hiker_50km')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'hiker_50km'));
      }
    }
    if (!unlockedIds.contains('hiker_100km') && totalDistance >= 100000) {
      if (await unlockBadge('hiker_100km')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'hiker_100km'));
      }
    }
    if (!unlockedIds.contains('hiker_500km') && totalDistance >= 500000) {
      if (await unlockBadge('hiker_500km')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'hiker_500km'));
      }
    }

    // Controllo badge dislivello
    if (!unlockedIds.contains('climber_1000m') && totalElevation >= 1000) {
      if (await unlockBadge('climber_1000m')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'climber_1000m'));
      }
    }
    if (!unlockedIds.contains('climber_5000m') && totalElevation >= 5000) {
      if (await unlockBadge('climber_5000m')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'climber_5000m'));
      }
    }
    if (!unlockedIds.contains('climber_10000m') && totalElevation >= 10000) {
      if (await unlockBadge('climber_10000m')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'climber_10000m'));
      }
    }

    // Controllo badge social
    if (!unlockedIds.contains('social_5_followers') && followersCount >= 5) {
      if (await unlockBadge('social_5_followers')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'social_5_followers'));
      }
    }
    if (!unlockedIds.contains('social_50_cheers') && cheersReceived >= 50) {
      if (await unlockBadge('social_50_cheers')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'social_50_cheers'));
      }
    }

    // Controllo badge streak
    if (!unlockedIds.contains('streak_3') && currentStreak >= 3) {
      if (await unlockBadge('streak_3')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'streak_3'));
      }
    }
    if (!unlockedIds.contains('streak_7') && currentStreak >= 7) {
      if (await unlockBadge('streak_7')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'streak_7'));
      }
    }
    if (!unlockedIds.contains('streak_30') && currentStreak >= 30) {
      if (await unlockBadge('streak_30')) {
        newBadges.add(availableBadges.firstWhere((b) => b.id == 'streak_30'));
      }
    }

    return newBadges;
  }
}

// ============================================
// MODELLI
// ============================================

class LevelInfo {
  final int level;
  final int totalXp;
  final int currentLevelXp;
  final int xpForNextLevel;
  final double progress;
  final String levelName;
  final int nextLevelXp;

  const LevelInfo({
    required this.level,
    required this.totalXp,
    required this.currentLevelXp,
    required this.xpForNextLevel,
    required this.progress,
    required this.levelName,
    required this.nextLevelXp,
  });

  String get progressText => '$currentLevelXp / $xpForNextLevel XP';
  String get nextLevelText => '$nextLevelXp XP per il prossimo livello';
}

class XpRewardResult {
  final bool success;
  final int? xpGranted;
  final int? totalXp;
  final bool leveledUp;
  final int? newLevel;
  final String? error;

  const XpRewardResult({
    required this.success,
    this.xpGranted,
    this.totalXp,
    this.leveledUp = false,
    this.newLevel,
    this.error,
  });
}

enum GameBadgeCategory {
  milestone,
  distance,
  elevation,
  social,
  streak,
  challenge,
}

class GameBadge {
  final String id;
  final String name;
  final String description;
  final String icon;
  final GameBadgeCategory category;
  final String? requirement;

  const GameBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    this.requirement,
  });
}

class UnlockedBadge {
  final GameBadge badge;
  final DateTime unlockedAt;

  const UnlockedBadge({
    required this.badge,
    required this.unlockedAt,
  });
}
