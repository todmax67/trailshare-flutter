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
  bool _loaded = false;

  double get horizontalFovDeg => _hFovDeg;
  double get verticalFovDeg => _vFovDeg;
  double get maxDistanceKmValue => _maxDistKm;
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
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[MFSettings] load error: $e');
      _loaded = true;
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

  /// Reset ai valori di default (FOV + distanza).
  Future<void> reset() async {
    await setHorizontalFov(MountainProjection.defaultHorizontalFovDeg);
    await setVerticalFov(MountainProjection.defaultVerticalFovDeg);
    await setMaxDistanceKm(defaultDistanceKm);
  }
}
