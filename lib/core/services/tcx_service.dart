import 'dart:io';
import 'dart:math';
import 'package:xml/xml.dart';
import '../../data/models/track.dart';
import '../utils/elevation_processor.dart';

/// Servizio per import file TCX (Garmin, Polar, Suunto, ecc.)
class TcxService {

  /// Parsa un file TCX e restituisce una Track
  Future<Track?> parseTcxFile(File file) async {
    try {
      final content = await file.readAsString();
      return parseTcxString(content, fileName: file.path.split('/').last);
    } catch (e) {
      print('[TcxService] Errore lettura file: $e');
      return null;
    }
  }

  /// Parsa una stringa TCX e restituisce una Track
  Track? parseTcxString(String tcxContent, {String? fileName}) {
    try {
      final document = XmlDocument.parse(tcxContent);
      final root = document.rootElement;

      String name = fileName?.replaceAll('.tcx', '') ?? 'Attività importata';
      String? sport;
      List<TrackPoint> points = [];

      // Struttura: Activities > Activity > Lap > Track > Trackpoint
      final activities = root.findAllElements('Activity');
      for (final activity in activities) {
        // Sport dall'attributo
        final sportAttr = activity.getAttribute('Sport');
        if (sportAttr != null) sport = sportAttr;

        // ID come nome (è il timestamp di inizio)
        final id = activity.findElements('Id').firstOrNull?.innerText;
        if (id != null && id.isNotEmpty) {
          // Prova a formattare la data come nome
          final dt = DateTime.tryParse(id);
          if (dt != null && sport != null) {
            name = '${_mapSportName(sport)} del ${dt.day}/${dt.month}/${dt.year}';
          }
        }

        final laps = activity.findAllElements('Lap');
        for (final lap in laps) {
          final tracks = lap.findAllElements('Track');
          for (final track in tracks) {
            final trackpoints = track.findAllElements('Trackpoint');
            for (final tp in trackpoints) {
              final point = _parseTrackpoint(tp);
              if (point != null) {
                points.add(point);
              }
            }
          }
        }
      }

      // Fallback: prova Courses > Course > Track > Trackpoint
      if (points.isEmpty) {
        final courses = root.findAllElements('Course');
        for (final course in courses) {
          final courseName = course.findElements('Name').firstOrNull?.innerText;
          if (courseName != null && courseName.isNotEmpty) {
            name = courseName;
          }

          final tracks = course.findAllElements('Track');
          for (final track in tracks) {
            final trackpoints = track.findAllElements('Trackpoint');
            for (final tp in trackpoints) {
              final point = _parseTrackpoint(tp);
              if (point != null) {
                points.add(point);
              }
            }
          }
        }
      }

      if (points.isEmpty) {
        print('[TcxService] Nessun punto trovato nel TCX');
        return null;
      }

      final activityType = _mapSportToActivityType(sport);
      final stats = _calculateStats(points);

      print('[TcxService] Parsati ${points.length} punti da "$name" (sport: $sport)');

      return Track(
        id: 'imported_tcx_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        description: 'Importato da file TCX',
        points: points,
        activityType: activityType,
        createdAt: _extractTime(points) ?? DateTime.now(),
        stats: stats,
      );
    } catch (e) {
      print('[TcxService] Errore parsing TCX: $e');
      return null;
    }
  }

  /// Parsa un singolo Trackpoint
  TrackPoint? _parseTrackpoint(XmlElement tp) {
    try {
      // Coordinate
      final position = tp.findElements('Position').firstOrNull;
      if (position == null) return null;

      final latStr = position.findElements('LatitudeDegrees').firstOrNull?.innerText;
      final lonStr = position.findElements('LongitudeDegrees').firstOrNull?.innerText;
      if (latStr == null || lonStr == null) return null;

      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);
      if (lat == null || lon == null) return null;
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;

      // Quota
      double? elevation;
      final altStr = tp.findElements('AltitudeMeters').firstOrNull?.innerText;
      if (altStr != null) {
        elevation = double.tryParse(altStr);
      }

      // Timestamp
      DateTime timestamp = DateTime.now();
      final timeStr = tp.findElements('Time').firstOrNull?.innerText;
      if (timeStr != null) {
        timestamp = DateTime.tryParse(timeStr) ?? DateTime.now();
      }

      return TrackPoint(
        latitude: lat,
        longitude: lon,
        elevation: elevation,
        timestamp: timestamp,
      );
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAPPING SPORT
  // ═══════════════════════════════════════════════════════════════════════════

  String _mapSportName(String sport) {
    switch (sport.toLowerCase()) {
      case 'running': return 'Corsa';
      case 'biking': return 'Bicicletta';
      case 'hiking': return 'Trekking';
      case 'walking': return 'Camminata';
      case 'other': return 'Attività';
      default: return sport;
    }
  }

  ActivityType _mapSportToActivityType(String? sport) {
    if (sport == null) return ActivityType.trekking;

    final s = sport.toLowerCase();
    if (s.contains('run')) return ActivityType.running;
    if (s.contains('bik') || s.contains('cycl')) return ActivityType.cycling;
    if (s.contains('walk')) return ActivityType.walking;
    if (s.contains('hik')) return ActivityType.trekking;
    if (s.contains('ski')) return ActivityType.skiTouring;

    return ActivityType.trekking;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICHE (stesse di GpxService/FitService)
  // ═══════════════════════════════════════════════════════════════════════════

  DateTime? _extractTime(List<TrackPoint> points) {
    for (final p in points) {
      if (p.timestamp.year > 2000) return p.timestamp;
    }
    return null;
  }

  TrackStats _calculateStats(List<TrackPoint> points) {
    if (points.isEmpty) return const TrackStats();

    double distance = 0;
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      distance += _calculateDistance(
        prev.latitude, prev.longitude,
        curr.latitude, curr.longitude,
      );
    }

    final processor = const ElevationProcessor();
    final rawElevations = points.map((p) => p.elevation).toList();
    final eleResult = processor.process(rawElevations);

    Duration dur = Duration.zero;
    if (points.first.timestamp.year > 2000 && points.last.timestamp.year > 2000) {
      dur = points.last.timestamp.difference(points.first.timestamp);
    }

    return TrackStats(
      distance: distance,
      elevationGain: eleResult.elevationGain,
      elevationLoss: eleResult.elevationLoss,
      duration: dur,
      minElevation: eleResult.minElevation,
      maxElevation: eleResult.maxElevation,
    );
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double deg) => deg * pi / 180;
}
