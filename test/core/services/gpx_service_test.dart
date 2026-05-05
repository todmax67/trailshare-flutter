import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/services/gpx_service.dart';
import 'package:trailshare_flutter/data/models/track.dart';

void main() {
  late GpxService service;

  setUp(() {
    service = GpxService();
  });

  String fixture(String name) =>
      File('test/fixtures/$name').readAsStringSync();

  group('GpxService.parseGpxString', () {
    test('parses a standard <trk><trkseg><trkpt> file', () {
      final track = service.parseGpxString(fixture('sample_track.gpx'));

      expect(track, isNotNull);
      expect(track!.name, 'Sentiero del Test');
      expect(track.points.length, 5);
      expect(track.points.first.latitude, 46.0);
      expect(track.points.first.longitude, 9.0);
      expect(track.points.first.elevation, 1000.0);
    });

    test('falls back to <rte><rtept> when no track points are present', () {
      final track = service.parseGpxString(fixture('route_only.gpx'));

      expect(track, isNotNull);
      expect(track!.name, 'Itinerario pianificato');
      expect(track.points.length, 3);
      expect(track.points.last.elevation, 550.0);
    });

    test('returns null for a GPX file with no points at all', () {
      final track = service.parseGpxString(fixture('invalid.gpx'));
      expect(track, isNull);
    });

    test('returns null for malformed XML', () {
      final track = service.parseGpxString('<not-xml');
      expect(track, isNull);
    });

    test('rejects out-of-range latitude/longitude silently', () {
      const malformed = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
    <trkpt lat="999" lon="0"><ele>10</ele></trkpt>
    <trkpt lat="46.0" lon="9.0"><ele>1000</ele></trkpt>
  </trkseg></trk>
</gpx>''';
      final track = service.parseGpxString(malformed);
      expect(track, isNotNull);
      expect(track!.points.length, 1);
      expect(track.points.first.latitude, 46.0);
    });

    test('computes a non-zero distance for a 5-point track', () {
      final track = service.parseGpxString(fixture('sample_track.gpx'))!;
      expect(track.stats.distance, greaterThan(400));
      expect(track.stats.distance, lessThan(700));
    });

    test('computes elevation gain ignoring small noise', () {
      final track = service.parseGpxString(fixture('sample_track.gpx'))!;
      expect(track.stats.elevationGain, greaterThan(0));
      expect(track.stats.maxElevation, 1100.0);
      expect(track.stats.minElevation, 1000.0);
    });

    test('computes duration from first/last timestamps', () {
      final track = service.parseGpxString(fixture('sample_track.gpx'))!;
      expect(track.stats.duration, const Duration(minutes: 20));
    });
  });

  group('GpxService.generateGpx', () {
    test('produces a string that can be re-parsed back to the same points',
        () {
      final original = Track(
        id: 't1',
        name: 'Roundtrip',
        points: [
          TrackPoint(
            latitude: 45.0,
            longitude: 9.0,
            elevation: 500,
            timestamp: DateTime.utc(2026, 5, 1, 10, 0, 0),
          ),
          TrackPoint(
            latitude: 45.001,
            longitude: 9.001,
            elevation: 510,
            timestamp: DateTime.utc(2026, 5, 1, 10, 1, 0),
          ),
        ],
        activityType: ActivityType.trekking,
        createdAt: DateTime.utc(2026, 5, 1, 10, 0, 0),
        stats: const TrackStats(),
      );

      final gpx = service.generateGpx(original);
      final reparsed = service.parseGpxString(gpx);

      expect(reparsed, isNotNull);
      expect(reparsed!.name, 'Roundtrip');
      expect(reparsed.points.length, 2);
      expect(reparsed.points.first.latitude, 45.0);
      expect(reparsed.points.last.elevation, 510);
    });

    test('escapes XML special characters in the track name', () {
      final track = Track(
        id: 't2',
        name: 'Foo & <Bar> "Baz"',
        points: const [],
        activityType: ActivityType.trekking,
        createdAt: DateTime.utc(2026, 5, 1),
        stats: const TrackStats(),
      );

      final gpx = service.generateGpx(track);
      expect(gpx, contains('Foo &amp; &lt;Bar&gt; &quot;Baz&quot;'));
      expect(gpx, isNot(contains('Foo & <Bar> "Baz"')));
    });
  });
}
