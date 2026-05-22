/// Configurazione globale della monetizzazione di TrailShare Pro.
///
/// **Stato 2026-04**: la monetizzazione è attiva solo su iOS. Su Android
/// non possiamo ancora vendere abbonamenti perché Google Play in Italia
/// richiede una Partita IVA registrata come merchant — e finché non è
/// aperta (decisione fiscale dell'autore in attesa di consulenza
/// commercialista), gli utenti Android hanno **Pro gratis**.
///
/// Quando si aprirà la P.IVA software e configureremo Google Play Console
/// con i prodotti `trailshare_pro_monthly` / `trailshare_pro_yearly`,
/// basterà flippare [androidMonetizationEnabled] a `true` e ricompilare.
///
/// ⚠️ **Migrazione utenti free → paid**: gli utenti Android che hanno
/// usato l'app gratis durante questo periodo NON saranno automaticamente
/// degradati al cambio del flag. La migration policy (grandfather /
/// 30-day grace / notifica in-app) sarà definita in 6.B prima di
/// abilitare la monetizzazione Android.
class MonetizationConfig {
  MonetizationConfig._();

  /// Se la monetizzazione è abilitata su iOS.
  /// Default: `true` — abbiamo configurato App Store Connect.
  static const bool iosMonetizationEnabled = true;

  /// Se la monetizzazione è abilitata su Android.
  /// Default: `false` — in attesa di P.IVA + Google Play merchant setup.
  ///
  /// Quando questo è `false`:
  /// - [ProGateService.isPro] ritorna sempre `true` su Android
  /// - [SubscriptionManager.init] esce subito senza connettersi a Play
  /// - [PaywallSheet] mostra una variante "Pro gratis su Android"
  /// - Il dev toggle in Settings è nascosto su Android
  static const bool androidMonetizationEnabled = false;
}
