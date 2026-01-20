import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/track.dart';
import '../../core/utils/geohash_util.dart';

/// Repository per i sentieri pubblici con supporto GeoHash per query geospaziali
/// 
/// Il GeoHash permette di fare query efficienti su milioni di documenti
/// senza caricare tutto in memoria.
class PublicTrailsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _trailsCollection {
    return _firestore.collection('public_trails');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUERY GEOHASH-BASED (SCALABILI)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Carica sentieri in un bounding box usando GeoHash
  /// 
  /// Questa è la query principale per la mappa. Scala a milioni di documenti.
  /// 
  /// [minLat], [maxLat], [minLng], [maxLng] - Bounding box
  /// [limit] - Limite per singola query (default 200)
  Future<List<PublicTrail>> getTrailsInBounds({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int limit = 200,
  }) async {
    try {
      // Prima prova con GeoHash (più efficiente se disponibile)
      // NOTA: Il campo si chiama 'geoHash' con H maiuscola nei documenti esistenti
      final geohashResults = await _getTrailsInBoundsGeohash(
        minLat: minLat,
        maxLat: maxLat,
        minLng: minLng,
        maxLng: maxLng,
        limit: limit,
      );
      
      // Se GeoHash ha trovato risultati, usali
      if (geohashResults.isNotEmpty) {
        return geohashResults;
      }
      
      // Altrimenti usa query legacy (documenti senza geohash)
      print('[PublicTrails] ⚠️ GeoHash vuoto, uso query legacy');
      return _getTrailsInBoundsLegacy(
        minLat: minLat,
        maxLat: maxLat,
        minLng: minLng,
        maxLng: maxLng,
        limit: limit,
      );
      
    } catch (e) {
      print('[PublicTrails] Errore getTrailsInBounds: $e');
      // Fallback alla query legacy
      return _getTrailsInBoundsLegacy(
        minLat: minLat,
        maxLat: maxLat,
        minLng: minLng,
        maxLng: maxLng,
        limit: limit,
      );
    }
  }

  /// Query con GeoHash (per documenti migrati)
  /// NOTA: Usa 'geoHash' con H maiuscola (campo esistente nei documenti)
  Future<List<PublicTrail>> _getTrailsInBoundsGeohash({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int limit = 200,
  }) async {
    // Calcola precisione geohash ottimale per l'area visualizzata
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final areaSizeKm = math.max(latDiff, lngDiff) * 111; // ~111 km per grado
    final precision = GeoHashUtil.precisionForRadius(areaSizeKm / 2);
    
    print('[PublicTrails] Query geoHash con precisione $precision per area ~${areaSizeKm.toStringAsFixed(0)}km');
    
    // Ottieni i range di geohash per la query
    final ranges = GeoHashUtil.getQueryRanges(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      precision: precision,
    );
    
    print('[PublicTrails] Eseguo ${ranges.length} query geoHash');
    
    // Esegui query parallele per ogni range
    final trails = <PublicTrail>[];
    final seenIds = <String>{};
    
    // Limita il numero di query parallele per evitare rate limiting
    final maxParallelQueries = math.min(ranges.length, 10);
    
    for (int i = 0; i < ranges.length; i += maxParallelQueries) {
      final batch = ranges.skip(i).take(maxParallelQueries);
      
      final futures = batch.map((range) async {
        try {
          // NOTA: Usa 'geoHash' con H maiuscola!
          final snapshot = await _trailsCollection
              .where('geoHash', isGreaterThanOrEqualTo: range.start)
              .where('geoHash', isLessThan: range.end)
              .limit(limit ~/ ranges.length + 10) // Distribuisci il limite
              .get();
          
          return snapshot.docs;
        } catch (e) {
          print('[PublicTrails] Errore query range ${range.start}: $e');
          return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        }
      });
      
      final results = await Future.wait(futures);
      
      for (final docs in results) {
        for (final doc in docs) {
          // Evita duplicati
          if (seenIds.contains(doc.id)) continue;
          seenIds.add(doc.id);
          
          final trail = _docToTrail(doc);
          if (trail != null) {
            // Verifica che sia effettivamente nel bounding box
            // (geohash può includere aree leggermente fuori)
            if (trail.startLat >= minLat && 
                trail.startLat <= maxLat &&
                trail.startLng >= minLng && 
                trail.startLng <= maxLng) {
              trails.add(trail);
            }
          }
        }
      }
      
      // Se abbiamo già abbastanza risultati, esci
      if (trails.length >= limit) break;
    }

    print('[PublicTrails] ✅ Trovati ${trails.length} sentieri (geoHash)');
    return trails.take(limit).toList();
  }

  /// Carica sentieri vicini a un punto usando GeoHash
  Future<List<PublicTrail>> getTrailsNearby({
    required LatLng center,
    double radiusKm = 30,
    int limit = 100,
  }) async {
    try {
      // Calcola bounding box dal centro e raggio
      final latDelta = radiusKm / 111.0; // ~111 km per grado di latitudine
      final lngDelta = radiusKm / (111.0 * math.cos(center.latitude * math.pi / 180));
      
      final trails = await getTrailsInBounds(
        minLat: center.latitude - latDelta,
        maxLat: center.latitude + latDelta,
        minLng: center.longitude - lngDelta,
        maxLng: center.longitude + lngDelta,
        limit: limit * 2, // Carica di più, filtreremo per distanza
      );
      
      // Calcola distanza effettiva e filtra per raggio
      final trailsWithDistance = <PublicTrail>[];
      for (final trail in trails) {
        final distance = _calculateDistance(
          center,
          LatLng(trail.startLat, trail.startLng),
        );
        
        if (distance <= radiusKm) {
          trailsWithDistance.add(trail.copyWith(distanceFromUser: distance));
        }
      }
      
      // Ordina per distanza
      trailsWithDistance.sort((a, b) => 
        (a.distanceFromUser ?? double.infinity)
            .compareTo(b.distanceFromUser ?? double.infinity)
      );
      
      print('[PublicTrails] ✅ Trovati ${trailsWithDistance.length} sentieri entro ${radiusKm}km');
      return trailsWithDistance.take(limit).toList();
      
    } catch (e) {
      print('[PublicTrails] Errore getTrailsNearby: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FALLBACK LEGACY (per documenti senza geohash)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Query legacy senza geohash (meno efficiente ma funziona sempre)
  Future<List<PublicTrail>> _getTrailsInBoundsLegacy({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int limit = 100,
  }) async {
    print('[PublicTrails] ⚠️ Usando query legacy (senza geohash)');
    
    try {
      // Carica documenti e filtra lato client
      // Questo è meno efficiente ma funziona sempre
      final snapshot = await _trailsCollection
          .limit(1000) // Carica più documenti per avere copertura
          .get();
      
      print('[PublicTrails] Legacy: caricati ${snapshot.docs.length} documenti da filtrare');
      
      final trails = <PublicTrail>[];
      for (final doc in snapshot.docs) {
        final trail = _docToTrail(doc);
        if (trail != null) {
          // Filtra per bounding box
          if (trail.startLat >= minLat && 
              trail.startLat <= maxLat &&
              trail.startLng >= minLng && 
              trail.startLng <= maxLng) {
            trails.add(trail);
          }
        }
        
        // Esci se abbiamo abbastanza risultati
        if (trails.length >= limit) break;
      }

      print('[PublicTrails] ✅ Trovati ${trails.length} sentieri (legacy)');
      return trails.take(limit).toList();
    } catch (e) {
      print('[PublicTrails] Errore query legacy: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ALTRE QUERY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Carica sentieri generici (fallback)
  Future<List<PublicTrail>> getTrails({int limit = 50}) async {
    try {
      final snapshot = await _trailsCollection.limit(limit).get();
      
      final trails = <PublicTrail>[];
      for (final doc in snapshot.docs) {
        final trail = _docToTrail(doc);
        if (trail != null) {
          trails.add(trail);
        }
      }

      print('[PublicTrails] Caricati ${trails.length} sentieri');
      return trails;
    } catch (e) {
      print('[PublicTrails] Errore: $e');
      return [];
    }
  }

  Future<List<PublicTrail>> getTrailsByRegion(String region, {int limit = 50}) async {
    try {
      final snapshot = await _trailsCollection
          .where('region', isEqualTo: region)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => _docToTrail(doc))
          .where((trail) => trail != null)
          .cast<PublicTrail>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<PublicTrail>> searchTrails(String query, {int limit = 20}) async {
    try {
      // Per la ricerca testuale, dobbiamo comunque caricare e filtrare
      // In futuro: usare Algolia o Firebase Extensions per full-text search
      final snapshot = await _trailsCollection.limit(500).get();
      final queryLower = query.toLowerCase();
      
      return snapshot.docs
          .map((doc) => _docToTrail(doc))
          .where((trail) => trail != null)
          .cast<PublicTrail>()
          .where((trail) =>
              trail.name.toLowerCase().contains(queryLower) ||
              (trail.ref?.toLowerCase().contains(queryLower) ?? false))
          .take(limit)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<PublicTrail?> getTrailById(String trailId) async {
    try {
      final doc = await _trailsCollection.doc(trailId).get();
      if (!doc.exists) return null;
      return _docToTrail(doc);
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIGRAZIONE GEOHASH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Aggiunge geohash a tutti i documenti che non ce l'hanno
  /// 
  /// Chiamare una sola volta o periodicamente per nuovi documenti.
  /// ATTENZIONE: Può richiedere molto tempo con milioni di documenti.
  Future<int> migrateToGeohash({int batchSize = 50}) async {
    int updated = 0;
    int processed = 0;
    int skipped = 0;
    int noCoords = 0;
    DocumentSnapshot? lastDoc;
    
    print('[PublicTrails] 🔄 Inizio migrazione geohash (batch: $batchSize)...');
    
    while (true) {
      // Carica batch di documenti
      Query<Map<String, dynamic>> query = _trailsCollection
          .limit(batchSize);
      
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }
      
      final snapshot = await query.get();
      
      if (snapshot.docs.isEmpty) {
        print('[PublicTrails] Nessun altro documento da processare');
        break;
      }
      
      final batch = _firestore.batch();
      int batchUpdates = 0;
      
      for (final doc in snapshot.docs) {
        processed++;
        final data = doc.data();
        
        // Salta se ha già geoHash (H maiuscola - campo esistente)
        if (data['geoHash'] != null && data['geoHash'].toString().isNotEmpty) {
          skipped++;
          continue;
        }
        
        // Estrai coordinate
        double? lat, lng;
        String coordSource = '';
        
        // 1. Prova startLat/startLng
        if (data['startLat'] != null && data['startLng'] != null) {
          lat = (data['startLat'] as num?)?.toDouble();
          lng = (data['startLng'] as num?)?.toDouble();
          coordSource = 'startLat/Lng';
        }
        
        // 2. Prova startPoint
        if (lat == null && data['startPoint'] != null) {
          final sp = data['startPoint'];
          if (sp is GeoPoint) {
            lat = sp.latitude;
            lng = sp.longitude;
            coordSource = 'startPoint GeoPoint';
          } else if (sp is Map) {
            lat = (sp['lat'] ?? sp['latitude'] as num?)?.toDouble();
            lng = (sp['lng'] ?? sp['lon'] ?? sp['longitude'] as num?)?.toDouble();
            coordSource = 'startPoint Map';
          }
        }
        
        // 3. Prova geometry.coordinatesJson
        if (lat == null) {
          final geometry = data['geometry'];
          if (geometry != null && geometry is Map) {
            final coordsJsonStr = geometry['coordinatesJson'];
            if (coordsJsonStr != null && coordsJsonStr is String) {
              try {
                final List<dynamic> coordsList = jsonDecode(coordsJsonStr);
                if (coordsList.isNotEmpty) {
                  final first = coordsList.first;
                  if (first is List && first.length >= 2) {
                    lng = (first[0] as num).toDouble();
                    lat = (first[1] as num).toDouble();
                    coordSource = 'geometry.coordinatesJson';
                  }
                }
              } catch (e) {
                print('[PublicTrails] Errore parsing geometry per ${doc.id}: $e');
              }
            }
          }
        }
        
        // 4. Prova points array
        if (lat == null && data['points'] != null) {
          final points = data['points'];
          if (points is List && points.isNotEmpty) {
            final first = points.first;
            if (first is Map) {
              lat = (first['lat'] ?? first['latitude'] ?? first['y'] as num?)?.toDouble();
              lng = (first['lng'] ?? first['lon'] ?? first['longitude'] ?? first['x'] as num?)?.toDouble();
              coordSource = 'points array';
            }
          }
        }
        
        // Debug: mostra primi documenti
        if (processed <= 3) {
          print('[PublicTrails] Doc ${doc.id}: lat=$lat, lng=$lng, source=$coordSource');
          print('[PublicTrails]   Keys: ${data.keys.toList()}');
        }
        
        if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
          final geohash = GeoHashUtil.encode(lat, lng, precision: 7);
          batch.update(doc.reference, {
            'geohash': geohash,
            'startLat': lat,
            'startLng': lng,
          });
          batchUpdates++;
          updated++;
        } else {
          noCoords++;
          if (noCoords <= 5) {
            print('[PublicTrails] ⚠️ Doc ${doc.id} senza coordinate valide');
            print('[PublicTrails]   Keys disponibili: ${data.keys.toList()}');
          }
        }
      }
      
      if (batchUpdates > 0) {
        await batch.commit();
      }
      
      print('[PublicTrails] Processati: $processed, Aggiornati: $updated, Saltati: $skipped, Senza coords: $noCoords');
      
      lastDoc = snapshot.docs.last;
      
      // Se abbiamo caricato meno del batch size, abbiamo finito
      if (snapshot.docs.length < batchSize) {
        break;
      }
      
      // Pausa per evitare rate limiting e liberare memoria
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    print('[PublicTrails] ✅ Migrazione completata: $updated documenti aggiornati, $noCoords senza coordinate');
    return updated;
  }

  /// Verifica quanti documenti hanno geoHash
  /// NOTA: Il campo si chiama 'geoHash' con H maiuscola
  Future<({int withGeohash, int withoutGeohash})> checkGeohashCoverage() async {
    try {
      // Carica un campione di documenti per verificare
      final snapshot = await _trailsCollection.limit(500).get();
      
      int withGeohash = 0;
      int withoutGeohash = 0;
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Controlla 'geoHash' (H maiuscola) - il campo esistente nei documenti
        if (data['geoHash'] != null && data['geoHash'].toString().isNotEmpty) {
          withGeohash++;
        } else {
          withoutGeohash++;
        }
      }
      
      print('[PublicTrails] Coverage check: $withGeohash con geoHash, $withoutGeohash senza');
      
      return (
        withGeohash: withGeohash,
        withoutGeohash: withoutGeohash,
      );
    } catch (e) {
      print('[PublicTrails] Errore verifica coverage: $e');
      return (withGeohash: 0, withoutGeohash: 0);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calcola distanza tra due punti in km usando formula Haversine
  double _calculateDistance(LatLng p1, LatLng p2) {
    const earthRadius = 6371.0; // km
    
    final dLat = _toRadians(p2.latitude - p1.latitude);
    final dLng = _toRadians(p2.longitude - p1.longitude);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(p1.latitude)) * 
        math.cos(_toRadians(p2.latitude)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  PublicTrail? _docToTrail(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) return null;

      List<TrackPoint> points = [];
      
      // geometry è un Map con {type, coordinatesJson}
      final geometry = data['geometry'];
      
      if (geometry != null && geometry is Map) {
        final coordsJsonStr = geometry['coordinatesJson'];
        
        if (coordsJsonStr != null && coordsJsonStr is String) {
          // Parse la stringa JSON
          final List<dynamic> coordsList = jsonDecode(coordsJsonStr);
          
          // Ogni elemento è [lon, lat, ele]
          for (var p in coordsList) {
            if (p is List && p.length >= 2) {
              final lon = (p[0] as num).toDouble();
              final lat = (p[1] as num).toDouble();
              final ele = p.length > 2 && p[2] != null ? (p[2] as num).toDouble() : null;
              
              if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
                points.add(TrackPoint(
                  longitude: lon,
                  latitude: lat,
                  elevation: ele,
                  timestamp: DateTime.now(),
                ));
              }
            }
          }
        }
      }

      if (points.isEmpty) {
        return null;
      }

      String name = data['name']?.toString() ?? '';
      final ref = data['ref']?.toString();
      if (name.isEmpty && ref != null) name = 'Sentiero $ref';
      if (name.isEmpty) name = 'Sentiero';

      // Estrai startPoint se presente, altrimenti usa il primo punto
      double? startLat;
      double? startLng;
      
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
      
      // Fallback al primo punto
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
        geohash: data['geoHash']?.toString(), // NOTA: 'geoHash' con H maiuscola!
      );
    } catch (e) {
      print('[PublicTrails] Errore parsing ${doc.id}: $e');
      return null;
    }
  }
}

/// Modello per sentiero pubblico
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
  final String? geohash; // ⭐ NUOVO: GeoHash per query efficienti

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

  String get displayName {
    if (ref != null && ref!.isNotEmpty) {
      return '$ref - $name';
    }
    return name;
  }
  
  /// Nome della rete sentieristica (es. "CAI Bergamo")
  String get networkName => network ?? '';

  String get distanceFromUserFormatted {
    if (distanceFromUser == null) return '';
    if (distanceFromUser! < 1) {
      return '${(distanceFromUser! * 1000).toStringAsFixed(0)} m';
    }
    return '${distanceFromUser!.toStringAsFixed(1)} km';
  }

  String get difficultyIcon {
    switch (difficulty?.toLowerCase()) {
      case 't':
      case 'turistico':
      case 'facile':
      case 'easy':
        return '🟢';
      case 'e':
      case 'escursionistico':
      case 'medio':
      case 'medium':
        return '🔵';
      case 'ee':
      case 'escursionisti esperti':
      case 'difficile':
      case 'hard':
        return '🟠';
      case 'eea':
      case 'alpinistico':
      case 'molto difficile':
        return '🔴';
      default:
        return '⚪';
    }
  }

  String get difficultyName {
    switch (difficulty?.toLowerCase()) {
      case 't':
        return 'Turistico';
      case 'e':
        return 'Escursionistico';
      case 'ee':
        return 'Esperti';
      case 'eea':
        return 'Alpinistico';
      default:
        return difficulty ?? 'N/D';
    }
  }
  
  /// Converte in Track per compatibilità con widget esistenti
  Track toTrack() {
    return Track(
      id: 'public_$id',
      name: displayName,
      description: 'Sentiero ${ref ?? ""} - ${network ?? ""}',
      points: points,
      activityType: ActivityType.trekking,
      createdAt: DateTime.now(),
      stats: TrackStats(
        distance: length ?? 0,
        elevationGain: elevationGain ?? 0,
        duration: Duration(minutes: duration ?? 0),
      ),
    );
  }

  /// Crea una copia con valori modificati
  PublicTrail copyWith({
    String? id,
    String? name,
    String? ref,
    String? network,
    String? operator,
    String? difficulty,
    List<TrackPoint>? points,
    double? length,
    double? elevationGain,
    String? region,
    bool? isCircular,
    String? quality,
    int? duration,
    double? startLat,
    double? startLng,
    double? distanceFromUser,
    String? geohash,
  }) {
    return PublicTrail(
      id: id ?? this.id,
      name: name ?? this.name,
      ref: ref ?? this.ref,
      network: network ?? this.network,
      operator: operator ?? this.operator,
      difficulty: difficulty ?? this.difficulty,
      points: points ?? this.points,
      length: length ?? this.length,
      elevationGain: elevationGain ?? this.elevationGain,
      region: region ?? this.region,
      isCircular: isCircular ?? this.isCircular,
      quality: quality ?? this.quality,
      duration: duration ?? this.duration,
      startLat: startLat ?? this.startLat,
      startLng: startLng ?? this.startLng,
      distanceFromUser: distanceFromUser ?? this.distanceFromUser,
      geohash: geohash ?? this.geohash,
    );
  }
}
