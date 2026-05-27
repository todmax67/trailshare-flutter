/// Configurazione globale della monetizzazione di TrailShare Pro.
///
/// **Stato 2026-05-26**: monetizzazione attiva su **iOS** e **Android**.
///
/// Storia: la monetizzazione Android è stata abilitata il 2026-05-26
/// dopo apertura partita IVA come privato. I prodotti Pro
/// (`trailshare_pro_monthly` / `trailshare_pro_yearly`) sono configurati
/// su Google Play Console con prezzi €2,99/mese e €19,99/anno + trial
/// 14 giorni sul piano annuale.
///
/// **Migrazione utenti pre-2026-05-26 (Grandfather policy):**
/// tutti gli utenti il cui account Firebase Auth è stato creato prima
/// di 2026-05-26 sono **Pro a vita gratis su qualsiasi piattaforma**
/// (Android + iOS) come riconoscimento per averci usato durante il
/// periodo beta/early-adopter. La policy è applicata da
/// [ProGateService.syncFromFirestore] confrontando
/// `FirebaseAuth.user.metadata.creationTime` con
/// [androidGrandfatherCutoff].
///
/// Usiamo `creationTime` (sempre disponibile su FirebaseAuth) invece
/// di un campo custom `users/{uid}.createdAt` perché quel campo non
/// è mai stato scritto sistematicamente dall'app, quindi su 114 utenti
/// esistenti la maggior parte non l'aveva e sarebbe stata
/// erroneamente esclusa dal grandfather.
///
/// Cross-platform: `proStatus` viene scritto autoritativo su
/// Firestore, quindi un utente grandfathered che passa fra
/// iOS/Android mantiene lo stato Pro automaticamente al prossimo sync.
class MonetizationConfig {
  MonetizationConfig._();

  /// Se la monetizzazione è abilitata su iOS.
  /// Default: `true` — App Store Connect configurato dal 2026-04.
  static const bool iosMonetizationEnabled = true;

  /// Se la monetizzazione è abilitata su Android.
  /// Default: `true` dal 2026-05-26 — Google Play Console configurato
  /// con prodotti attivi e profilo pagamenti in setup.
  ///
  /// Quando questo è `false`:
  /// - [ProGateService.isPro] ritorna sempre `true` su Android
  /// - [SubscriptionManager.init] esce subito senza connettersi a Play
  /// - [PaywallSheet] mostra una variante "Pro gratis su Android"
  /// - Il dev toggle in Settings è nascosto su Android
  static const bool androidMonetizationEnabled = true;

  /// Cutoff per la Grandfather policy (iOS + Android).
  ///
  /// Tutti gli utenti con `FirebaseAuth.user.metadata.creationTime`
  /// **strettamente precedente** a questa data ricevono Pro gratis a
  /// vita su qualsiasi piattaforma come riconoscimento per averci
  /// usato durante il periodo beta/early-adopter.
  ///
  /// La data è il momento in cui [androidMonetizationEnabled] è passato
  /// da `false` a `true` (2026-05-26 mezzanotte UTC). NON cambiare questa
  /// data dopo il deploy in prod, altrimenti utenti già grandfathered
  /// perderebbero lo stato.
  ///
  /// Nome storico mantenuto (`androidGrandfatherCutoff`) per coerenza
  /// git/codice, ma la policy è cross-platform.
  static final DateTime androidGrandfatherCutoff =
      DateTime.utc(2026, 5, 26);
}
