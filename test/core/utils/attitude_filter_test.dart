import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/attitude_filter.dart';

/// Un filtro si giudica su due numeri che tirano in direzioni opposte: quanto
/// trema da fermi e quanto resta indietro in movimento. Migliorarne uno solo è
/// facile e non vuol dire niente, quindi qui si misurano **tutti e due** contro
/// il filtro che c'era prima.
void main() {
  /// EMA adattivo com'era: alpha ricavato dalla velocità, fra 0,20 e 0,50.
  /// Replica dell'EMA adattivo che stava in DeviceAttitudeService, per avere un
  /// termine di paragone e non un'opinione.
  List<double> runEma(List<double> input, double dt) {
    const alphaMin = 0.20, alphaMax = 0.50, rateForMax = 30.0;
    double? prev;
    final out = <double>[];
    for (final x in input) {
      if (prev == null) {
        prev = x;
        out.add(x);
        continue;
      }
      final rate = ((x - prev) / dt).abs();
      final t = (rate / rateForMax).clamp(0.0, 1.0);
      final alpha = alphaMin + t * (alphaMax - alphaMin);
      prev = prev + alpha * (x - prev);
      out.add(prev);
    }
    return out;
  }

  List<double> runOneEuro(List<double> input, double dt) {
    final f = OneEuroFilter();
    return [for (final x in input) f.filter(x, dt)];
  }

  /// Scarto quadratico medio dalla media: il tremolio.
  double rms(List<double> v) {
    final m = v.reduce((a, b) => a + b) / v.length;
    var s = 0.0;
    for (final x in v) {
      s += (x - m) * (x - m);
    }
    return math.sqrt(s / v.length);
  }

  group('da fermi: il tremolio non deve peggiorare', () {
    test('con rumore realistico One Euro è fermo almeno quanto l\'EMA', () {
      final rnd = math.Random(7);
      // 0,05° rms sull'assetto fuso, che è l'ordine di grandezza dichiarato
      // dai sensori quando il telefono è appoggiato.
      final input = [
        for (var i = 0; i < 400; i++) 100 + (rnd.nextDouble() - 0.5) * 0.17,
      ];
      const dt = 0.02;

      final ema = rms(runEma(input, dt).sublist(50));
      final euro = rms(runOneEuro(input, dt).sublist(50));

      expect(euro, lessThanOrEqualTo(ema * 1.05),
          reason: 'one euro $euro, ema $ema');
    });
  });

  group('in movimento: il ritardo deve calare', () {
    /// Quanti gradi il filtro resta indietro a regime, su una rampa costante.
    double lagDeg(List<double> Function(List<double>, double) run,
        double degPerSecond, double dt) {
      final n = 600;
      final input = [for (var i = 0; i < n; i++) i * degPerSecond * dt];
      final out = run(input, dt);
      // A regime la differenza è costante: si media sull'ultima parte.
      var s = 0.0;
      var c = 0;
      for (var i = n - 100; i < n; i++) {
        s += input[i] - out[i];
        c++;
      }
      return s / c;
    }

    test('a 40°/s One Euro resta molto meno indietro dell\'EMA', () {
      const dt = 0.02;
      final ema = lagDeg(runEma, 40, dt);
      final euro = lagDeg(runOneEuro, 40, dt);
      expect(euro, lessThan(ema * 0.6),
          reason: 'one euro ${euro.toStringAsFixed(3)}°, '
              'ema ${ema.toStringAsFixed(3)}°');
    });

    test('anche a 10°/s, cioè un movimento lento di ricerca', () {
      const dt = 0.02;
      final ema = lagDeg(runEma, 10, dt);
      final euro = lagDeg(runOneEuro, 10, dt);
      expect(euro, lessThan(ema),
          reason: 'one euro ${euro.toStringAsFixed(3)}°, '
              'ema ${ema.toStringAsFixed(3)}°');
    });

    test('più si va veloce, più il filtro si apre', () {
      const dt = 0.02;
      // Non è il ritardo assoluto a dover calare — a velocità doppia si
      // percorre il doppio — ma il rapporto fra ritardo e velocità.
      final lento = lagDeg(runOneEuro, 5, dt) / 5;
      final veloce = lagDeg(runOneEuro, 60, dt) / 60;
      expect(veloce, lessThan(lento),
          reason: 'è questa l\'idea del filtro: fermo smorza, veloce apre');
    });
  });

  group('il giro dei 360°', () {
    test('passando per nord non si fa il giro lungo', () {
      final f = AngleOneEuroFilter();
      // Da 355° a 5°, un grado alla volta attraversando lo zero.
      final input = [for (var i = 0; i < 30; i++) (355 + i) % 360.0];
      final out = [for (final x in input) f.filter(x.toDouble(), 0.02)];

      // Nessun passo del filtro può essere un balzo di mezzo giro.
      for (var i = 1; i < out.length; i++) {
        var d = (out[i] - out[i - 1]).abs();
        if (d > 180) d = 360 - d;
        expect(d, lessThan(10),
            reason: 'salto fra ${out[i - 1]} e ${out[i]}');
      }
      // E alla fine deve essere arrivato dalle parti giuste.
      var errore = (out.last - 24).abs();
      if (errore > 180) errore = 360 - errore;
      expect(errore, lessThan(6));
    });

    test('l\'uscita resta sempre in [0, 360)', () {
      final f = AngleOneEuroFilter();
      final rnd = math.Random(3);
      for (var i = 0; i < 500; i++) {
        final v = f.filter(rnd.nextDouble() * 720 - 360, 0.02);
        expect(v, inInclusiveRange(0, 360));
        expect(v, lessThan(360));
      }
    });
  });

  group('ogni angolo ha il suo taglio', () {
    test('alzare il telefono senza ruotare non prende il filtro lento', () {
      // È il difetto concreto del filtro precedente: il coefficiente veniva
      // dalla velocità dell'AZIMUT e si applicava anche al beccheggio, quindi
      // inquadrare una cima alzando il telefono — senza girarsi — prendeva lo
      // smorzamento da "fermo".
      final f = AttitudeFilter();
      const dt = 0.02;
      double? ultimo;
      for (var i = 0; i < 300; i++) {
        final r = f.filter(
          azimuthDeg: 90, // fermo
          pitchDeg: i * 40 * dt, // sale a 40°/s
          rollDeg: 0,
          timestampMs: i * dt * 1000,
        );
        ultimo = r.pitchDeg;
      }
      final atteso = 299 * 40 * dt;
      expect(atteso - ultimo!, lessThan(0.35),
          reason: 'ritardo sul beccheggio ${atteso - ultimo}°, '
              'con azimut fermo non deve essere quello da riposo');
    });
  });

  group('il tempo viene dal sensore', () {
    test('un buco lungo non produce un dt assurdo', () {
      final f = AttitudeFilter();
      f.filter(azimuthDeg: 10, pitchDeg: 0, rollDeg: 0, timestampMs: 1000);
      // App in sottofondo per dieci secondi, poi riprende.
      final r = f.filter(
          azimuthDeg: 20, pitchDeg: 0, rollDeg: 0, timestampMs: 11000);
      expect(r.azimuthDeg, greaterThan(10));
      expect(r.azimuthDeg, lessThan(20));
      expect(r.azimuthDeg.isFinite, isTrue);
    });

    test('un salto all\'indietro dell\'orologio non rompe niente', () {
      final f = AttitudeFilter();
      f.filter(azimuthDeg: 10, pitchDeg: 0, rollDeg: 0, timestampMs: 5000);
      final r = f.filter(
          azimuthDeg: 12, pitchDeg: 0, rollDeg: 0, timestampMs: 4000);
      expect(r.azimuthDeg.isFinite, isTrue);
      expect(r.azimuthDeg, inInclusiveRange(10, 12));
    });

    test('senza timestamp si usa il passo nominale invece di inventarlo', () {
      final f = AttitudeFilter();
      final a = f.filter(azimuthDeg: 10, pitchDeg: 0, rollDeg: 0);
      final b = f.filter(azimuthDeg: 20, pitchDeg: 0, rollDeg: 0);
      expect(a.azimuthDeg, 10);
      expect(b.azimuthDeg, greaterThan(10));
    });
  });

  test('il primo campione passa intatto, non parte da zero', () {
    // Partire da zero farebbe volare le etichette da nord alla direzione vera
    // ogni volta che si apre la schermata.
    final f = AttitudeFilter();
    final r = f.filter(
        azimuthDeg: 237, pitchDeg: -12, rollDeg: 3, timestampMs: 0);
    expect(r.azimuthDeg, closeTo(237, 1e-9));
    expect(r.pitchDeg, closeTo(-12, 1e-9),
        reason: 'il beccheggio NON gira: -12 deve restare -12, non diventare 348');
    expect(r.rollDeg, closeTo(3, 1e-9));
  });
}
