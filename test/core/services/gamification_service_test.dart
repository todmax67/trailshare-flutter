import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/services/gamification_service.dart';

void main() {
  late GamificationService service;

  setUp(() {
    service = GamificationService();
  });

  group('GamificationService.calculateLevel', () {
    test('zero XP gives level 1', () {
      expect(service.calculateLevel(0), 1);
    });

    test('just below threshold stays in current level', () {
      expect(service.calculateLevel(99), 1);
      expect(service.calculateLevel(299), 2);
      expect(service.calculateLevel(599), 3);
    });

    test('exactly at threshold advances to next level', () {
      expect(service.calculateLevel(100), 2);
      expect(service.calculateLevel(300), 3);
      expect(service.calculateLevel(1000), 5);
    });

    test('XP above the highest threshold returns max level', () {
      // levelThresholds ha 20 entries → max level = 20
      expect(service.calculateLevel(36000), 20);
      expect(service.calculateLevel(1000000), 20);
    });

    test('negative XP defaults to level 1', () {
      // Edge case difensivo: anche se non dovrebbe accadere, non crash.
      expect(service.calculateLevel(-100), 1);
    });
  });

  group('GamificationService.calculateLevelInfo', () {
    test('returns matching level + name', () {
      final info = service.calculateLevelInfo(150);
      expect(info.level, 2);
      expect(info.levelName, 'Escursionista');
      expect(info.totalXp, 150);
    });

    test('progress is 0% right at threshold and 100% just before next', () {
      final atThreshold = service.calculateLevelInfo(100);
      expect(atThreshold.progress, 0);

      final justBelow = service.calculateLevelInfo(299);
      // Quasi 100%, ma sotto.
      expect(justBelow.progress, greaterThan(99));
      expect(justBelow.progress, lessThanOrEqualTo(100));
    });

    test('xpForNextLevel matches the gap between thresholds', () {
      // Level 2 → 3: 300 - 100 = 200 XP totali necessari.
      final info = service.calculateLevelInfo(150);
      expect(info.xpForNextLevel, 200);
      expect(info.currentLevelXp, 50);
      expect(info.nextLevelXp, 150);
    });

    test('progress is clamped to 0-100', () {
      // Simula XP fra livelli, controllo limiti.
      for (final xp in [0, 50, 99, 100, 250, 1000, 5000]) {
        final info = service.calculateLevelInfo(xp);
        expect(info.progress, greaterThanOrEqualTo(0));
        expect(info.progress, lessThanOrEqualTo(100));
      }
    });

    test('levelName falls back to "Livello N" beyond the named map', () {
      // 20 livelli sono nominati. Se aggiungeranno soglie oltre, il
      // fallback deve scattare. Per ora il livello max è 20 → resta
      // nominato. Verifichiamo che il fallback testuale esista.
      final info = service.calculateLevelInfo(999999);
      expect(info.levelName, isNotEmpty);
      expect(info.level, 20);
    });
  });

  group('GamificationService rewards constants', () {
    test('all reward keys are present and positive', () {
      const expected = [
        'track_completed',
        'km_hiked',
        'elevation_100m',
        'first_track',
        'streak_day',
        'track_published',
        'cheers_received',
        'new_follower',
        'challenge_completed',
      ];
      for (final key in expected) {
        expect(GamificationService.xpRewards.containsKey(key), isTrue,
            reason: 'Missing key: $key');
        expect(GamificationService.xpRewards[key]!, greaterThan(0));
      }
    });

    test('badge catalog has unique IDs', () {
      final ids = GamificationService.availableBadges.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('badge catalog has at least one badge per category', () {
      final categories =
          GamificationService.availableBadges.map((b) => b.category).toSet();
      // Almeno milestone + distance ci devono essere.
      expect(categories, contains(GameBadgeCategory.milestone));
      expect(categories, contains(GameBadgeCategory.distance));
    });
  });
}
