import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../utils/elevation_processor.dart';
import '../../data/models/navigation_step.dart';

/// Punto con elevazione per il routing
class RoutePoint {
  final double latitude;
  final double longitude;
  final double? elevation;
  final double? distanceFromStart; // metri

  const RoutePoint({
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.distanceFromStart,
  });

  LatLng get latLng => LatLng(latitude, longitude);
}

/// Risultato del routing
class RouteResult {
  final List<RoutePoint> points;
  final double distance; // metri
  final double elevationGain; // metri
  final double elevationLoss; // metri
  final double estimatedDuration; // secondi
  final List<double> elevationProfile; // elevazioni lungo il percorso
  final List<NavigationStep> steps; // istruzioni turn-by-turn (opzionale)

  const RouteResult({
    required this.points,
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    required this.estimatedDuration,
    required this.elevationProfile,
    this.steps = const [],
  });

  double get distanceKm => distance / 1000;
  
  String get durationFormatted {
    final hours = (estimatedDuration / 3600).floor();
    final mins = ((estimatedDuration % 3600) / 60).floor();
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}

/// Tipo di attività per il routing
enum RoutingProfile {
  hiking,
  cycling,
}

/// Servizio per calcolare percorsi tramite Cloud Function proxy ORS
class RoutingService {
  final String proxyBaseUrl;

  RoutingService({required this.proxyBaseUrl});

  /// Calcola un percorso tra waypoint
  /// [waypoints] - Lista di punti (minimo 2)
  /// [profile] - Tipo di attività (hiking/cycling)
  Future<RouteResult?> calculateRoute(
    List<LatLng> waypoints, {
    RoutingProfile profile = RoutingProfile.hiking,
  }) async {
    if (waypoints.length < 2) {
      debugPrint('[RoutingService] Servono almeno 2 waypoint');
      return null;
    }

    try {
      final profileString = _getProfileString(profile);
      final url = Uri.parse('$proxyBaseUrl/v2/directions/$profileString/geojson');

      // Costruisci il body della richiesta
      final coordinates = waypoints
          .map((p) => [p.longitude, p.latitude])
          .toList();

      final body = jsonEncode({
        'coordinates': coordinates,
        'elevation': true,
        'instructions': true,
        'geometry_simplify': false,
      });

      debugPrint('[RoutingService] Richiesta routing: ${waypoints.length} waypoint, profilo: $profileString');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        debugPrint('[RoutingService] Errore API: ${response.statusCode} - ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);
      return _parseRouteResponse(data);
    } catch (e) {
      debugPrint('[RoutingService] Errore: $e');
      return null;
    }
  }

  String _getProfileString(RoutingProfile profile) {
    switch (profile) {
      case RoutingProfile.hiking:
        return 'foot-hiking';
      case RoutingProfile.cycling:
        return 'cycling-mountain';
    }
  }

  RouteResult? _parseRouteResponse(Map<String, dynamic> data) {
    try {
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return null;

      final feature = features.first;
      final geometry = feature['geometry'];
      final properties = feature['properties'];

      // Parse coordinate con elevazione
      final coordinates = geometry['coordinates'] as List;
      final List<RoutePoint> points = [];
      final List<double> elevationProfile = [];
      double cumulativeDistance = 0;

      for (int i = 0; i < coordinates.length; i++) {
        final coord = coordinates[i] as List;
        final lon = (coord[0] as num).toDouble();
        final lat = (coord[1] as num).toDouble();
        final ele = coord.length > 2 ? (coord[2] as num).toDouble() : null;

        // Calcola distanza cumulativa
        if (i > 0) {
          final prevCoord = coordinates[i - 1] as List;
          final prevLat = (prevCoord[1] as num).toDouble();
          final prevLon = (prevCoord[0] as num).toDouble();
          cumulativeDistance += _haversineDistance(prevLat, prevLon, lat, lon);
        }

        points.add(RoutePoint(
          latitude: lat,
          longitude: lon,
          elevation: ele,
          distanceFromStart: cumulativeDistance,
        ));

        if (ele != null) {
          elevationProfile.add(ele);
        }
      }

      // Parse summary
      final summary = properties['summary'] as Map<String, dynamic>?;
      final distance = (summary?['distance'] as num?)?.toDouble() ?? cumulativeDistance;
      final duration = (summary?['duration'] as num?)?.toDouble() ?? 0;

      // Calcola dislivello con ElevationProcessor (smoothing + isteresi)
      // Non usiamo ascent/descent di ORS perché sono calcolati raw
      double elevationGain = 0;
      double elevationLoss = 0;

      if (elevationProfile.length > 2) {
        // Parametri tarati per dati ORS routing: i profili da DEM
        // (SRTM/EU-DEM) hanno accuratezza ±5-10m e punti molto densi
        // (~5-15m tra l'uno e l'altro). Senza filtraggio aggressivo le
        // micro-oscillazioni si sommano gonfiando totalGain di 3-4×
        // (es. 500m reali → 1900m).
        final processor = const ElevationProcessor(
          hysteresisThreshold: 8.0,   // era 3.0: ignora variazioni < 8m
          smoothingWindow: 15,         // era 5: smussa oscillazioni dense
          medianWindow: 7,             // era 0: rimuove outlier puntuali
        );
        final rawElevations = elevationProfile
            .map((e) => e)
            .toList();
        final eleResult = processor.process(rawElevations);
        elevationGain = eleResult.elevationGain;
        elevationLoss = eleResult.elevationLoss;
      }

      // Parse navigation steps (turn-by-turn)
      final steps = _parseSteps(properties);

      debugPrint('[RoutingService] Route calcolata: ${points.length} punti, ${(distance/1000).toStringAsFixed(1)} km, +${elevationGain.toStringAsFixed(0)}m, ${steps.length} istruzioni');

      return RouteResult(
        points: points,
        distance: distance,
        elevationGain: elevationGain,
        elevationLoss: elevationLoss,
        estimatedDuration: duration,
        elevationProfile: elevationProfile,
        steps: steps,
      );
    } catch (e) {
      debugPrint('[RoutingService] Errore parsing: $e');
      return null;
    }
  }

  /// Estrae la lista di [NavigationStep] dalle properties di ORS
  List<NavigationStep> _parseSteps(Map<String, dynamic> properties) {
    try {
      final segments = properties['segments'] as List?;
      if (segments == null) return [];

      final List<NavigationStep> result = [];
      int stepIndex = 0;

      for (final seg in segments) {
        final segMap = seg as Map<String, dynamic>;
        final steps = segMap['steps'] as List?;
        if (steps == null) continue;

        for (final s in steps) {
          final stepMap = s as Map<String, dynamic>;
          final type = (stepMap['type'] as num?)?.toInt();
          final distance = (stepMap['distance'] as num?)?.toDouble() ?? 0;
          final wayPoints = stepMap['way_points'] as List?;
          if (wayPoints == null || wayPoints.length < 2) continue;

          final wpStart = (wayPoints[0] as num).toInt();
          final wpEnd = (wayPoints[1] as num).toInt();
          final name = stepMap['name'] as String?;

          result.add(NavigationStep(
            index: stepIndex++,
            maneuver: ManeuverType.fromOrsType(type),
            distance: distance,
            wayPointStart: wpStart,
            wayPointEnd: wpEnd,
            streetName: (name == null || name == '-') ? null : name,
          ));
        }
      }

      return result;
    } catch (e) {
      debugPrint('[RoutingService] Errore parsing steps: $e');
      return [];
    }
  }

  /// Calcola distanza Haversine tra due punti (in metri)
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Raggio Terra in metri
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }
}
