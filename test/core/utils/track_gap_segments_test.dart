import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
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

  group('rilevamento dei buchi non dichiarati', () {
    // Un punto ogni 10 secondi, passo regolare: registrazione sana.
    TrackPoint at(int seconds, {double lat = 45.0, double lng = 9.0}) =>
        TrackPoint(
          latitude: lat,
          longitude: lng,
          timestamp: DateTime.utc(2026, 8, 16, 10).add(Duration(seconds: seconds)),
        );

    // Bilancio "da congelamento": quasi tutto il tempo della traccia risulta
    // NON in movimento, come succede quando i campioni mancano davvero.
    const dFreeze = Duration(minutes: 40);
    const mFreeze = Duration(minutes: 2);

    test('una registrazione sana non produce candidati', () {
      final pts = [for (var i = 0; i < 100; i++) at(i * 10, lat: 45.0 + i * 0.0001)];
      expect(
        detectUndeclaredGaps(pts, const [],
            duration: const Duration(minutes: 17),
            movingTime: const Duration(minutes: 16)),
        isEmpty,
      );
    });

    test('la pausa pranzo (tanto tempo, stesso posto) NON e\' un candidato', () {
      final pts = [
        at(0),
        at(60, lat: 45.001),
        // 40 minuti fermi al rifugio: ricompare a ~11 m da dove si era fermato.
        at(60 + 2400, lat: 45.0011),
        at(60 + 2460, lat: 45.002),
      ];
      // Il bilancio coprirebbe (la sosta non e' movimento): a respingere
      // dev'essere la soglia spaziale.
      expect(
        detectUndeclaredGaps(pts, const [],
            duration: const Duration(minutes: 42), movingTime: mFreeze),
        isEmpty,
        reason: 'chi si ferma resta dov\'e\': dichiarare qui sarebbe sbagliato',
      );
    });

    test('il congelamento (tempo, distanza E bilancio) e\' un candidato', () {
      final pts = [
        at(0),
        at(60, lat: 45.001),
        // 37 minuti dopo, 5,5 km piu' in la': la firma del caso reale.
        at(60 + 2220, lat: 45.051),
        at(60 + 2280, lat: 45.052),
      ];
      final found = detectUndeclaredGaps(pts, const [],
          duration: dFreeze, movingTime: mFreeze);
      expect(found, hasLength(1));
      expect(found.single.cause, TrackGap.causeOwnerDeclared);
      // Gli estremi sono ESATTI (timestamp dei punti), non stime del watchdog.
      expect(found.single.startedAt, pts[1].timestamp);
      expect(found.single.endedAt, pts[2].timestamp);
    });

    test('il rettilineo compresso da Douglas-Peucker NON passa il bilancio', () {
      // Stessa firma spaziale e temporale del congelamento — ma il tempo in
      // movimento dice che in quei minuti si stava pedalando: l'arco e' un
      // rettilineo di pianura collassato dalla semplificazione, non un buco.
      // E' il difetto trovato dalla revisione avversariale della Fase 1.
      final pts = [
        at(0),
        at(60, lat: 45.001),
        at(60 + 2220, lat: 45.051),
        at(60 + 2280, lat: 45.052),
      ];
      expect(
        detectUndeclaredGaps(pts, const [],
            duration: const Duration(minutes: 39),
            movingTime: const Duration(minutes: 38)),
        isEmpty,
        reason: 'il tempo di quell\'arco risulta in movimento: nessun buco',
      );
    });

    test('senza un tempo in movimento attendibile non si propone niente', () {
      final pts = [
        at(0),
        at(60, lat: 45.001),
        at(60 + 2220, lat: 45.051),
      ];
      // movingTime == duration: le tracce pre-2.10.0, dove era una copia.
      expect(
        detectUndeclaredGaps(pts, const [],
            duration: dFreeze, movingTime: dFreeze),
        isEmpty,
      );
      // movingTime zero: mai calcolato (split/merge, import senza tempi).
      expect(
        detectUndeclaredGaps(pts, const [],
            duration: dFreeze, movingTime: Duration.zero),
        isEmpty,
      );
    });

    test('il bilancio tiene i buchi piu\' lunghi e scarta chi non ci sta', () {
      final pts = [
        at(0),
        at(60, lat: 45.001),
        at(60 + 2220, lat: 45.051), // 37 minuti: il congelamento vero
        at(60 + 2280, lat: 45.052),
        at(60 + 2280 + 360, lat: 45.057), // 6 minuti, 550 m: sospetto piccolo
        at(60 + 2280 + 420, lat: 45.058),
      ];
      // Il bilancio copre solo i 37 minuti: il piccolo resta fuori.
      final found = detectUndeclaredGaps(pts, const [],
          duration: const Duration(minutes: 46), movingTime: const Duration(minutes: 9));
      expect(found, hasLength(1));
      expect(found.single.duration, const Duration(minutes: 37));
    });

    group('regime d\'epoca: tracce salvate prima della riduzione per forma', () {
      // Le tracce di allora hanno movingTime copiato dalla durata — che nel
      // regime moderno spegnerebbe tutto — ma non possono avere rettilinei
      // collassati: la riduzione uniforme conservava la cadenza temporale.
      test('il buco vero viene proposto anche con movingTime inattendibile', () {
        final pts = [
          at(0),
          at(60, lat: 45.001),
          at(60 + 2220, lat: 45.051),
          at(60 + 2280, lat: 45.052),
        ];
        final found = detectUndeclaredGaps(pts, const [],
            duration: dFreeze,
            movingTime: dFreeze, // copia: pre-2.10.0
            savedBeforeShapeSimplification: true);
        expect(found, hasLength(1),
            reason: 'senza Douglas-Peucker un arco lungo e\' un buco vero');
        expect(found.single.duration, const Duration(minutes: 37));
      });

      test('la pausa pranzo resta esclusa: la soglia spaziale vale sempre', () {
        final pts = [
          at(0),
          at(60, lat: 45.001),
          at(60 + 2400, lat: 45.0011),
          at(60 + 2460, lat: 45.002),
        ];
        expect(
          detectUndeclaredGaps(pts, const [],
              duration: dFreeze,
              movingTime: dFreeze,
              savedBeforeShapeSimplification: true),
          isEmpty,
        );
      });

      test('la stessa traccia nel regime moderno resta bloccata dal bilancio', () {
        final pts = [
          at(0),
          at(60, lat: 45.001),
          at(60 + 2220, lat: 45.051),
        ];
        expect(
          detectUndeclaredGaps(pts, const [],
              duration: dFreeze, movingTime: dFreeze),
          isEmpty,
          reason: 'movingTime==duration senza regime d\'epoca = non attendibile',
        );
      });

      test('la data di soglia e\' quella del cambio di riduzione', () {
        expect(kShapeSimplifiedSince, DateTime.utc(2026, 8, 5));
      });
    });

    test('sotto la soglia spaziale non scatta, anche con tanto tempo', () {
      final pts = [
        at(0),
        // 30 minuti ma ~111 m: sotto i 300 m richiesti.
        at(1800, lat: 45.001),
      ];
      expect(
        detectUndeclaredGaps(pts, const [],
            duration: dFreeze, movingTime: mFreeze),
        isEmpty,
      );
    });

    test('sotto la soglia temporale non scatta, anche con tanta distanza', () {
      final pts = [
        at(0),
        // 4 minuti e 5,5 km: puo' essere un dato sporco, non un buco da 5 min.
        at(240, lat: 45.05),
      ];
      expect(
        detectUndeclaredGaps(pts, const [],
            duration: dFreeze, movingTime: mFreeze),
        isEmpty,
      );
    });

    test('un arco gia\' coperto da un buco dichiarato viene saltato', () {
      final pts = [
        at(0),
        at(60, lat: 45.001),
        at(60 + 2220, lat: 45.051),
      ];
      final declared = [
        TrackGap(
          startedAt: pts[1].timestamp,
          endedAt: pts[2].timestamp,
          cause: TrackGap.causeAppFrozen,
        ),
      ];
      expect(
        detectUndeclaredGaps(pts, declared,
            duration: dFreeze, movingTime: mFreeze),
        isEmpty,
        reason: 'il watchdog l\'aveva gia\' visto: niente doppioni',
      );
    });

    test('un orologio che torna indietro non e\' un buco', () {
      final pts = [
        at(3600),
        at(0, lat: 45.05), // timestamp precedente: dato inaffidabile
        at(3660, lat: 45.051),
      ];
      expect(
        detectUndeclaredGaps(pts, const [],
            duration: dFreeze, movingTime: mFreeze),
        isEmpty,
      );
    });

    test('due congelamenti danno due candidati distinti', () {
      final pts = [
        at(0),
        at(60, lat: 45.001),
        at(60 + 2220, lat: 45.051),
        at(60 + 2280, lat: 45.052),
        at(60 + 2280 + 2220, lat: 45.102),
      ];
      expect(
        detectUndeclaredGaps(pts, const [],
            duration: const Duration(minutes: 78), movingTime: const Duration(minutes: 3)),
        hasLength(2),
      );
    });

    test('straightLineMeters misura solo i ponti, in linea retta', () {
      final pts = [
        at(0),
        at(60, lat: 45.001),
        at(60 + 2220, lat: 45.051), // ponte da ~5,56 km
        at(60 + 2280, lat: 45.052),
      ];
      final gaps = detectUndeclaredGaps(pts, const [],
          duration: dFreeze, movingTime: mFreeze);
      final metres = straightLineMeters(pts, gaps);
      expect(metres, greaterThan(5400));
      expect(metres, lessThan(5700));
      expect(straightLineMeters(pts, const []), 0);
    });
  });

  group('chi offre e chi disegna scelgono lo stesso buco', () {
    // Non e' un dettaglio estetico: la scheda offre "ricostruisci" su UN buco
    // e salva li' la ricostruzione; se il disegnatore ne guarda un altro, la
    // ricostruzione esiste nel database e non compare mai sulla mappa. Il
    // legame regge solo finche' le due parti usano la STESSA regola, ed e'
    // quello che questo test blocca.
    final points = [p(0), p(5), p(40), p(45)];
    final multipli = [
      gap(6, 20),
      TrackGap(
        startedAt: DateTime.utc(2026, 8, 16, 10, 20),
        endedAt: DateTime.utc(2026, 8, 16, 10, 39),
        cause: TrackGap.causeAppFrozen,
        reconstruction: const [LatLng(45.01, 9.01), LatLng(45.02, 9.02)],
      ),
    ];

    test('un arco, un buco rappresentativo', () {
      expect(gapsRappresentativi(points, multipli), hasLength(1));
    });

    test('e\' esattamente quello che il disegnatore userebbe', () {
      final disegnato = splitTrackOnGaps(points, multipli)
          .firstWhere((s) => s.isGap)
          .gap;
      expect(gapsRappresentativi(points, multipli).single.startedAt,
          disegnato!.startedAt);
    });

    test('senza ricostruzioni vince il piu\' lungo, non il primo', () {
      final soloTempo = [gap(6, 12), gap(12, 39)];
      expect(gapsRappresentativi(points, soloTempo).single.startedAt,
          DateTime.utc(2026, 8, 16, 10, 12));
    });

    test('un buco fuori da ogni arco non diventa un\'offerta', () {
      // Il watchdog puo\' aver scritto un buco che i punti non confermano:
      // offrirne la ricostruzione manderebbe su una pagina senza estremi.
      final fuori = [gap(100, 120)];
      expect(gapsRappresentativi(points, fuori), isEmpty);
    });
  });
}
