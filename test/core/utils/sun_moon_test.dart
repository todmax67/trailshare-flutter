import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/sun_moon.dart';

/// L'astronomia è facile da sbagliare in modo plausibile: un segno invertito o
/// una convenzione di azimut diversa produce numeri dall'aria sensata e un sole
/// disegnato dalla parte opposta del cielo.
///
/// Questi test non confrontano con una libreria: verificano proprietà
/// **geometriche note**, che si possono derivare a mano e che nessuna formula
/// sbagliata può soddisfare per caso.
void main() {
  group('altezza massima del sole', () {
    // A mezzogiorno solare l'altezza vale 90 - |latitudine - declinazione|.
    // Ai solstizi la declinazione e' ±23,44°, quindi il valore e' calcolabile
    // esattamente senza consultare nessuna effemeride.

    double maxElevationOnDay(DateTime utcMidnight, double lat, double lng) {
      var best = -90.0;
      for (var m = 0; m < 24 * 60; m += 5) {
        final e = sunPosition(utcMidnight.add(Duration(minutes: m)), lat, lng)
            .elevationDeg;
        if (e > best) best = e;
      }
      return best;
    }

    test('solstizio d\'estate a 45°N: 68,4°', () {
      final max = maxElevationOnDay(DateTime.utc(2026, 6, 21), 45, 0);
      expect(max, closeTo(90 - 45 + 23.44, 0.6));
    });

    test('solstizio d\'inverno a 45°N: 21,6°', () {
      final max = maxElevationOnDay(DateTime.utc(2026, 12, 21), 45, 0);
      expect(max, closeTo(90 - 45 - 23.44, 0.6));
    });

    test('equinozio all\'equatore: il sole passa allo zenit', () {
      final max = maxElevationOnDay(DateTime.utc(2026, 3, 20), 0, 0);
      expect(max, greaterThan(89.0));
    });

    test('notte polare: a 80°N in dicembre il sole non sorge mai', () {
      final max = maxElevationOnDay(DateTime.utc(2026, 12, 21), 80, 0);
      expect(max, lessThan(0));
    });

    test('sole di mezzanotte: a 80°N in giugno non tramonta mai', () {
      var worst = 90.0;
      final midnight = DateTime.utc(2026, 6, 21);
      for (var m = 0; m < 24 * 60; m += 5) {
        final e = sunPosition(midnight.add(Duration(minutes: m)), 80, 0)
            .elevationDeg;
        if (e < worst) worst = e;
      }
      expect(worst, greaterThan(0));
    });
  });

  group('azimut — la convenzione è nord, in senso orario', () {
    test('a mezzogiorno solare, alle nostre latitudini, il sole è a sud', () {
      // Se la convenzione fosse "dal sud" come negli almanacchi, qui uscirebbe
      // 0° e il sole verrebbe disegnato a nord.
      var bestElev = -90.0;
      var azAtNoon = 0.0;
      final midnight = DateTime.utc(2026, 6, 21);
      for (var m = 0; m < 24 * 60; m += 2) {
        final p = sunPosition(midnight.add(Duration(minutes: m)), 45, 9);
        if (p.elevationDeg > bestElev) {
          bestElev = p.elevationDeg;
          azAtNoon = p.azimuthDeg;
        }
      }
      expect(azAtNoon, closeTo(180, 2));
    });

    test('il sole sorge a est e tramonta a ovest', () {
      final midnight = DateTime.utc(2026, 3, 20);
      SkyPosition? atRise;
      SkyPosition? atSet;
      SkyPosition? prev;
      for (var m = 0; m < 24 * 60; m += 2) {
        final p = sunPosition(midnight.add(Duration(minutes: m)), 45, 0);
        if (prev != null) {
          if (prev.elevationDeg <= 0 && p.elevationDeg > 0) atRise ??= p;
          if (prev.elevationDeg > 0 && p.elevationDeg <= 0) atSet ??= p;
        }
        prev = p;
      }
      // All'equinozio il sole sorge quasi esattamente a est e tramonta a ovest,
      // ovunque ci si trovi.
      expect(atRise!.azimuthDeg, closeTo(90, 2));
      expect(atSet!.azimuthDeg, closeTo(270, 2));
    });

    test('nell\'emisfero sud a mezzogiorno il sole è a nord', () {
      var bestElev = -90.0;
      var az = 0.0;
      final midnight = DateTime.utc(2026, 6, 21);
      for (var m = 0; m < 24 * 60; m += 2) {
        final p = sunPosition(midnight.add(Duration(minutes: m)), -33, 151);
        if (p.elevationDeg > bestElev) {
          bestElev = p.elevationDeg;
          az = p.azimuthDeg;
        }
      }
      // L'azimut e' ciclico: 359,9° e' nord quanto 0,1°, quindi si confronta
      // la distanza angolare e non il numero.
      final fromNorth = math.min(az, 360 - az);
      expect(fromNorth, lessThan(3),
          reason: 'a Sydney a mezzogiorno il sole sta a nord, non a sud');
    });
  });

  group('alba e tramonto', () {
    test('all\'equinozio il giorno dura circa dodici ore', () {
      final r = sunriseSunset(DateTime.utc(2026, 3, 20), 45, 0);
      expect(r.sunrise, isNotNull);
      expect(r.sunset, isNotNull);
      final hours = r.sunset!.difference(r.sunrise!).inMinutes / 60;
      expect(hours, closeTo(12, 0.4));
    });

    test('d\'estate a 45°N il giorno è molto più lungo che d\'inverno', () {
      final summer = sunriseSunset(DateTime.utc(2026, 6, 21), 45, 0);
      final winter = sunriseSunset(DateTime.utc(2026, 12, 21), 45, 0);
      final sh = summer.sunset!.difference(summer.sunrise!).inMinutes / 60;
      final wh = winter.sunset!.difference(winter.sunrise!).inMinutes / 60;
      expect(sh, closeTo(15.5, 0.6));
      expect(wh, closeTo(8.7, 0.6));
    });

    test('in notte polare non ci sono né alba né tramonto', () {
      final r = sunriseSunset(DateTime.utc(2026, 12, 21), 80, 0);
      expect(r.sunrise, isNull);
      expect(r.sunset, isNull);
    });
  });

  group('luna', () {
    test('resta in un intervallo di declinazione plausibile', () {
      // La luna non si allontana mai dall'eclittica piu' di ~5°, quindi la sua
      // altezza massima resta entro limiti calcolabili.
      var best = -90.0;
      final start = DateTime.utc(2026, 8, 12);
      for (var h = 0; h < 24 * 30; h++) {
        final p = moonPosition(start.add(Duration(hours: h)), 45, 9).position;
        if (p.elevationDeg > best) best = p.elevationDeg;
      }
      // A 45°N il massimo teorico e' 90-45+23,44+5,15 = 73,6°.
      expect(best, lessThan(75));
      expect(best, greaterThan(35));
    });

    test('la frazione illuminata percorre un ciclo completo in un mese', () {
      var minF = 1.0;
      var maxF = 0.0;
      final start = DateTime.utc(2026, 8, 1);
      for (var h = 0; h < 24 * 30; h += 6) {
        final f =
            moonPosition(start.add(Duration(hours: h)), 45, 9).illuminatedFraction;
        if (f < minF) minF = f;
        if (f > maxF) maxF = f;
      }
      expect(minF, lessThan(0.1), reason: 'deve passare per la luna nuova');
      expect(maxF, greaterThan(0.9), reason: 'e per la luna piena');
    });

    test('sorge e tramonta, non resta fissa', () {
      var above = 0;
      var below = 0;
      final start = DateTime.utc(2026, 8, 12);
      for (var h = 0; h < 48; h++) {
        final p = moonPosition(start.add(Duration(hours: h)), 45, 9).position;
        if (p.elevationDeg > 0) {
          above++;
        } else {
          below++;
        }
      }
      expect(above, greaterThan(10));
      expect(below, greaterThan(10));
    });

    test('il nome della fase segue la frazione illuminata', () {
      // Si scorre un mese: i nomi devono arrivare tutti, e nell'ordine giusto —
      // la piena non puo' precedere una crescente nello stesso ciclo.
      final seen = <String>[];
      final start = DateTime.utc(2026, 8, 1);
      for (var h = 0; h < 24 * 30; h += 12) {
        final label = moonPhaseLabel(moonPhase(start.add(Duration(hours: h))));
        if (seen.isEmpty || seen.last != label) seen.add(label);
      }
      expect(seen, contains('luna nuova'));
      expect(seen, contains('luna piena'));
      expect(seen.any((s) => s.contains('crescente')), isTrue);
      expect(seen.any((s) => s.contains('calante')), isTrue);
      expect(seen.indexWhere((s) => s.contains('crescente')),
          lessThan(seen.indexOf('luna piena')));
    });
  });

  group('sparizione dietro il terreno', () {
    // Il valore vero della funzione: non il tramonto da almanacco, ma l'istante
    // in cui il sole passa dietro la cresta.

    final day = DateTime.utc(2026, 6, 21, 22); // mezzanotte locale a 45°N, +2
    final track = sunTrack(day, 45.9, 9.9, stepMinutes: 1);

    test('con orizzonte piatto coincide col tramonto astronomico', () {
      final flat = horizonCrossing(track, (_) => 0);
      final astro = sunriseSunset(day, 45.9, 9.9).sunset!;
      expect(flat, isNotNull);
      // La soglia astronomica e' -0,833° per la rifrazione, quindi il passaggio
      // per lo zero arriva qualche minuto prima. Non di piu'.
      final gap = astro.difference(flat!.time).inMinutes;
      expect(gap, inInclusiveRange(0, 8));
    });

    test('una cresta a ovest anticipa il tramonto', () {
      // Muraglia di 20° fra 250° e 300°: il sole di giugno tramonta a nordovest
      // e ci finisce dentro.
      double ridge(double az) => (az > 250 && az < 300) ? 20 : 0;
      final behind = horizonCrossing(track, ridge);
      final flat = horizonCrossing(track, (_) => 0);
      expect(behind, isNotNull);
      expect(behind!.time.isBefore(flat!.time), isTrue,
          reason: 'dietro una cresta il sole sparisce prima');
      expect(behind.elevationDeg, greaterThan(15),
          reason: 'sparisce mentre e\' ancora alto nel cielo');
    });

    test('dove il terreno è ignoto non si dichiara nessun tramonto', () {
      // Tutto NaN: la funzione deve tacere, non ripiegare su un orizzonte
      // piatto immaginario.
      expect(horizonCrossing(track, (_) => double.nan), isNull);
    });

    test('sa distinguere la sparizione dalla ricomparsa', () {
      final sets = horizonCrossing(track, (_) => 0, descending: true)!;
      final rises = horizonCrossing(track, (_) => 0, descending: false)!;
      expect(rises.time.isBefore(sets.time), isTrue,
          reason: 'in una giornata l\'alba viene prima del tramonto');
      expect(rises.azimuthDeg, lessThan(90),
          reason: 'a giugno il sole sorge a nordest');
      expect(sets.azimuthDeg, greaterThan(270),
          reason: 'e tramonta a nordovest');
    });

    test('`after` trova il passaggio successivo, non quello di stamattina', () {
      final noon = day.add(const Duration(hours: 12));
      final next = horizonCrossing(track, (_) => 0, descending: false,
          after: noon);
      // Dopo mezzogiorno non c'e' nessun'altra alba in giornata.
      expect(next, isNull);
    });
  });
}
