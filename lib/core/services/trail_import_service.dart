import 'package:flutter/foundation.dart';
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
        debugPrint('[TrailImport] Errore ricerca "$searchTerm": ${response.statusCode}');
        return [];
      }
      
      final data = jsonDecode(response.body);
      final results = data['results'] as List? ?? [];
      return results.map((r) => WaymarkedRoute.fromJson(r)).where((r) => r.name.isNotEmpty).toList();
    } catch (e) {
      debugPrint('[TrailImport] Errore searchWaymarkedTrails: $e');
      return [];
    }
  }

  /// Cerca sentieri per area geografica (bounding box)
  Future<List<WaymarkedRoute>> searchByBbox({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int limit = 100,
  }) async {
    try {
      // API Waymarked: bbox in EPSG:3857 web mercator, ordine
      // west,south,east,north. (Con WGS84 l'endpoint accetta la query
      // ma torna sempre results=[].)
      final sw = _lonLatToMercator(minLng, minLat);
      final ne = _lonLatToMercator(maxLng, maxLat);
      final bbox = "${sw[0].toStringAsFixed(1)},${sw[1].toStringAsFixed(1)},${ne[0].toStringAsFixed(1)},${ne[1].toStringAsFixed(1)}";
      final url = "$_waymarkedApiBase/list/by_area?bbox=$bbox&limit=$limit";
      debugPrint("[TrailImport] Ricerca bbox: $bbox");
      
      final response = await http.get(Uri.parse(url), headers: {"Accept": "application/json"});
      
      if (response.statusCode != 200) {
        debugPrint("[TrailImport] Errore bbox: ${response.statusCode}");
        return [];
      }
      
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // L'API Waymarked usa chiavi diverse a seconda dell'endpoint:
      // `results` per /list/search, `routes` per /list/by_area.
      // Fallback su qualsiasi value che sia List<Map>.
      List? results = (data['results'] ?? data['routes'] ?? data['relations']) as List?;
      if (results == null) {
        // ultimo tentativo: prima List trovata
        for (final v in data.values) {
          if (v is List && v.isNotEmpty && v.first is Map) {
            results = v;
            break;
          }
        }
      }
      results ??= const [];
      debugPrint("[TrailImport] Bbox response keys=${data.keys.toList()} → ${results.length} percorsi");
      return results.map((r) => WaymarkedRoute.fromJson(r as Map<String, dynamic>)).where((r) => r.name.isNotEmpty).toList();
    } catch (e) {
      debugPrint("[TrailImport] Errore searchByBbox: $e");
      return [];
    }
  }


  /// Ottieni bounding box da nome luogo usando Nominatim (OpenStreetMap)
  Future<Map<String, double>?> getBboxFromPlaceName(String placeName) async {
    try {
      final url = "https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(placeName)}&format=json&limit=1";
      debugPrint("[TrailImport] Geocoding: $placeName");
      
      final response = await http.get(
        Uri.parse(url),
        headers: {"User-Agent": "TrailShare App", "Accept": "application/json"},
      );
      
      if (response.statusCode != 200) {
        debugPrint("[TrailImport] Errore Nominatim: ${response.statusCode}");
        return null;
      }
      
      final List<dynamic> data = jsonDecode(response.body);
      if (data.isEmpty) {
        debugPrint("[TrailImport] Nessun risultato per: $placeName");
        return null;
      }
      
      final result = data[0];
      final bbox = result["boundingbox"] as List<dynamic>?;
      if (bbox == null || bbox.length < 4) return null;
      
      // Nominatim bbox: [minLat, maxLat, minLng, maxLng]
      final minLat = double.tryParse(bbox[0].toString()) ?? 0;
      final maxLat = double.tryParse(bbox[1].toString()) ?? 0;
      final minLng = double.tryParse(bbox[2].toString()) ?? 0;
      final maxLng = double.tryParse(bbox[3].toString()) ?? 0;
      
      debugPrint("[TrailImport] Bbox per $placeName: $minLat,$maxLat,$minLng,$maxLng");
      return {"minLat": minLat, "maxLat": maxLat, "minLng": minLng, "maxLng": maxLng};
    } catch (e) {
      debugPrint("[TrailImport] Errore getBboxFromPlaceName: $e");
      return null;
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
      debugPrint('[TrailImport] Errore getWaymarkedRouteDetails: $e');
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
      if (ways is List) {
        for (final way in ways) {
          extractFromRoute(way as Map<String, dynamic>?);
        }
      }

      final main = routeObj['main'];
      if (main is List) {
        for (final sub in main) {
          extractFromRoute(sub as Map<String, dynamic>?);
        }
      }
    }
    
    extractFromRoute(details.route);
    return coords;
  }

  /// Scarica elevazioni per coordinate
  Future<List<double>> fetchElevations(List<List<double>> coords) async {
    final elevations = <double>[];
    final sampleRate = (coords.length / 500).ceil().clamp(1, 10);
    final sampledCoords = <List<double>>[];
    
    for (int i = 0; i < coords.length; i += sampleRate) {
      sampledCoords.add(coords[i]);
    }
    
    for (int i = 0; i < sampledCoords.length; i += _maxElevationPointsPerRequest) {
      final batch = sampledCoords.skip(i).take(_maxElevationPointsPerRequest).toList();
      final locations = batch.map((c) => '${c[1]},${c[0]}').join('|');
      
      try {
        final response = await http.get(Uri.parse('$_openTopoDataBase?locations=$locations'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['results'] != null) {
            for (final r in data['results']) {
              elevations.add((r['elevation'] as num?)?.toDouble() ?? 0);
            }
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
      if (diff > 3) {
        gain += diff;
      } else if (diff < -3) {
        loss += diff.abs();
      }
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

  /// Parsing URL Waymarked Trails per estrarre l'ID della relation.
  /// Pattern accettati:
  ///   - https://hiking.waymarkedtrails.org/#route?type=relation&id=12345
  ///   - https://waymarkedtrails.org/hiking/relations/12345
  ///   - 12345 (solo numero)
  int? parseWaymarkedId(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    // Se è solo un numero
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    // Pattern ?id=12345
    final m1 = RegExp(r'[?&]id=(\d+)').firstMatch(raw);
    if (m1 != null) return int.tryParse(m1.group(1)!);
    // Pattern /relations/12345
    final m2 = RegExp(r'/relations?/(\d+)').firstMatch(raw);
    if (m2 != null) return int.tryParse(m2.group(1)!);
    // Pattern /relation/12345
    final m3 = RegExp(r'relation[/=](\d+)').firstMatch(raw);
    if (m3 != null) return int.tryParse(m3.group(1)!);
    return null;
  }

  /// Importa un singolo sentiero direttamente dal suo ID Waymarked
  /// (A2). Bypassa la fase di ricerca: l'utente conosce già l'OSM
  /// relation che vuole importare.
  Future<ImportResult> importSingleFromWaymarked({
    required int relationId,
    required String region,
    bool updateExisting = false,
    void Function(ImportProgress)? onProgress,
  }) async {
    final imported = <ImportedTrail>[];
    final skipped = <SkippedTrail>[];
    final errors = <ImportError>[];

    onProgress?.call(ImportProgress(
      phase: 'import',
      current: 1,
      total: 1,
      message: 'Recupero dati per relation $relationId...',
    ));

    try {
      final details = await getWaymarkedRouteDetails(relationId);
      if (details == null) {
        return ImportResult(
          imported: imported,
          skipped: [SkippedTrail(name: 'relation $relationId', reason: 'Dettagli non disponibili (404?)')],
          errors: errors,
          totalFound: 1,
        );
      }
      final fakeRoute = WaymarkedRoute(
        id: details.id,
        name: details.name,
        ref: details.tags?['ref']?.toString(),
        group: details.tags?['network']?.toString(),
        symbol: details.tags?['osmc:symbol']?.toString(),
      );
      await _processSingleRoute(
        route: fakeRoute,
        details: details,
        region: region,
        geoBbox: null,
        updateExisting: updateExisting,
        imported: imported,
        skipped: skipped,
        errors: errors,
      );
    } catch (e) {
      errors.add(ImportError(
        name: 'relation $relationId',
        error: e.toString(),
      ));
    }

    await _writeImportHistory(
      regionName: region,
      source: 'waymarked_single:$relationId',
      imported: imported.length,
      skipped: skipped.length,
      errors: errors.length,
    );

    return ImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
      totalFound: 1,
    );
  }

  /// Importa sentieri da Waymarked Trails
  Future<ImportResult> importFromWaymarked({
    required List<String> searchTerms,
    required String region,
    List<double>? geoBbox,
    bool updateExisting = false,
    void Function(ImportProgress)? onProgress,
  }) async {
    final imported = <ImportedTrail>[];
    final skipped = <SkippedTrail>[];
    final errors = <ImportError>[];
    final allRoutes = <int, WaymarkedRoute>{};
    
    // 1a. SEARCH BY BBOX — se abbiamo un bbox della regione, prendiamo
    //     direttamente tutti i percorsi tracciati nell'area (fino a
    //     limit=200). Funziona anche su regioni dove i preset
    //     hardcoded non hanno termini specifici (es. Calabria,
    //     Sardegna) ed è la strategia più affidabile.
    if (geoBbox != null) {
      onProgress?.call(ImportProgress(
        phase: 'search',
        current: 1,
        total: searchTerms.length + 1,
        message: 'Ricerca geografica nel bbox $region...',
      ));
      // Waymarked `by_area` rifiuta bbox troppo grandi (>~0.5° lato → torna
      // []). Tile in sotto-bbox di max ~0.5° e accumula.
      try {
        const tileSize = 0.5;
        final tiles = <List<double>>[];
        for (double la = geoBbox[0]; la < geoBbox[1]; la += tileSize) {
          for (double lo = geoBbox[2]; lo < geoBbox[3]; lo += tileSize) {
            tiles.add([
              la,
              (la + tileSize).clamp(geoBbox[0], geoBbox[1]),
              lo,
              (lo + tileSize).clamp(geoBbox[2], geoBbox[3]),
            ]);
          }
        }
        debugPrint('[TrailImport] Bbox $region → ${tiles.length} tile da ${tileSize}°');
        int tileIdx = 0;
        for (final t in tiles) {
          tileIdx++;
          onProgress?.call(ImportProgress(
            phase: 'search',
            current: tileIdx,
            total: tiles.length,
            message: 'Tile $tileIdx/${tiles.length} ($region)',
          ));
          final byBbox = await searchByBbox(
            minLat: t[0], maxLat: t[1], minLng: t[2], maxLng: t[3],
            limit: 200,
          );
          for (final route in byBbox) {
            allRoutes.putIfAbsent(route.id, () => route);
          }
          await Future.delayed(_apiDelay);
        }
        debugPrint('[TrailImport] Bbox search totale → ${allRoutes.length} percorsi unici');
      } catch (e) {
        debugPrint('[TrailImport] bbox search error: $e');
      }
    }

    // 1b. Cerca per termini (opzionale: arricchisce con percorsi che
    //     potrebbero non avere geometria completa nel bbox ma sono
    //     comunque taggati con quel nome).
    for (int t = 0; t < searchTerms.length; t++) {
      final term = searchTerms[t];
      onProgress?.call(ImportProgress(
        phase: 'search',
        current: t + 2,
        total: searchTerms.length + 2,
        message: 'Ricerca "$term"...',
      ));
      for (final route in await searchWaymarkedTrails(term)) {
        allRoutes.putIfAbsent(route.id, () => route);
      }
      await Future.delayed(_apiDelay);
    }

    // NOTA: rimossa la ricerca aggiuntiva per nome regione — produceva
    // falsi positivi (es. "Piemonte" → match solo su Sentiero Italia -
    // Piemonte E00, ignorando tutto il resto). Con il tiling bbox il
    // recupero geografico è completo.
    debugPrint("[TrailImport] Trovati ${allRoutes.length} percorsi unici");
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
        await _processSingleRoute(
          route: route,
          details: null, // verrà fetchato dentro
          region: region,
          geoBbox: geoBbox,
          updateExisting: updateExisting,
          imported: imported,
          skipped: skipped,
          errors: errors,
        );
      } catch (e) {
        errors.add(ImportError(name: route.name, error: e.toString()));
        debugPrint('[TrailImport] ❌ ${route.name}: $e');
      }
      await Future.delayed(_apiDelay);
    }

    // A4 — salva storico import
    await _writeImportHistory(
      regionName: region,
      source: 'waymarked_search',
      imported: imported.length,
      skipped: skipped.length,
      errors: errors.length,
    );

    return ImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
      totalFound: allRoutes.length,
    );
  }

  /// Helper: processa una singola route (search risultato o single-import).
  /// Estrae coordinate, filtra bbox, fetch elevazioni, scrive Firestore.
  /// Update mode: se [updateExisting]=true e il doc esiste, aggiorna
  /// invece di skippare. (C10)
  Future<void> _processSingleRoute({
    required WaymarkedRoute route,
    required WaymarkedRouteDetails? details,
    required String region,
    required List<double>? geoBbox,
    required bool updateExisting,
    required List<ImportedTrail> imported,
    required List<SkippedTrail> skipped,
    required List<ImportError> errors,
  }) async {
    // Dettagli (se non passati dal chiamante)
    details ??= await getWaymarkedRouteDetails(route.id);
    if (details == null) {
      skipped.add(SkippedTrail(name: route.name, reason: 'Dettagli non disponibili'));
      return;
    }

    final coords = extractCoordinatesFromDetails(details);
    if (coords.length < 5) {
      skipped.add(SkippedTrail(name: route.name, reason: 'Troppi pochi punti'));
      return;
    }

    if (geoBbox != null) {
      final center = coords[coords.length ~/ 2];
      if (center[1] < geoBbox[0] || center[1] > geoBbox[1] ||
          center[0] < geoBbox[2] || center[0] > geoBbox[3]) {
        skipped.add(SkippedTrail(name: route.name, reason: 'Fuori area'));
        return;
      }
    }

    final docId = 'wmt_relation_${route.id}';
    final existingDoc = await _trailsCollection.doc(docId).get();
    if (existingDoc.exists && !updateExisting) {
      skipped.add(SkippedTrail(name: route.name, reason: 'Già importato'));
      return;
    }

    // Filtra coord non-finite (NaN/Inf) prodotte da mercator su geometrie sporche.
    coords.removeWhere((c) =>
        c.length < 2 ||
        !c[0].isFinite ||
        !c[1].isFinite ||
        c[1].abs() > 90 ||
        c[0].abs() > 180);
    if (coords.length < 5) {
      skipped.add(SkippedTrail(name: route.name, reason: 'Coord non valide'));
      return;
    }

    final elevations = await fetchElevations(coords);
    final elevationStats = calculateElevationStats(elevations);
    final distance = _calculateTotalDistance(coords);
    final isCircular = _isCircular(coords);
    final center = coords[coords.length ~/ 2];
    // Guard: se center o stats non finiti, salta.
    if (!center[0].isFinite || !center[1].isFinite ||
        !distance.isFinite || !elevationStats.gain.isFinite) {
      skipped.add(SkippedTrail(name: route.name, reason: 'Valori non finiti'));
      return;
    }
    final geoHash = GeoHashUtil.encode(center[1], center[0], precision: 7);

    final coordsWithEle = <List<double>>[];
    for (int j = 0; j < coords.length; j++) {
      coordsWithEle.add([
        coords[j][0],
        coords[j][1],
        j < elevations.length ? elevations[j] : 0.0,
      ]);
    }

    // Firestore limita un documento a 1 MB. Super-route come Sentiero Italia
    // possono avere 50k+ punti → coordinatesJson > 1MB → write rifiutato
    // con "invalid nested entity". Downsample finché il JSON sta sotto ~800 KB.
    var coordsForWrite = coordsWithEle;
    var coordsJson = jsonEncode(coordsForWrite);
    const maxJsonBytes = 800 * 1024;
    while (coordsJson.length > maxJsonBytes && coordsForWrite.length > 500) {
      final stride = (coordsForWrite.length / (coordsForWrite.length / 2).ceil()).ceil();
      final reduced = <List<double>>[];
      for (int j = 0; j < coordsForWrite.length; j += stride) {
        reduced.add(coordsForWrite[j]);
      }
      // mantieni sempre l'ultimo punto per chiusura tracciato
      if (reduced.last != coordsForWrite.last) reduced.add(coordsForWrite.last);
      coordsForWrite = reduced;
      coordsJson = jsonEncode(coordsForWrite);
      debugPrint('[TrailImport] downsample ${route.name} → ${coordsForWrite.length} pts (${coordsJson.length} bytes)');
    }
    if (coordsJson.length > maxJsonBytes) {
      skipped.add(SkippedTrail(name: route.name, reason: 'Tracciato troppo grande (${coordsJson.length ~/ 1024} KB)'));
      return;
    }

    // C9 — Activity type smart dai tag OSM (route=hiking|mtb|bicycle|foot)
    final activityType = _activityTypeFromTags(details.tags);
    // Difficoltà smart: prima `sac_scale` OSM, poi fallback su euristica
    final difficulty = _difficultyFromTags(details.tags) ??
        _estimateDifficulty(distance, elevationStats.gain);

    // Calcola simplifiedPoints (max ~30 pt) per il Discover map: il doc
    // index resta piccolo (~2 KB) e si carica veloce anche con 1000+ trail.
    // La geometria completa è in public_trail_geometries/{docId}.
    final simplifiedPoints = _samplePoints(coordsForWrite, 30);

    final docData = <String, dynamic>{
      'name': route.name,
      'osmId': route.id,
      'source': 'waymarked',
      'region': region,
      // Geometry "metadata-only" nel doc index: niente coordinatesJson pesante.
      'geometry': {
        'type': 'LineString',
      },
      'simplifiedPoints': simplifiedPoints,
      'center': GeoPoint(center[1], center[0]),
      'startPoint': {'lat': coords.first[1], 'lon': coords.first[0]},
      'endPoint': {'lat': coords.last[1], 'lon': coords.last[0]},
      // Anche denormalizzati startLat/startLng per il filter Discover.
      'startLat': coords.first[1],
      'startLng': coords.first[0],
      'geoHash': geoHash,
      'geoHashes': [
        geoHash,
        geoHash.substring(0, 6),
        geoHash.substring(0, 5),
        geoHash.substring(0, 4),
      ],
      'pointsCount': coordsForWrite.length,
      'distance': distance.round(),
      'elevationGain': elevationStats.gain.round(),
      'elevationLoss': elevationStats.loss.round(),
      'maxAltitude': elevationStats.max.round(),
      'minAltitude': elevationStats.min.round(),
      'isCircular': isCircular,
      'difficulty': difficulty,
      'activityType': activityType,
      'quality': 'excellent',
      'isRoute': true,
      'symbol': route.symbol,
      'network': route.group,
      'ref': route.ref,
      'from': details.from,
      'to': details.to,
      'isRifugioRoute': route.name.toLowerCase().contains('rifugio') ||
          (details.to?.toLowerCase().contains('rifugio') ?? false),
      'searchTerms': _generateSearchTerms(
          route.name, route.ref, details.from, details.to),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // Su nuovo doc, scrivi anche importedAt; su update preserva il valore originale
    if (!existingDoc.exists) {
      docData['importedAt'] = FieldValue.serverTimestamp();
    }
    await _trailsCollection.doc(docId).set(docData, SetOptions(merge: existingDoc.exists));

    // Geometry pesante separata: 1 doc per trail, lazy-loaded dal detail.
    await _firestore.collection('public_trail_geometries').doc(docId).set({
      'coordinatesJson': coordsJson,
      'pointsCount': coordsForWrite.length,
      'osmId': route.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    imported.add(ImportedTrail(
      docId: docId,
      name: route.name,
      distance: distance,
      elevationGain: elevationStats.gain,
    ));
    final action = existingDoc.exists ? '🔄 aggiornato' : '✅ nuovo';
    debugPrint(
        '[TrailImport] $action ${route.name} - ${(distance / 1000).toStringAsFixed(1)}km, +${elevationStats.gain.round()}m, type=$activityType');
  }

  /// C9 — Mappa il tag OSM `route` al nostro activityType TrailShare.
  String _activityTypeFromTags(Map<String, dynamic>? tags) {
    if (tags == null) return 'trekking';
    final r = tags['route']?.toString().toLowerCase();
    switch (r) {
      case 'mtb':
      case 'mountain_biking':
        return 'mountainBiking';
      case 'bicycle':
      case 'cycling':
        return 'cycling';
      case 'piste':
      case 'ski':
      case 'ski_tour':
      case 'ski_touring':
        return 'skiTouring';
      case 'horse':
        return 'walking';
      case 'foot':
      case 'hiking':
      case 'walking':
      case 'trekking':
      default:
        return 'trekking';
    }
  }

  /// Parsa la SAC scale ufficiale CAI in codice difficoltà TrailShare.
  /// https://wiki.openstreetmap.org/wiki/Key:sac_scale
  String? _difficultyFromTags(Map<String, dynamic>? tags) {
    if (tags == null) return null;
    final sac = tags['sac_scale']?.toString().toLowerCase();
    if (sac == null) return null;
    switch (sac) {
      case 'hiking':
        return 't';
      case 'mountain_hiking':
        return 'e';
      case 'demanding_mountain_hiking':
        return 'ee';
      case 'alpine_hiking':
      case 'demanding_alpine_hiking':
      case 'difficult_alpine_hiking':
        return 'eea';
    }
    return null;
  }

  /// A4 — Scrive un record nella collezione `trail_imports` con uno
  /// snapshot dell'operazione (chi/quando/quanti). Best-effort:
  /// fallimento qui non blocca il caller.
  Future<void> _writeImportHistory({
    required String regionName,
    required String source,
    required int imported,
    required int skipped,
    required int errors,
  }) async {
    try {
      await _firestore.collection('trail_imports').add({
        'regionName': regionName,
        'source': source,
        'imported': imported,
        'skipped': skipped,
        'errors': errors,
        'at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[TrailImport] history write error: $e');
    }
  }

  // Utility methods
  List<double> _webMercatorToLonLat(double x, double y) {
    final lon = (x * 180) / 20037508.34;
    final lat = (math.atan(math.exp((y * math.pi) / 20037508.34)) * 360) / math.pi - 90;
    return [lon, lat];
  }

  /// Campiona N punti equidistanti per simplifiedPoints.
  /// Output: List<Map<String,double>> [{lng, lat}, ...]. Firestore non
  /// accetta array di array, per questo usiamo lista di mappe.
  List<Map<String, double>> _samplePoints(List<List<double>> coords, int maxPoints) {
    if (coords.isEmpty) return const [];
    Map<String, double> toPt(List<double> c) => {'lng': c[0], 'lat': c[1]};
    if (coords.length <= maxPoints) return coords.map(toPt).toList();
    final stride = coords.length / maxPoints;
    final out = <Map<String, double>>[];
    for (int i = 0; i < maxPoints; i++) {
      final idx = (i * stride).floor().clamp(0, coords.length - 1);
      out.add(toPt(coords[idx]));
    }
    final last = toPt(coords.last);
    if (out.last['lng'] != last['lng'] || out.last['lat'] != last['lat']) {
      out.add(last);
    }
    return out;
  }

  /// WGS84 → EPSG:3857 web mercator. L'API Waymarked by_area accetta bbox in mercator.
  List<double> _lonLatToMercator(double lon, double lat) {
    final x = lon * 20037508.34 / 180;
    final y = math.log(math.tan((90 + lat) * math.pi / 360)) / (math.pi / 180);
    return [x, y * 20037508.34 / 180];
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
        if (p < total && n < total) {
          result[i] = result[p] + (i - p) / rate * (result[n] - result[p]);
        } else if (p < total) {
          result[i] = result[p];
        }
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
