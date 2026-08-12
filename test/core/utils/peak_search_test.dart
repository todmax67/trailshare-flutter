import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/peak_search.dart';
import 'package:trailshare_flutter/data/models/mountain_peak.dart';

/// Con trentasettemila cime il difficile non è trovare, è ordinare: cercando
/// «monte» le corrispondenze sono migliaia. Questi test bloccano l'ordine, che
/// è l'unica cosa che rende la ricerca utile invece che esaustiva.
void main() {
  MountainPeak p(String name,
          {double lat = 46, double lng = 10, double? ele}) =>
      MountainPeak(
        id: name,
        name: name,
        latitude: lat,
        longitude: lng,
        elevation: ele,
      );

  group('accenti e apostrofi non devono servire per trovare', () {
    test('la piegatura toglie gli accenti di tutte le lingue del catalogo', () {
      // Il catalogo è italiano, tedesco, francese e ladino insieme.
      expect(foldForSearch('Tête de Chabrière'), 'tete de chabriere');
      expect(foldForSearch('Grünsee Spitze'), 'grunsee spitze');
      expect(foldForSearch("Corno d'Aquilio"), "corno d'aquilio");
      expect(foldForSearch('Cima d’Asta'), "cima d'asta");
    });

    test('cercare senza accento trova lo stesso', () {
      final r = searchPeaksByName([p('Tête de Chabrière')], 'tete');
      expect(r, hasLength(1));
    });

    test('l\'apostrofo del telefono trova quello del dataset', () {
      // Sono due caratteri Unicode diversi, e nessuno se lo aspetta.
      final r = searchPeaksByName([p('Cima d’Asta')], "d'asta");
      expect(r, hasLength(1));
    });
  });

  group('la qualità della corrispondenza viene prima della distanza', () {
    test('l\'esatto lontano batte il somigliante vicino', () {
      // Chi scrive «Monte Rosa» sa cosa vuole, anche se è a 200 km.
      final vicino = p('Monte Rosalia', lat: 46.0, lng: 10.0);
      final lontano = p('Monte Rosa', lat: 45.9, lng: 7.9);
      final r = searchPeaksByName(
        [vicino, lontano],
        'monte rosa',
        observerLat: 46.0,
        observerLng: 10.0,
      );
      expect(r.first.peak.name, 'Monte Rosa');
    });

    test('l\'inizio di parola conta: «coca» trova «Pizzo di Coca»', () {
      // È il caso più comune di tutti: il nome proprio sta dopo il tipo.
      final r = searchPeaksByName([p('Pizzo di Coca'), p('Cocazzo')], 'coca');
      expect(r.map((h) => h.peak.name), contains('Pizzo di Coca'));
      // «Cocazzo» inizia con la query, quindi vince: è comunque una
      // corrispondenza migliore.
      expect(r.first.peak.name, 'Cocazzo');
    });

    test('la sottostringa in mezzo a una parola viene per ultima', () {
      final r = searchPeaksByName(
          [p('Sassocoso'), p('Coso'), p('Monte Coso')], 'coso');
      final nomi = r.map((h) => h.peak.name).toList();
      expect(nomi.indexOf('Coso'), lessThan(nomi.indexOf('Monte Coso')));
      expect(nomi.indexOf('Monte Coso'), lessThan(nomi.indexOf('Sassocoso')));
    });
  });

  group('a parità di corrispondenza vince la più vicina', () {
    test('fra venticinque omonimi si intende quello che si ha davanti', () {
      final peaks = [
        p('Monte Nero', lat: 40.0, lng: 15.0), // lontanissimo
        p('Monte Nero', lat: 46.01, lng: 10.01), // dietro casa
        p('Monte Nero', lat: 44.0, lng: 11.0),
      ];
      final r = searchPeaksByName(peaks, 'monte nero',
          observerLat: 46.0, observerLng: 10.0);
      expect(r.first.peak.latitude, closeTo(46.01, 1e-9));
      expect(r.first.distanceMeters, lessThan(2000));
    });

    test('senza posizione si ripiega sulla quota, non sull\'ordine del file',
        () {
      final peaks = [
        p('Monte Nero', ele: 900),
        p('Monte Nero', ele: 2400),
        p('Monte Nero', ele: 1500),
      ];
      final r = searchPeaksByName(peaks, 'monte nero');
      expect(r.first.peak.elevation, 2400);
      expect(r.first.distanceMeters, isNull);
    });
  });

  group('i confini', () {
    test('una lettera sola non è una ricerca', () {
      // Su trentasettemila cime restituirebbe quasi l\'elenco intero.
      expect(searchPeaksByName([p('Monte Rosa')], 'm'), isEmpty);
      expect(searchPeaksByName([p('Monte Rosa')], ''), isEmpty);
      expect(searchPeaksByName([p('Monte Rosa')], '  '), isEmpty);
    });

    test('due lettere sì', () {
      expect(searchPeaksByName([p('Monte Rosa')], 'mo'), hasLength(1));
    });

    test('gli spazi ai bordi non contano', () {
      expect(searchPeaksByName([p('Monte Rosa')], '  rosa  '), hasLength(1));
    });

    test('il limite si rispetta', () {
      final peaks = [for (var i = 0; i < 200; i++) p('Monte $i')];
      expect(searchPeaksByName(peaks, 'monte', limit: 15), hasLength(15));
    });

    test('niente corrispondenze, niente risultati', () {
      expect(searchPeaksByName([p('Monte Rosa')], 'cervino'), isEmpty);
    });
  });

  group('di quanto girarsi', () {
    test('il segno dice da che parte, ed è metà dell\'informazione', () {
      // «47°» non dice niente, «47° a destra» sì.
      expect(relativeTurnDeg(90, 137), closeTo(47, 1e-9));
      expect(relativeTurnDeg(90, 43), closeTo(-47, 1e-9));
    });

    test('non si fa mai il giro lungo', () {
      // Da 350° a 10° sono venti gradi a destra, non trecentoquaranta a
      // sinistra: e' il difetto che si vede solo puntando a nord.
      expect(relativeTurnDeg(350, 10), closeTo(20, 1e-9));
      expect(relativeTurnDeg(10, 350), closeTo(-20, 1e-9));
      expect(relativeTurnDeg(0, 180).abs(), closeTo(180, 1e-9));
    });

    test('resta sempre entro mezzo giro', () {
      for (var a = 0; a < 360; a += 7) {
        for (var b = 0; b < 360; b += 11) {
          final t = relativeTurnDeg(a.toDouble(), b.toDouble());
          expect(t, inInclusiveRange(-180, 180));
        }
      }
    });
  });
}
