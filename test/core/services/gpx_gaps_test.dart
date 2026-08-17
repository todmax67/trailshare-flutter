import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
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

  group('il tratto ricostruito esce come segmento dichiarato', () {
    Track conRicostruzione() => trackWith(gaps: [
          TrackGap(
            startedAt: DateTime.utc(2026, 8, 16, 10, 5),
            endedAt: DateTime.utc(2026, 8, 16, 10, 40),
            cause: TrackGap.causeAppFrozen,
            reconstruction: const [
              LatLng(45.05, 9.0),
              LatLng(45.10, 9.01),
              LatLng(45.15, 9.02),
            ],
            reconstructedAt: DateTime.utc(2026, 8, 17),
          ),
        ]);

    test('aggiunge un terzo segmento fra i due misurati', () {
      final gpx = svc.generateGpx(conRicostruzione());
      expect('<trkseg>'.allMatches(gpx).length, 3,
          reason: 'percorso, ricostruito, percorso');
      expect('</trkseg>'.allMatches(gpx).length, 3);
    });

    test('lo dichiara nel file, non solo nella nostra scheda', () {
      final gpx = svc.generateGpx(conRicostruzione());
      expect(gpx, contains('ricostruito dal proprietario'),
          reason: 'l\'etichetta deve viaggiare col GPX');
    });

    test('i punti ricostruiti NON hanno orario', () {
      final gpx = svc.generateGpx(conRicostruzione());
      // I tre punti ricostruiti sono senza <time>: inventarlo darebbe
      // velocita' false a chi importa la traccia.
      final senzaTime = RegExp(r'<trkpt[^>]*></trkpt>').allMatches(gpx).length;
      expect(senzaTime, 3);
    });

    test('i punti misurati restano quattro, con il loro orario', () {
      final gpx = svc.generateGpx(conRicostruzione());
      expect('<time>'.allMatches(gpx).length, 5,
          reason: '4 punti misurati + 1 nei metadata');
    });
  });

  group('il giro completo esporta-reimporta non falsifica la traccia', () {
    // Il difetto critico della Fase 2: l'esportazione era onesta, il rientro
    // no. I punti disegnati tornavano dentro points e dentro stats.distance,
    // con orari inventati da DateTime.now() — e da li' li vedevano segmenti,
    // classifica, XP e Apple Health.
    Track conRicostruzione() => trackWith(gaps: [
          TrackGap(
            startedAt: DateTime.utc(2026, 8, 16, 10, 5),
            endedAt: DateTime.utc(2026, 8, 16, 10, 40),
            cause: TrackGap.causeAppFrozen,
            reconstruction: const [
              LatLng(45.05, 9.0),
              LatLng(45.10, 9.01),
              LatLng(45.15, 9.02),
            ],
          ),
        ]);

    test('il reimport restituisce SOLO i punti misurati', () {
      final gpx = svc.generateGpx(conRicostruzione());
      final back = svc.parseGpxString(gpx);
      expect(back, isNotNull);
      expect(back!.points, hasLength(4),
          reason: 'i 3 punti disegnati non devono rientrare fra i misurati');
    });

    test('nessun punto reimportato ha le coordinate della ricostruzione', () {
      final back = svc.parseGpxString(svc.generateGpx(conRicostruzione()))!;
      for (final r in const [
        LatLng(45.05, 9.0),
        LatLng(45.10, 9.01),
        LatLng(45.15, 9.02),
      ]) {
        final trovato = back.points.any((p) =>
            (p.latitude - r.latitude).abs() < 1e-9 &&
            (p.longitude - r.longitude).abs() < 1e-9);
        expect(trovato, isFalse, reason: 'punto ricostruito rientrato: $r');
      }
    });

    test('la distanza reimportata non gonfia per il tratto disegnato', () {
      final senza = svc.parseGpxString(svc.generateGpx(trackWith(gaps: const [])))!;
      final con = svc.parseGpxString(svc.generateGpx(conRicostruzione()))!;
      expect(con.stats.distance, closeTo(senza.stats.distance, 1),
          reason: 'la ricostruzione non deve entrare nei chilometri');
    });

    test('la marcatura e un elemento leggibile, non un commento', () {
      final gpx = svc.generateGpx(conRicostruzione());
      expect(gpx, contains('<name>$kReconstructedSegmentName</name>'),
          reason: 'un commento XML lo scarta ogni parser, compreso il nostro');
    });
  });
}


final _s = DateTime.utc(2026, 8, 16, 10, 5);
final _e = DateTime.utc(2026, 8, 16, 10, 40);