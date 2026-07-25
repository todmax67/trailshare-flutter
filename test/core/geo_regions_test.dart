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
      expect(GeoRegions.byCountry('FR').length, 2);
      expect(GeoRegions.byCountry('CH').length, 1);
    });
  });
}
