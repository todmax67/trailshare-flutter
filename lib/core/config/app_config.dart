/// Configurazione dell'app
/// 
/// Per sicurezza, queste chiavi dovrebbero essere caricate da:
/// - Variabili d'ambiente (flutter run --dart-define=ORS_API_KEY=xxx)
/// - File .env con flutter_dotenv
/// - Firebase Remote Config

class AppConfig {
  /// OpenRouteService API Key
  /// Ottieni la tua chiave gratuita su: https://openrouteservice.org/dev/#/signup
  /// Piano gratuito: 2000 richieste/giorno
  static const String orsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjJkZWEzNGEzNWZiNjQ1ZjU5MmFkNmQwZWRlOWU3MDRhIiwiaCI6Im11cm11cjY0In0=';

  /// Verifica se la API key è configurata
  static bool get isOrsConfigured => orsApiKey.isNotEmpty;
}
