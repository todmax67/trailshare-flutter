import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/track.dart';

/// Repository per i sentieri pubblici con supporto geolocalizzazione
class PublicTrailsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _trailsCollection {
    return _firestore.collection('public_trails');
  }

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

  /// Carica sentieri vicini alla posizione specificata
  /// 
  /// [center] - Posizione centrale (es. posizione utente)
  /// [radiusKm] - Raggio di ricerca in km
  /// [limit] - Numero massimo di sentieri da caricare
  Future<List<PublicTrail>> getTrailsNearby({
    required LatLng center,
    double radiusKm = 30,
    int limit = 100,
  }) async {
    try {
      // Firestore non supporta query geospaziali native senza GeoHash
      // Quindi carichiamo più sentieri e filtriamo lato client
      // 
      // Per ottimizzare in futuro: aggiungere campo 'geohash' ai documenti
      // e usare query con range su quel campo
      
      final snapshot = await _trailsCollection
          .limit(500) // Carichiamo di più per avere abbastanza scelta
          .get();
      
      final trails = <PublicTrail>[];
      for (final doc in snapshot.docs) {
        final trail = _docToTrail(doc);
        if (trail != null) {
          // Calcola distanza dal centro al punto di partenza del sentiero
          final distance = _calculateDistance(
            center,
            LatLng(trail.startLat, trail.startLng),
          );
          
          // Filtra per raggio
          if (distance <= radiusKm) {
            trails.add(trail.copyWith(distanceFromUser: distance));
          }
        }
      }

      // Ordina per distanza
      trails.sort((a, b) => 
        (a.distanceFromUser ?? double.infinity)
            .compareTo(b.distanceFromUser ?? double.infinity)
      );

      // Limita risultati
      final result = trails.take(limit).toList();
      
      print('[PublicTrails] Trovati ${result.length} sentieri entro ${radiusKm}km');
      return result;
    } catch (e) {
      print('[PublicTrails] Errore getTrailsNearby: $e');
      return [];
    }
  }

  /// Carica sentieri in un bounding box
  Future<List<PublicTrail>> getTrailsInBounds({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int limit = 100,
  }) async {
    try {
      // Firestore non supporta query su due campi con range diversi
      // Quindi carichiamo e filtriamo lato client
      final snapshot = await _trailsCollection.limit(500).get();
      
      final trails = <PublicTrail>[];
      for (final doc in snapshot.docs) {
        final trail = _docToTrail(doc);
        if (trail != null) {
          // Verifica se il punto di partenza è nel bounding box
          if (trail.startLat >= minLat && 
              trail.startLat <= maxLat &&
              trail.startLng >= minLng && 
              trail.startLng <= maxLng) {
            trails.add(trail);
          }
        }
      }

      print('[PublicTrails] Trovati ${trails.length} sentieri nel bounding box');
      return trails.take(limit).toList();
    } catch (e) {
      print('[PublicTrails] Errore getTrailsInBounds: $e');
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
      final snapshot = await _trailsCollection.limit(200).get();
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
  final double? distanceFromUser; // Distanza dalla posizione utente in km

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
  });

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
    );
  }

  String get displayName => ref != null && ref!.isNotEmpty ? '$name ($ref)' : name;
  double get lengthKm => (length ?? 0) / 1000;

  /// Distanza formattata dall'utente
  String get distanceFromUserFormatted {
    if (distanceFromUser == null) return '';
    if (distanceFromUser! < 1) {
      return '${(distanceFromUser! * 1000).toStringAsFixed(0)} m';
    }
    return '${distanceFromUser!.toStringAsFixed(1)} km';
  }

  String get difficultyIcon {
    switch (difficulty?.toLowerCase()) {
      case 'facile': return '🟢';
      case 'media': return '🔵';
      case 'difficile': return '🔴';
      default: return '⚪';
    }
  }

  String get difficultyName {
    switch (difficulty?.toLowerCase()) {
      case 'facile': return 'Facile';
      case 'media': return 'Media';
      case 'difficile': return 'Difficile';
      default: return 'Non classificato';
    }
  }

  String get networkName {
    switch (network) {
      case 'lwn': return 'Locale';
      case 'rwn': return 'Regionale';
      case 'nwn': return 'Nazionale';
      case 'iwn': return 'Internazionale';
      default: return '';
    }
  }

  String get durationFormatted {
    if (duration == null || duration == 0) return '--';
    final hours = duration! ~/ 3600;
    final mins = (duration! % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  Track toTrack() {
    return Track(
      id: 'osm_$id',
      name: displayName,
      description: _buildDescription(),
      points: points,
      activityType: ActivityType.trekking,
      createdAt: DateTime.now(),
      stats: TrackStats(
        distance: length ?? 0,
        elevationGain: elevationGain ?? 0,
      ),
    );
  }

  String _buildDescription() {
    final parts = <String>[];
    if (operator != null) parts.add('Gestore: $operator');
    if (networkName.isNotEmpty) parts.add('Rete: $networkName');
    if (difficulty != null) parts.add('Difficoltà: $difficultyName');
    if (isCircular) parts.add('Percorso ad anello');
    return parts.join('\n');
  }
}
