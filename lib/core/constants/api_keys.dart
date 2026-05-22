/// Raccolta di API key di terze parti compilate dentro il binario.
///
/// **Sicurezza**: queste chiavi finiscono dentro l'IPA/APK e sono
/// estraibili con un decompiler. Per ognuna serve **restringerle lato
/// dashboard del fornitore** al bundle ID `com.trailshare.app`, così
/// anche se vengono estratte non sono utilizzabili in app di terzi.
///
/// In futuro (Epic 6.D?) valutiamo lo spostamento in Firebase Remote
/// Config per poterle ruotare senza un nuovo release.
class ApiKeys {
  ApiKeys._();

  /// MapTiler Cloud — usato per gli stili mappa Pro (Topo, Satellite,
  /// Inverno). Free tier: 100k tile/mese.
  ///
  /// **Restrizione attiva su dashboard MapTiler**: User-Agent deve
  /// contenere [mapTilerUserAgent]. Senza quell'header MapTiler
  /// rifiuta la richiesta. Le `TileLayer` che usano questi stili
  /// devono settare `userAgentPackageName: ApiKeys.mapTilerUserAgent`.
  static const String mapTiler = 'EagFyuDbTNmVOAX1zlbz';

  /// User-Agent da mandare insieme alle richieste tile MapTiler. Deve
  /// matchare la restrizione UA configurata sulla chiave nella
  /// dashboard MapTiler (`Intestazione user-agent consentita`).
  static const String mapTilerUserAgent = 'TrailShareApp';
}
