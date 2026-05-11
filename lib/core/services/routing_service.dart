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

/// Esito dettagliato del calcolo routing. Sostituisce il pattern "ritorno
/// null = errore" così la UI può mostrare messaggi mirati ("waypoint #3
/// lontano dai sentieri") invece del generico "prova waypoint più vicini".
///
/// Compatibilità con i call sites attuali mantenuta via [calculateRoute]
/// che continua a ritornare `RouteResult?` (null = errore generico). Per
/// errori strutturati i caller possono usare [calculateRouteWithDetails].
class RoutingFailure {
  /// Codice errore ORS (es. 2010 = punto non raggiungibile).
  final int code;
  /// Messaggio originale ORS (utile per debug).
  final String message;
  /// Indice del waypoint problematico (0-based) se identificabile. null
  /// se l'errore non riguarda uno specifico waypoint (es. rete down).
  final int? waypointIndex;
  /// Messaggio user-friendly localizzato in italiano.
  final String userMessage;

  const RoutingFailure({
    required this.code,
    required this.message,
    this.waypointIndex,
    required this.userMessage,
  });
}

class RoutingOutcome {
  final RouteResult? result;
  final RoutingFailure? failure;

  const RoutingOutcome.success(RouteResult this.result) : failure = null;
  const RoutingOutcome.error(RoutingFailure this.failure) : result = null;

  bool get isSuccess => result != null;
}

/// Servizio per calcolare percorsi tramite Cloud Function proxy ORS
class RoutingService {
  final String proxyBaseUrl;

  /// Raggio di snap per waypoint (metri). ORS cerca il punto routable più
  /// vicino entro questo raggio. 5km copre praticamente ogni click in zona
  /// montana italiana senza far calcolare percorsi assurdi su click oceano.
  static const int _snapRadiusMeters = 5000;

  RoutingService({required this.proxyBaseUrl});

  /// Calcola un percorso tra waypoint. Ritorna `null` su qualunque errore
  /// (back-compat con i call sites pre-Sprint planner-fix). Per ottenere
  /// dettagli strutturati usa [calculateRouteWithDetails].
  Future<RouteResult?> calculateRoute(
    List<LatLng> waypoints, {
    RoutingProfile profile = RoutingProfile.hiking,
  }) async {
    final outcome =
        await calculateRouteWithDetails(waypoints, profile: profile);
    return outcome.result;
  }

  /// Versione dettagliata: ritorna [RoutingOutcome] con risultato o
  /// failure strutturato (codice ORS, indice waypoint problematico,
  /// messaggio user-friendly).
  ///
  /// Fix 8.B1.3: invia `radiuses` per ogni waypoint così ORS prova a
  /// snappare al sentiero più vicino entro [_snapRadiusMeters] invece di
  /// rifiutare ogni click off-network. Quando snap fallisce comunque,
  /// parsa l'errore ORS code 2010 per identificare quale waypoint l'utente
  /// deve spostare.
  Future<RoutingOutcome> calculateRouteWithDetails(
    List<LatLng> waypoints, {
    RoutingProfile profile = RoutingProfile.hiking,
  }) async {
    if (waypoints.length < 2) {
      return RoutingOutcome.error(const RoutingFailure(
        code: -1,
        message: 'Servono almeno 2 waypoint',
        userMessage: 'Aggiungi almeno 2 punti sulla mappa.',
      ));
    }

    try {
      final profileString = _getProfileString(profile);
      final url =
          Uri.parse('$proxyBaseUrl/v2/directions/$profileString/geojson');

      final coordinates = waypoints
          .map((p) => [p.longitude, p.latitude])
          .toList();
      final radiuses =
          List<int>.filled(waypoints.length, _snapRadiusMeters);

      final body = jsonEncode({
        'coordinates': coordinates,
        'radiuses': radiuses,
        'elevation': true,
        'instructions': true,
        'geometry_simplify': false,
      });

      debugPrint(
          '[RoutingService] Richiesta routing: ${waypoints.length} waypoint, profilo: $profileString, snap=${_snapRadiusMeters}m');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode != 200) {
        debugPrint(
            '[RoutingService] Errore API: ${response.statusCode} - ${response.body}');
        return RoutingOutcome.error(_parseErrorBody(response.body, waypoints));
      }

      final data = jsonDecode(response.body);
      final parsed = _parseRouteResponse(data);
      if (parsed == null) {
        return RoutingOutcome.error(const RoutingFailure(
          code: -2,
          message: 'Empty geometry from ORS',
          userMessage:
              'Routing fallito: la risposta del server è incompleta. Riprova.',
        ));
      }
      return RoutingOutcome.success(parsed);
    } catch (e) {
      debugPrint('[RoutingService] Errore: $e');
      return RoutingOutcome.error(RoutingFailure(
        code: -3,
        message: e.toString(),
        userMessage: 'Errore di rete: $e',
      ));
    }
  }

  /// Parsa il body di errore ORS. Code 2010 = "Could not find routable
  /// point within X meters of coordinate N" → estraiamo l'indice N.
  RoutingFailure _parseErrorBody(String body, List<LatLng> waypoints) {
    try {
      final data = jsonDecode(body);
      final err = data['error'];
      if (err is Map<String, dynamic>) {
        final code = (err['code'] as num?)?.toInt() ?? -1;
        final message = err['message']?.toString() ?? body;
        if (code == 2010) {
          // ORS message: "Could not find routable point within a radius
          // of 5000.0 meters of specified coordinate 2: 9.65, 45.83."
          final match = RegExp(r'coordinate\s+(\d+)').firstMatch(message);
          final wpIndex = match != null ? int.tryParse(match.group(1)!) : null;
          final humanIdx = wpIndex != null ? wpIndex + 1 : null;
          return RoutingFailure(
            code: code,
            message: message,
            waypointIndex: wpIndex,
            userMessage: humanIdx != null
                ? 'Il waypoint #$humanIdx è troppo lontano dai sentieri '
                    '(oltre ${_snapRadiusMeters ~/ 1000} km). Spostalo più '
                    'vicino a una mulattiera o sentiero conosciuto.'
                : 'Uno dei waypoint è lontano da qualsiasi sentiero. '
                    'Avvicinalo a una mulattiera o sentiero conosciuto.',
          );
        }
        return RoutingFailure(
          code: code,
          message: message,
          userMessage: 'Routing fallito (codice $code). $message',
        );
      }
    } catch (_) {
      // body non JSON o struttura inattesa, cade nel fallback
    }
    return RoutingFailure(
      code: -1,
      message: body,
      userMessage:
          'Routing fallito: il server non ha trovato un percorso. '
          'Prova waypoint più vicini fra loro o cambia attività.',
    );
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
