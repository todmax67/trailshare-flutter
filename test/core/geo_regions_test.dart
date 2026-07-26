import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/constants/geo_regions.dart';

void main() {
  group('resolveByBbox — casi reali misurati sul database', () {
    // Coordinate prese dai doc public_trails etichettati "Piemonte"
    // per errore (bbox del Piemonte che sborda in Francia/Svizzera).
    test('Chamonix non è Piemonte', () {
      final r = GeoRegions.resolveByBbox(45.9237, 6.8694);
      expect(r?.code, 'haute_savoie');
      expect(r?.countryCode, 'FR');
    });

    test('Courmayeur resta Valle d\'Aosta e non Piemonte', () {
      final r = GeoRegions.resolveByBbox(45.7900, 6.9700);
      expect(r?.code, 'valle_d_aosta');
      expect(r?.countryCode, 'IT');
    });

    test('Tour du Pays du Mont-Blanc (partenza reale) è francese', () {
      final r = GeoRegions.resolveByBbox(45.823, 6.739);
      expect(r?.countryCode, 'FR');
    });

    test('una coordinata piemontese resta Piemonte', () {
      final r = GeoRegions.resolveByBbox(45.07, 7.69); // Torino
      expect(r?.code, 'piemonte');
    });

    test('la più specifica vince sulla più grande', () {
      // Punto dentro sia Piemonte (grande) sia Valle d'Aosta (piccola).
      final r = GeoRegions.resolveByBbox(45.7, 7.3);
      expect(r?.code, 'valle_d_aosta');
    });

    test('fuori da tutti i bbox → null', () {
      expect(GeoRegions.resolveByBbox(52.5, 13.4), isNull); // Berlino
    });
  });

  group('modello', () {
    test('i code sono unici su tutti i paesi', () {
      final codes = GeoRegions.all.map((r) => r.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('la sentinella non contiene mai nulla', () {
      final intl = GeoRegions.byCode('international')!;
      expect(intl.contains(45.0, 9.0), isFalse);
      expect(intl.isSentinel, isTrue);
    });

    test('countryFlag deriva dal codice ISO', () {
      expect(GeoRegions.byCode('haute_savoie')!.countryFlag, '🇫🇷');
      expect(GeoRegions.byCode('valais')!.countryFlag, '🇨🇭');
      expect(GeoRegions.byCode('lombardia')!.countryFlag, '🇮🇹');
    });

    test('byCountry filtra correttamente', () {
      expect(GeoRegions.byCountry('IT').length, 20);
      for (final cc in ['FR', 'CH', 'AT', 'SI']) {
        expect(GeoRegions.byCountry(cc), isNotEmpty, reason: cc);
      }
      // La sentinella non appartiene a nessun paese.
      expect(GeoRegions.byCountry(''), hasLength(1));
    });
  });

  group('arco alpino — coordinate reali dall\'audit', () {
    test('Zermatt è Vallese, non Piemonte', () {
      final r = GeoRegions.resolveByBbox(46.0207, 7.7491);
      expect(r?.countryCode, 'CH');
    });

    test('Bernina/Grigioni non è Lombardia', () {
      final r = GeoRegions.resolveByBbox(46.4100, 9.9000);
      expect(r?.countryCode, 'CH');
    });

    // Limite DOCUMENTATO di resolveByBbox, non un bug: il Triglav
    // (Slovenia) cade dentro il rettangolo del Friuli, che è più
    // piccolo di quello sloveno e quindi vince. Nessun rettangolo può
    // risolvere un confine: per questo il paese si salva sul contenuto
    // (campo `country`) invece di dedurlo. Il test blinda il fatto che
    // il ripiego è approssimato, così nessuno ci costruisce sopra.
    test('sui confini il ripiego geometrico può sbagliare — per questo '
        'il paese va memorizzato', () {
      final r = GeoRegions.resolveByBbox(46.3833, 13.8358); // Triglav, SI
      expect(r?.countryCode, 'IT',
          reason: 'il bbox del Friuli è più piccolo e vince: '
              'atteso, ed è il motivo per cui esiste il campo country');
    });

    test('Innsbruck è Tirolo, non Trentino', () {
      final r = GeoRegions.resolveByBbox(47.2692, 11.4041);
      expect(r?.countryCode, 'AT');
    });

    test('il catalogo copre i 5 paesi alpini', () {
      for (final cc in ['IT', 'FR', 'CH', 'AT', 'SI']) {
        expect(GeoRegions.byCountry(cc), isNotEmpty, reason: cc);
      }
    });
  });
}
