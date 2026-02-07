import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../utils/elevation_processor.dart';

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

  const RouteResult({
    required this.points,
    required this.distance,
    required this.elevationGain,
    required this.elevationLoss,
    required this.estimatedDuration,
    required this.elevationProfile,
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

/// Servizio per calcolare percorsi tramite OpenRouteService
class RoutingService {
  final String apiKey;
  static const String _baseUrl = 'https://api.openrouteservice.org/v2';

  RoutingService({required this.apiKey});

  /// Calcola un percorso tra waypoint
  /// [waypoints] - Lista di punti (minimo 2)
  /// [profile] - Tipo di attività (hiking/cycling)
  Future<RouteResult?> calculateRoute(
    List<LatLng> waypoints, {
    RoutingProfile profile = RoutingProfile.hiking,
  }) async {
    if (waypoints.length < 2) {
      print('[RoutingService] Servono almeno 2 waypoint');
      return null;
    }

    try {
      final profileString = _getProfileString(profile);
      final url = Uri.parse('$_baseUrl/directions/$profileString/geojson');

      // Costruisci il body della richiesta
      final coordinates = waypoints
          .map((p) => [p.longitude, p.latitude])
          .toList();

      final body = jsonEncode({
        'coordinates': coordinates,
        'elevation': true,
        'instructions': false,
        'geometry_simplify': false,
      });

      print('[RoutingService] Richiesta routing: ${waypoints.length} waypoint, profilo: $profileString');

      final response = await http.post(
        url,
        headers: {
          'Authorization': apiKey,
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        print('[RoutingService] Errore API: ${response.statusCode} - ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);
      return _parseRouteResponse(data);
    } catch (e) {
      print('[RoutingService] Errore: $e');
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
        final processor = const ElevationProcessor(
          hysteresisThreshold: 3.0,
          smoothingWindow: 5,
          medianWindow: 0,  // non serve per dati routing (già puliti)
        );
        final rawElevations = elevationProfile
            .map((e) => e)
            .toList();
        final eleResult = processor.process(rawElevations);
        elevationGain = eleResult.elevationGain;
        elevationLoss = eleResult.elevationLoss;
      }

      print('[RoutingService] Route calcolata: ${points.length} punti, ${(distance/1000).toStringAsFixed(1)} km, +${elevationGain.toStringAsFixed(0)}m');

      return RouteResult(
        points: points,
        distance: distance,
        elevationGain: elevationGain,
        elevationLoss: elevationLoss,
        estimatedDuration: duration,
        elevationProfile: elevationProfile,
      );
    } catch (e) {
      print('[RoutingService] Errore parsing: $e');
      return null;
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
