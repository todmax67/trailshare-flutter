/// Configurazione dell'app
library;

class AppConfig {
  /// URL del proxy ORS tramite Cloud Function
  /// Le richieste passano dal backend che detiene la API key in modo sicuro
  static const String orsProxyBaseUrl =
      'https://europe-west3-trailshare-5334b.cloudfunctions.net/orsProxy';

  /// Verifica se il proxy ORS è configurato
  static bool get isOrsConfigured => orsProxyBaseUrl.isNotEmpty;

  /// Feature flag — nuova Home Feed (prototipo branch prototype/home-feed).
  /// Quando `true`, la tab 0 della bottom nav diventa HomeFeedPage e
  /// l'index di default è 0. Quando `false`, comportamento legacy
  /// (tab 0 = Scopri, default = Community).
  ///
  /// Default `true` SOLO sul branch prototipo per il test. Tornerà a
  /// `false` (o dietro Remote Config) prima del merge in main.
  static const bool useNewHomeFeed = true;
}
