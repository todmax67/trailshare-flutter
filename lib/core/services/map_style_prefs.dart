import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/map_styles.dart';
import 'pro_gate_service.dart';

/// Preferenza globale dello stile mappa, condivisa tra tutte le interfacce
/// mappa dell'app (Discover, Planner, Registrazione, Track fullscreen, ...).
///
/// L'indice si riferisce alla lista [mapStyles]. Viene caricato all'avvio
/// in `main()` (load()) così le pagine possono leggerlo sincronicamente via
/// [index] come valore iniziale del proprio `_currentMapStyle`, e salvato
/// ad ogni cambio con [setIndex].
class MapStylePrefs {
  MapStylePrefs._();
  static final MapStylePrefs _instance = MapStylePrefs._();
  factory MapStylePrefs() => _instance;

  static const String _key = 'preferred_map_style_index';

  int _index = 0;

  /// Indice dello stile preferito in [mapStyles]. Già clampato a un valore
  /// valido e, se lo stile è Pro ma l'utente non è (più) Pro, ricade su
  /// Standard (0) per evitare di mostrare uno stile bloccato.
  int get index {
    final styles = mapStyles;
    var i = _index.clamp(0, styles.length - 1);
    if (styles[i].isPro && !ProGateService().isPro) i = 0;
    return i;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _index = prefs.getInt(_key) ?? 0;
    } catch (e) {
      debugPrint('[MapStylePrefs] load error: $e');
      _index = 0;
    }
  }

  Future<void> setIndex(int i) async {
    _index = i;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, i);
    } catch (e) {
      debugPrint('[MapStylePrefs] save error: $e');
    }
  }
}
