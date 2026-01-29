import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';

/// Cache locale per sentieri pubblici
/// 
/// Usa Hive per storage veloce e persistente.
/// I sentieri sono cachati per zona (geohash prefix).
class TrailsCacheService {
  static const String _boxName = 'trails_cache';
  static const String _metaBoxName = 'trails_cache_meta';
  
  // Durata cache: 24 ore
  static const Duration _cacheDuration = Duration(hours: 24);
  
  Box<String>? _box;
  Box<String>? _metaBox;
  
  bool _isInitialized = false;
  
  /// Inizializza il servizio cache
  Future<void> init() async {
    if (_isInitialized) return;
    
    try {
      await Hive.initFlutter();
      _box = await Hive.openBox<String>(_boxName);
      _metaBox = await Hive.openBox<String>(_metaBoxName);
      _isInitialized = true;
      print('[TrailsCache] ✅ Inizializzato');
    } catch (e) {
      print('[TrailsCache] ❌ Errore inizializzazione: $e');
    }
  }
  
  /// Genera chiave cache per una zona (basata su geohash a 4 caratteri ~40km)
  String _getZoneKey(double minLat, double maxLat, double minLng, double maxLng) {
    // Usa il centro della zona per generare un geohash semplificato
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final geohash = _encodeGeohash(centerLat, centerLng, 4);
    return 'zone_$geohash';
  }
  
  /// Salva sentieri in cache per una zona
  Future<void> cacheTrailsForZone({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required List<CachedTrail> trails,
  }) async {
    if (!_isInitialized || _box == null) return;
    
    try {
      final key = _getZoneKey(minLat, maxLat, minLng, maxLng);
      final data = trails.map((t) => t.toJson()).toList();
      await _box!.put(key, jsonEncode(data));
      
      // Salva timestamp
      await _metaBox!.put('${key}_timestamp', DateTime.now().toIso8601String());
      
      print('[TrailsCache] 💾 Salvati ${trails.length} sentieri per $key');
    } catch (e) {
      print('[TrailsCache] Errore salvataggio: $e');
    }
  }
  
  /// Recupera sentieri dalla cache per una zona
  Future<List<CachedTrail>?> getTrailsForZone({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) async {
    if (!_isInitialized || _box == null) return null;
    
    try {
      final key = _getZoneKey(minLat, maxLat, minLng, maxLng);
      
      // Verifica se cache è scaduta
      final timestampStr = _metaBox!.get('${key}_timestamp');
      if (timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        if (DateTime.now().difference(timestamp) > _cacheDuration) {
          print('[TrailsCache] ⏰ Cache scaduta per $key');
          return null;
        }
      }
      
      final data = _box!.get(key);
      if (data == null) return null;
      
      final List<dynamic> jsonList = jsonDecode(data);
      final trails = jsonList.map((j) => CachedTrail.fromJson(j)).toList();
      
      print('[TrailsCache] ⚡ Cache hit: ${trails.length} sentieri per $key');
      return trails;
    } catch (e) {
      print('[TrailsCache] Errore lettura: $e');
      return null;
    }
  }
  
  /// Invalida tutta la cache (da chiamare dopo import nuovi sentieri)
  Future<void> invalidateAll() async {
    if (!_isInitialized) return;
    
    try {
      await _box?.clear();
      await _metaBox?.clear();
      print('[TrailsCache] 🗑️ Cache invalidata');
    } catch (e) {
      print('[TrailsCache] Errore invalidazione: $e');
    }
  }
  
  /// Invalida cache per una zona specifica
  Future<void> invalidateZone(String geohashPrefix) async {
    if (!_isInitialized || _box == null) return;
    
    final keysToDelete = _box!.keys.where((k) => k.toString().contains(geohashPrefix)).toList();
    for (final key in keysToDelete) {
      await _box!.delete(key);
      await _metaBox!.delete('${key}_timestamp');
    }
  }
  
  /// Statistiche cache
  Future<Map<String, dynamic>> getStats() async {
    if (!_isInitialized || _box == null) {
      return {'initialized': false};
    }
    
    return {
      'initialized': true,
      'zonesCount': _box!.length,
      'sizeBytes': _box!.keys.fold<int>(0, (sum, k) => sum + (_box!.get(k)?.length ?? 0)),
    };
  }
  
  /// Encode geohash semplice
  String _encodeGeohash(double lat, double lng, int precision) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    
    double minLat = -90, maxLat = 90;
    double minLng = -180, maxLng = 180;
    String hash = '';
    int bit = 0;
    int ch = 0;
    bool isLon = true;
    
    while (hash.length < precision) {
      if (isLon) {
        final mid = (minLng + maxLng) / 2;
        if (lng >= mid) {
          ch |= 1 << (4 - bit);
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (lat >= mid) {
          ch |= 1 << (4 - bit);
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }
      isLon = !isLon;
      if (bit < 4) {
        bit++;
      } else {
        hash += base32[ch];
        bit = 0;
        ch = 0;
      }
    }
    
    return hash;
  }
}

/// Modello leggero per sentiero in cache
/// Contiene solo i dati necessari per visualizzazione mappa/lista
class CachedTrail {
  final String id;
  final String name;
  final String? ref;
  final String? difficulty;
  final double? length;
  final double? elevationGain;
  final bool isCircular;
  final double startLat;
  final double startLng;
  final String? network;
  
  /// Coordinate semplificate per polyline su mappa (max 30 punti)
  final List<LatLng> simplifiedCoords;
  
  const CachedTrail({
    required this.id,
    required this.name,
    this.ref,
    this.difficulty,
    this.length,
    this.elevationGain,
    this.isCircular = false,
    required this.startLat,
    required this.startLng,
    this.network,
    required this.simplifiedCoords,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ref': ref,
    'difficulty': difficulty,
    'length': length,
    'elevationGain': elevationGain,
    'isCircular': isCircular,
    'startLat': startLat,
    'startLng': startLng,
    'network': network,
    'coords': simplifiedCoords.map((c) => [c.latitude, c.longitude]).toList(),
  };
  
  factory CachedTrail.fromJson(Map<String, dynamic> json) {
    final coordsList = (json['coords'] as List?) ?? [];
    final coords = coordsList.map((c) => LatLng(c[0] as double, c[1] as double)).toList();
    
    return CachedTrail(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      ref: json['ref'] as String?,
      difficulty: json['difficulty'] as String?,
      length: (json['length'] as num?)?.toDouble(),
      elevationGain: (json['elevationGain'] as num?)?.toDouble(),
      isCircular: json['isCircular'] as bool? ?? false,
      startLat: (json['startLat'] as num?)?.toDouble() ?? 0,
      startLng: (json['startLng'] as num?)?.toDouble() ?? 0,
      network: json['network'] as String?,
      simplifiedCoords: coords,
    );
  }
  
  double get lengthKm => (length ?? 0) / 1000;
}

/// Singleton instance
final trailsCacheService = TrailsCacheService();
