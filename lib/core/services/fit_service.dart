import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:fit_sdk/fit_sdk.dart' hide ActivityType, File;
import '../../data/models/track.dart';
import '../utils/elevation_processor.dart';

/// Servizio per import file FIT (Garmin, Strava, Wahoo, ecc.)
class FitService {

  /// FIT epoch: secondi dal 1989-12-31 00:00:00 UTC
  static const _fitEpochOffset = 631065600;

  /// Parsa un file FIT e restituisce una Track
  Future<Track?> parseFitFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return parseFitBytes(bytes, fileName: file.path.split('/').last);
    } catch (e) {
      print('[FitService] Errore lettura file: $e');
      return null;
    }
  }

  /// Parsa bytes FIT e restituisce una Track
  Track? parseFitBytes(Uint8List bytes, {String? fileName}) {
    try {
      final decoder = Decode();
      
      String? name;
      String? sport;
      DateTime? startTime;
      List<TrackPoint> points = [];
      int recordCount = 0;
      // Per Garmin recenti: coordinate in GpsMetadata, altri dati in Record
      double? pendingLat, pendingLon;
      DateTime? pendingTimestamp;

      decoder.onMesg = (Mesg mesg) {
        // Debug: log tutti i messaggi
        switch (mesg.name) {
          case 'Session':
            _extractSessionInfo(mesg, (n) => name = n, (s) => sport = s, (t) => startTime = t);
            break;
            
          case 'Activity':
            if (startTime == null) {
              _extractActivityTime(mesg, (t) => startTime = t);
            }
            break;

          case 'GpsMetadata':
            // Debug: mostra campi
            for (final f in mesg.fields) {
            }
            // Garmin recenti: coordinate GPS separate dai record
            for (final field in mesg.fields) {
              if (field.value == null) continue;
              switch (field.name) {
                case 'position_lat':
                case 'enhanced_latitude':
                  pendingLat = _semicirclesToDegrees(field.value);
                  break;
                case 'position_long':
                case 'enhanced_longitude':
                  pendingLon = _semicirclesToDegrees(field.value);
                  break;
                case 'timestamp':
                  pendingTimestamp = _fitTimestampToDateTime(field.value);
                  break;
              }
            }
            // Se abbiamo coordinate complete, crea il punto
            if (pendingLat != null && pendingLon != null &&
                pendingLat! >= -90 && pendingLat! <= 90 &&
                pendingLon! >= -180 && pendingLon! <= 180) {
              points.add(TrackPoint(
                latitude: pendingLat!,
                longitude: pendingLon!,
                timestamp: pendingTimestamp ?? DateTime.now(),
              ));
              pendingLat = null;
              pendingLon = null;
            }
            break;

          case 'Record':
            if (recordCount < 2) {
              for (final f in mesg.fields) {
              }
              recordCount++;
            }
            final point = _parseRecordMessage(mesg);
            if (point != null) {
              points.add(point);
            } else if (pendingLat != null && pendingLon != null) {
              // Usa coordinate da GpsMetadata + dati dal record
              double? elevation;
              DateTime? ts;
              for (final f in mesg.fields) {
                if (f.value == null) continue;
                if (f.name == 'altitude' || f.name == 'enhanced_altitude') {
                  elevation = _toDouble(f.value);
                }
                if (f.name == 'timestamp') {
                  ts = _fitTimestampToDateTime(f.value);
                }
              }
              if (pendingLat! >= -90 && pendingLat! <= 90 &&
                  pendingLon! >= -180 && pendingLon! <= 180) {
                points.add(TrackPoint(
                  latitude: pendingLat!,
                  longitude: pendingLon!,
                  elevation: elevation,
                  timestamp: ts ?? pendingTimestamp ?? DateTime.now(),
                ));
              }
              pendingLat = null;
              pendingLon = null;
            }
            break;
        }
      };

      decoder.read(bytes);

      // Rimuovi punti duplicati (stesse coordinate consecutive)
      if (points.length > 1) {
        final deduped = <TrackPoint>[points.first];
        for (int i = 1; i < points.length; i++) {
          if (points[i].latitude != points[i-1].latitude ||
              points[i].longitude != points[i-1].longitude) {
            deduped.add(points[i]);
          }
        }
        points = deduped;
      }

      if (points.isEmpty) {
        print('[FitService] Nessun punto GPS trovato nel file FIT');
        return null;
      }

      // Nome: usa quello dalla session, oppure il nome file
      final trackName = name ??
          fileName?.replaceAll('.fit', '').replaceAll('_', ' ') ??
          'Attività importata';

      // Tipo attività dal campo sport
      final activityType = _mapSportToActivityType(sport);

      // Statistiche
      final stats = _calculateStats(points);

      print('[FitService] Parsati ${points.length} punti da "$trackName" (sport: $sport)');

      return Track(
        id: 'imported_fit_${DateTime.now().millisecondsSinceEpoch}',
        name: trackName,
        description: 'Importato da file FIT',
        points: points,
        activityType: activityType,
        createdAt: startTime ?? _extractTime(points) ?? DateTime.now(),
        stats: stats,
      );
    } catch (e) {
      return null;
    }
  }

  /// Estrai info dalla session message
  void _extractSessionInfo(
    Mesg mesg,
    void Function(String) onName,
    void Function(String) onSport,
    void Function(DateTime) onTime,
  ) {
    for (final field in mesg.fields) {
      if (field.value == null) continue;
      
      switch (field.name) {
        case 'sport':
          onSport(field.value.toString());
          break;
        case 'start_time':
          final dt = _fitTimestampToDateTime(field.value);
          if (dt != null) onTime(dt);
          break;
      }
    }
  }

  /// Estrai timestamp dall'activity message
  void _extractActivityTime(Mesg mesg, void Function(DateTime) onTime) {
    for (final field in mesg.fields) {
      if (field.name == 'timestamp' && field.value != null) {
        final dt = _fitTimestampToDateTime(field.value);
        if (dt != null) onTime(dt);
      }
    }
  }

  /// Parsa un record message in TrackPoint
  TrackPoint? _parseRecordMessage(Mesg mesg) {
    double? lat, lon, elevation;
    DateTime? timestamp;

    for (final field in mesg.fields) {
      if (field.value == null) continue;

      final name = field.name.toLowerCase();
      switch (name) {
        case 'positionlat':
        case 'position_lat':
          lat = _semicirclesToDegrees(field.value);
          break;
        case 'positionlong':
        case 'position_long':
          lon = _semicirclesToDegrees(field.value);
          break;
        case 'altitude':
        case 'enhancedaltitude':
        case 'enhanced_altitude':
          elevation = _toDouble(field.value);
          break;
        case 'timestamp':
          timestamp = _fitTimestampToDateTime(field.value);
          break;
          default:
            // Log messaggi sconosciuti con 7 campi (possibili coordinate GPS)
            if (mesg.num == 325) {
              for (final f in mesg.fields) {
              }
            }
            break;
      }
    }

    if (lat == null || lon == null) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;

    return TrackPoint(
      latitude: lat,
      longitude: lon,
      elevation: elevation,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONVERSIONI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Converte semicircoli (formato FIT) in gradi decimali
  double? _semicirclesToDegrees(dynamic value) {
    final v = _toDouble(value);
    if (v == null) return null;
    return v * (180.0 / pow(2, 31));
  }

  /// Converte timestamp FIT (secondi dal 1989-12-31) in DateTime
  DateTime? _fitTimestampToDateTime(dynamic value) {
    if (value == null) return null;
    try {
      final seconds = value is int ? value : (value as num).toInt();
      return DateTime.fromMillisecondsSinceEpoch(
        (seconds + _fitEpochOffset) * 1000,
        isUtc: true,
      ).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Converte un valore numerico generico in double
  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Mappa sport FIT → ActivityType dell'app
  ActivityType _mapSportToActivityType(String? sport) {
    if (sport == null) return ActivityType.trekking;
    
    final s = sport.toLowerCase();
    if (s.contains('run') || s.contains('trail')) return ActivityType.running;
    if (s.contains('cycling') || s.contains('biking')) return ActivityType.cycling;
    if (s.contains('walk')) return ActivityType.walking;
    if (s.contains('hik')) return ActivityType.trekking;
    if (s.contains('mountain_biking')) return ActivityType.mountainBiking;
    if (s.contains('ski')) return ActivityType.skiTouring;
    if (s.contains('snowshoe')) return ActivityType.snowshoeing;
    
    return ActivityType.trekking;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICHE (identiche a GpxService)
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
