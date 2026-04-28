import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/monetization_config.dart';

/// Feature flag che decide se l'utente ha accesso alle funzioni
/// **TrailShare Pro** (a pagamento).
///
/// Stato attuale (v2.1.0): l'infrastruttura paywall (6.B) non è ancora
/// stata implementata, quindi il gate è basato su una preferenza locale
/// `pro_unlocked` (default: true durante lo sviluppo + closed testing).
///
/// Quando arriverà 6.B (StoreKit + Play Billing + receipt validation),
/// il valore tornerà da una verifica remota dello stato abbonamento
/// dell'utente, con cache locale per il funzionamento offline.
///
/// Pattern singleton + ChangeNotifier per consentire alla UI di
/// reagire al cambio di stato (es. paywall sheet che si chiude dopo
/// successful purchase).
class ProGateService extends ChangeNotifier {
  ProGateService._();
  static final ProGateService _instance = ProGateService._();
  factory ProGateService() => _instance;

  static const _kKey = 'pro_unlocked';
  static const bool _defaultUnlocked = true; // closed testing / dev

  bool _unlocked = _defaultUnlocked;
  bool _loaded = false;

  /// Ritorna `true` se l'utente ha accesso alle funzioni Pro.
  ///
  /// Su Android, finché [MonetizationConfig.androidMonetizationEnabled]
  /// è `false` (attesa P.IVA / Google Play merchant), Pro è **sempre**
  /// sbloccato — gli utenti Android hanno tutto gratis temporaneamente.
  bool get isPro {
    if (Platform.isAndroid &&
        !MonetizationConfig.androidMonetizationEnabled) {
      return true;
    }
    return _unlocked;
  }

  /// `true` se la monetizzazione è effettivamente attiva su questa
  /// piattaforma (cioè può esistere un acquisto reale). Usato dalla UI
  /// per decidere se mostrare il paywall o un messaggio "Pro gratis".
  bool get isMonetizationActive {
    if (Platform.isAndroid) {
      return MonetizationConfig.androidMonetizationEnabled;
    }
    if (Platform.isIOS) {
      return MonetizationConfig.iosMonetizationEnabled;
    }
    return false;
  }

  bool get isLoaded => _loaded;

  /// Carica lo stato persistito. Idempotente.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _unlocked = prefs.getBool(_kKey) ?? _defaultUnlocked;
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[ProGate] load error: $e');
      _loaded = true;
    }
  }

  /// Imposta lo stato Pro. Usato dal flow di purchase (ancora da
  /// integrare) o dalla developer settings page per testing.
  Future<void> setUnlocked(bool value) async {
    if (_unlocked == value) return;
    _unlocked = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kKey, value);
    } catch (e) {
      debugPrint('[ProGate] save error: $e');
    }
  }
}
