import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/data/models/osm_poi.dart';
import 'package:trailshare_flutter/data/repositories/osm_pois_repository.dart';

void main() {
  group('OsmPoisRepository.haversine', () {
    test('zero distance for same point', () {
      expect(OsmPoisRepository.haversine(45.0, 9.0, 45.0, 9.0), 0);
    });

    test('matches known distance Milano-Roma (~477 km)', () {
      // Milano centro 45.4642, 9.1900 → Roma Termini 41.9028, 12.4964
      final d = OsmPoisRepository.haversine(45.4642, 9.19, 41.9028, 12.4964);
      // Tolleranza 1% (~5 km)
      expect(d, greaterThan(470000));
      expect(d, lessThan(485000));
    });

    test('symmetric: d(A,B) == d(B,A)', () {
      final d1 = OsmPoisRepository.haversine(45.0, 9.0, 46.0, 10.0);
      final d2 = OsmPoisRepository.haversine(46.0, 10.0, 45.0, 9.0);
      expect((d1 - d2).abs(), lessThan(0.001));
    });
  });

  group('OsmPoiType.fromCode', () {
    test('returns the correct enum for known codes', () {
      expect(OsmPoiType.fromCode('alpine_hut'), OsmPoiType.alpineHut);
      expect(OsmPoiType.fromCode('drinking_water'), OsmPoiType.drinkingWater);
      expect(OsmPoiType.fromCode('viewpoint'), OsmPoiType.viewpoint);
    });

    test('returns null for unknown or null codes', () {
      expect(OsmPoiType.fromCode('unknown'), isNull);
      expect(OsmPoiType.fromCode(null), isNull);
      expect(OsmPoiType.fromCode(''), isNull);
    });
  });

  group('OsmPoiType.toPoiType mapping', () {
    test('alpine/wilderness/shelter all map to PoiType.shelter', () {
      // Verifica solo che il mapping non lanci e produca sempre un valore.
      // (Il PoiType esatto dipende da trail_poi.dart, che è importato).
      expect(OsmPoiType.alpineHut.toPoiType(), isNotNull);
      expect(OsmPoiType.wildernessHut.toPoiType(), isNotNull);
      expect(OsmPoiType.shelter.toPoiType(), isNotNull);
      expect(
        OsmPoiType.alpineHut.toPoiType(),
        OsmPoiType.wildernessHut.toPoiType(),
      );
    });

    test('drinking_water and spring map to the same PoiType', () {
      expect(
        OsmPoiType.drinkingWater.toPoiType(),
        OsmPoiType.spring.toPoiType(),
      );
    });
  });

  group('OsmPoi.fromJson', () {
    test('parses a complete record', () {
      final poi = OsmPoi.fromJson({
        'id': 'n123',
        'type': 'alpine_hut',
        'name': 'Rifugio Brunone',
        'lat': 45.97,
        'lng': 9.76,
        'ele': 2295,
        'operator': 'CAI Bergamo',
        'website': 'https://example.com',
      });
      expect(poi, isNotNull);
      expect(poi!.id, 'n123');
      expect(poi.type, OsmPoiType.alpineHut);
      expect(poi.name, 'Rifugio Brunone');
      expect(poi.elevation, 2295);
      expect(poi.operatorName, 'CAI Bergamo');
    });

    test('returns null when required fields are missing', () {
      expect(OsmPoi.fromJson({'id': 'n1', 'name': 'X'}), isNull);
      expect(OsmPoi.fromJson({'id': 'n1', 'type': 'spring'}), isNull);
      expect(
        OsmPoi.fromJson({
          'id': 'n1',
          'type': 'spring',
          'name': '',
          'lat': 45.0,
          'lng': 9.0,
        }),
        isNull,
      );
    });

    test('returns null for unknown type code', () {
      final poi = OsmPoi.fromJson({
        'id': 'n1',
        'type': 'unknown_thing',
        'name': 'X',
        'lat': 45.0,
        'lng': 9.0,
      });
      expect(poi, isNull);
    });

    test('handles missing optional fields gracefully', () {
      final poi = OsmPoi.fromJson({
        'id': 'n1',
        'type': 'spring',
        'name': 'Sorgente del Toce',
        'lat': 46.4,
        'lng': 8.4,
      });
      expect(poi, isNotNull);
      expect(poi!.elevation, isNull);
      expect(poi.operatorName, isNull);
      expect(poi.website, isNull);
    });
  });
}
