import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/monetization_config.dart';
import '../constants/pro_products.dart';

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
  static const _kProductKey = 'pro_current_product_id';
  static const bool _defaultUnlocked = true; // closed testing / dev

  bool _unlocked = _defaultUnlocked;
  String? _currentProductId;
  bool _loaded = false;

  // Sottoscrizione a authStateChanges; viene aperta da
  // [initFirestoreSync] e chiusa da [dispose]. Singleton, vive per tutta
  // la durata dell'app.
  StreamSubscription<User?>? _authSub;
  bool _firestoreSyncInProgress = false;

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

  /// Identificatore del prodotto IAP attualmente attivo (es.
  /// `trailshare_pro_monthly` o `trailshare_pro_yearly`). `null` se
  /// l'utente è Pro per altri motivi (Android free Pro) o non lo è.
  ///
  /// Persistito su SharedPreferences così sopravvive ai restart app.
  /// Pulito quando l'abbonamento scade o viene esplicitamente revocato.
  String? get currentProductId => _currentProductId;

  /// `true` se l'utente ha attivo il piano mensile.
  bool get isMonthly => _currentProductId == ProProducts.monthly;

  /// `true` se l'utente ha attivo il piano annuale.
  bool get isYearly => _currentProductId == ProProducts.yearly;

  bool get isLoaded => _loaded;

  /// Carica lo stato persistito. Idempotente.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _unlocked = prefs.getBool(_kKey) ?? _defaultUnlocked;
      _currentProductId = prefs.getString(_kProductKey);
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[ProGate] load error: $e');
      _loaded = true;
    }
  }

  /// Imposta lo stato Pro. Usato dal flow di purchase (ancora da
  /// integrare) o dalla developer settings page per testing.
  ///
  /// Se [value] è `false`, viene anche pulito [currentProductId]
  /// (l'abbonamento non è più attivo, quindi non c'è più un prodotto).
  Future<void> setUnlocked(bool value) async {
    if (_unlocked == value) return;
    _unlocked = value;
    if (!value) {
      _currentProductId = null;
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kKey, value);
      if (!value) {
        await prefs.remove(_kProductKey);
      }
    } catch (e) {
      debugPrint('[ProGate] save error: $e');
    }
  }

  /// Salva il [productId] dell'abbonamento attivo. Chiamato da
  /// [SubscriptionManager] all'esito di un acquisto/restore confermato.
  ///
  /// Notifica i listener (la UI si aggiorna immediatamente) e persiste
  /// il valore così sopravvive ai restart dell'app.
  Future<void> setCurrentProductId(String? productId) async {
    if (_currentProductId == productId) return;
    _currentProductId = productId;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (productId == null) {
        await prefs.remove(_kProductKey);
      } else {
        await prefs.setString(_kProductKey, productId);
      }
    } catch (e) {
      debugPrint('[ProGate] save productId error: $e');
    }
  }

  // ───────────── Cross-device sync (6.B3) ─────────────

  /// Apre la sottoscrizione a [FirebaseAuth.authStateChanges] per
  /// sincronizzare lo stato Pro con `users/{uid}.proStatus` su
  /// Firestore (sorgente autorevole, scritta da `validateAppleReceipt`).
  ///
  /// Comportamento:
  /// - **Login**: chiama [syncFromFirestore] → eventualmente sblocca/blocca
  ///   Pro in base allo stato remoto (incluso productId attivo).
  /// - **Logout**: chiama [setUnlocked(false)] perché Pro è legato
  ///   all'account, non al device.
  ///
  /// Idempotente — chiamare più volte non duplica le sottoscrizioni.
  /// Da invocare in `main.dart` subito dopo [load].
  void initFirestoreSync() {
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        debugPrint('[ProGate] auth signed out → lock Pro');
        setUnlocked(false);
      } else {
        debugPrint('[ProGate] auth signed in (${user.uid}) → sync Firestore');
        syncFromFirestore();
      }
    });
  }

  /// Legge `users/{uid}.proStatus` da Firestore e allinea lo stato
  /// locale. Sicura da chiamare manualmente (es. dopo restore acquisti
  /// o pull-to-refresh in Settings).
  ///
  /// Resta no-op se l'utente non è autenticato. Su errore di rete
  /// mantiene il cache locale (offline-friendly).
  Future<void> syncFromFirestore() async {
    if (_firestoreSyncInProgress) {
      debugPrint('[ProGate] syncFromFirestore: already in progress, skip');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[ProGate] syncFromFirestore: no auth user, skip');
      return;
    }
    _firestoreSyncInProgress = true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data();
      final proStatus = data?['proStatus'] as Map<String, dynamic>?;

      if (proStatus == null) {
        debugPrint('[ProGate] syncFromFirestore: no proStatus on remote — '
            'keep local cache');
        return;
      }

      final remoteIsPro = proStatus['isPro'] == true;
      final expiresAtMs = (proStatus['expiresAtMs'] as num?)?.toInt();
      final productId = proStatus['productId'] as String?;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Pro è davvero attivo se: il server lo dice E non è scaduto.
      // Quando arriveranno i webhook V2 (6.B5), `isPro` sarà
      // aggiornato anche su revoche/cancellazioni autonome; per ora
      // ricontrolliamo l'expiry localmente per sicurezza.
      final stillActive =
          remoteIsPro && (expiresAtMs == null || expiresAtMs > now);

      debugPrint('[ProGate] syncFromFirestore: remoteIsPro=$remoteIsPro '
          'productId=$productId expires=$expiresAtMs stillActive=$stillActive');

      await setUnlocked(stillActive);
      if (stillActive) {
        await setCurrentProductId(productId);
      }
    } catch (e) {
      debugPrint('[ProGate] syncFromFirestore error (offline?): $e');
      // Manteniamo cache locale: niente blocco utente per problema rete.
    } finally {
      _firestoreSyncInProgress = false;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
