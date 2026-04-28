/// Identificatori dei prodotti TrailShare Pro su App Store / Play Store.
///
/// Questi ID **devono coincidere esattamente** con quelli configurati su:
/// - **App Store Connect** → I miei app → TrailShare → Acquisti in-app
/// - **Google Play Console** → Crea/gestisci prodotti → Abbonamenti
///
/// Convenzione naming: `pro_<periodo>` per evitare collisioni future con
/// eventuali prodotti consumabili (es. `pack_<nome>`) o non-consumable
/// (es. `unlock_<feature>`).
///
/// Aggiornato: 2026-04 (Epic 6.B paywall foundation).
class ProProducts {
  ProProducts._();

  /// Abbonamento mensile auto-rinnovabile — €2,99/mese.
  /// Nessun trial.
  static const String monthly = 'trailshare_pro_monthly';

  /// Abbonamento annuale auto-rinnovabile — €19,99/anno.
  /// Trial gratuito 14 giorni (configurato server-side su App Store / Play).
  static const String yearly = 'trailshare_pro_yearly';

  /// Set completo da passare a `InAppPurchase.queryProductDetails`.
  static const Set<String> all = {monthly, yearly};

  /// Ritorna `true` se [productId] è un prodotto Pro riconosciuto.
  static bool isProProduct(String productId) => all.contains(productId);

  /// Helper UI: ritorna `true` se [productId] è il piano annuale.
  static bool isYearly(String productId) => productId == yearly;
}
