import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:math';
import 'package:xml/xml.dart';
import '../utils/moving_time.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/track.dart';
import '../utils/elevation_processor.dart';

/// Servizio per gestione file GPX (import/export)
/// Nome del `<trkseg>` che contiene un tratto ricostruito dal proprietario.
///
/// La stessa stringa serve a scriverlo e a riconoscerlo al reimport: se le due
/// parti divergono, l'esportazione resta onesta e il rientro no — che e'
/// esattamente il difetto trovato dalla revisione della Fase 2.
const String kReconstructedSegmentName = 'ricostruito dal proprietario';

class GpxService {
  
  /// Parsa un file GPX e restituisce una Track
  Future<Track?> parseGpxFile(File file) async {
    try {
      final content = await file.readAsString();
      return parseGpxString(content, fileName: file.path.split('/').last);
    } catch (e) {
      debugPrint('[GpxService] Errore lettura file: $e');
      return null;
    }
  }

  /// Parsa una stringa GPX e restituisce una Track
  Track? parseGpxString(String gpxContent, {String? fileName}) {
    try {
      final document = XmlDocument.parse(gpxContent);
      final gpx = document.rootElement;

      String name = _extractName(gpx) ?? fileName?.replaceAll('.gpx', '') ?? 'Traccia importata';
      List<TrackPoint> points = [];
      
      // Prima prova <trk><trkseg><trkpt>
      final trkElements = gpx.findAllElements('trk');
      for (final trk in trkElements) {
        final trkName = trk.findElements('name').firstOrNull?.innerText;
        if (trkName != null && trkName.isNotEmpty) {
          name = trkName;
        }
        
        final trksegs = trk.findAllElements('trkseg');
        for (final seg in trksegs) {
          // Un segmento marcato come ricostruito NON entra fra i punti
          // misurati. Senza questo controllo l'esportazione era onesta e il
          // rientro no: reimportando un GPX nostro, i punti disegnati dal
          // proprietario finivano in `points` e in `stats.distance` — e da li'
          // in poi li vedevano segmenti cronometrati, classifica, XP e Apple
          // Health. Tutto il progetto poggia sul fatto che non li vedano mai.
          //
          // Si scartano invece di ricostruire il TrackGap: qui manca il
          // contesto per dedurne gli estremi in modo affidabile, e perdere il
          // disegno e' molto meno grave che spacciarlo per misurato.
          final segName = seg.findElements('name').firstOrNull?.innerText.trim();
          if (segName == kReconstructedSegmentName) {
            debugPrint('[GpxService] segmento ricostruito saltato in import');
            continue;
          }
          final trkpts = seg.findAllElements('trkpt');
          for (final pt in trkpts) {
            final point = _parseTrackPoint(pt);
            if (point != null) {
              points.add(point);
            }
          }
        }
      }

      // Se non ci sono track points, prova <rte><rtept>
      if (points.isEmpty) {
        final rteElements = gpx.findAllElements('rte');
        for (final rte in rteElements) {
          final rteName = rte.findElements('name').firstOrNull?.innerText;
          if (rteName != null && rteName.isNotEmpty) {
            name = rteName;
          }
          
          final rtepts = rte.findAllElements('rtept');
          for (final pt in rtepts) {
            final point = _parseTrackPoint(pt);
            if (point != null) {
              points.add(point);
            }
          }
        }
      }

      // Se ancora vuoto, prova <wpt>
      if (points.isEmpty) {
        final wpts = gpx.findAllElements('wpt');
        for (final pt in wpts) {
          final point = _parseTrackPoint(pt);
          if (point != null) {
            points.add(point);
          }
        }
      }

      if (points.isEmpty) {
        debugPrint('[GpxService] Nessun punto trovato nel GPX');
        return null;
      }

      debugPrint('[GpxService] Parsati ${points.length} punti da "$name"');

      final stats = _calculateStats(points);

      return Track(
        id: 'imported_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        description: 'Importato da GPX',
        points: points,
        activityType: ActivityType.trekking,
        createdAt: _extractTime(points) ?? DateTime.now(),
        stats: stats,
      );
    } catch (e) {
      debugPrint('[GpxService] Errore parsing GPX: $e');
      return null;
    }
  }

  String? _extractName(XmlElement gpx) {
    final metadata = gpx.findElements('metadata').firstOrNull;
    if (metadata != null) {
      final name = metadata.findElements('name').firstOrNull?.innerText;
      if (name != null && name.isNotEmpty) return name;
    }
    final name = gpx.findElements('name').firstOrNull?.innerText;
    if (name != null && name.isNotEmpty) return name;
    return null;
  }

  TrackPoint? _parseTrackPoint(XmlElement pt) {
    try {
      final latStr = pt.getAttribute('lat');
      final lonStr = pt.getAttribute('lon');
      
      if (latStr == null || lonStr == null) return null;
      
      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);
      
      if (lat == null || lon == null) return null;
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;

      double? elevation;
      final eleElement = pt.findElements('ele').firstOrNull;
      if (eleElement != null) {
        elevation = double.tryParse(eleElement.innerText);
      }

      DateTime timestamp = DateTime.now();
      final timeElement = pt.findElements('time').firstOrNull;
      if (timeElement != null) {
        timestamp = DateTime.tryParse(timeElement.innerText) ?? DateTime.now();
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

  DateTime? _extractTime(List<TrackPoint> points) {
    for (final p in points) {
      if (p.timestamp.year > 2000) {
        return p.timestamp;
      }
    }
    return null;
  }

  TrackStats _calculateStats(List<TrackPoint> points) {
    if (points.isEmpty) {
      return const TrackStats();
    }

    // Calcola distanza (invariato)
    double distance = 0;
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      distance += _calculateDistance(
        prev.latitude, prev.longitude,
        curr.latitude, curr.longitude,
      );
    }

    // Elevazione: usa ElevationProcessor (spike removal + smoothing + isteresi)
    final processor = const ElevationProcessor();
    final rawElevations = points.map((p) => p.elevation).toList();
    final eleResult = processor.process(rawElevations);

    // Durata (se abbiamo timestamp validi)
    Duration dur = Duration.zero;
    if (points.first.timestamp.year > 2000 && points.last.timestamp.year > 2000) {
      dur = points.last.timestamp.difference(points.first.timestamp);
    }

    // Tempo di movimento: somma dei delta tra punti consecutivi quando la
    // velocità del segmento supera la soglia. Le pause (pranzo al rifugio,
    // foto) hanno dt grande con spostamento minimo → escluse. È il numero
    // che Komoot/Strava/Bosch mostrano come tempo principale.
    final Duration moving =
        dur > Duration.zero ? computeMovingTime(points) : Duration.zero;

    return TrackStats(
      distance: distance,
      elevationGain: eleResult.elevationGain,
      elevationLoss: eleResult.elevationLoss,
      duration: dur,
      movingTime: moving,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT GPX
  // ═══════════════════════════════════════════════════════════════════════════

  String generateGpx(Track track) {
    final buffer = StringBuffer();
    
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="TrailShare"');
    buffer.writeln('  xmlns="http://www.topografix.com/GPX/1/1">');
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name>${_escapeXml(track.name)}</name>');
    buffer.writeln('    <time>${track.createdAt.toUtc().toIso8601String()}</time>');
    buffer.writeln('  </metadata>');
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>${_escapeXml(track.name)}</name>');
    if (track.description != null) {
      buffer.writeln('    <desc>${_escapeXml(track.description!)}</desc>');
    }
    // Un <trkseg> per ogni tratto continuo, non uno solo per tutta la traccia.
    //
    // E' il modo che il formato GPX prevede da sempre per dire "qui la
    // registrazione si e' interrotta": lo standard descrive proprio il segmento
    // nuovo come cio' che si apre quando il ricevitore perde il segnale o viene
    // spento. Ogni programma che legge GPX lo capisce — Garmin, Strava, komoot,
    // QGIS — e disegna uno stacco invece di una retta.
    //
    // Con un segmento unico, invece, il buco diventava una linea dritta
    // indistinguibile dal percorso vero appena il file usciva dall'app: qualsiasi
    // avviso mostrato nella nostra scheda non viaggia con il file.
    final ordered = [...track.gaps]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final breaks = ordered.map((g) => g.startedAt).toList();
    var nextBreak = 0;
    var segmentOpen = false;

    for (final point in track.points) {
      // Si chiude il segmento al primo punto successivo all'inizio del buco.
      while (nextBreak < breaks.length &&
          point.timestamp.isAfter(breaks[nextBreak])) {
        if (segmentOpen) {
          buffer.writeln('    </trkseg>');
          segmentOpen = false;
        }
        // Il tratto ricostruito dal proprietario esce come segmento SUO, con
        // un nome che lo dichiara: cosi' l'etichetta viaggia col file invece
        // di restare nella nostra scheda. Senza <time> sui punti — quegli
        // orari non esistono, e inventarli darebbe velocita' false a chi
        // importa la traccia.
        final g = ordered[nextBreak];
        if (g.hasReconstruction) {
          buffer.writeln('    <trkseg>');
          // Un COMMENTO XML non e' una marcatura: ogni parser lo scarta, e il
          // nostro reimportava questi punti come misurati, con orari
          // inventati. Serve un elemento che sopravviva al giro — <name> lo e',
          // ed e' quello che il progetto chiedeva.
          buffer.writeln('      <name>$kReconstructedSegmentName</name>');
          buffer.writeln(
              '      <!-- Non registrato dal GPS: percorso dichiarato da chi ha camminato -->');
          for (final p in g.reconstruction) {
            buffer.writeln(
                '      <trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>');
          }
          buffer.writeln('    </trkseg>');
        }
        nextBreak++;
      }
      if (!segmentOpen) {
        buffer.writeln('    <trkseg>');
        segmentOpen = true;
      }

      buffer.write('      <trkpt lat="${point.latitude}" lon="${point.longitude}">');
      if (point.elevation != null) {
        buffer.write('<ele>${point.elevation!.toStringAsFixed(1)}</ele>');
      }
      buffer.write('<time>${point.timestamp.toUtc().toIso8601String()}</time>');
      buffer.writeln('</trkpt>');
    }

    // Una traccia senza punti resta con il segmento vuoto di prima, per non
    // cambiare la forma del file rispetto a com'era.
    if (!segmentOpen) buffer.writeln('    <trkseg>');
    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');
    
    return buffer.toString();
  }

  Future<String> saveGpxToFile(Track track) async {
    final gpxContent = generateGpx(track);
    final directory = await getTemporaryDirectory();
    final safeName = track.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final fileName = '${safeName}_${DateTime.now().millisecondsSinceEpoch}.gpx';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(gpxContent);
    return file.path;
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
