import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/geohash_util.dart';

void main() {
  group('GeoHashUtil.encode', () {
    test('encodes Milano (45.4642, 9.1900) at default precision 7', () {
      final hash = GeoHashUtil.encode(45.4642, 9.1900);
      // Geohash conosciuto per Milano centro: u0nd9
      expect(hash, startsWith('u0nd'));
      expect(hash.length, 7);
    });

    test('encodes the equator/prime-meridian origin', () {
      final hash = GeoHashUtil.encode(0, 0, precision: 5);
      // Origin geohash inizia con 's' standard.
      expect(hash, startsWith('s'));
    });

    test('precision parameter controls the output length', () {
      expect(GeoHashUtil.encode(45.46, 9.19, precision: 1).length, 1);
      expect(GeoHashUtil.encode(45.46, 9.19, precision: 5).length, 5);
      expect(GeoHashUtil.encode(45.46, 9.19, precision: 9).length, 9);
    });

    test('different points produce different hashes', () {
      final milano = GeoHashUtil.encode(45.4642, 9.1900);
      final roma = GeoHashUtil.encode(41.9028, 12.4964);
      expect(milano, isNot(roma));
    });

    test('nearby points share a long common prefix', () {
      final a = GeoHashUtil.encode(45.4642, 9.1900);
      final b = GeoHashUtil.encode(45.4643, 9.1901); // ~10m
      // Almeno i primi 6 caratteri (≈1.2 km cell) devono combaciare.
      expect(a.substring(0, 6), b.substring(0, 6));
    });
  });

  group('GeoHashUtil.decode', () {
    test('decodes back to a point inside the original cell', () {
      const lat = 45.4642;
      const lng = 9.1900;
      final hash = GeoHashUtil.encode(lat, lng, precision: 7);
      final decoded = GeoHashUtil.decode(hash);
      // Precision 7 ≈ 153m: il roundtrip deve essere entro questa
      // tolleranza in entrambe le dimensioni.
      expect((decoded.latitude - lat).abs(), lessThan(0.001));
      expect((decoded.longitude - lng).abs(), lessThan(0.001));
    });

    test('higher precision = tighter roundtrip', () {
      const lat = 45.4642;
      const lng = 9.1900;
      final loose = GeoHashUtil.decode(GeoHashUtil.encode(lat, lng, precision: 4));
      final tight = GeoHashUtil.decode(GeoHashUtil.encode(lat, lng, precision: 9));
      final looseErr = (loose.latitude - lat).abs() + (loose.longitude - lng).abs();
      final tightErr = (tight.latitude - lat).abs() + (tight.longitude - lng).abs();
      expect(tightErr, lessThan(looseErr));
    });

    test('is case-insensitive', () {
      final lower = GeoHashUtil.decode('u0nd9k0');
      final upper = GeoHashUtil.decode('U0ND9K0');
      expect(lower.latitude, upper.latitude);
      expect(lower.longitude, upper.longitude);
    });
  });

  group('GeoHashUtil.precisionForRadius', () {
    test('big radii map to short precisions', () {
      expect(GeoHashUtil.precisionForRadius(5000), 1);
      expect(GeoHashUtil.precisionForRadius(700), 2);
      expect(GeoHashUtil.precisionForRadius(100), 3);
    });

    test('small radii map to long precisions', () {
      expect(GeoHashUtil.precisionForRadius(1.0), 6);
      expect(GeoHashUtil.precisionForRadius(0.1), 7);
      expect(GeoHashUtil.precisionForRadius(0.01), 9);
    });

    test('boundary cases match the documented thresholds', () {
      expect(GeoHashUtil.precisionForRadius(2500), 1);
      expect(GeoHashUtil.precisionForRadius(20), 4);
      expect(GeoHashUtil.precisionForRadius(2.4), 5);
    });
  });

  group('GeoHashUtil.getNeighbors', () {
    test('always includes the original geohash', () {
      const hash = 'u0nd9';
      final neighbors = GeoHashUtil.getNeighbors(hash);
      expect(neighbors, contains(hash));
    });

    test('returns no duplicates and at most 9 entries', () {
      final neighbors = GeoHashUtil.getNeighbors('u0nd9');
      expect(neighbors.toSet().length, neighbors.length);
      expect(neighbors.length, lessThanOrEqualTo(9));
    });
  });

  group('GeoHashUtil.getBoundingBoxHashes', () {
    test('returns at least one hash for a non-empty box', () {
      final hashes = GeoHashUtil.getBoundingBoxHashes(
        minLat: 45.4,
        maxLat: 45.5,
        minLng: 9.1,
        maxLng: 9.2,
        precision: 5,
      );
      expect(hashes, isNotEmpty);
    });

    test('all returned hashes have the requested precision', () {
      final hashes = GeoHashUtil.getBoundingBoxHashes(
        minLat: 45.4,
        maxLat: 45.5,
        minLng: 9.1,
        maxLng: 9.2,
        precision: 6,
      );
      for (final h in hashes) {
        expect(h.length, 6);
      }
    });
  });

  group('GeoHashUtil.getQueryRanges', () {
    test('produces ranges where end > start (Firestore-friendly)', () {
      final ranges = GeoHashUtil.getQueryRanges(
        minLat: 45.4,
        maxLat: 45.5,
        minLng: 9.1,
        maxLng: 9.2,
        precision: 5,
      );
      expect(ranges, isNotEmpty);
      for (final r in ranges) {
        expect(r.end.compareTo(r.start), greaterThan(0));
      }
    });

    test('ranges end with "~" sentinel after base32 alphabet', () {
      final ranges = GeoHashUtil.getQueryRanges(
        minLat: 45.4,
        maxLat: 45.5,
        minLng: 9.1,
        maxLng: 9.2,
      );
      for (final r in ranges) {
        expect(r.end.endsWith('~'), isTrue);
      }
    });
  });
}
