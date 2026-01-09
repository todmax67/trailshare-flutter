import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../../data/models/track.dart';

/// Servizio per il tracking GPS
class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final _positionController = StreamController<TrackPoint>.broadcast();
  
  /// Stream dei punti GPS
  Stream<TrackPoint> get positionStream => _positionController.stream;
  
  /// Configurazione location settings per tracking preciso
  LocationSettings get _trackingSettings => const LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 5, // Aggiorna ogni 5 metri
  );

  /// Verifica e richiede permessi
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Ottieni posizione corrente
  Future<TrackPoint?> getCurrentPosition() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return _positionToTrackPoint(position);
    } catch (e) {
      print('Error getting current position: $e');
      return null;
    }
  }

  /// Avvia tracking continuo
  Future<bool> startTracking() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return false;

    // Ferma eventuale tracking precedente
    await stopTracking();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _trackingSettings,
    ).listen(
      (Position position) {
        final trackPoint = _positionToTrackPoint(position);
        _positionController.add(trackPoint);
      },
      onError: (error) {
        print('Location stream error: $error');
      },
    );

    return true;
  }

  /// Ferma tracking
  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Pausa tracking (stesso di stop per ora)
  Future<void> pauseTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Riprendi tracking
  Future<bool> resumeTracking() async {
    return startTracking();
  }

  /// Converte Position di Geolocator in TrackPoint
  TrackPoint _positionToTrackPoint(Position position) {
    return TrackPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      elevation: position.altitude > 0 ? position.altitude : null,
      timestamp: position.timestamp,
      speed: position.speed > 0 ? position.speed : null,
      accuracy: position.accuracy,
      heading: position.heading > 0 ? position.heading : null,
    );
  }

  /// Cleanup
  void dispose() {
    _positionSubscription?.cancel();
    _positionController.close();
  }
}
