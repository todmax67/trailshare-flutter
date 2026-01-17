import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';

/// Pagina Privacy Policy
/// 
/// Mostra la privacy policy dell'app, obbligatoria per App Store e Play Store.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  // URL della privacy policy online (opzionale)
  static const String _privacyPolicyUrl = 'https://trailshare.app/privacy';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Center(
              child: Column(
                children: [
                  Icon(Icons.privacy_tip_outlined, size: 48, color: AppColors.primary),
                  SizedBox(height: 8),
                  Text(
                    'Privacy Policy',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Ultimo aggiornamento: Gennaio 2025',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Sezioni
            _buildSection(
              'Introduzione',
              'TrailShare ("noi", "nostro" o "app") rispetta la tua privacy. '
              'Questa informativa descrive quali dati raccogliamo, come li utilizziamo '
              'e i tuoi diritti in merito.',
            ),

            _buildSection(
              'Dati che raccogliamo',
              '• **Dati di registrazione**: email, nome utente, foto profilo (opzionale)\n'
              '• **Dati di posizione**: coordinate GPS durante la registrazione delle tracce\n'
              '• **Dati delle attività**: tracce registrate, statistiche, dislivello, distanza\n'
              '• **Dati social**: follower, following, "cheers" (like)\n'
              '• **Dati del dispositivo**: modello, sistema operativo, per migliorare l\'app',
            ),

            _buildSection(
              'Come utilizziamo i tuoi dati',
              '• Fornire e migliorare i servizi dell\'app\n'
              '• Salvare e sincronizzare le tue tracce\n'
              '• Abilitare funzionalità social (follow, cheers, classifica)\n'
              '• Funzionalità LiveTrack per condividere la posizione in tempo reale\n'
              '• Analisi aggregate per migliorare l\'esperienza utente',
            ),

            _buildSection(
              'Condivisione dei dati',
              '• **Non vendiamo** i tuoi dati personali a terzi\n'
              '• Le tracce pubblicate sono visibili ad altri utenti\n'
              '• LiveTrack condivide la posizione solo con chi ha il link\n'
              '• Utilizziamo Firebase (Google) per l\'archiviazione sicura dei dati',
            ),

            _buildSection(
              'Conservazione dei dati',
              'I tuoi dati vengono conservati finché mantieni un account attivo. '
              'Puoi eliminare il tuo account in qualsiasi momento dalla sezione '
              'Impostazioni, e tutti i tuoi dati verranno rimossi entro 30 giorni.',
            ),

            _buildSection(
              'I tuoi diritti',
              '• **Accesso**: puoi visualizzare tutti i tuoi dati nell\'app\n'
              '• **Modifica**: puoi modificare il tuo profilo in qualsiasi momento\n'
              '• **Eliminazione**: puoi eliminare il tuo account e tutti i dati associati\n'
              '• **Esportazione**: puoi esportare le tue tracce in formato GPX',
            ),

            _buildSection(
              'Sicurezza',
              'Utilizziamo Firebase Authentication e Firestore con crittografia '
              'per proteggere i tuoi dati. Le connessioni sono protette tramite HTTPS.',
            ),

            _buildSection(
              'Minori',
              'L\'app non è destinata a minori di 13 anni. Non raccogliamo '
              'consapevolmente dati di bambini sotto questa età.',
            ),

            _buildSection(
              'Modifiche alla policy',
              'Potremmo aggiornare questa privacy policy. Ti notificheremo '
              'di eventuali modifiche significative tramite l\'app o email.',
            ),

            _buildSection(
              'Contatti',
              'Per domande sulla privacy, contattaci a:\n'
              '📧 privacy@trailshare.app',
            ),

            const SizedBox(height: 24),

            // Link versione web
            Center(
              child: TextButton.icon(
                onPressed: () => _openPrivacyPolicyWeb(context),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Visualizza versione web'),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPrivacyPolicyWeb(BuildContext context) async {
    final uri = Uri.parse(_privacyPolicyUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire il link')),
        );
      }
    }
  }
}
