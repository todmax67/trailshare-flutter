import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../constants/monetization_config.dart';
import '../constants/pro_products.dart';
import 'pro_gate_service.dart';

/// Risultato dell'acquisto restituito a chi ha lanciato `purchase(...)`.
enum PurchaseOutcome {
  /// Acquisto andato a buon fine, l'utente è ora Pro.
  success,

  /// L'utente ha annullato il flow di acquisto (chiusura sheet).
  canceled,

  /// Fallimento (errore di rete, carta rifiutata, ecc.). [SubscriptionManager.lastError]
  /// contiene il messaggio.
  error,

  /// In attesa: il purchase è in stato pending (richiede conferma genitori,
  /// Pix/SEPA in elaborazione, ecc.). Verrà completato in async sul listener.
  pending,
}

/// Stato dello store di acquisto. Espone [products] e [isPro] reattivi.
///
/// Pattern singleton + ChangeNotifier (allineato a [ProGateService]).
///
/// Architettura (6.B1):
/// 1. **init()** — apre la connessione, sottoscrive lo stream di
///    `purchaseStream`, fa la query iniziale dei prodotti.
/// 2. **purchase(productId)** — lancia il flow nativo (App Store sheet
///    / Play billing) e ritorna l'outcome.
/// 3. **restore()** — chiama `restorePurchases()` che ri-emette tutti
///    gli acquisti attivi sullo stream.
/// 4. **_handlePurchaseUpdate** — riceve gli eventi dallo stream e
///    aggiorna [ProGateService] di conseguenza.
///
/// Receipt validation server-side (6.B2): per ora `_verifyReceipt` è uno
/// stub che ritorna sempre `true`. In 6.B2 chiameremo una Cloud Function
/// che valida con Apple `verifyReceipt` / Google Play Developer API.
class SubscriptionManager extends ChangeNotifier {
  SubscriptionManager._();
  static final SubscriptionManager _instance = SubscriptionManager._();
  factory SubscriptionManager() => _instance;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _initialized = false;
  bool _available = false;
  List<ProductDetails> _products = const [];
  String? _lastError;

  /// Completer attivo durante un flow di acquisto, completato dal listener
  /// quando arriva l'evento corrispondente. Permette a `purchase(...)` di
  /// essere awaitable nonostante il design event-driven di in_app_purchase.
  Completer<PurchaseOutcome>? _activePurchase;
  String? _activePurchaseProductId;

  // ───────────── Public API ─────────────

  /// `true` quando [init] è stato chiamato e ha terminato.
  bool get isInitialized => _initialized;

  /// `true` se lo store IAP è disponibile su questo device (alcuni
  /// emulatori, build cinesi, regioni non supportate ritornano `false`).
  bool get isStoreAvailable => _available;

  /// Prodotti Pro disponibili (vuoto se [init] non ha ancora caricato o
  /// se lo store non li espone — es. ID non configurati).
  List<ProductDetails> get products => _products;

  /// Recupera un prodotto per ID (null se non disponibile).
  ProductDetails? productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Ultimo errore loggato (null se nessuno).
  String? get lastError => _lastError;

  /// Inizializza il manager. Idempotente.
  ///
  /// Da chiamare in `main()` dopo `Firebase.initializeApp()` e dopo
  /// `ProGateService().load()`.
  ///
  /// Su Android, finché [MonetizationConfig.androidMonetizationEnabled]
  /// è `false`, esce subito senza tentare alcuna connessione a Play
  /// Billing — gli utenti Android hanno Pro gratis automaticamente
  /// (vedi [ProGateService.isPro]).
  Future<void> init() async {
    if (_initialized) return;
    debugPrint('[SubscriptionManager] init()');

    // Skip Android se monetizzazione non attiva (manca P.IVA / merchant
    // Google Play). Marchiamo come inizializzato così la UI non resta
    // in loading state aspettando uno store che non interrogheremo mai.
    if (Platform.isAndroid &&
        !MonetizationConfig.androidMonetizationEnabled) {
      debugPrint('[SubscriptionManager] Android monetization disabled, '
          'skip init (users get free Pro)');
      _available = false;
      _initialized = true;
      notifyListeners();
      return;
    }

    try {
      _available = await _iap.isAvailable();
      debugPrint('[SubscriptionManager] store available: $_available');

      if (!_available) {
        _initialized = true;
        notifyListeners();
        return;
      }

      // Sottoscrivi lo stream PRIMA di fare query/restore: gli eventi pending
      // di acquisti precedenti potrebbero arrivare immediatamente.
      _purchaseSub = _iap.purchaseStream.listen(
        _handlePurchaseUpdate,
        onDone: () {
          debugPrint('[SubscriptionManager] purchaseStream done');
          _purchaseSub?.cancel();
        },
        onError: (Object e, StackTrace st) {
          debugPrint('[SubscriptionManager] purchaseStream error: $e');
          _lastError = e.toString();
          notifyListeners();
        },
      );

      // Carica i prodotti (best-effort, non bloccante per init).
      await _loadProducts();
      _initialized = true;
      notifyListeners();
    } catch (e, st) {
      debugPrint('[SubscriptionManager] init error: $e\n$st');
      _lastError = e.toString();
      _initialized = true;
      notifyListeners();
    }
  }

  /// Ricarica la lista prodotti dallo store. Utile dopo cambio regione,
  /// retry dopo errore di rete, ecc.
  Future<void> refreshProducts() async {
    if (!_available) return;
    await _loadProducts();
    notifyListeners();
  }

  Future<void> _loadProducts() async {
    try {
      final response = await _iap.queryProductDetails(ProProducts.all);
      if (response.error != null) {
        debugPrint('[SubscriptionManager] queryProductDetails error: '
            '${response.error}');
        _lastError = response.error!.message;
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('[SubscriptionManager] product IDs not found: '
            '${response.notFoundIDs}');
      }
      _products = response.productDetails;
      debugPrint('[SubscriptionManager] loaded ${_products.length} products: '
          '${_products.map((p) => "${p.id}@${p.price}").join(", ")}');
    } catch (e) {
      debugPrint('[SubscriptionManager] _loadProducts error: $e');
      _lastError = e.toString();
    }
  }

  /// Lancia il flow di acquisto per [productId]. Ritorna quando la
  /// transazione è terminata (success/error/canceled) oppure rimasta
  /// pending (caso raro: pagamento differito).
  ///
  /// Se [productId] non è disponibile, ritorna [PurchaseOutcome.error]
  /// con messaggio in [lastError].
  Future<PurchaseOutcome> purchase(String productId) async {
    if (!_available) {
      _lastError = 'Store non disponibile su questo dispositivo';
      return PurchaseOutcome.error;
    }
    final product = productById(productId);
    if (product == null) {
      _lastError = 'Prodotto $productId non disponibile';
      return PurchaseOutcome.error;
    }
    if (_activePurchase != null) {
      // Acquisto già in corso, evita doppia chiamata.
      _lastError = 'Acquisto già in corso';
      return PurchaseOutcome.error;
    }

    _activePurchase = Completer<PurchaseOutcome>();
    _activePurchaseProductId = productId;

    final param = PurchaseParam(productDetails: product);
    try {
      // Per gli abbonamenti usiamo `buyNonConsumable` (è la API corretta:
      // gli auto-renewable subscriptions sono trattati come non-consumable
      // dal punto di vista del client, lo store gestisce il rinnovo).
      final ok = await _iap.buyNonConsumable(purchaseParam: param);
      debugPrint('[SubscriptionManager] buyNonConsumable returned $ok '
          'for $productId');
      if (!ok) {
        // Lo store non ha potuto avviare il flow (es. utente non loggato
        // sullo store). Il listener non riceverà eventi: completiamo qui.
        _completeActive(PurchaseOutcome.error,
            error: 'Impossibile avviare l\'acquisto');
      }
    } catch (e) {
      debugPrint('[SubscriptionManager] buyNonConsumable threw: $e');
      _completeActive(PurchaseOutcome.error, error: e.toString());
    }

    return _activePurchase!.future;
  }

  /// Ripristina gli acquisti precedenti. Lo store ri-emette gli eventi
  /// di acquisto attivi sullo stream, dove il listener li elabora normalmente.
  ///
  /// Nota: non ritorna lo stato Pro direttamente — si controlla
  /// [ProGateService.isPro] dopo qualche secondo per vedere se è cambiato.
  Future<void> restore() async {
    if (!_available) {
      _lastError = 'Store non disponibile';
      return;
    }
    debugPrint('[SubscriptionManager] restorePurchases()');
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[SubscriptionManager] restore error: $e');
      _lastError = e.toString();
      notifyListeners();
    }
  }

  // ───────────── Purchase stream handler ─────────────

  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> updates) async {
    for (final purchase in updates) {
      debugPrint('[SubscriptionManager] purchase update '
          'id=${purchase.productID} status=${purchase.status} '
          'pendingComplete=${purchase.pendingCompletePurchase}');

      switch (purchase.status) {
        case PurchaseStatus.pending:
          // Mostriamo eventualmente un loader nella UI; il flow non
          // si conclude finché non arriva uno stato terminale.
          if (_isActive(purchase)) {
            // Non completiamo ancora — aspettiamo lo stato finale.
          }
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final isValid = await _verifyReceipt(purchase);
          if (isValid && ProProducts.isProProduct(purchase.productID)) {
            await ProGateService().setUnlocked(true);
            // Salva il productId attivo così la UI sa quale piano
            // l'utente ha (per mostrare upgrade vs manage).
            await ProGateService().setCurrentProductId(purchase.productID);
            debugPrint('[SubscriptionManager] Pro UNLOCKED via '
                '${purchase.status} of ${purchase.productID}');
          } else {
            debugPrint('[SubscriptionManager] receipt validation failed for '
                '${purchase.productID}');
          }
          if (_isActive(purchase)) {
            _completeActive(PurchaseOutcome.success);
          }
          break;

        case PurchaseStatus.error:
          debugPrint('[SubscriptionManager] purchase error: '
              '${purchase.error?.message}');
          _lastError = purchase.error?.message ?? 'Errore acquisto';
          if (_isActive(purchase)) {
            _completeActive(PurchaseOutcome.error,
                error: purchase.error?.message);
          }
          break;

        case PurchaseStatus.canceled:
          debugPrint('[SubscriptionManager] user canceled');
          if (_isActive(purchase)) {
            _completeActive(PurchaseOutcome.canceled);
          }
          break;
      }

      // Sempre completare la transazione lato store quando richiesto,
      // anche per acquisti restored, altrimenti restano in coda.
      if (purchase.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(purchase);
        } catch (e) {
          debugPrint('[SubscriptionManager] completePurchase error: $e');
        }
      }
    }
    notifyListeners();
  }

  bool _isActive(PurchaseDetails purchase) {
    return _activePurchase != null &&
        !_activePurchase!.isCompleted &&
        purchase.productID == _activePurchaseProductId;
  }

  void _completeActive(PurchaseOutcome outcome, {String? error}) {
    if (error != null) _lastError = error;
    final c = _activePurchase;
    _activePurchase = null;
    _activePurchaseProductId = null;
    if (c != null && !c.isCompleted) c.complete(outcome);
  }

  // ───────────── Receipt validation (stub per 6.B2) ─────────────

  /// Valida il receipt server-side. **Stub temporaneo** in 6.B1: ritorna
  /// sempre `true`. In 6.B2 chiameremo una Cloud Function che:
  /// - iOS: invia `purchase.verificationData.serverVerificationData` ad
  ///   Apple `https://buy.itunes.apple.com/verifyReceipt` (sandbox in dev).
  /// - Android: usa Google Play Developer API + service account per
  ///   verificare `purchase.verificationData.serverVerificationData`
  ///   (purchase token).
  ///
  /// Restituisce `true` solo se il receipt è autentico e l'abbonamento
  /// è ancora attivo (non scaduto, non rimborsato).
  Future<bool> _verifyReceipt(PurchaseDetails purchase) async {
    debugPrint('[SubscriptionManager] _verifyReceipt STUB (6.B2 todo) '
        'platform=${Platform.operatingSystem} '
        'productId=${purchase.productID} '
        'transactionId=${purchase.purchaseID}');
    // TODO(6.B2): chiamare Cloud Function `validateReceipt`.
    return true;
  }

  // ───────────── Cleanup ─────────────

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
