import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/track_gap_segments.dart';
import 'package:trailshare_flutter/data/models/track.dart';

TrackPoint p(int minute) => TrackPoint(
      latitude: 45.0 + minute / 1000,
      longitude: 9.0,
      timestamp: DateTime.utc(2026, 8, 16, 10, minute),
    );

TrackGap gap(int fromMin, int toMin) => TrackGap(
      startedAt: DateTime.utc(2026, 8, 16, 10, fromMin),
      endedAt: DateTime.utc(2026, 8, 16, 10, toMin),
      cause: 'appFrozen',
    );

void main() {
  group('senza buchi', () {
    test('resta un tratto solo, con tutti i punti', () {
      final s = splitTrackOnGaps([p(0), p(1), p(2)], const []);
      expect(s, hasLength(1));
      expect(s.single.isGap, isFalse);
      expect(s.single.points, hasLength(3));
    });

    test('una traccia vuota non produce tratti', () {
      expect(splitTrackOnGaps(const [], const []), isEmpty);
    });

    test('un punto solo non e\' un percorso ma non si perde', () {
      final s = splitTrackOnGaps([p(0)], const []);
      expect(s, hasLength(1));
      expect(s.single.points, hasLength(1));
    });
  });

  group('con un buco in mezzo', () {
    // Punti a 0, 5, 40, 45: fra il 5 e il 40 la registrazione si e' fermata.
    final points = [p(0), p(5), p(40), p(45)];
    final gaps = [gap(6, 39)];

    test('produce percorso, ponte, percorso', () {
      final s = splitTrackOnGaps(points, gaps);
      expect(s.map((x) => x.kind).toList(), [
        TrackSegmentKind.recorded,
        TrackSegmentKind.gap,
        TrackSegmentKind.recorded,
      ]);
    });

    test('il ponte ha due soli punti: non e\' un percorso', () {
      final bridge = splitTrackOnGaps(points, gaps).firstWhere((x) => x.isGap);
      expect(bridge.points, hasLength(2));
      expect(bridge.points.first.timestamp.minute, 5);
      expect(bridge.points.last.timestamp.minute, 40);
    });

    test('il ponte porta con se\' quanto e\' durata l\'interruzione', () {
      final bridge = splitTrackOnGaps(points, gaps).firstWhere((x) => x.isGap);
      expect(bridge.gapDuration, const Duration(minutes: 33));
    });

    test('nessun punto viene perso per strada', () {
      final s = splitTrackOnGaps(points, gaps);
      final recorded = s.where((x) => !x.isGap).expand((x) => x.points);
      // I due estremi del ponte compaiono anche nei tratti percorsi: e' giusto,
      // sono punti veri. Quello che conta e' che nessuno sparisca.
      for (final pt in points) {
        expect(recorded.any((r) => r.timestamp == pt.timestamp), isTrue,
            reason: 'perso il punto ${pt.timestamp}');
      }
    });
  });

  group('la tolleranza sugli estremi', () {
    test('un buco che non coincide col timestamp del punto viene comunque preso', () {
      // Il watchdog e' preciso al tick: la finestra non combacia mai esatta.
      final s = splitTrackOnGaps([p(0), p(5), p(40)], [gap(7, 38)]);
      expect(s.any((x) => x.isGap), isTrue);
    });

    test('un buco fuori dalla traccia non spezza niente', () {
      final s = splitTrackOnGaps([p(0), p(1), p(2)], [gap(50, 60)]);
      expect(s, hasLength(1));
      expect(s.single.isGap, isFalse);
    });
  });

  group('due buchi', () {
    test('danno due ponti distinti', () {
      final s = splitTrackOnGaps(
        [p(0), p(5), p(40), p(45), p(80)],
        [gap(6, 39), gap(46, 79)],
      );
      expect(s.where((x) => x.isGap), hasLength(2));
    });
  });

  group('un buco a inizio traccia', () {
    test('non lascia un tratto percorso di un punto solo', () {
      final s = splitTrackOnGaps([p(0), p(40), p(45)], [gap(1, 39)]);
      // Il primo punto da solo non e' un percorso: entra nel ponte e basta.
      expect(s.first.isGap, isTrue);
      expect(s.where((x) => !x.isGap).every((x) => x.points.length >= 2), isTrue);
    });
  });

  test('il totale del tempo perso somma tutti i buchi', () {
    expect(
      totalGapDuration([gap(0, 10), gap(20, 25)]),
      const Duration(minutes: 15),
    );
    expect(totalGapDuration(const []), Duration.zero);
  });
}
