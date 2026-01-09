import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/track.dart';

/// Repository per i sentieri pubblici
class PublicTrailsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _trailsCollection {
    return _firestore.collection('public_trails');
  }

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
  });

  String get displayName => ref != null && ref!.isNotEmpty ? '$name ($ref)' : name;
  double get lengthKm => (length ?? 0) / 1000;

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
