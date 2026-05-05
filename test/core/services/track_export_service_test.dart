import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/services/track_export_service.dart';
import 'package:trailshare_flutter/data/models/track.dart';

void main() {
  late TrackExportService service;

  setUp(() {
    service = TrackExportService();
  });

  Track makeTrack({
    String name = 'Test track',
    ActivityType activity = ActivityType.cycling,
    Map<DateTime, int>? hr,
    double? calories,
  }) {
    final start = DateTime.utc(2026, 5, 1, 8);
    return Track(
      id: 't1',
      name: name,
      points: [
        TrackPoint(
          latitude: 45.0,
          longitude: 9.0,
          elevation: 500,
          timestamp: start,
        ),
        TrackPoint(
          latitude: 45.001,
          longitude: 9.001,
          elevation: 510,
          timestamp: start.add(const Duration(minutes: 1)),
        ),
        TrackPoint(
          latitude: 45.002,
          longitude: 9.002,
          elevation: 520,
          timestamp: start.add(const Duration(minutes: 2)),
        ),
      ],
      activityType: activity,
      createdAt: start,
      stats: TrackStats(
        distance: 200,
        duration: const Duration(minutes: 2),
        maxSpeed: 5.5,
      ),
      heartRateData: hr,
      healthCalories: calories,
    );
  }

  group('ExportFormat enum', () {
    test('extension and displayName for all formats', () {
      expect(ExportFormat.gpx.extension, 'gpx');
      expect(ExportFormat.tcx.extension, 'tcx');
      expect(ExportFormat.kml.extension, 'kml');
      expect(ExportFormat.fit.extension, 'fit');
      expect(ExportFormat.gpx.displayName, 'GPX');
      expect(ExportFormat.fit.displayName, 'FIT');
    });
  });

  group('TrackExportService.generateTcx', () {
    test('produces a valid-looking TCX 2.0 envelope', () {
      final tcx = service.generateTcx(makeTrack());

      expect(tcx, contains('<?xml version="1.0"'));
      expect(tcx, contains('<TrainingCenterDatabase'));
      expect(tcx, contains('xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"'));
      expect(tcx, contains('</TrainingCenterDatabase>'));
    });

    test('includes one Trackpoint per Track point', () {
      final tcx = service.generateTcx(makeTrack());
      final count = '<Trackpoint>'.allMatches(tcx).length;
      expect(count, 3);
    });

    test('cycling maps to Sport="Biking"', () {
      final tcx = service.generateTcx(makeTrack(activity: ActivityType.cycling));
      expect(tcx, contains('Sport="Biking"'));
    });

    test('running maps to Sport="Running"', () {
      final tcx = service.generateTcx(makeTrack(activity: ActivityType.running));
      expect(tcx, contains('Sport="Running"'));
    });

    test('trekking falls back to Sport="Other"', () {
      final tcx = service.generateTcx(makeTrack(activity: ActivityType.trekking));
      expect(tcx, contains('Sport="Other"'));
    });

    test('emits Calories from healthCalories when available', () {
      final tcx = service.generateTcx(makeTrack(calories: 350.6));
      expect(tcx, contains('<Calories>351</Calories>'));
    });

    test('emits Calories>0 when healthCalories is null', () {
      final tcx = service.generateTcx(makeTrack());
      expect(tcx, contains('<Calories>0</Calories>'));
    });

    test('attaches HeartRateBpm when timestamp is within ±30s', () {
      final start = DateTime.utc(2026, 5, 1, 8);
      final tcx = service.generateTcx(makeTrack(hr: {
        start: 120,
        start.add(const Duration(minutes: 1)): 140,
      }));
      expect(tcx, contains('<HeartRateBpm><Value>120</Value></HeartRateBpm>'));
      expect(tcx, contains('<HeartRateBpm><Value>140</Value></HeartRateBpm>'));
    });

    test('skips HeartRateBpm when nearest sample is far away', () {
      final start = DateTime.utc(2026, 5, 1, 8);
      // L'unico campione è a 1 ora di distanza dal primo punto
      final tcx = service.generateTcx(makeTrack(hr: {
        start.add(const Duration(hours: 1)): 150,
      }));
      expect(tcx, isNot(contains('<HeartRateBpm>')));
    });

    test('escapes XML special chars in track name (Notes)', () {
      final tcx = service.generateTcx(makeTrack(name: 'Foo & <Bar>'));
      expect(tcx, contains('<Notes>Foo &amp; &lt;Bar&gt;</Notes>'));
    });

    test('writes cumulative DistanceMeters that grows monotonically', () {
      final tcx = service.generateTcx(makeTrack());
      final distances = RegExp(r'<DistanceMeters>([\d.]+)</DistanceMeters>')
          .allMatches(tcx)
          .map((m) => double.parse(m.group(1)!))
          .toList();
      // Prima occorrenza è la DistanceMeters totale del Lap, poi i Trackpoint.
      // La sequenza dei Trackpoint deve essere non-decrescente partendo da 0.
      final perPoint = distances.skip(1).toList();
      expect(perPoint.length, 3);
      expect(perPoint.first, 0);
      for (int i = 1; i < perPoint.length; i++) {
        expect(perPoint[i], greaterThanOrEqualTo(perPoint[i - 1]));
      }
    });
  });

  group('TrackExportService.generateKml', () {
    test('produces a KML 2.2 envelope with LineString coordinates', () {
      final kml = service.generateKml(makeTrack());
      expect(kml, contains('<?xml version="1.0"'));
      expect(kml, contains('<kml xmlns="http://www.opengis.net/kml/2.2">'));
      expect(kml, contains('<LineString>'));
      expect(kml, contains('</kml>'));
    });

    test('coordinates are in lon,lat,ele order (KML spec)', () {
      final kml = service.generateKml(makeTrack());
      // Primo punto: lat=45, lon=9, ele=500 → "9.0,45.0,500.0"
      expect(kml, contains('9.0,45.0,500.0'));
    });

    test('uses 0 as elevation when point has no elevation', () {
      final start = DateTime.utc(2026, 5, 1);
      final track = Track(
        id: 't',
        name: 'no-ele',
        points: [
          TrackPoint(latitude: 45, longitude: 9, timestamp: start),
        ],
        activityType: ActivityType.trekking,
        createdAt: start,
        stats: const TrackStats(),
      );
      final kml = service.generateKml(track);
      expect(kml, contains('9.0,45.0,0'));
    });

    test('escapes XML special chars in track name', () {
      final kml = service.generateKml(makeTrack(name: 'A & B'));
      expect(kml, contains('A &amp; B'));
    });
  });
}
