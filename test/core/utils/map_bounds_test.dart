import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailshare_flutter/core/utils/map_bounds.dart';

/// I casi che hanno prodotto il crash del 2026-07-31 sulla 2.9.4:
/// `_TileLayerState._clampToNativeZoom` → *Unsupported operation: Infinity or
/// NaN*. Tutti passavano i controlli che c'erano in giro per l'app
/// (`isNotEmpty`, `length >= 2`) e arrivavano intatti a `CameraFit.bounds`.
void main() {
  group('safeBounds', () {
    test('senza punti non c\'e\' niente da inquadrare', () {
      expect(safeBounds(const []), isNull);
    });

    test('una traccia normale non viene toccata', () {
      final b = safeBounds(const [
        LatLng(45.90, 9.60),
        LatLng(46.00, 9.75),
      ])!;
      expect(b.south, closeTo(45.90, 1e-9));
      expect(b.north, closeTo(46.00, 1e-9));
      expect(b.west, closeTo(9.60, 1e-9));
      expect(b.east, closeTo(9.75, 1e-9));
    });

    test('un punto solo diventa un riquadro con area, non un punto', () {
      final b = safeBounds(const [LatLng(45.9, 9.6)])!;
      expect(b.north - b.south, greaterThan(0));
      expect(b.east - b.west, greaterThan(0));
      // Resta centrato dov'era: allargare non deve spostare.
      expect((b.north + b.south) / 2, closeTo(45.9, 1e-9));
      expect((b.east + b.west) / 2, closeTo(9.6, 1e-9));
    });

    test('punti tutti identici: e\' il caso che mandava lo zoom a infinito', () {
      // Registrazione avviata e chiusa senza muoversi. Dieci punti: supera
      // sia isNotEmpty sia length >= 2, e produceva un riquadro di area zero.
      final b = safeBounds(List.filled(10, const LatLng(45.9, 9.6)))!;
      expect(b.north - b.south, greaterThan(0));
      expect(b.east - b.west, greaterThan(0));
    });

    test('un NaN in mezzo a punti buoni non avvelena il riquadro', () {
      final b = safeBounds([
        const LatLng(45.90, 9.60),
        LatLng(double.nan, double.nan),
        const LatLng(46.00, 9.75),
      ])!;
      expect(b.south, closeTo(45.90, 1e-9));
      expect(b.north, closeTo(46.00, 1e-9));
      expect(b.north.isFinite && b.south.isFinite, isTrue);
    });

    test('gli infiniti vengono scartati come i NaN', () {
      final b = safeBounds([
        const LatLng(45.90, 9.60),
        LatLng(double.infinity, double.negativeInfinity),
        const LatLng(46.00, 9.75),
      ])!;
      expect(b.north, closeTo(46.00, 1e-9));
      expect(b.west, closeTo(9.60, 1e-9));
    });

    test('coordinate fuori dai limiti terrestri vengono scartate', () {
      final b = safeBounds(const [
        LatLng(45.90, 9.60),
        LatLng(999.0, 999.0),
      ])!;
      expect(b.north, lessThanOrEqualTo(90));
      expect(b.east, lessThanOrEqualTo(180));
    });

    test('se sono TUTTI invalidi non si inventa un riquadro', () {
      final b = safeBounds([
        LatLng(double.nan, 9.6),
        const LatLng(91.0, 9.6),
      ]);
      expect(b, isNull);
    });

    test('un punto al polo non sfonda i limiti allargandosi', () {
      final b = safeBounds(const [LatLng(90.0, 180.0)])!;
      expect(b.north, lessThanOrEqualTo(90.0));
      expect(b.east, lessThanOrEqualTo(180.0));
      expect(b.north - b.south, greaterThan(0));
    });
  });
}
