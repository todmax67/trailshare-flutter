import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fit_sdk/fit_sdk.dart' hide ActivityType, File;

import '../../data/models/track.dart';
import 'gpx_service.dart';

/// Formati supportati per l'esportazione di una traccia.
enum ExportFormat {
  /// GPX 1.1 — universale, supportato da ~tutte le app outdoor.
  gpx,

  /// TCX (Training Center XML) — Garmin/Strava/TrainingPeaks. Include
  /// HR, calorie, sport.
  tcx,

  /// KML — Google Earth, Google Maps "My Maps". Solo geometria.
  kml,

  /// FIT (Flexible and Interoperable Data Transfer) — formato nativo
  /// Garmin/Wahoo, richiesto da Garmin Connect per import.
  fit;

  String get extension {
    switch (this) {
      case ExportFormat.gpx:
        return 'gpx';
      case ExportFormat.tcx:
        return 'tcx';
      case ExportFormat.kml:
        return 'kml';
      case ExportFormat.fit:
        return 'fit';
    }
  }

  /// Etichetta short da UI.
  String get displayName {
    switch (this) {
      case ExportFormat.gpx:
        return 'GPX';
      case ExportFormat.tcx:
        return 'TCX';
      case ExportFormat.kml:
        return 'KML';
      case ExportFormat.fit:
        return 'FIT';
    }
  }
}

/// Servizio unificato per esportare una [Track] nei vari formati.
///
/// Genera il file in una directory temporanea e ne ritorna il path, pronto
/// da passare a `Share.shareXFiles` o simili.
class TrackExportService {
  final GpxService _gpxService;

  TrackExportService({GpxService? gpxService})
      : _gpxService = gpxService ?? GpxService();

  /// Genera il file nel formato richiesto e ritorna il path assoluto.
  Future<String> exportToFile(Track track, ExportFormat format) async {
    switch (format) {
      case ExportFormat.gpx:
        return _gpxService.saveGpxToFile(track);
      case ExportFormat.tcx:
        return _saveTextToFile(_generateTcx(track), track, 'tcx');
      case ExportFormat.kml:
        return _saveTextToFile(_generateKml(track), track, 'kml');
      case ExportFormat.fit:
        return _saveBytesToFile(_generateFit(track), track, 'fit');
    }
  }

  // ─── TCX ───────────────────────────────────────────────────────────────────

  /// Genera TCX 2.0 (Training Center XML). Spec ufficiale Garmin.
  String _generateTcx(Track track) {
    final buf = StringBuffer();
    final startIso = track.createdAt.toUtc().toIso8601String();
    final sport = _tcxSport(track.activityType);

    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<TrainingCenterDatabase');
    buf.writeln('  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"');
    buf.writeln('  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">');
    buf.writeln('  <Activities>');
    buf.writeln('    <Activity Sport="$sport">');
    buf.writeln('      <Id>$startIso</Id>');
    buf.writeln('      <Lap StartTime="$startIso">');
    buf.writeln('        <TotalTimeSeconds>${track.stats.duration.inSeconds}</TotalTimeSeconds>');
    buf.writeln('        <DistanceMeters>${track.stats.distance.toStringAsFixed(1)}</DistanceMeters>');
    buf.writeln('        <MaximumSpeed>${track.stats.maxSpeed.toStringAsFixed(2)}</MaximumSpeed>');
    if (track.healthCalories != null) {
      buf.writeln('        <Calories>${track.healthCalories!.round()}</Calories>');
    } else {
      buf.writeln('        <Calories>0</Calories>');
    }
    buf.writeln('        <Intensity>Active</Intensity>');
    buf.writeln('        <TriggerMethod>Manual</TriggerMethod>');
    buf.writeln('        <Track>');

    // HR map se disponibile (ricerca BPM più vicino nel tempo a ogni punto).
    final hrEntries = track.heartRateData != null
        ? (track.heartRateData!.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        : null;

    double cumDistance = 0;
    for (int i = 0; i < track.points.length; i++) {
      final p = track.points[i];
      if (i > 0) {
        cumDistance += track.points[i - 1].distanceTo(p);
      }
      final iso = p.timestamp.toUtc().toIso8601String();

      buf.writeln('          <Trackpoint>');
      buf.writeln('            <Time>$iso</Time>');
      buf.writeln('            <Position>');
      buf.writeln('              <LatitudeDegrees>${p.latitude}</LatitudeDegrees>');
      buf.writeln('              <LongitudeDegrees>${p.longitude}</LongitudeDegrees>');
      buf.writeln('            </Position>');
      if (p.elevation != null) {
        buf.writeln('            <AltitudeMeters>${p.elevation!.toStringAsFixed(1)}</AltitudeMeters>');
      }
      buf.writeln('            <DistanceMeters>${cumDistance.toStringAsFixed(1)}</DistanceMeters>');

      if (hrEntries != null && hrEntries.isNotEmpty) {
        final bpm = _nearestHr(hrEntries, p.timestamp);
        if (bpm != null) {
          buf.writeln('            <HeartRateBpm><Value>$bpm</Value></HeartRateBpm>');
        }
      }

      if (p.speed != null) {
        buf.writeln('            <Extensions>');
        buf.writeln('              <TPX xmlns="http://www.garmin.com/xmlschemas/ActivityExtension/v2">');
        buf.writeln('                <Speed>${p.speed!.toStringAsFixed(2)}</Speed>');
        buf.writeln('              </TPX>');
        buf.writeln('            </Extensions>');
      }

      buf.writeln('          </Trackpoint>');
    }

    buf.writeln('        </Track>');
    buf.writeln('        <Notes>${_escapeXml(track.name)}</Notes>');
    buf.writeln('      </Lap>');
    buf.writeln('      <Creator xsi:type="Application_t">');
    buf.writeln('        <Name>TrailShare</Name>');
    buf.writeln('      </Creator>');
    buf.writeln('    </Activity>');
    buf.writeln('  </Activities>');
    buf.writeln('  <Author xsi:type="Application_t">');
    buf.writeln('    <Name>TrailShare</Name>');
    buf.writeln('  </Author>');
    buf.writeln('</TrainingCenterDatabase>');

    return buf.toString();
  }

  int? _nearestHr(List<MapEntry<DateTime, int>> entries, DateTime t) {
    if (entries.isEmpty) return null;
    MapEntry<DateTime, int>? best;
    int bestDiff = 1 << 30;
    for (final e in entries) {
      final diff = (e.key.difference(t)).inSeconds.abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = e;
        if (diff == 0) break;
      }
    }
    // Considera valido solo se entro ±30 s dal timestamp del punto.
    if (best != null && bestDiff <= 30) return best.value;
    return null;
  }

  String _tcxSport(ActivityType type) {
    switch (type) {
      case ActivityType.cycling:
      case ActivityType.mountainBiking:
      case ActivityType.gravelBiking:
      case ActivityType.eBike:
      case ActivityType.eMountainBike:
        return 'Biking';
      case ActivityType.running:
      case ActivityType.trailRunning:
        return 'Running';
      default:
        return 'Other';
    }
  }

  // ─── KML ───────────────────────────────────────────────────────────────────

  /// Genera KML 2.2 per Google Earth / Google Maps.
  String _generateKml(Track track) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buf.writeln('  <Document>');
    buf.writeln('    <name>${_escapeXml(track.name)}</name>');
    if (track.description != null) {
      buf.writeln('    <description>${_escapeXml(track.description!)}</description>');
    }
    buf.writeln('    <Style id="trailshare-line">');
    buf.writeln('      <LineStyle>');
    // KML colori: aabbggrr (alpha, blue, green, red). Verde TrailShare.
    buf.writeln('        <color>ff50af4c</color>');
    buf.writeln('        <width>4</width>');
    buf.writeln('      </LineStyle>');
    buf.writeln('    </Style>');
    buf.writeln('    <Placemark>');
    buf.writeln('      <name>${_escapeXml(track.name)}</name>');
    buf.writeln('      <styleUrl>#trailshare-line</styleUrl>');
    buf.writeln('      <LineString>');
    buf.writeln('        <tessellate>1</tessellate>');
    buf.writeln('        <altitudeMode>clampToGround</altitudeMode>');
    buf.writeln('        <coordinates>');
    for (final p in track.points) {
      final ele = p.elevation?.toStringAsFixed(1) ?? '0';
      buf.writeln('          ${p.longitude},${p.latitude},$ele');
    }
    buf.writeln('        </coordinates>');
    buf.writeln('      </LineString>');
    buf.writeln('    </Placemark>');
    buf.writeln('  </Document>');
    buf.writeln('</kml>');
    return buf.toString();
  }

  // ─── FIT ───────────────────────────────────────────────────────────────────

  /// FIT epoch = secondi dal 1989-12-31 00:00:00 UTC.
  static const _fitEpochOffset = 631065600;

  /// Fattore di conversione gradi → semicircles FIT (2^31 / 180).
  static const _semicirclesPerDegree = 11930464.711111111;

  /// Genera bytes FIT minimali (FileId + Records + Session). Accettato da
  /// Garmin Connect, Strava, Wahoo per import.
  Uint8List _generateFit(Track track) {
    final enc = Encode();
    enc.open();

    final startEpoch = (track.createdAt.millisecondsSinceEpoch ~/ 1000) - _fitEpochOffset;

    // ── FileId (required) ──
    final fileId = Mesg.fromMesgNum(MesgNum.fileId);
    fileId.setFieldValue(0, 4);   // type = activity
    fileId.setFieldValue(1, 255); // manufacturer = development (placeholder)
    fileId.setFieldValue(2, 0);   // product
    fileId.setFieldValue(4, startEpoch); // time_created
    enc.writeMesgDefinition(MesgDefinition.fromMesg(fileId));
    enc.writeMesg(fileId);

    // ── Records ──
    final recordTemplate = Mesg.fromMesgNum(MesgNum.record);
    // Campi che useremo (richiede definizione prima di scrivere valori).
    recordTemplate.setFieldValue(253, startEpoch);          // timestamp
    recordTemplate.setFieldValue(0, 0);                      // position_lat (semicircles)
    recordTemplate.setFieldValue(1, 0);                      // position_long
    recordTemplate.setFieldValue(2, 0);                      // altitude (scaled)
    recordTemplate.setFieldValue(5, 0);                      // distance (scaled)
    final recordDef = MesgDefinition.fromMesg(recordTemplate);
    enc.writeMesgDefinition(recordDef);

    double cumDistance = 0;
    for (int i = 0; i < track.points.length; i++) {
      final p = track.points[i];
      if (i > 0) {
        cumDistance += track.points[i - 1].distanceTo(p);
      }
      final rec = Mesg.fromMesgNum(MesgNum.record);
      final tsEpoch = (p.timestamp.millisecondsSinceEpoch ~/ 1000) - _fitEpochOffset;
      rec.setFieldValue(253, tsEpoch);
      rec.setFieldValue(0, (p.latitude * _semicirclesPerDegree).round());
      rec.setFieldValue(1, (p.longitude * _semicirclesPerDegree).round());
      // altitude: FIT scale = 5, offset = 500 → stored = (m + 500) * 5
      final ele = p.elevation ?? 0;
      rec.setFieldValue(2, ((ele + 500) * 5).round());
      // distance: FIT scale = 100 → stored = m * 100
      rec.setFieldValue(5, (cumDistance * 100).round());
      enc.writeMesg(rec, recordDef);
    }

    // ── Session (riassunto per Garmin Connect) ──
    final session = Mesg.fromMesgNum(MesgNum.session);
    session.setFieldValue(253, startEpoch);                         // timestamp
    session.setFieldValue(2, startEpoch);                           // start_time
    session.setFieldValue(7, track.stats.duration.inSeconds * 1000); // total_elapsed_time (ms, scale 1000)
    session.setFieldValue(8, track.stats.movingTime.inSeconds * 1000); // total_timer_time
    session.setFieldValue(9, (track.stats.distance * 100).round()); // total_distance (scale 100)
    session.setFieldValue(5, _fitSport(track.activityType));        // sport
    enc.writeMesgDefinition(MesgDefinition.fromMesg(session));
    enc.writeMesg(session);

    // ── Activity (chiusura) ──
    final activity = Mesg.fromMesgNum(MesgNum.activity);
    activity.setFieldValue(253, startEpoch);
    activity.setFieldValue(1, 1);   // num_sessions
    activity.setFieldValue(2, 0);   // type = manual
    activity.setFieldValue(3, 26);  // event_type = stop
    enc.writeMesgDefinition(MesgDefinition.fromMesg(activity));
    enc.writeMesg(activity);

    return enc.close();
  }

  int _fitSport(ActivityType type) {
    switch (type) {
      case ActivityType.cycling:
      case ActivityType.gravelBiking:
      case ActivityType.eBike:
        return 2; // cycling
      case ActivityType.mountainBiking:
      case ActivityType.eMountainBike:
        return 2; // FIT distingue sub_sport, manteniamo sport=cycling
      case ActivityType.running:
      case ActivityType.trailRunning:
        return 1; // running
      case ActivityType.walking:
        return 11; // walking
      case ActivityType.trekking:
        return 17; // hiking
      case ActivityType.alpineSkiing:
      case ActivityType.snowboarding:
        return 13; // alpine_skiing / snowboarding share top-level
      case ActivityType.skiTouring:
      case ActivityType.nordicSkiing:
        return 12; // cross_country_skiing
      case ActivityType.snowshoeing:
        return 17; // hiking
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Future<String> _saveTextToFile(String content, Track track, String ext) async {
    final dir = await getTemporaryDirectory();
    final fileName = '${_safeName(track.name)}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
    debugPrint('[TrackExport] $ext salvato: ${file.path}');
    return file.path;
  }

  Future<String> _saveBytesToFile(Uint8List bytes, Track track, String ext) async {
    final dir = await getTemporaryDirectory();
    final fileName = '${_safeName(track.name)}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    debugPrint('[TrackExport] $ext salvato: ${file.path} (${bytes.length}B)');
    return file.path;
  }

  String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');

  String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
