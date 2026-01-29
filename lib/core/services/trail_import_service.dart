import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/geohash_util.dart';

/// Servizio per importare sentieri da fonti esterne
/// 
/// Fonti supportate:
/// - Waymarked Trails API (sentieri di alta qualità, CAI, etc.)
/// - OpenTopoData (elevazioni)
class TrailImportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  static const String _waymarkedApiBase = 'https://hiking.waymarkedtrails.org/api/v1';
  static const String _openTopoDataBase = 'https://api.opentopodata.org/v1/eudem25m';
  static const Duration _apiDelay = Duration(milliseconds: 500);
  static const Duration _elevationDelay = Duration(milliseconds: 1100);
  static const int _maxElevationPointsPerRequest = 100;
  
  CollectionReference<Map<String, dynamic>> get _trailsCollection =>
      _firestore.collection('public_trails');

  /// Cerca sentieri su Waymarked Trails
  Future<List<WaymarkedRoute>> searchWaymarkedTrails(String searchTerm) async {
    try {
      final url = '$_waymarkedApiBase/list/search?query=${Uri.encodeComponent(searchTerm)}&limit=100';
      final response = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'});
      
      if (response.statusCode != 200) {
        print('[TrailImport] Errore ricerca "$searchTerm": ${response.statusCode}');
        return [];
      }
      
      final data = jsonDecode(response.body);
      final results = data['results'] as List? ?? [];
      return results.map((r) => WaymarkedRoute.fromJson(r)).where((r) => r.name.isNotEmpty).toList();
    } catch (e) {
      print('[TrailImport] Errore searchWaymarkedTrails: $e');
      return [];
    }
  }

  /// Ottieni dettagli completi di un percorso
  Future<WaymarkedRouteDetails?> getWaymarkedRouteDetails(int routeId) async {
    try {
      final url = '$_waymarkedApiBase/details/relation/$routeId';
      final response = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'});
      if (response.statusCode != 200) return null;
      return WaymarkedRouteDetails.fromJson(jsonDecode(response.body));
    } catch (e) {
      print('[TrailImport] Errore getWaymarkedRouteDetails: $e');
      return null;
    }
  }

  /// Estrae coordinate dalla struttura route
  List<List<double>> extractCoordinatesFromDetails(WaymarkedRouteDetails details) {
    final coords = <List<double>>[];
    
    void extractFromRoute(Map<String, dynamic>? routeObj) {
      if (routeObj == null) return;
      
      final geometry = routeObj['geometry'];
      if (geometry != null && geometry['coordinates'] != null) {
        for (final coord in (geometry['coordinates'] as List)) {
          if (coord is List && coord.length >= 2) {
            final lonLat = _webMercatorToLonLat((coord[0] as num).toDouble(), (coord[1] as num).toDouble());
            coords.add(lonLat);
          }
        }
      }
      
      final ways = routeObj['ways'];
      if (ways is List) for (final way in ways) extractFromRoute(way as Map<String, dynamic>?);
      
      final main = routeObj['main'];
      if (main is List) for (final sub in main) extractFromRoute(sub as Map<String, dynamic>?);
    }
    
    extractFromRoute(details.route);
    return coords;
  }

  /// Scarica elevazioni per coordinate
  Future<List<double>> fetchElevations(List<List<double>> coords) async {
    final elevations = <double>[];
    final sampleRate = (coords.length / 500).ceil().clamp(1, 10);
    final sampledCoords = <List<double>>[];
    
    for (int i = 0; i < coords.length; i += sampleRate) sampledCoords.add(coords[i]);
    
    for (int i = 0; i < sampledCoords.length; i += _maxElevationPointsPerRequest) {
      final batch = sampledCoords.skip(i).take(_maxElevationPointsPerRequest).toList();
      final locations = batch.map((c) => '${c[1]},${c[0]}').join('|');
      
      try {
        final response = await http.get(Uri.parse('$_openTopoDataBase?locations=$locations'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['results'] != null) {
            for (final r in data['results']) elevations.add((r['elevation'] as num?)?.toDouble() ?? 0);
          }
        } else {
          elevations.addAll(List.filled(batch.length, 0.0));
        }
      } catch (e) {
        elevations.addAll(List.filled(batch.length, 0.0));
      }
      
      if (i + _maxElevationPointsPerRequest < sampledCoords.length) await Future.delayed(_elevationDelay);
    }
    
    return sampleRate > 1 && elevations.isNotEmpty 
        ? _interpolateElevations(coords.length, elevations, sampleRate) 
        : elevations;
  }

  /// Calcola statistiche elevazione
  ElevationStats calculateElevationStats(List<double> elevations) {
    if (elevations.isEmpty) return const ElevationStats(gain: 0, loss: 0, min: 0, max: 0);
    
    double gain = 0, loss = 0, min = elevations.first, max = elevations.first;
    
    for (int i = 1; i < elevations.length; i++) {
      final diff = elevations[i] - elevations[i - 1];
      if (diff > 3) gain += diff;
      else if (diff < -3) loss += diff.abs();
      if (elevations[i] < min) min = elevations[i];
      if (elevations[i] > max) max = elevations[i];
    }
    
    return ElevationStats(
      gain: gain.round().toDouble(), 
      loss: loss.round().toDouble(), 
      min: min.round().toDouble(), 
      max: max.round().toDouble(),
    );
  }

  /// Importa sentieri da Waymarked Trails
  Future<ImportResult> importFromWaymarked({
    required List<String> searchTerms,
    required String region,
    List<double>? geoBbox,
    void Function(ImportProgress)? onProgress,
  }) async {
    final imported = <ImportedTrail>[];
    final skipped = <SkippedTrail>[];
    final errors = <ImportError>[];
    final allRoutes = <int, WaymarkedRoute>{};
    
    // 1. Cerca percorsi
    for (int t = 0; t < searchTerms.length; t++) {
      final term = searchTerms[t];
      onProgress?.call(ImportProgress(
        phase: 'search', 
        current: t + 1, 
        total: searchTerms.length, 
        message: 'Ricerca "$term"...',
      ));
      
      for (final route in await searchWaymarkedTrails(term)) {
        allRoutes.putIfAbsent(route.id, () => route);
      }
      await Future.delayed(_apiDelay);
    }
    
    print('[TrailImport] Trovati ${allRoutes.length} percorsi unici');
    
    // 2. Processa percorsi
    final routesList = allRoutes.values.toList();
    
    for (int i = 0; i < routesList.length; i++) {
      final route = routesList[i];
      onProgress?.call(ImportProgress(
        phase: 'import', 
        current: i + 1, 
        total: routesList.length, 
        message: 'Import "${route.name}"...',
      ));
      
      try {
        // Dettagli
        final details = await getWaymarkedRouteDetails(route.id);
        if (details == null) {
          skipped.add(SkippedTrail(name: route.name, reason: 'Dettagli non disponibili'));
          continue;
        }
        
        // Coordinate
        final coords = extractCoordinatesFromDetails(details);
        if (coords.length < 5) {
          skipped.add(SkippedTrail(name: route.name, reason: 'Troppi pochi punti'));
          continue;
        }
        
        // Filtro geografico
        if (geoBbox != null) {
          final center = coords[coords.length ~/ 2];
          if (center[0] < geoBbox[0] || center[0] > geoBbox[2] || 
              center[1] < geoBbox[1] || center[1] > geoBbox[3]) {
            skipped.add(SkippedTrail(name: route.name, reason: 'Fuori area'));
            continue;
          }
        }
        
        // Verifica duplicato
        final existingDoc = await _trailsCollection.doc('wmt_relation_${route.id}').get();
        if (existingDoc.exists) {
          skipped.add(SkippedTrail(name: route.name, reason: 'Già importato'));
          continue;
        }
        
        // Elevazioni
        final elevations = await fetchElevations(coords);
        final elevationStats = calculateElevationStats(elevations);
        
        // Calcoli
        final distance = _calculateTotalDistance(coords);
        final isCircular = _isCircular(coords);
        final center = coords[coords.length ~/ 2];
        final geoHash = GeoHashUtil.encode(center[1], center[0], precision: 7);
        
        // Coordinate con elevazione
        final coordsWithEle = <List<double>>[];
        for (int j = 0; j < coords.length; j++) {
          coordsWithEle.add([coords[j][0], coords[j][1], j < elevations.length ? elevations[j] : 0.0]);
        }
        
        // Upload
        final docId = 'wmt_relation_${route.id}';
        await _trailsCollection.doc(docId).set({
          'name': route.name,
          'osmId': route.id,
          'source': 'waymarked',
          'region': region,
          'geometry': {'type': 'LineString', 'coordinatesJson': jsonEncode(coordsWithEle)},
          'center': GeoPoint(center[1], center[0]),
          'startPoint': {'lat': coords.first[1], 'lon': coords.first[0]},
          'endPoint': {'lat': coords.last[1], 'lon': coords.last[0]},
          'geoHash': geoHash,
          'geoHashes': [geoHash, geoHash.substring(0, 6), geoHash.substring(0, 5), geoHash.substring(0, 4)],
          'pointsCount': coordsWithEle.length,
          'distance': distance.round(),
          'elevationGain': elevationStats.gain.round(),
          'elevationLoss': elevationStats.loss.round(),
          'maxAltitude': elevationStats.max.round(),
          'minAltitude': elevationStats.min.round(),
          'isCircular': isCircular,
          'difficulty': _estimateDifficulty(distance, elevationStats.gain),
          'activityType': 'escursionismo',
          'quality': 'excellent',
          'isRoute': true,
          'symbol': route.symbol,
          'network': route.group,
          'ref': route.ref,
          'from': details.from,
          'to': details.to,
          'isRifugioRoute': route.name.toLowerCase().contains('rifugio') || 
                           (details.to?.toLowerCase().contains('rifugio') ?? false),
          'searchTerms': _generateSearchTerms(route.name, route.ref, details.from, details.to),
          'importedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        imported.add(ImportedTrail(
          docId: docId, 
          name: route.name, 
          distance: distance, 
          elevationGain: elevationStats.gain,
        ));
        print('[TrailImport] ✅ ${route.name} - ${(distance/1000).toStringAsFixed(1)}km, +${elevationStats.gain.round()}m');
        
      } catch (e) {
        errors.add(ImportError(name: route.name, error: e.toString()));
        print('[TrailImport] ❌ ${route.name}: $e');
      }
      
      await Future.delayed(_apiDelay);
    }
    
    return ImportResult(
      imported: imported, 
      skipped: skipped, 
      errors: errors, 
      totalFound: allRoutes.length,
    );
  }

  // Utility methods
  List<double> _webMercatorToLonLat(double x, double y) {
    final lon = (x * 180) / 20037508.34;
    final lat = (math.atan(math.exp((y * math.pi) / 20037508.34)) * 360) / math.pi - 90;
    return [lon, lat];
  }

  double _calculateTotalDistance(List<List<double>> coords) {
    double total = 0;
    for (int i = 1; i < coords.length; i++) {
      total += _haversineDistance(coords[i-1][1], coords[i-1][0], coords[i][1], coords[i][0]);
    }
    return total;
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat/2) * math.sin(dLat/2) + 
              math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * 
              math.sin(dLon/2) * math.sin(dLon/2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  bool _isCircular(List<List<double>> coords) => 
      coords.length >= 3 && _haversineDistance(coords.first[1], coords.first[0], coords.last[1], coords.last[0]) < 100;

  String _estimateDifficulty(double dist, double gain) {
    final km = dist / 1000;
    if (km < 5 && gain < 300) return 'T';
    if (km < 10 && gain < 600) return 'E';
    if (gain / km > 100 || gain > 1200) return 'EE';
    return 'E';
  }

  List<String> _generateSearchTerms(String name, String? ref, String? from, String? to) {
    final terms = <String>{};
    void add(String? t) => t?.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9àèéìòùç\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((s) => s.length > 2)
        .forEach(terms.add);
    add(name); add(ref); add(from); add(to);
    if (name.toLowerCase().contains('rifugio')) terms.add('rifugio');
    return terms.toList();
  }

  List<double> _interpolateElevations(int total, List<double> sampled, int rate) {
    final result = List<double>.filled(total, 0);
    for (int i = 0; i < sampled.length; i++) {
      final idx = i * rate;
      if (idx < total) result[idx] = sampled[i];
    }
    for (int i = 0; i < total; i++) {
      if (result[i] == 0) {
        final p = (i ~/ rate) * rate, n = p + rate;
        if (p < total && n < total) result[i] = result[p] + (i - p) / rate * (result[n] - result[p]);
        else if (p < total) result[i] = result[p];
      }
    }
    return result;
  }
}

// Models
class WaymarkedRoute {
  final int id;
  final String name;
  final String? ref, group, symbol;
  final List<String>? itinerary;
  
  const WaymarkedRoute({required this.id, required this.name, this.ref, this.group, this.symbol, this.itinerary});
  
  factory WaymarkedRoute.fromJson(Map<String, dynamic> j) => WaymarkedRoute(
    id: j['id'] as int,
    name: j['name']?.toString() ?? '',
    ref: j['ref']?.toString(),
    group: j['group']?.toString(),
    symbol: j['symbol_description']?.toString(),
    itinerary: (j['itinerary'] as List?)?.map((e) => e.toString()).toList(),
  );
}

class WaymarkedRouteDetails {
  final int id;
  final String name;
  final String? from, to, operator;
  final Map<String, dynamic>? route, tags;
  
  const WaymarkedRouteDetails({required this.id, required this.name, this.from, this.to, this.operator, this.route, this.tags});
  
  factory WaymarkedRouteDetails.fromJson(Map<String, dynamic> j) => WaymarkedRouteDetails(
    id: j['id'] as int? ?? 0,
    name: j['name']?.toString() ?? '',
    from: j['tags']?['from']?.toString(),
    to: j['tags']?['to']?.toString(),
    operator: j['operator']?.toString(),
    route: j['route'] as Map<String, dynamic>?,
    tags: j['tags'] as Map<String, dynamic>?,
  );
}

class ElevationStats {
  final double gain, loss, min, max;
  const ElevationStats({required this.gain, required this.loss, required this.min, required this.max});
}

class ImportProgress {
  final String phase, message;
  final int current, total;
  const ImportProgress({required this.phase, required this.current, required this.total, required this.message});
  double get percentage => total > 0 ? current / total : 0;
}

class ImportResult {
  final List<ImportedTrail> imported;
  final List<SkippedTrail> skipped;
  final List<ImportError> errors;
  final int totalFound;
  const ImportResult({required this.imported, required this.skipped, required this.errors, required this.totalFound});
}

class ImportedTrail {
  final String docId, name;
  final double distance, elevationGain;
  const ImportedTrail({required this.docId, required this.name, required this.distance, required this.elevationGain});
}

class SkippedTrail {
  final String name, reason;
  const SkippedTrail({required this.name, required this.reason});
}

class ImportError {
  final String name, error;
  const ImportError({required this.name, required this.error});
}
