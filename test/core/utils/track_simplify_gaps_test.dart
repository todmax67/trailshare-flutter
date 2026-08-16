import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/track_simplify.dart';
import 'package:trailshare_flutter/data/models/track.dart';

/// La guardia temporale della semplificazione: nessun arco della traccia
/// salvata puo' coprire 5+ minuti SE fra i suoi estremi c'erano punti
/// registrati. Senza, un rettilineo percorso lentamente collassava nei due
/// estremi e diventava indistinguibile da un congelamento vero — il difetto
/// principale trovato dalla revisione avversariale della Fase 1 (2026-08-16).
void main() {
  TrackPoint at(int seconds, double lat, [double lng = 9.0]) => TrackPoint(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.utc(2026, 8, 16, 10).add(Duration(seconds: seconds)),
      );

  Duration maxArc(List<TrackPoint> pts) {
    var m = Duration.zero;
    for (var i = 1; i < pts.length; i++) {
      final dt = pts[i].timestamp.difference(pts[i - 1].timestamp);
      if (dt > m) m = dt;
    }
    return m;
  }

  test('un rettilineo lungo NON collassa oltre i 5 minuti', () {
    // 30 minuti su una retta perfetta, un punto ogni 10 s: Douglas-Peucker da
    // solo terrebbe i due estremi, creando un arco da 30 minuti identico a un
    // congelamento.
    final pts = [for (var i = 0; i <= 180; i++) at(i * 10, 45.0 + i * 0.0004)];
    final out = simplifyTrack(pts);

    expect(out.length, greaterThan(2),
        reason: 'la guardia deve reinserire punti sul rettilineo');
    expect(maxArc(out), lessThan(const Duration(minutes: 5)),
        reason: 'dove i dati esistevano, nessun arco lungo deve sopravvivere');
  });

  test('un buco vero resta un arco lungo: e\' la firma che serve', () {
    // Retta con 37 minuti SENZA punti nel mezzo: il buco non va "riparato".
    final before = [for (var i = 0; i <= 30; i++) at(i * 10, 45.0 + i * 0.0004)];
    final after = [
      for (var i = 0; i <= 30; i++)
        at(300 + 2220 + i * 10, 45.05 + i * 0.0004)
    ];
    final out = simplifyTrack([...before, ...after]);

    expect(maxArc(out), greaterThanOrEqualTo(const Duration(minutes: 37)),
        reason: 'il buco reale deve restare visibile nella traccia salvata');
    // E deve essere UNO solo: tutto il resto sta sotto la soglia.
    final long = <Duration>[];
    for (var i = 1; i < out.length; i++) {
      final dt = out[i].timestamp.difference(out[i - 1].timestamp);
      if (dt >= const Duration(minutes: 5)) long.add(dt);
    }
    expect(long, hasLength(1));
  });

  test('su una traccia breve e curva la guardia non tocca niente', () {
    // Zigzag di 5 minuti totali: nessun arco puo' avvicinarsi alla soglia.
    final pts = [
      for (var i = 0; i <= 30; i++)
        at(i * 10, 45.0 + i * 0.0005, 9.0 + (i.isEven ? 0.0006 : -0.0006))
    ];
    final out = simplifyTrack(pts);
    expect(maxArc(out), lessThan(const Duration(minutes: 5)));
  });

  test('l\'ordine cronologico sopravvive alla guardia', () {
    final pts = [for (var i = 0; i <= 240; i++) at(i * 10, 45.0 + i * 0.0004)];
    final out = simplifyTrack(pts);
    for (var i = 1; i < out.length; i++) {
      expect(out[i].timestamp.isAfter(out[i - 1].timestamp), isTrue);
    }
  });
}
