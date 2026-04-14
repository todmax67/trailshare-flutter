import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../../data/models/navigation_step.dart';

/// Helper stateless per i calcoli geometrici della navigazione turn-by-turn.
class NavigationService {
  /// Trova l'indice del punto del polyline più vicino alla posizione utente.
  /// Limita la ricerca a partire da [minIndex] per evitare "salti indietro"
  /// sul percorso (ottimizzazione quando si sta navigando in avanti).
  static int findNearestPointIndex(
    List<LatLng> points,
    LatLng user, {
    int minIndex = 0,
  }) {
    if (points.isEmpty) return 0;
    double bestDist = double.infinity;
    int bestIdx = minIndex;
    for (var i = minIndex; i < points.length; i++) {
      final d = distanceMeters(points[i], user);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// Distanza Haversine tra due coordinate (in metri).
  static double distanceMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final sinLat = math.sin(dLat / 2);
    final sinLon = math.sin(dLon / 2);
    final h = sinLat * sinLat +
        math.cos(_deg2rad(a.latitude)) *
            math.cos(_deg2rad(b.latitude)) *
            sinLon * sinLon;
    return 2 * R * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  /// Distanza minima tra [user] e il polyline (usata per off-route detection).
  static double distanceToPolyline(List<LatLng> points, LatLng user) {
    if (points.isEmpty) return double.infinity;
    double best = double.infinity;
    for (final p in points) {
      final d = distanceMeters(p, user);
      if (d < best) best = d;
    }
    return best;
  }

  /// Distanza residua lungo il polyline dall'indice corrente alla fine dello step.
  /// Somma la distanza dall'utente al punto successivo + i segmenti fino al way_point finale.
  static double remainingDistanceInStep(
    List<LatLng> points,
    int userIndex,
    LatLng userPos,
    NavigationStep step,
  ) {
    if (points.isEmpty || userIndex >= points.length) return 0;
    // Clamp alla fine dello step
    final endIdx = math.min(step.wayPointEnd, points.length - 1);
    if (userIndex >= endIdx) return 0;

    // Tratto dall'utente al punto del polyline successivo
    double total = distanceMeters(userPos, points[userIndex + 1]);
    for (var i = userIndex + 1; i < endIdx; i++) {
      total += distanceMeters(points[i], points[i + 1]);
    }
    return total;
  }

  /// Somma le distanze tra tutti i punti da [fromIndex] fino a fine polyline.
  static double remainingDistanceTotal(
    List<LatLng> points,
    int fromIndex,
    LatLng userPos,
  ) {
    if (points.isEmpty || fromIndex >= points.length - 1) return 0;
    double total = distanceMeters(userPos, points[fromIndex + 1]);
    for (var i = fromIndex + 1; i < points.length - 1; i++) {
      total += distanceMeters(points[i], points[i + 1]);
    }
    return total;
  }

  /// Trova lo step "corrente" in base all'indice utente sul polyline.
  /// Restituisce lo step il cui wayPointEnd è >= userIndex (ancora da raggiungere).
  static NavigationStep? currentStep(
    List<NavigationStep> steps,
    int userIndex,
  ) {
    for (final s in steps) {
      if (s.wayPointEnd >= userIndex) return s;
    }
    return steps.isNotEmpty ? steps.last : null;
  }

  /// Prossimo step dopo quello corrente (per anteprima UI).
  static NavigationStep? nextStep(
    List<NavigationStep> steps,
    NavigationStep? current,
  ) {
    if (current == null) return null;
    final nextIdx = current.index + 1;
    if (nextIdx >= steps.length) return null;
    return steps[nextIdx];
  }

  static double _deg2rad(double deg) => deg * math.pi / 180;
}
