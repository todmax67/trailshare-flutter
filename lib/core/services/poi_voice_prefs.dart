import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/trail_poi.dart';

/// Preferenze utente sulla notifica vocale POI durante guided recording.
///
/// Per ogni [PoiType] l'utente può attivare/disattivare l'annuncio vocale.
/// Default:
/// - tipi "critici" (`isDefaultAnnounceable` true) → annunciati
/// - altri → silenziosi
///
/// Le preferenze sono salvate in SharedPreferences con chiave
/// `poi_voice_<firestoreKey>` → bool. Se la chiave non esiste si usa il
/// default del tipo.
class PoiVoicePrefs {
  PoiVoicePrefs._();
  static final PoiVoicePrefs _i = PoiVoicePrefs._();
  factory PoiVoicePrefs() => _i;

  static const String _keyPrefix = 'poi_voice_';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Ritorna se un POI di questo tipo deve essere annunciato.
  /// Legge la preferenza utente, fallback al default del tipo.
  Future<bool> isAnnounceable(PoiType type) async {
    final prefs = await _p;
    return prefs.getBool('$_keyPrefix${type.firestoreKey}') ??
        type.isDefaultAnnounceable;
  }

  /// Versione sincrona (usa una cache). Chiamala solo dopo [load].
  bool isAnnounceableSync(PoiType type) {
    final prefs = _prefs;
    if (prefs == null) return type.isDefaultAnnounceable;
    return prefs.getBool('$_keyPrefix${type.firestoreKey}') ??
        type.isDefaultAnnounceable;
  }

  /// Pre-carica le preferenze in cache. Chiamare all'avvio della sessione
  /// guidata così la detection successiva può essere sincrona.
  Future<void> load() async {
    await _p;
  }

  /// Imposta la preferenza per un tipo. Null = ripristino default.
  Future<void> setAnnounceable(PoiType type, bool? value) async {
    final prefs = await _p;
    final k = '$_keyPrefix${type.firestoreKey}';
    if (value == null) {
      await prefs.remove(k);
    } else {
      await prefs.setBool(k, value);
    }
  }

  /// Ritorna il numero di tipi attualmente attivi (per badge nelle settings).
  Future<int> countActive() async {
    final prefs = await _p;
    int count = 0;
    for (final t in PoiType.values) {
      final val = prefs.getBool('$_keyPrefix${t.firestoreKey}');
      if (val ?? t.isDefaultAnnounceable) count++;
    }
    return count;
  }
}
