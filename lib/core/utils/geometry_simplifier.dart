import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Utility per semplificazione geometrie
/// 
/// Usa algoritmo Douglas-Peucker per ridurre il numero di punti
/// mantenendo la forma del percorso.
class GeometrySimplifier {
  
  /// Semplifica una lista di coordinate usando Douglas-Peucker
  /// 
  /// [points] - Lista di coordinate originali
  /// [tolerance] - Tolleranza in gradi (default 0.0001 ≈ 11 metri)
  /// [maxPoints] - Numero massimo di punti nel risultato
  static List<LatLng> simplify(
    List<LatLng> points, {
    double tolerance = 0.0001,
    int maxPoints = 30,
  }) {
    if (points.length <= 2) return points;
    if (points.length <= maxPoints) return points;
    
    // Prima passa: Douglas-Peucker
    var simplified = _douglasPeucker(points, tolerance);
    
    // Se ancora troppi punti, aumenta tolleranza
    int iterations = 0;
    while (simplified.length > maxPoints && iterations < 10) {
      tolerance *= 2;
      simplified = _douglasPeucker(points, tolerance);
      iterations++;
    }
    
    // Se ancora troppi, campiona uniformemente
    if (simplified.length > maxPoints) {
      simplified = _uniformSample(simplified, maxPoints);
    }
    
    return simplified;
  }
  
  /// Algoritmo Douglas-Peucker
  static List<LatLng> _douglasPeucker(List<LatLng> points, double tolerance) {
    if (points.length < 3) return List.from(points);
    
    // Trova il punto più lontano dalla linea start-end
    double maxDistance = 0;
    int maxIndex = 0;
    
    final start = points.first;
    final end = points.last;
    
    for (int i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(points[i], start, end);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }
    
    // Se il punto più lontano supera la tolleranza, divide e ricorri
    if (maxDistance > tolerance) {
      final left = _douglasPeucker(points.sublist(0, maxIndex + 1), tolerance);
      final right = _douglasPeucker(points.sublist(maxIndex), tolerance);
      
      // Unisci (rimuovi duplicato al punto di giunzione)
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      // Tutti i punti intermedi possono essere rimossi
      return [start, end];
    }
  }
  
  /// Calcola distanza perpendicolare di un punto da una linea
  static double _perpendicularDistance(LatLng point, LatLng lineStart, LatLng lineEnd) {
    final dx = lineEnd.longitude - lineStart.longitude;
    final dy = lineEnd.latitude - lineStart.latitude;
    
    // Linea degenere (start == end)
    if (dx == 0 && dy == 0) {
      return _distance(point, lineStart);
    }
    
    // Proiezione del punto sulla linea
    final t = ((point.longitude - lineStart.longitude) * dx + 
               (point.latitude - lineStart.latitude) * dy) / (dx * dx + dy * dy);
    
    // Punto più vicino sulla linea
    final nearestLng = lineStart.longitude + t * dx;
    final nearestLat = lineStart.latitude + t * dy;
    
    return _distance(point, LatLng(nearestLat, nearestLng));
  }
  
  /// Distanza euclidea semplice (per coordinate vicine va bene)
  static double _distance(LatLng a, LatLng b) {
    final dx = a.longitude - b.longitude;
    final dy = a.latitude - b.latitude;
    return math.sqrt(dx * dx + dy * dy);
  }
  
  /// Campionamento uniforme
  static List<LatLng> _uniformSample(List<LatLng> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    
    final result = <LatLng>[points.first];
    final step = (points.length - 1) / (maxPoints - 1);
    
    for (int i = 1; i < maxPoints - 1; i++) {
      final index = (i * step).round();
      if (index < points.length) {
        result.add(points[index]);
      }
    }
    
    result.add(points.last);
    return result;
  }
  
  /// Calcola bounding box di una lista di punti
  static LatLngBounds getBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(const LatLng(0, 0), const LatLng(0, 0));
    }
    
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    
    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }
  
  /// Calcola il centro di una lista di punti
  static LatLng getCenter(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    
    final bounds = getBounds(points);
    return LatLng(
      (bounds.southWest.latitude + bounds.northEast.latitude) / 2,
      (bounds.southWest.longitude + bounds.northEast.longitude) / 2,
    );
  }
}

/// Classe LatLngBounds se non disponibile
class LatLngBounds {
  final LatLng southWest;
  final LatLng northEast;
  
  const LatLngBounds(this.southWest, this.northEast);
  
  double get south => southWest.latitude;
  double get north => northEast.latitude;
  double get west => southWest.longitude;
  double get east => northEast.longitude;
}
