import 'dart:math' as math;

/// Utility per calcolo e manipolazione GeoHash
/// 
/// GeoHash è un sistema di geocoding che codifica coordinate geografiche
/// in una stringa alfanumerica. Punti vicini hanno prefissi comuni.
/// 
/// Precisione (caratteri -> area approssimativa):
/// - 1: ~5000 km
/// - 2: ~1250 km
/// - 3: ~156 km
/// - 4: ~39 km
/// - 5: ~4.9 km
/// - 6: ~1.2 km
/// - 7: ~153 m
/// - 8: ~38 m
/// - 9: ~4.8 m
class GeoHashUtil {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  
  /// Calcola il geohash per una coppia lat/lng
  /// 
  /// [latitude] - Latitudine (-90 a 90)
  /// [longitude] - Longitudine (-180 a 180)
  /// [precision] - Numero di caratteri (default 7 ≈ 153m)
  static String encode(double latitude, double longitude, {int precision = 7}) {
    double minLat = -90.0, maxLat = 90.0;
    double minLng = -180.0, maxLng = 180.0;
    
    final buffer = StringBuffer();
    bool isEven = true;
    int bit = 0;
    int ch = 0;
    
    while (buffer.length < precision) {
      if (isEven) {
        // Longitude
        final mid = (minLng + maxLng) / 2;
        if (longitude >= mid) {
          ch |= (1 << (4 - bit));
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        // Latitude
        final mid = (minLat + maxLat) / 2;
        if (latitude >= mid) {
          ch |= (1 << (4 - bit));
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }
      
      isEven = !isEven;
      
      if (bit < 4) {
        bit++;
      } else {
        buffer.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    
    return buffer.toString();
  }
  
  /// Decodifica un geohash in coordinate (centro del rettangolo)
  static ({double latitude, double longitude}) decode(String geohash) {
    double minLat = -90.0, maxLat = 90.0;
    double minLng = -180.0, maxLng = 180.0;
    bool isEven = true;
    
    for (int i = 0; i < geohash.length; i++) {
      final ch = _base32.indexOf(geohash[i].toLowerCase());
      if (ch == -1) continue;
      
      for (int bit = 4; bit >= 0; bit--) {
        final mask = 1 << bit;
        if (isEven) {
          // Longitude
          final mid = (minLng + maxLng) / 2;
          if ((ch & mask) != 0) {
            minLng = mid;
          } else {
            maxLng = mid;
          }
        } else {
          // Latitude
          final mid = (minLat + maxLat) / 2;
          if ((ch & mask) != 0) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        isEven = !isEven;
      }
    }
    
    return (
      latitude: (minLat + maxLat) / 2,
      longitude: (minLng + maxLng) / 2,
    );
  }
  
  /// Calcola i geohash che coprono un bounding box
  /// 
  /// Restituisce una lista di prefissi geohash che coprono l'area.
  /// Utile per query Firestore con range.
  static List<String> getBoundingBoxHashes({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int precision = 5,
  }) {
    final hashes = <String>{};
    
    // Calcola step size basato sulla precisione
    // Approssimazione: ogni livello di precisione divide per ~8 in lat e ~4 in lng
    final latStep = 180.0 / math.pow(8, precision / 2);
    final lngStep = 360.0 / math.pow(4, (precision + 1) / 2);
    
    // Itera sul bounding box e raccogli tutti i geohash unici
    double lat = minLat;
    while (lat <= maxLat) {
      double lng = minLng;
      while (lng <= maxLng) {
        final hash = encode(lat, lng, precision: precision);
        hashes.add(hash);
        lng += lngStep * 0.5; // Overlap per sicurezza
      }
      lat += latStep * 0.5;
    }
    
    // Aggiungi anche i corner
    hashes.add(encode(minLat, minLng, precision: precision));
    hashes.add(encode(minLat, maxLng, precision: precision));
    hashes.add(encode(maxLat, minLng, precision: precision));
    hashes.add(encode(maxLat, maxLng, precision: precision));
    
    return hashes.toList();
  }
  
  /// Ottiene i geohash vicini (8 direzioni + centro)
  static List<String> getNeighbors(String geohash) {
    final decoded = decode(geohash);
    final precision = geohash.length;
    
    // Calcola delta basato sulla precisione
    final delta = 180.0 / math.pow(2, precision * 2.5);
    
    final neighbors = <String>[];
    for (int dlat = -1; dlat <= 1; dlat++) {
      for (int dlng = -1; dlng <= 1; dlng++) {
        final lat = decoded.latitude + (dlat * delta);
        final lng = decoded.longitude + (dlng * delta);
        
        if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
          neighbors.add(encode(lat, lng, precision: precision));
        }
      }
    }
    
    return neighbors.toSet().toList(); // Rimuovi duplicati
  }
  
  /// Calcola la precisione ottimale per un raggio di ricerca
  /// 
  /// [radiusKm] - Raggio in km
  /// Restituisce la precisione del geohash che copre approssimativamente quell'area
  static int precisionForRadius(double radiusKm) {
    if (radiusKm >= 2500) return 1;
    if (radiusKm >= 630) return 2;
    if (radiusKm >= 78) return 3;
    if (radiusKm >= 20) return 4;
    if (radiusKm >= 2.4) return 5;
    if (radiusKm >= 0.61) return 6;
    if (radiusKm >= 0.076) return 7;
    if (radiusKm >= 0.019) return 8;
    return 9;
  }
  
  /// Genera query ranges per Firestore
  /// 
  /// Restituisce una lista di coppie (start, end) per query whereGreaterThanOrEqualTo/whereLessThan
  static List<({String start, String end})> getQueryRanges({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int precision = 5,
  }) {
    final hashes = getBoundingBoxHashes(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      precision: precision,
    );
    
    // Raggruppa hash con stesso prefisso per ridurre il numero di query
    final prefixMap = <String, List<String>>{};
    for (final hash in hashes) {
      final prefix = hash.substring(0, math.min(precision - 1, hash.length));
      prefixMap.putIfAbsent(prefix, () => []).add(hash);
    }
    
    // Genera ranges
    final ranges = <({String start, String end})>[];
    for (final entry in prefixMap.entries) {
      final sorted = entry.value..sort();
      ranges.add((
        start: sorted.first,
        end: sorted.last + '~', // ~ è dopo tutti i caratteri base32
      ));
    }
    
    return ranges;
  }
}
