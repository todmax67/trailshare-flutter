import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;

/// Servizio per la geolocalizzazione in background
/// 
/// Gestisce il tracking GPS anche quando l'app è in background o lo schermo è bloccato.
/// Usa il plugin flutter_background_geolocation che è il più affidabile per iOS e Android.
class BackgroundGeolocationService {
  static final BackgroundGeolocationService _instance = BackgroundGeolocationService._internal();
  factory BackgroundGeolocationService() => _instance;
  BackgroundGeolocationService._internal();

  // Stream controller per le posizioni
  final _locationController = StreamController<LocationData>.broadcast();
  Stream<LocationData> get locationStream => _locationController.stream;

  // Stream controller per gli eventi (start, stop, errori)
  final _eventController = StreamController<GeolocationEvent>.broadcast();
  Stream<GeolocationEvent> get eventStream => _eventController.stream;

  // Stato
  bool _isTracking = false;
  bool _isInitialized = false;
  String _activityType = 'walking'; // walking, running, cycling

  bool get isTracking => _isTracking;
  bool get isInitialized => _isInitialized;

  /// Inizializza il servizio di geolocalizzazione
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Configura il plugin
      await bg.BackgroundGeolocation.ready(bg.Config(
        // Configurazione generale
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 5.0, // metri minimi tra aggiornamenti
        stopOnTerminate: false, // Continua anche se l'app viene terminata
        startOnBoot: false, // Non avviare al boot del dispositivo
        
        // Configurazione background
        enableHeadless: true,
        foregroundService: true,
        
        // Notifica Android
        notification: bg.Notification(
          title: "TrailShare sta registrando",
          text: "Tocca per tornare all'app",
          channelName: "TrailShare Tracking",
          smallIcon: "drawable/ic_notification", // Assicurati di avere questa icona
          largeIcon: "drawable/ic_notification",
          priority: bg.Config.NOTIFICATION_PRIORITY_HIGH,
        ),
        
        // iOS
        activityType: bg.Config.ACTIVITY_TYPE_FITNESS,
        pausesLocationUpdatesAutomatically: false,
        
        // Debug (disabilitare in produzione)
        debug: kDebugMode,
        logLevel: kDebugMode ? bg.Config.LOG_LEVEL_VERBOSE : bg.Config.LOG_LEVEL_OFF,
      ));

      // Listener per le posizioni
      bg.BackgroundGeolocation.onLocation(_onLocation);
      
      // Listener per errori
      bg.BackgroundGeolocation.onProviderChange(_onProviderChange);
      
      // Listener per cambio stato autorizzazione
      bg.BackgroundGeolocation.onAuthorization(_onAuthorization);

      _isInitialized = true;
      debugPrint('[BackgroundGeo] Inizializzato');
      
      return true;
    } catch (e) {
      debugPrint('[BackgroundGeo] Errore inizializzazione: $e');
      _eventController.add(GeolocationEvent(
        type: GeolocationEventType.error,
        message: 'Errore inizializzazione: $e',
      ));
      return false;
    }
  }

  /// Imposta il tipo di attività (influenza la precisione GPS)
  void setActivityType(String type) {
    _activityType = type;
    
    int bgActivityType;
    switch (type.toLowerCase()) {
      case 'running':
      case 'trailrunning':
        bgActivityType = bg.Config.ACTIVITY_TYPE_FITNESS;
        break;
      case 'cycling':
      case 'bike':
        bgActivityType = bg.Config.ACTIVITY_TYPE_OTHER_NAVIGATION;
        break;
      default:
        bgActivityType = bg.Config.ACTIVITY_TYPE_FITNESS;
    }
    
    bg.BackgroundGeolocation.setConfig(bg.Config(
      activityType: bgActivityType,
    ));
    
    debugPrint('[BackgroundGeo] Activity type: $type');
  }

  /// Avvia il tracking GPS
  Future<bool> startTracking() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    if (_isTracking) {
      debugPrint('[BackgroundGeo] Tracking già attivo');
      return true;
    }

    try {
      // Richiedi permessi se necessario
      final status = await bg.BackgroundGeolocation.requestPermission();
      
      if (status != bg.ProviderChangeEvent.AUTHORIZATION_STATUS_ALWAYS &&
          status != bg.ProviderChangeEvent.AUTHORIZATION_STATUS_WHEN_IN_USE) {
        _eventController.add(GeolocationEvent(
          type: GeolocationEventType.permissionDenied,
          message: 'Permesso GPS negato',
        ));
        return false;
      }

      // Avvia tracking
      await bg.BackgroundGeolocation.start();
      
      _isTracking = true;
      _eventController.add(GeolocationEvent(
        type: GeolocationEventType.started,
        message: 'Tracking avviato',
      ));
      
      debugPrint('[BackgroundGeo] Tracking avviato');
      return true;
    } catch (e) {
      debugPrint('[BackgroundGeo] Errore avvio: $e');
      _eventController.add(GeolocationEvent(
        type: GeolocationEventType.error,
        message: 'Errore avvio tracking: $e',
      ));
      return false;
    }
  }

  /// Ferma il tracking GPS
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    try {
      await bg.BackgroundGeolocation.stop();
      
      _isTracking = false;
      _eventController.add(GeolocationEvent(
        type: GeolocationEventType.stopped,
        message: 'Tracking fermato',
      ));
      
      debugPrint('[BackgroundGeo] Tracking fermato');
    } catch (e) {
      debugPrint('[BackgroundGeo] Errore stop: $e');
    }
  }

  /// Ottiene la posizione corrente (una tantum)
  Future<LocationData?> getCurrentPosition() async {
    try {
      final location = await bg.BackgroundGeolocation.getCurrentPosition(
        timeout: 30,
        maximumAge: 5000,
        desiredAccuracy: 10,
        samples: 3,
      );
      
      return LocationData(
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
        altitude: location.coords.altitude,
        accuracy: location.coords.accuracy,
        speed: location.coords.speed,
        heading: location.coords.heading,
        timestamp: DateTime.parse(location.timestamp),
      );
    } catch (e) {
      debugPrint('[BackgroundGeo] Errore getCurrentPosition: $e');
      return null;
    }
  }

  /// Callback per nuove posizioni
  void _onLocation(bg.Location location) {
    final locationData = LocationData(
      latitude: location.coords.latitude,
      longitude: location.coords.longitude,
      altitude: location.coords.altitude,
      accuracy: location.coords.accuracy,
      speed: location.coords.speed,
      heading: location.coords.heading,
      timestamp: DateTime.parse(location.timestamp),
      isMoving: location.isMoving,
      activity: location.activity?.type,
      batteryLevel: location.battery?.level,
    );

    _locationController.add(locationData);
    
    debugPrint('[BackgroundGeo] Nuova posizione: ${location.coords.latitude}, ${location.coords.longitude}');
  }

  /// Callback per cambio provider GPS
  void _onProviderChange(bg.ProviderChangeEvent event) {
    debugPrint('[BackgroundGeo] Provider change: enabled=${event.enabled}, status=${event.status}');
    
    if (!event.enabled) {
      _eventController.add(GeolocationEvent(
        type: GeolocationEventType.gpsDisabled,
        message: 'GPS disabilitato',
      ));
    }
  }

  /// Callback per cambio autorizzazione
  void _onAuthorization(bg.AuthorizationEvent event) {
    debugPrint('[BackgroundGeo] Authorization: ${event.status}');
    
    if (event.status == bg.ProviderChangeEvent.AUTHORIZATION_STATUS_DENIED) {
      _eventController.add(GeolocationEvent(
        type: GeolocationEventType.permissionDenied,
        message: 'Permesso GPS negato',
      ));
    }
  }

  /// Pulisce le risorse
  void dispose() {
    _locationController.close();
    _eventController.close();
  }
}

/// Dati di una posizione
class LocationData {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final double speed;
  final double heading;
  final DateTime timestamp;
  final bool? isMoving;
  final String? activity;
  final double? batteryLevel;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.altitude = 0,
    this.accuracy = 0,
    this.speed = 0,
    this.heading = 0,
    required this.timestamp,
    this.isMoving,
    this.activity,
    this.batteryLevel,
  });

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'accuracy': accuracy,
    'speed': speed,
    'heading': heading,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Eventi del servizio di geolocalizzazione
class GeolocationEvent {
  final GeolocationEventType type;
  final String message;
  final dynamic data;

  const GeolocationEvent({
    required this.type,
    required this.message,
    this.data,
  });
}

enum GeolocationEventType {
  started,
  stopped,
  error,
  permissionDenied,
  gpsDisabled,
}
