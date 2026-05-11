import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferenze utente per l'auto-hide dello stats HUD nella pagina di
/// registrazione (1.D4).
///
/// - `enabled` (default true) → HUD scompare dopo [seconds] secondi di
///   inattività; tap su mappa, su chip mini o eventi di stato lo rimostrano.
/// - `seconds` (default 10) → valori consentiti: 5, 10, 20.
///
/// Singleton con ChangeNotifier così la UI (Settings + RecordPage) può
/// reagire al cambio senza ricariche.
class HudPrefsService extends ChangeNotifier {
  HudPrefsService._();
  static final HudPrefsService _instance = HudPrefsService._();
  factory HudPrefsService() => _instance;

  static const _kEnabledKey = 'auto_hide_hud_enabled';
  static const _kSecondsKey = 'auto_hide_hud_seconds';
  static const _defaultEnabled = true;
  static const _defaultSeconds = 10;
  static const allowedSeconds = [5, 10, 20];

  bool _enabled = _defaultEnabled;
  int _seconds = _defaultSeconds;
  bool _loaded = false;

  bool get enabled => _enabled;
  int get seconds => _seconds;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabledKey) ?? _defaultEnabled;
      final raw = prefs.getInt(_kSecondsKey) ?? _defaultSeconds;
      _seconds = allowedSeconds.contains(raw) ? raw : _defaultSeconds;
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[HudPrefs] load error: $e');
      _loaded = true;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabledKey, value);
    } catch (e) {
      debugPrint('[HudPrefs] setEnabled error: $e');
    }
  }

  Future<void> setSeconds(int value) async {
    if (!allowedSeconds.contains(value) || _seconds == value) return;
    _seconds = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSecondsKey, value);
    } catch (e) {
      debugPrint('[HudPrefs] setSeconds error: $e');
    }
  }
}
