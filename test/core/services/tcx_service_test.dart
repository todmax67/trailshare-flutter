import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/services/tcx_service.dart';
import 'package:trailshare_flutter/data/models/track.dart';

void main() {
  late TcxService service;

  setUp(() {
    service = TcxService();
  });

  String fixture(String name) =>
      File('test/fixtures/$name').readAsStringSync();

  group('TcxService.parseTcxString', () {
    test('parses an Activity-style TCX (Garmin biking)', () {
      final track = service.parseTcxString(fixture('sample_garmin.tcx'));

      expect(track, isNotNull);
      expect(track!.points.length, 3);
      expect(track.points.first.latitude, 45.5);
      expect(track.points.first.elevation, 200.0);
      expect(track.activityType, ActivityType.cycling);
    });

    test('falls back to Course-style TCX when no Activity is present', () {
      final track = service.parseTcxString(fixture('course.tcx'));

      expect(track, isNotNull);
      expect(track!.name, 'Anello del Resegone');
      expect(track.points.length, 2);
      expect(track.points.last.elevation, 1200.0);
    });

    test('builds a sport-aware track name from the Id timestamp', () {
      final track = service.parseTcxString(fixture('sample_garmin.tcx'))!;
      expect(track.name, contains('Bicicletta'));
      expect(track.name, contains('15/4/2026'));
    });

    test('returns null when no Trackpoints exist anywhere', () {
      const empty = '''<?xml version="1.0"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities><Activity Sport="Other"><Id>2026-01-01T00:00:00Z</Id></Activity></Activities>
</TrainingCenterDatabase>''';
      final track = service.parseTcxString(empty);
      expect(track, isNull);
    });

    test('returns null on malformed XML', () {
      final track = service.parseTcxString('<not-tcx');
      expect(track, isNull);
    });

    test('skips Trackpoints with missing Position', () {
      const partial = '''<?xml version="1.0"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities><Activity Sport="Running"><Id>2026-01-01T10:00:00Z</Id>
    <Lap><Track>
      <Trackpoint><Time>2026-01-01T10:00:00Z</Time></Trackpoint>
      <Trackpoint><Time>2026-01-01T10:01:00Z</Time>
        <Position><LatitudeDegrees>45.0</LatitudeDegrees><LongitudeDegrees>9.0</LongitudeDegrees></Position>
        <AltitudeMeters>500</AltitudeMeters>
      </Trackpoint>
    </Track></Lap>
  </Activity></Activities>
</TrainingCenterDatabase>''';
      final track = service.parseTcxString(partial);
      expect(track, isNotNull);
      expect(track!.points.length, 1);
      expect(track.activityType, ActivityType.running);
    });

    test('maps Sport attribute to ActivityType correctly', () {
      String tcxWithSport(String sport) => '''<?xml version="1.0"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities><Activity Sport="$sport"><Id>2026-01-01T00:00:00Z</Id>
    <Lap><Track>
      <Trackpoint><Time>2026-01-01T00:00:00Z</Time>
        <Position><LatitudeDegrees>45</LatitudeDegrees><LongitudeDegrees>9</LongitudeDegrees></Position>
      </Trackpoint>
    </Track></Lap>
  </Activity></Activities>
</TrainingCenterDatabase>''';

      expect(service.parseTcxString(tcxWithSport('Running'))!.activityType,
          ActivityType.running);
      expect(service.parseTcxString(tcxWithSport('Biking'))!.activityType,
          ActivityType.cycling);
      expect(service.parseTcxString(tcxWithSport('Hiking'))!.activityType,
          ActivityType.trekking);
      expect(service.parseTcxString(tcxWithSport('Walking'))!.activityType,
          ActivityType.walking);
    });
  });
}
