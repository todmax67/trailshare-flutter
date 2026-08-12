import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/mountain_projection.dart';

/// Settings utente del Mountain Finder: FOV orizzontale/verticale della
/// camera, persistiti su SharedPreferences.
///
/// Ogni telefono ha una camera leggermente diversa (lente, sensore,
/// crop in modalità portrait): il default 60° h × 80° v è una media
/// prudente per smartphone moderni, ma può richiedere un fine-tuning
/// di ±5-10° per allineare perfettamente i pin AR alle cime reali.
///
/// Singleton + [ChangeNotifier]: la `MountainFinderPage` ascolta i
/// cambiamenti per ri-proiettare i pin in tempo reale durante la
/// calibrazione.
class MountainFinderSettings extends ChangeNotifier {
  MountainFinderSettings._();
  static final MountainFinderSettings _instance =
      MountainFinderSettings._();
  factory MountainFinderSettings() => _instance;

  static const _kHFov = 'mf_hfov_deg';
  static const _kVFov = 'mf_vfov_deg';
  static const _kMaxDistKm = 'mf_max_distance_km';
  static const _kAlignAz = 'mf_align_azimuth_deg';
  static const _kAlignPitch = 'mf_align_pitch_deg';
  static const _kAlignLat = 'mf_align_lat';
  static const _kAlignLng = 'mf_align_lng';

  /// Distanza oltre la quale una correzione manuale va buttata.
  ///
  /// La correzione compensa il campo magnetico **locale**: misurata dentro casa
  /// vale una decina di gradi, all'aperto uno o due. Portarsela dietro
  /// spostandosi non è conservativo, è dannoso — diventa essa stessa l'errore.
  static const double alignValidityMeters = 1000;

  /// Correzione manuale massima applicabile con il trascinamento, in gradi.
  /// Oltre questo non si sta più correggendo un errore di puntamento: si sta
  /// sbagliando cima.
  static const double maxAlignOffsetDeg = 25;

  // Range ammessi nello slider di calibrazione.
  static const double minHFov = 40;
  static const double maxHFov = 95;
  static const double minVFov = 40;
  static const double maxVFov = 115;

  // Range ammesso per il filtro distanza (km).
  static const double minDistanceKm = 5;
  static const double maxDistanceKm = 150;
  static const double defaultDistanceKm = 60;

  /// Distanze "preset" rapide nel filter sheet.
  static const List<double> distancePresetsKm = [10, 30, 60, 100];

  double _hFovDeg = MountainProjection.defaultHorizontalFovDeg;
  double _vFovDeg = MountainProjection.defaultVerticalFovDeg;
  double _maxDistKm = defaultDistanceKm;
  double _alignAzDeg = 0;
  double _alignPitchDeg = 0;
  double? _alignLat;
  double? _alignLng;
  bool _loaded = false;

  double get horizontalFovDeg => _hFovDeg;
  double get verticalFovDeg => _vFovDeg;
  double get maxDistanceKmValue => _maxDistKm;

  /// Correzione manuale del puntamento, in gradi, applicata sopra ai sensori.
  ///
  /// Serve perché il magnetometro di uno smartphone sbaglia regolarmente di
  /// qualche grado — vicino a roccia ferrosa, funivie, ferrate, o per la
  /// custodia magnetica — e nessuna fusione di sensori lo risolve. Tutti i
  /// concorrenti seri danno all'utente questa manopola: senza, l'unica reazione
  /// possibile a un errore è chiudere l'app.
  double get alignAzimuthOffsetDeg => _alignAzDeg;
  double get alignPitchOffsetDeg => _alignPitchDeg;
  bool get hasAlignOffset => _alignAzDeg != 0 || _alignPitchDeg != 0;

  /// Posizione in cui la correzione manuale è stata tarata, se c'è.
  double? get alignLat => _alignLat;
  double? get alignLng => _alignLng;

  bool get isLoaded => _loaded;

  /// Carica i valori salvati. Idempotente.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _hFovDeg = prefs.getDouble(_kHFov) ??
          MountainProjection.defaultHorizontalFovDeg;
      _vFovDeg = prefs.getDouble(_kVFov) ??
          MountainProjection.defaultVerticalFovDeg;
      _maxDistKm = prefs.getDouble(_kMaxDistKm) ?? defaultDistanceKm;
      _alignAzDeg = prefs.getDouble(_kAlignAz) ?? 0;
      _alignPitchDeg = prefs.getDouble(_kAlignPitch) ?? 0;
      _alignLat = prefs.getDouble(_kAlignLat);
      _alignLng = prefs.getDouble(_kAlignLng);
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[MFSettings] load error: $e');
      _loaded = true;
    }
  }

  /// Sposta la correzione manuale di [deltaAzDeg] / [deltaPitchDeg] gradi.
  ///
  /// Incrementale perché arriva da un trascinamento continuo: la scrittura su
  /// disco è differita ([commitAlignOffset]) per non fare una `SharedPreferences`
  /// per ogni frame di drag.
  void nudgeAlignOffset({double deltaAzDeg = 0, double deltaPitchDeg = 0}) {
    if (deltaAzDeg == 0 && deltaPitchDeg == 0) return;
    _alignAzDeg = (_alignAzDeg + deltaAzDeg)
        .clamp(-maxAlignOffsetDeg, maxAlignOffsetDeg)
        .toDouble();
    _alignPitchDeg = (_alignPitchDeg + deltaPitchDeg)
        .clamp(-maxAlignOffsetDeg, maxAlignOffsetDeg)
        .toDouble();
    notifyListeners();
  }

  /// Persiste la correzione manuale corrente, insieme al punto in cui è stata
  /// tarata. Da chiamare a fine trascinamento.
  Future<void> commitAlignOffset({double? latitude, double? longitude}) async {
    if (latitude != null && longitude != null) {
      _alignLat = latitude;
      _alignLng = longitude;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kAlignAz, _alignAzDeg);
      await prefs.setDouble(_kAlignPitch, _alignPitchDeg);
      final lat = _alignLat, lng = _alignLng;
      if (lat != null && lng != null) {
        await prefs.setDouble(_kAlignLat, lat);
        await prefs.setDouble(_kAlignLng, lng);
      }
    } catch (e) {
      debugPrint('[MFSettings] save align error: $e');
    }
  }

  /// Azzera la correzione manuale. Deve restare a un solo tocco: un offset
  /// tarato in un posto è sbagliato in un altro, e l'utente deve poter tornare
  /// ai sensori nudi senza chiedersi come.
  Future<void> resetAlignOffset() async {
    if (!hasAlignOffset) return;
    _alignAzDeg = 0;
    _alignPitchDeg = 0;
    _alignLat = null;
    _alignLng = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kAlignAz, 0);
      await prefs.setDouble(_kAlignPitch, 0);
      await prefs.remove(_kAlignLat);
      await prefs.remove(_kAlignLng);
    } catch (e) {
      debugPrint('[MFSettings] reset align error: $e');
    }
  }

  Future<void> setMaxDistanceKm(double km) async {
    final clamped = km.clamp(minDistanceKm, maxDistanceKm).toDouble();
    if ((clamped - _maxDistKm).abs() < 0.5) return;
    _maxDistKm = clamped;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kMaxDistKm, _maxDistKm);
    } catch (e) {
      debugPrint('[MFSettings] save maxDist error: $e');
    }
  }

  Future<void> setHorizontalFov(double deg) async {
    final clamped = deg.clamp(minHFov, maxHFov).toDouble();
    if ((clamped - _hFovDeg).abs() < 0.01) return;
    _hFovDeg = clamped;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kHFov, _hFovDeg);
    } catch (e) {
      debugPrint('[MFSettings] save hfov error: $e');
    }
  }

  Future<void> setVerticalFov(double deg) async {
    final clamped = deg.clamp(minVFov, maxVFov).toDouble();
    if ((clamped - _vFovDeg).abs() < 0.01) return;
    _vFovDeg = clamped;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kVFov, _vFovDeg);
    } catch (e) {
      debugPrint('[MFSettings] save vfov error: $e');
    }
  }

  /// Reset ai valori di default (FOV + distanza + correzione manuale).
  Future<void> reset() async {
    await setHorizontalFov(MountainProjection.defaultHorizontalFovDeg);
    await setVerticalFov(MountainProjection.defaultVerticalFovDeg);
    await setMaxDistanceKm(defaultDistanceKm);
    await resetAlignOffset();
  }
}
