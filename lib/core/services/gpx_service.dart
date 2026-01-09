import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../data/models/track.dart';

/// Servizio per generare e esportare file GPX
class GpxService {
  
  /// Genera contenuto GPX da una traccia
  String generateGpx(Track track) {
    final buffer = StringBuffer();
    
    // Header GPX
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="TrailShare"');
    buffer.writeln('  xmlns="http://www.topografix.com/GPX/1/1"');
    buffer.writeln('  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"');
    buffer.writeln('  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">');
    
    // Metadata
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name>${_escapeXml(track.name)}</name>');
    if (track.description != null && track.description!.isNotEmpty) {
      buffer.writeln('    <desc>${_escapeXml(track.description!)}</desc>');
    }
    buffer.writeln('    <time>${track.createdAt.toUtc().toIso8601String()}</time>');
    buffer.writeln('  </metadata>');
    
    // Track
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>${_escapeXml(track.name)}</name>');
    buffer.writeln('    <type>${track.activityType.name}</type>');
    
    // Track segment
    buffer.writeln('    <trkseg>');
    
    for (final point in track.points) {
      buffer.write('      <trkpt lat="${point.latitude}" lon="${point.longitude}">');
      
      if (point.elevation != null) {
        buffer.write('<ele>${point.elevation!.toStringAsFixed(1)}</ele>');
      }
      
      buffer.write('<time>${point.timestamp.toUtc().toIso8601String()}</time>');
      
      buffer.writeln('</trkpt>');
    }
    
    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');
    
    return buffer.toString();
  }

  /// Salva GPX su file temporaneo e ritorna il path
  Future<String> saveGpxToFile(Track track) async {
    final gpxContent = generateGpx(track);
    
    // Ottieni directory temporanea
    final directory = await getTemporaryDirectory();
    
    // Nome file sicuro
    final safeName = track.name
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
    
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${safeName}_$timestamp.gpx';
    
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(gpxContent);
    
    return file.path;
  }

  /// Escape caratteri speciali XML
  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
