import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/services/gpx_service.dart';
import 'package:trailshare_flutter/data/models/track.dart';

/// L'esportazione GPX deve spezzare la traccia dove la registrazione si e'
/// interrotta. E' l'unico modo perche' l'informazione sopravviva all'uscita
/// dall'app: qualsiasi avviso mostrato nella nostra scheda resta nella nostra
/// scheda, il file invece finisce su Garmin, Strava e komoot.
void main() {
  TrackPoint p(int minute, double lat) => TrackPoint(
        latitude: lat,
        longitude: 9.0,
        timestamp: DateTime.utc(2026, 8, 16, 10, minute),
      );

  Track trackWith({required List<TrackGap> gaps}) => Track(
        name: 'Giro',
        createdAt: DateTime.utc(2026, 8, 16, 12),
        points: [p(0, 45.0), p(5, 45.1), p(40, 45.2), p(45, 45.3)],
        gaps: gaps,
      );

  final svc = GpxService();

  test('senza buchi resta un segmento solo, come prima', () {
    final gpx = svc.generateGpx(trackWith(gaps: const []));
    expect('<trkseg>'.allMatches(gpx).length, 1);
    expect('</trkseg>'.allMatches(gpx).length, 1);
    expect('<trkpt'.allMatches(gpx).length, 4);
  });

  test('un buco spezza la traccia in due segmenti', () {
    final gpx = svc.generateGpx(trackWith(gaps: [
      TrackGap(
        startedAt: DateTime.utc(2026, 8, 16, 10, 5),
        endedAt: DateTime.utc(2026, 8, 16, 10, 40),
        cause: 'appFrozen',
      ),
    ]));

    expect('<trkseg>'.allMatches(gpx).length, 2,
        reason: 'il buco deve aprire un segmento nuovo');
    expect('</trkseg>'.allMatches(gpx).length, 2);
    // Nessun punto si perde: cambia come sono raggruppati, non quanti sono.
    expect('<trkpt'.allMatches(gpx).length, 4);
  });

  test('due buchi danno tre segmenti', () {
    final gpx = svc.generateGpx(trackWith(gaps: [
      TrackGap(
        startedAt: DateTime.utc(2026, 8, 16, 10, 5),
        endedAt: DateTime.utc(2026, 8, 16, 10, 40),
        cause: 'appFrozen',
      ),
      TrackGap(
        startedAt: DateTime.utc(2026, 8, 16, 10, 40),
        endedAt: DateTime.utc(2026, 8, 16, 10, 45),
        cause: 'streamStalled',
      ),
    ]));
    expect('<trkseg>'.allMatches(gpx).length, 3);
    expect('<trkpt'.allMatches(gpx).length, 4);
  });

  test('il file resta un GPX valido e ben formato', () {
    final gpx = svc.generateGpx(trackWith(gaps: [
      TrackGap(
        startedAt: DateTime.utc(2026, 8, 16, 10, 5),
        endedAt: DateTime.utc(2026, 8, 16, 10, 40),
        cause: 'appFrozen',
      ),
    ]));
    expect(gpx, startsWith('<?xml version="1.0"'));
    expect(gpx.trim(), endsWith('</gpx>'));
    expect('<trkseg>'.allMatches(gpx).length,
        '</trkseg>'.allMatches(gpx).length,
        reason: 'ogni segmento aperto va chiuso');
  });

  group('il modello del buco', () {
    test('sopravvive al giro su Firestore', () {
      final g = TrackGap(cause: 'appFrozen', startedAt: _s, endedAt: _e);
      final back = TrackGap.fromMap(g.toMap());
      expect(back.startedAt, g.startedAt);
      expect(back.endedAt, g.endedAt);
      expect(back.cause, 'appFrozen');
      expect(back.duration, const Duration(minutes: 35));
    });

    test('un buco senza fine leggibile non sparisce', () {
      final back = TrackGap.fromMap({
        'startedAt': _s.toIso8601String(),
        'cause': 'appFrozen',
      });
      expect(back.duration, Duration.zero);
      expect(back.startedAt, _s,
          reason: 'resta un buco dichiarato, non una traccia che torna intera');
    });
  });
}

final _s = DateTime.utc(2026, 8, 16, 10, 5);
final _e = DateTime.utc(2026, 8, 16, 10, 40);
