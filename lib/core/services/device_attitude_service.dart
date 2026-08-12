import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../utils/camera_orientation.dart';
import '../utils/mountain_projection.dart';

/// Un campione di orientamento del telefono, pronto per la proiezione AR.
class DeviceAttitude {
  /// Terna della fotocamera nel sistema ENU locale.
  final CameraBasis basis;

  /// Incertezza indicativa della bussola in gradi. `null` = magnetometro
  /// inaffidabile: è il momento di suggerire la calibrazione a otto.
  final double? accuracyDeg;

  /// False se non è stato possibile riferirsi al nord geografico (manca la
  /// declinazione magnetica): le etichette saranno sfasate di qualche grado.
  final bool isTrueNorth;

  /// False quando siamo sul ripiego bussola + accelerometro, che non conosce
  /// il roll e sbanda quando ci si muove.
  final bool isNative;

  const DeviceAttitude({
    required this.basis,
    required this.accuracyDeg,
    required this.isTrueNorth,
    required this.isNative,
  });

  /// True quando la bussola si dichiara inaffidabile.
  bool get needsCalibration => accuracyDeg == null;
}

/// Sorgente **unica** dell'orientamento del telefono per l'AR.
///
/// Prima di questo servizio l'orientamento arrivava da due sorgenti scollegate:
/// `flutter_compass` per l'azimut e l'accelerometro grezzo per il pitch. Tre
/// problemi, tutti visibili a occhio:
///
/// 1. `CompassEvent.heading` dice dove punta il **bordo alto** del telefono,
///    non l'obiettivo posteriore — e quando si alza il telefono verso una cima
///    le due direzioni divergono;
/// 2. su Android il riferimento è il nord **magnetico**, su iOS quello
///    geografico: nelle Alpi sono 3,5-4,5° di differenza, cioè ~70 px di
///    sfasamento costante su Android e su iOS no;
/// 3. il **roll** non era rappresentabile, quindi bastava inclinare di lato il
///    telefono per far scivolare le etichette.
///
/// Ora l'assetto completo arriva dalla sensor fusion del sistema operativo
/// (Android `TYPE_ROTATION_VECTOR`, iOS `CMDeviceMotion` con riferimento al
/// nord geografico) come matrice device→ENU, e diventa una [CameraBasis].
///
/// Se il canale nativo non risponde si ripiega sul vecchio schema
/// bussola + accelerometro (roll 0), così su un dispositivo anomalo la
/// funzione degrada invece di sparire.
class DeviceAttitudeService {
  DeviceAttitudeService._();
  static final DeviceAttitudeService _instance = DeviceAttitudeService._();
  factory DeviceAttitudeService() => _instance;

  static const MethodChannel _method =
      MethodChannel('com.trailshare.app/attitude');
  static const EventChannel _events =
      EventChannel('com.trailshare.app/attitude_events');

  StreamController<DeviceAttitude>? _controller;
  StreamSubscription<dynamic>? _nativeSub;
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  bool _usingFallback = false;

  // Stato dello smoothing (in spazio angolare: azimut con wrap-around, pitch,
  // roll). L'assetto nativo è già fuso col giroscopio e quindi molto più
  // pulito del magnetometro grezzo: gli basta un filtro leggero, mentre il
  // ripiego ne ha bisogno di uno robusto.
  double? _azimuth;
  double _pitch = 0;
  double _roll = 0;
  DateTime? _lastSample;

  static const double _nativeAlphaMin = 0.20;
  static const double _nativeAlphaMax = 0.50;
  static const double _fallbackAlphaMin = 0.06;
  static const double _fallbackAlphaMax = 0.30;
  static const double _rateForMaxAlpha = 30.0; // °/s

  // Ultimi valori grezzi del ripiego, che arrivano da due stream separati.
  double _fallbackHeading = 0;
  double _fallbackPitch = 0;
  double? _fallbackAccuracy;

  /// Log una tantum alla prima lettura: quale sorgente ha vinto e a quale nord
  /// siamo riferiti. Sono le due domande che decidono se l'allineamento può
  /// essere corretto, e in release il pannello diagnostico lo vede solo un
  /// admin — questo si legge anche da `flutter run --release`.
  bool _loggedFirstSample = false;

  /// True se la sensor fusion nativa è disponibile su questo dispositivo.
  Future<bool> isNativeAvailable() async {
    try {
      final ok = await _method.invokeMethod<bool>('isAvailable');
      return ok ?? false;
    } catch (e) {
      debugPrint('[Attitude] isAvailable non disponibile: $e');
      return false;
    }
  }

  /// Campo visivo del fotogramma pieno della fotocamera posteriore, in gradi,
  /// nell'orientamento nativo del sensore. `null` se la piattaforma non sa
  /// rispondere — in quel caso restano i valori di calibrazione manuale.
  ///
  /// Il ritaglio della preview NON è applicato qui: lo fa `screenFovFromSensor`,
  /// perché dipende da come la preview è composta a schermo e questo lo sa solo
  /// la pagina.
  Future<({double horizontalDeg, double verticalDeg})?> sensorFieldOfView() async {
    try {
      final r = await _method.invokeMethod('getCameraFov');
      if (r is! Map) return null;
      final h = (r['horizontalDeg'] as num?)?.toDouble();
      final v = (r['verticalDeg'] as num?)?.toDouble();
      if (h == null || v == null || h <= 1 || v <= 1) return null;
      debugPrint('[Attitude] FOV sensore: '
          '${h.toStringAsFixed(1)}x${v.toStringAsFixed(1)}° ${r['sensorMm'] ?? r['format'] ?? ''}');
      return (horizontalDeg: h, verticalDeg: v);
    } catch (e) {
      debugPrint('[Attitude] FOV sensore non disponibile: $e');
      return null;
    }
  }

  /// True quando siamo sul ripiego bussola + accelerometro.
  bool get isUsingFallback => _usingFallback;

  /// Comunica la posizione alla piattaforma: serve ad Android per calcolare la
  /// declinazione magnetica. Da richiamare quando l'utente si sposta di qualche
  /// chilometro — la declinazione cambia di ~1° ogni 100-150 km, quindi non
  /// serve inseguire ogni fix.
  Future<void> setLocation({
    required double latitude,
    required double longitude,
    double altitude = 0,
  }) async {
    try {
      final declination = await _method.invokeMethod('setLocation', {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
      });
      // Android restituisce la declinazione applicata (iOS torna `true`: lì il
      // nord geografico lo dà già il sistema). Loggarla è il modo più diretto
      // per verificare in campo che la correzione ci sia davvero.
      if (declination is num && declination != _lastDeclinationDeg) {
        _lastDeclinationDeg = declination.toDouble();
        debugPrint('[Attitude] declinazione magnetica applicata: '
            '${declination.toStringAsFixed(2)}°');
      }
    } catch (e) {
      debugPrint('[Attitude] setLocation fallita: $e');
    }
  }

  double? _lastDeclinationDeg;

  /// Stream dell'orientamento. Broadcast: più pagine possono ascoltarlo, i
  /// sensori si accendono al primo ascoltatore e si spengono con l'ultimo.
  Stream<DeviceAttitude> get stream {
    _controller ??= StreamController<DeviceAttitude>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    return _controller!.stream;
  }

  void _start() {
    _resetSmoothing();
    _usingFallback = false;
    try {
      _nativeSub = _events.receiveBroadcastStream().listen(
            _onNativeSample,
            onError: (Object e) {
              debugPrint('[Attitude] canale nativo in errore ($e) → ripiego');
              _startFallback();
            },
          );
    } catch (e) {
      debugPrint('[Attitude] canale nativo non apribile ($e) → ripiego');
      _startFallback();
    }
  }

  void _stop() {
    _nativeSub?.cancel();
    _nativeSub = null;
    _compassSub?.cancel();
    _compassSub = null;
    _accelSub?.cancel();
    _accelSub = null;
    _resetSmoothing();
  }

  void _resetSmoothing() {
    _azimuth = null;
    _pitch = 0;
    _roll = 0;
    _lastSample = null;
    _loggedFirstSample = false;
  }

  void _onNativeSample(dynamic event) {
    if (event is! Map) return;
    final raw = event['m'];
    if (raw is! List || raw.length < 9) return;
    final m = raw.map((e) => (e as num).toDouble()).toList(growable: false);

    final basis = CameraBasis.fromDeviceToEnu(
      m,
      screenRotationDeg: (event['screenRotation'] as num?)?.toInt() ?? 0,
    );
    _emitSmoothed(
      azimuthDeg: basis.azimuthDeg,
      pitchDeg: basis.pitchDeg,
      rollDeg: basis.rollDeg,
      accuracyDeg: (event['accuracy'] as num?)?.toDouble(),
      isTrueNorth: event['trueNorth'] as bool? ?? false,
      isNative: true,
    );
  }

  void _startFallback() {
    if (_usingFallback) return;
    _usingFallback = true;
    _nativeSub?.cancel();
    _nativeSub = null;
    _resetSmoothing();

    _compassSub = FlutterCompass.events?.listen((event) {
      final raw = event.heading;
      if (raw == null) return;
      _fallbackHeading = raw < 0 ? raw + 360 : raw;
      _fallbackAccuracy = event.accuracy;
      _emitFallback();
    });
    _accelSub = accelerometerEventStream().listen((event) {
      _fallbackPitch = MountainProjection.pitchFromAccelerometer(
        event.x,
        event.y,
        event.z,
      );
    });
  }

  void _emitFallback() {
    _emitSmoothed(
      azimuthDeg: _fallbackHeading,
      pitchDeg: _fallbackPitch,
      // Il ripiego non conosce il roll: assumiamo telefono in bolla.
      rollDeg: 0,
      accuracyDeg: _fallbackAccuracy,
      // `CompassEvent.heading` è geografico su iOS e magnetico su Android:
      // senza il canale nativo non sappiamo correggere.
      isTrueNorth: false,
      isNative: false,
    );
  }

  /// Filtro passa-basso **adattivo** sugli angoli: quando il telefono è fermo
  /// smorza molto (le etichette si "ancorano" alle cime), quando si ruota in
  /// fretta lascia passare (niente lag). Lo smoothing sta qui e non nelle
  /// pagine, così le due schermate AR si comportano allo stesso modo.
  void _emitSmoothed({
    required double azimuthDeg,
    required double pitchDeg,
    required double rollDeg,
    required double? accuracyDeg,
    required bool isTrueNorth,
    required bool isNative,
  }) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;

    if (!_loggedFirstSample) {
      _loggedFirstSample = true;
      debugPrint('[Attitude] sorgente=${isNative ? "nativa" : "RIPIEGO"} '
          'nord=${isTrueNorth ? "geografico" : "MAGNETICO"} '
          'bussola=${accuracyDeg == null ? "inaffidabile" : "±${accuracyDeg.toStringAsFixed(0)}°"} '
          'az=${azimuthDeg.toStringAsFixed(1)} '
          'pitch=${pitchDeg.toStringAsFixed(1)} '
          'roll=${rollDeg.toStringAsFixed(1)}');
    }

    final now = DateTime.now();
    final prev = _azimuth;
    if (prev == null) {
      _azimuth = azimuthDeg;
      _pitch = pitchDeg;
      _roll = rollDeg;
    } else {
      double delta = azimuthDeg - prev;
      if (delta > 180) delta -= 360;
      if (delta < -180) delta += 360;

      final dt = _lastSample == null
          ? 0.05
          : (now.difference(_lastSample!).inMilliseconds / 1000.0)
              .clamp(0.01, 0.5);
      final rate = (delta / dt).abs();
      final alphaMin = isNative ? _nativeAlphaMin : _fallbackAlphaMin;
      final alphaMax = isNative ? _nativeAlphaMax : _fallbackAlphaMax;
      final t = (rate / _rateForMaxAlpha).clamp(0.0, 1.0);
      final alpha = alphaMin + t * (alphaMax - alphaMin);

      _azimuth = (prev + alpha * delta + 360) % 360;
      _pitch = _pitch + alpha * (pitchDeg - _pitch);

      double rollDelta = rollDeg - _roll;
      if (rollDelta > 180) rollDelta -= 360;
      if (rollDelta < -180) rollDelta += 360;
      _roll = _roll + alpha * rollDelta;
    }
    _lastSample = now;

    controller.add(DeviceAttitude(
      basis: CameraBasis.fromAngles(
        azimuthDeg: _azimuth!,
        pitchDeg: _pitch,
        rollDeg: _roll,
      ),
      accuracyDeg: accuracyDeg,
      isTrueNorth: isTrueNorth,
      isNative: isNative,
    ));
  }
}
