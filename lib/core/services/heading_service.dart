import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servizio che espone la "direzione di movimento" corrente dell'utente come
/// stream di gradi (0 = nord, 90 = est, 180 = sud, 270 = ovest).
///
/// Fonde due sorgenti:
/// - **GPS heading** (da `Geolocator`): affidabile solo quando l'utente si
///   muove a velocità >~1 m/s. Sotto questa soglia il device restituisce
///   heading=0 o -1 (invalido).
/// - **Bussola magnetica** (da `flutter_compass`): disponibile anche da
///   fermi, sensibile a interferenze magnetiche (zone ferrose, elettronica).
///
/// Smoothing con low-pass filter per evitare jitter: la rotazione della
/// mappa non "vibra" tra un update GPS e l'altro.
///
/// Persistenza della preferenza utente heading-up / north-up in
/// SharedPreferences (chiave `map_heading_up_enabled`).
class HeadingService extends ChangeNotifier {
  HeadingService._() {
    _subscribeCompass();
  }
  static final HeadingService _instance = HeadingService._();
  factory HeadingService() => _instance;

  static const String _prefsKey = 'map_heading_up_enabled';

  /// Smoothing factor del low-pass filter. Valori bassi = più smooth (più
  /// lag), valori alti = più reattivo (più jitter). 0.15 è un buon compromesso.
  static const double _alpha = 0.15;

  /// Velocità minima (m/s) sotto la quale il GPS heading non è affidabile.
  static const double _gpsHeadingMinSpeed = 0.8;

  double? _smoothed;
  StreamSubscription<CompassEvent>? _compassSub;
  bool _headingUpEnabled = false;
  bool _loaded = false;

  /// Gradi correnti smoothed, 0=nord. Null se nessuna sorgente ha ancora
  /// fornito dati.
  double? get currentHeading => _smoothed;

  /// True se l'utente ha attivato la modalità "heading-up" (mappa ruota).
  bool get isHeadingUp => _headingUpEnabled;

  /// Carica la preferenza persistente. Chiamare almeno una volta all'avvio
  /// o prima del primo render del toggle.
  Future<void> loadPreference() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _headingUpEnabled = prefs.getBool(_prefsKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  /// Cambia la preferenza e la persiste.
  Future<void> setHeadingUp(bool value) async {
    if (_headingUpEnabled == value) return;
    _headingUpEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
    notifyListeners();
  }

  Future<void> toggle() => setHeadingUp(!_headingUpEnabled);

  /// Da chiamare quando arriva un nuovo [Position] dal GPS. Se la velocità
  /// è sufficiente usa il GPS heading come sorgente primaria (più accurato
  /// del magnetometro).
  void updateFromPosition(Position position) {
    if (position.speed >= _gpsHeadingMinSpeed &&
        position.heading >= 0 &&
        position.heading <= 360) {
      _applyHeading(position.heading);
    }
    // Altrimenti: lasciamo che il compass stream continui a guidare.
  }

  /// Variante per chi opera su [TrackPoint] aggregati dal TrackingBloc
  /// (così evitiamo un secondo stream GPS duplicato).
  void updateFromSpeedAndHeading({double? speed, double? heading}) {
    if (speed == null || heading == null) return;
    if (speed < _gpsHeadingMinSpeed) return;
    if (heading < 0 || heading > 360) return;
    _applyHeading(heading);
  }

  void _subscribeCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      final h = event.heading;
      if (h == null) return;
      // La bussola ritorna -180..180 in alcuni casi; normalizziamo a 0..360.
      final normalized = h < 0 ? h + 360 : h;
      _applyHeading(normalized);
    });
  }

  void _applyHeading(double raw) {
    // Low-pass filter angolare: gestisce il wrap-around 359→0 interpretando
    // la differenza angolare come il path più breve.
    if (_smoothed == null) {
      _smoothed = raw;
    } else {
      double diff = raw - _smoothed!;
      while (diff > 180) {
        diff -= 360;
      }
      while (diff < -180) {
        diff += 360;
      }
      var next = _smoothed! + _alpha * diff;
      while (next < 0) {
        next += 360;
      }
      while (next >= 360) {
        next -= 360;
      }
      _smoothed = next;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    // Singleton: dispose solo in testing. In produzione resta vivo.
    _compassSub?.cancel();
    super.dispose();
  }
}
