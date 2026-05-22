import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/elevation_processor.dart';

void main() {
  group('ElevationProcessor.process', () {
    const processor = ElevationProcessor();

    test('returns empty result for empty input', () {
      final r = processor.process([]);
      expect(r.elevationGain, 0);
      expect(r.elevationLoss, 0);
      expect(r.smoothedElevations, isEmpty);
    });

    test('handles single-point input without crashing', () {
      final r = processor.process([1000.0]);
      expect(r.smoothedElevations.length, 1);
      expect(r.elevationGain, 0);
      expect(r.elevationLoss, 0);
      expect(r.maxElevation, 1000);
      expect(r.minElevation, 1000);
    });

    test('GPS noise below hysteresis threshold does not count as gain', () {
      // Tutti i punti oscillano di ±1m attorno a 1000m: nessun gain reale
      final noisy = List<double?>.generate(
        50,
        (i) => 1000.0 + (i.isEven ? 1.0 : -1.0),
      );
      final r = processor.process(noisy);
      expect(r.elevationGain, lessThan(5.0));
      expect(r.elevationLoss, lessThan(5.0));
    });

    test('detects a real 100m climb above hysteresis threshold', () {
      // Salita lineare 1000 → 1100 in 50 punti
      final climb = List<double?>.generate(50, (i) => 1000.0 + i * 2.0);
      final r = processor.process(climb);
      expect(r.elevationGain, greaterThan(85));
      expect(r.elevationGain, lessThan(105));
      expect(r.elevationLoss, lessThan(5));
    });

    test('symmetric out-and-back has matching gain and loss', () {
      final outAndBack = <double?>[
        for (int i = 0; i < 30; i++) 1000.0 + i * 2.0,
        for (int i = 30; i >= 0; i--) 1000.0 + i * 2.0,
      ];
      final r = processor.process(outAndBack);
      expect((r.elevationGain - r.elevationLoss).abs(), lessThan(8));
    });

    test('removes a single isolated spike of +500m', () {
      // 30 punti a 1000, uno spike a 1500, poi 30 punti a 1000
      final withSpike = <double?>[
        for (int i = 0; i < 30; i++) 1000.0,
        1500.0,
        for (int i = 0; i < 30; i++) 1000.0,
      ];
      final r = processor.process(withSpike);
      // Senza spike removal il gain sarebbe ~500, qui deve restare basso
      expect(r.elevationGain, lessThan(50));
    });

    test('handles null elevations by interpolation', () {
      final withNulls = <double?>[
        1000.0,
        null,
        null,
        1010.0,
        null,
        1020.0,
      ];
      final r = processor.process(withNulls);
      expect(r.smoothedElevations.length, 6);
      expect(r.smoothedElevations.first, isNotNull);
      expect(r.smoothedElevations.last, isNotNull);
    });
  });

  group('ElevationProcessor.calculateGainLoss', () {
    test('returns zero for fewer than 2 points', () {
      const p = ElevationProcessor();
      expect(p.calculateGainLoss([]).gain, 0);
      expect(p.calculateGainLoss([1000]).gain, 0);
    });

    test('matches process() gain/loss on clean data', () {
      const p = ElevationProcessor();
      final climb = List<double>.generate(20, (i) => 1000.0 + i * 5.0);
      final fast = p.calculateGainLoss(climb);
      // Climb of ~95m (after hysteresis cutoff)
      expect(fast.gain, greaterThan(80));
      expect(fast.loss, lessThan(5));
    });
  });

  group('ElevationProcessor.forActivity factory', () {
    test('cycling has lower hysteresis than trekking (più sensibile)', () {
      final cycling = ElevationProcessor.forActivity('cycling');
      final trekking = ElevationProcessor.forActivity('trekking');
      expect(cycling.hysteresisThreshold, lessThan(trekking.hysteresisThreshold));
    });

    test('unknown activity falls back to trekking defaults', () {
      final unknown = ElevationProcessor.forActivity('paragliding');
      final trekking = ElevationProcessor.forActivity('trekking');
      expect(unknown.hysteresisThreshold, trekking.hysteresisThreshold);
      expect(unknown.smoothingWindow, trekking.smoothingWindow);
    });
  });

  group('ElevationTracker (real-time)', () {
    test('starts with zero gain/loss', () {
      final tracker = const ElevationProcessor().createTracker();
      expect(tracker.elevationGain, 0);
      expect(tracker.elevationLoss, 0);
      expect(tracker.pointCount, 0);
    });

    test('null input does not advance the buffer', () {
      final tracker = const ElevationProcessor().createTracker();
      tracker.addPoint(null);
      expect(tracker.pointCount, 0);
    });

    test('rejects spikes above maxElevationChangePerPoint', () {
      final tracker = const ElevationProcessor(
        maxElevationChangePerPoint: 50,
      ).createTracker();
      tracker.addPoint(1000);
      tracker.addPoint(1005);
      tracker.addPoint(2000); // spike → ignored
      expect(tracker.pointCount, 2);
      expect(tracker.maxElevation, lessThan(1010));
    });

    test('commits gain when direction reverses (climb then descend)', () {
      // Hysteresis commits gain solo quando si inverte la direzione,
      // quindi una salita pura senza discesa lascia il gain "in volo".
      // Simuliamo un picco: salita 30 punti, poi discesa 30 punti.
      final tracker = const ElevationProcessor().createTracker();
      for (int i = 0; i < 30; i++) {
        tracker.addPoint(1000.0 + i * 3.0);
      }
      for (int i = 30; i >= 0; i--) {
        tracker.addPoint(1000.0 + i * 3.0);
      }
      expect(tracker.elevationGain, greaterThan(50));
    });
  });
}
