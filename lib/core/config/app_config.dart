/// Configurazione dell'app

class AppConfig {
  /// URL del proxy ORS tramite Cloud Function
  /// Le richieste passano dal backend che detiene la API key in modo sicuro
  static const String orsProxyBaseUrl =
      'https://europe-west3-trailshare-5334b.cloudfunctions.net/orsProxy';

  /// Verifica se il proxy ORS è configurato
  static bool get isOrsConfigured => orsProxyBaseUrl.isNotEmpty;
}
