import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/track.dart';
import '../../core/utils/geohash_util.dart';
import '../../core/services/trails_cache_service.dart';
import '../../core/utils/geometry_simplifier.dart';

/// Repository ottimizzato per sentieri pubblici
/// 
/// Ottimizzazioni:
/// 1. Cache locale con Hive
/// 2. Geometrie semplificate per mappa
/// 3. Clustering a zoom basso
/// 4. Lazy loading geometria completa
class PublicTrailsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TrailsCacheService _cache = trailsCacheService;
  
  // Soglie zoom per clustering
  static const double _clusterZoomThreshold = 9.0;
  static const double _simplifiedZoomThreshold = 14.0;

  CollectionReference<Map<String, dynamic>> get _trailsCollection {
    return _firestore.collection('public_trails');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // API PRINCIPALE - Usata dalla DiscoverPage
  // ═══════════════════════════════════════════════════════════════════════════

  /// Carica sentieri per viewport con ottimizzazioni
  /// 
  /// [zoom] - Livello zoom corrente per decidere cosa caricare
  Future<TrailsResult> getTrailsForViewport({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required double zoom,
    int limit = 200,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    // A zoom molto basso, restituisci solo cluster/conteggi
    if (zoom < _clusterZoomThreshold) {
      final clusters = await _getClusteredTrails(
        minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng,
      );
      stopwatch.stop();
      print('[PublicTrails] ⚡ Cluster in ${stopwatch.elapsedMilliseconds}ms');
      return TrailsResult(clusters: clusters, trails: [], fromCache: false);
    }
    
    // Prova cache prima
    final cached = await _cache.getTrailsForZone(
      minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng,
    );

    if (cached != null && cached.isNotEmpty) {
      stopwatch.stop();
      print('[PublicTrails] ⚡ Cache hit in ${stopwatch.elapsedMilliseconds}ms (${cached.length} sentieri)');
      return TrailsResult(
        clusters: [],
        trails: cached.map((c) => _cachedToPublicTrail(c)).toList(),
        fromCache: true,
      );
    }
    
    // Cache miss: carica da Firestore
    final trails = await _loadFromFirestore(
      minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng,
      limit: limit,
      simplified: zoom < _simplifiedZoomThreshold,
    );
    
    // Salva in cache (in background)
    _cacheTrailsAsync(minLat, maxLat, minLng, maxLng, trails);
    
    stopwatch.stop();
    print('[PublicTrails] 🌐 Firestore in ${stopwatch.elapsedMilliseconds}ms (${trails.length} sentieri)');
    
    return TrailsResult(clusters: [], trails: trails, fromCache: false);
  }

  /// Carica geometria completa per un sentiero (per pagina dettaglio)
  Future<List<TrackPoint>?> getFullGeometry(String trailId) async {
    try {
      final doc = await _trailsCollection.doc(trailId).get();
      if (!doc.exists) return null;
      
      final data = doc.data()!;
      final geometry = data['geometry'];
      
      if (geometry != null && geometry is Map) {
        final coordsJsonStr = geometry['coordinatesJson'];
        if (coordsJsonStr != null && coordsJsonStr is String) {
          final List<dynamic> coordsList = jsonDecode(coordsJsonStr);
          return coordsList.map((p) {
            if (p is List && p.length >= 2) {
              return TrackPoint(
                longitude: (p[0] as num).toDouble(),
                latitude: (p[1] as num).toDouble(),
                elevation: p.length > 2 ? (p[2] as num?)?.toDouble() : null,
                timestamp: DateTime.now(),
              );
            }
            return null;
          }).whereType<TrackPoint>().toList();
        }
      }
      return null;
    } catch (e) {
      print('[PublicTrails] Errore getFullGeometry: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLUSTERING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Genera cluster per zoom basso
  Future<List<TrailCluster>> _getClusteredTrails({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) async {
    try {
      // Dividi l'area in una griglia 4x4
      final latStep = (maxLat - minLat) / 4;
      final lngStep = (maxLng - minLng) / 4;
      
      final clusters = <TrailCluster>[];
      
      // Per ogni cella, conta i sentieri
      for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
          final cellMinLat = minLat + i * latStep;
          final cellMaxLat = minLat + (i + 1) * latStep;
          final cellMinLng = minLng + j * lngStep;
          final cellMaxLng = minLng + (j + 1) * lngStep;
          
          // Geohash per questa cella
          final centerLat = (cellMinLat + cellMaxLat) / 2;
          final centerLng = (cellMinLng + cellMaxLng) / 2;
          final geohash = GeoHashUtil.encode(centerLat, centerLng, precision: 5);
          
          // Query count (più veloce di caricare tutti i documenti)
          final snapshot = await _trailsCollection
              .where('geoHash', isGreaterThanOrEqualTo: geohash)
              .where('geoHash', isLessThan: '${geohash}z')
              .limit(100).count().get();
          final count = snapshot.count ?? 0;
          
          if (count > 0) {
            clusters.add(TrailCluster(
              center: LatLng(centerLat, centerLng),
              count: count,
              bounds: ClusterBounds(
                minLat: cellMinLat, maxLat: cellMaxLat,
                minLng: cellMinLng, maxLng: cellMaxLng,
              ),
            ));
          }
        }
      }
      
      return clusters;
    } catch (e) {
      print('[PublicTrails] Errore clustering: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIRESTORE QUERY
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<PublicTrail>> _loadFromFirestore({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required int limit,
    required bool simplified,
  }) async {
    try {
      // Calcola geohash ranges
      final latDiff = maxLat - minLat;
      final lngDiff = maxLng - minLng;
      final areaSizeKm = math.max(latDiff, lngDiff) * 111;
      final precision = areaSizeKm > 5 ? 4 : 5;
      
      final ranges = GeoHashUtil.getQueryRanges(
        minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng,
        precision: precision,
      );

      print('[PublicTrails] 📍 Query area: $minLat,$minLng → $maxLat,$maxLng (${areaSizeKm.toStringAsFixed(0)}km, precision: $precision)');
      print('[PublicTrails] 🔍 ${ranges.length} geohash ranges: ${ranges.take(5).map((r) => "${r.start}-${r.end}").join(", ")}');
      
      final trails = <PublicTrail>[];
      final seenIds = <String>{};
      
      // Query parallele
      final futures = ranges.take(10).map((range) async {
        try {
          final snapshot = await _trailsCollection
              .where('geoHash', isGreaterThanOrEqualTo: range.start)
              .where('geoHash', isLessThan: range.end)
              .limit(limit ~/ ranges.length + 10)
              .get();
          return snapshot.docs;
        } catch (e) {
          return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        }
      });
      
      final results = await Future.wait(futures);
      final totalDocs = results.fold<int>(0, (sum, docs) => sum + docs.length);
      print('[PublicTrails] 📦 Risultati: $totalDocs documenti da ${results.length} query');
      
      for (final docs in results) {
        for (final doc in docs) {
          if (seenIds.contains(doc.id)) continue;
          seenIds.add(doc.id);
          
          final trail = _docToTrail(doc, simplified: simplified);
          if (trail != null) {
            // Margine 50% per includere sentieri ai bordi del viewport
            final latMargin = (maxLat - minLat) * 0.5;
            final lngMargin = (maxLng - minLng) * 0.5;
            if (trail.startLat >= minLat - latMargin && trail.startLat <= maxLat + latMargin &&
                trail.startLng >= minLng - lngMargin && trail.startLng <= maxLng + lngMargin) {
              trails.add(trail);
            }
          }
          
          if (trails.length >= limit) break;
        }
        if (trails.length >= limit) break;
      }
      
      return trails;
    } catch (e) {
      print('[PublicTrails] Errore Firestore: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CACHE
  // ═══════════════════════════════════════════════════════════════════════════

  void _cacheTrailsAsync(double minLat, double maxLat, double minLng, double maxLng, List<PublicTrail> trails) {
    // Non bloccare - salva in background
    Future(() async {
      final cached = trails.map((t) => CachedTrail(
        id: t.id,
        name: t.name,
        ref: t.ref,
        difficulty: t.difficulty,
        length: t.length,
        elevationGain: t.elevationGain,
        isCircular: t.isCircular,
        startLat: t.startLat,
        startLng: t.startLng,
        network: t.network,
        simplifiedCoords: t.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
      )).toList();
      
      await _cache.cacheTrailsForZone(
        minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng,
        trails: cached,
      );
    });
  }

  PublicTrail _cachedToPublicTrail(CachedTrail cached) {
    return PublicTrail(
      id: cached.id,
      name: cached.name,
      ref: cached.ref,
      difficulty: cached.difficulty,
      length: cached.length,
      elevationGain: cached.elevationGain,
      isCircular: cached.isCircular,
      startLat: cached.startLat,
      startLng: cached.startLng,
      network: cached.network,
      points: cached.simplifiedCoords.map((c) => TrackPoint(
        latitude: c.latitude,
        longitude: c.longitude,
        timestamp: DateTime.now(),
      )).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DOCUMENT PARSING
  // ═══════════════════════════════════════════════════════════════════════════

  PublicTrail? _docToTrail(DocumentSnapshot<Map<String, dynamic>> doc, {bool simplified = true}) {
    try {
      final data = doc.data();
      if (data == null) return null;

      List<TrackPoint> points = [];
      
      final geometry = data['geometry'];
      if (geometry != null && geometry is Map) {
        final coordsJsonStr = geometry['coordinatesJson'];
        if (coordsJsonStr != null && coordsJsonStr is String) {
          final List<dynamic> coordsList = jsonDecode(coordsJsonStr);
          
          // Converti a LatLng per semplificazione
          final latLngPoints = <LatLng>[];
          for (var p in coordsList) {
            if (p is List && p.length >= 2) {
              final lon = (p[0] as num).toDouble();
              final lat = (p[1] as num).toDouble();
              if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
                latLngPoints.add(LatLng(lat, lon));
              }
            }
          }
          
          // Semplifica se richiesto
          final finalPoints = simplified 
              ? GeometrySimplifier.simplify(latLngPoints, maxPoints: 30)
              : latLngPoints;
          
          points = finalPoints.map((ll) => TrackPoint(
            latitude: ll.latitude,
            longitude: ll.longitude,
            timestamp: DateTime.now(),
          )).toList();
        }
      }

      if (points.isEmpty) return null;

      String name = data['name']?.toString() ?? '';
      final ref = data['ref']?.toString();
      if (name.isEmpty && ref != null) name = 'Sentiero $ref';
      if (name.isEmpty) name = 'Sentiero';

      double? startLat, startLng;
      if (data['startPoint'] != null) {
        final sp = data['startPoint'];
        if (sp is GeoPoint) {
          startLat = sp.latitude;
          startLng = sp.longitude;
        } else if (sp is Map) {
          startLat = (sp['lat'] ?? sp['latitude'] as num?)?.toDouble();
          startLng = (sp['lng'] ?? sp['lon'] ?? sp['longitude'] as num?)?.toDouble();
        }
      }
      startLat ??= points.first.latitude;
      startLng ??= points.first.longitude;

      return PublicTrail(
        id: doc.id,
        name: name,
        ref: ref,
        network: data['network']?.toString(),
        operator: data['operator']?.toString(),
        difficulty: data['difficulty']?.toString(),
        points: points,
        length: (data['distance'] as num?)?.toDouble(),
        elevationGain: (data['elevationGain'] as num?)?.toDouble(),
        region: data['region']?.toString(),
        isCircular: data['isCircular'] == true,
        quality: data['quality']?.toString(),
        duration: (data['duration'] as num?)?.toInt(),
        startLat: startLat,
        startLng: startLng,
        geohash: data['geoHash']?.toString(),
      );
    } catch (e) {
      print('[PublicTrails] Errore parsing ${doc.id}: $e');
      return null;
    }
  }

  /// Invalida cache (chiamare dopo import)
  Future<void> invalidateCache() async {
    await _cache.invalidateAll();
  }

  /// Verifica copertura GeoHash per migrazione
  Future<GeohashCoverage> checkGeohashCoverage() async {
    try {
      // Conta documenti con geoHash
      final withGeohashCount = await _trailsCollection
          .where('geoHash', isNull: false)
          .limit(100).count()
          .get();
      
      // Conta documenti totali
      final total = await _trailsCollection.count().get();
      
      final withGh = withGeohashCount.count ?? 0;
      final totalCount = total.count ?? 0;
      
      return GeohashCoverage(
        withGeohash: withGh,
        withoutGeohash: totalCount - withGh,
      );
    } catch (e) {
      print('[PublicTrails] Errore checkGeohashCoverage: $e');
      return GeohashCoverage(withGeohash: 0, withoutGeohash: 0);
    }
  }

  /// Carica sentieri senza geohash per migrazione
  Future<List<PublicTrail>> getTrailsWithoutGeohash({int limit = 100}) async {
    try {
      final snapshot = await _trailsCollection
          .where('geoHash', isNull: true)
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => _docToTrail(doc, simplified: false))
          .whereType<PublicTrail>()
          .toList();
    } catch (e) {
      print('[PublicTrails] Errore getTrailsWithoutGeohash: $e');
      return [];
    }
  }

  /// Aggiorna geohash per un sentiero
  Future<void> updateTrailGeohash(String trailId, String geohash, List<String> geohashes) async {
    try {
      await _trailsCollection.doc(trailId).update({
        'geoHash': geohash,
        'geoHashes': geohashes,
      });
    } catch (e) {
      print('[PublicTrails] Errore updateTrailGeohash: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METODO LEGACY - Per compatibilità con codice esistente
  // ═══════════════════════════════════════════════════════════════════════════

  /// Metodo legacy per caricare sentieri in bounds (senza clustering)
  Future<List<PublicTrail>> getTrailsInBounds({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int limit = 100,
  }) async {
    return _loadFromFirestore(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      limit: limit,
      simplified: true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MODELLI RISULTATO
// ═══════════════════════════════════════════════════════════════════════════

/// Risultato query con supporto clustering
class TrailsResult {
  final List<TrailCluster> clusters;
  final List<PublicTrail> trails;
  final bool fromCache;
  
  const TrailsResult({
    required this.clusters,
    required this.trails,
    required this.fromCache,
  });
  
  bool get hasClusters => clusters.isNotEmpty;
  bool get hasTrails => trails.isNotEmpty;
  int get totalCount => hasClusters 
      ? clusters.fold(0, (sum, c) => sum + c.count)
      : trails.length;
}

/// Cluster di sentieri per zoom basso
class TrailCluster {
  final LatLng center;
  final int count;
  final ClusterBounds bounds;
  
  const TrailCluster({
    required this.center,
    required this.count,
    required this.bounds,
  });
}

class ClusterBounds {
  final double minLat, maxLat, minLng, maxLng;
  const ClusterBounds({
    required this.minLat, required this.maxLat,
    required this.minLng, required this.maxLng,
  });
}

/// Risultato verifica copertura GeoHash
class GeohashCoverage {
  final int withGeohash;
  final int withoutGeohash;
  
  const GeohashCoverage({
    required this.withGeohash,
    required this.withoutGeohash,
  });
  
  int get total => withGeohash + withoutGeohash;
  double get percentage => total > 0 ? (withGeohash / total * 100) : 0;
}

/// Modello PublicTrail (stesso di prima per compatibilità)
class PublicTrail {
  final String id;
  final String name;
  final String? ref;
  final String? network;
  final String? operator;
  final String? difficulty;
  final List<TrackPoint> points;
  final double? length;
  final double? elevationGain;
  final String? region;
  final bool isCircular;
  final String? quality;
  final int? duration;
  final double startLat;
  final double startLng;
  final double? distanceFromUser;
  final String? geohash;

  const PublicTrail({
    required this.id,
    required this.name,
    this.ref,
    this.network,
    this.operator,
    this.difficulty,
    required this.points,
    this.length,
    this.elevationGain,
    this.region,
    this.isCircular = false,
    this.quality,
    this.duration,
    this.startLat = 0,
    this.startLng = 0,
    this.distanceFromUser,
    this.geohash,
  });

  double get lengthKm => (length ?? 0) / 1000;
  String get displayName => ref != null && ref!.isNotEmpty ? '$ref - $name' : name;
  String get networkName => network ?? '';

  String get difficultyIcon {
    switch (difficulty?.toLowerCase()) {
      case 't': case 'turistico': case 'facile': return '🟢';
      case 'e': case 'escursionistico': case 'medio': return '🔵';
      case 'ee': case 'escursionisti esperti': case 'difficile': return '🟠';
      case 'eea': case 'alpinistico': return '🔴';
      default: return '⚪';
    }
  }

  String get difficultyName {
    switch (difficulty?.toLowerCase()) {
      case 't': return 'Turistico';
      case 'e': return 'Escursionistico';
      case 'ee': return 'Esperti';
      case 'eea': return 'Alpinistico';
      default: return difficulty ?? 'N/D';
    }
  }

  PublicTrail copyWith({double? distanceFromUser}) {
    return PublicTrail(
      id: id, name: name, ref: ref, network: network, operator: operator,
      difficulty: difficulty, points: points, length: length,
      elevationGain: elevationGain, region: region, isCircular: isCircular,
      quality: quality, duration: duration, startLat: startLat, startLng: startLng,
      distanceFromUser: distanceFromUser ?? this.distanceFromUser,
      geohash: geohash,
    );
  }

  /// Distanza dall'utente formattata
  String get distanceFromUserFormatted {
    if (distanceFromUser == null) return '';
    if (distanceFromUser! < 1000) {
      return '${distanceFromUser!.toStringAsFixed(0)} m';
    }
    return '${(distanceFromUser! / 1000).toStringAsFixed(1)} km';
  }

  /// Converte PublicTrail in Track per compatibilità con altre parti dell'app
  Track toTrack() {
    return Track(
      id: id,
      name: name,
      points: points,
      activityType: ActivityType.trekking,
      createdAt: DateTime.now(),
      isPublic: true,
      stats: TrackStats(
        distance: length ?? 0,
        elevationGain: elevationGain ?? 0,
        elevationLoss: 0,
        duration: Duration(minutes: duration ?? 0),
      ),
    );
  }
}
