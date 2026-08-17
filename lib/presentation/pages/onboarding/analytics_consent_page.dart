import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/growth_analytics_service.dart';
import '../settings/privacy_policy_page.dart';

/// Richiesta di consenso alle statistiche d'uso.
///
/// Mostrata una sola volta, subito dopo l'onboarding — e agli utenti gia'
/// esistenti alla prima apertura dopo l'aggiornamento, perche' nessuno di
/// loro e' mai stato interpellato.
///
/// Le due scelte hanno lo stesso peso visivo di proposito. Un "Accetto"
/// grande e colorato accanto a un "No grazie" grigio e piccolo e' un dark
/// pattern: rende il consenso non libero, e quindi non valido.
///
/// Non c'e' modo di uscire senza rispondere (niente back, niente tap fuori):
/// finche' non c'e' una risposta Analytics resta spento, quindi rimandare non
/// darebbe comunque dati — ma lascerebbe la domanda aperta per sempre.
class AnalyticsConsentPage extends StatefulWidget {
  /// Invocata dopo che la scelta e' stata registrata.
  final VoidCallback onDecided;

  const AnalyticsConsentPage({super.key, required this.onDecided});

  @override
  State<AnalyticsConsentPage> createState() => _AnalyticsConsentPageState();
}

class _AnalyticsConsentPageState extends State<AnalyticsConsentPage> {
  bool _saving = false;

  Future<void> _decide(bool granted) async {
    if (_saving) return;
    setState(() => _saving = true);
    await GrowthAnalyticsService.instance.setAnalyticsConsent(granted);
    if (!mounted) return;
    widget.onDecided();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        const Icon(
                          Icons.insights_outlined,
                          size: 48,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.analyticsConsentTitle,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.analyticsConsentBody,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: context.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _bullet(context, Icons.check_circle_outline,
                            l10n.analyticsConsentIncluded),
                        _bullet(context, Icons.block_outlined,
                            l10n.analyticsConsentExcluded),
                        _bullet(context, Icons.settings_outlined,
                            l10n.analyticsConsentRevocable),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              settings: const RouteSettings(name: 'PrivacyPolicyPage'),
                              builder: (_) => const PrivacyPolicyPage(),
                            ),
                          ),
                          icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                          label: Text(l10n.privacyPolicy),
                        ),
                      ],
                    ),
                  ),
                ),

                // Stesso ingombro, stessa tipografia, nessuna gerarchia: la
                // scelta deve essere davvero libera.
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _decide(true),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: const BorderSide(color: AppColors.primary),
                      foregroundColor: AppColors.primary,
                    ),
                    child: Text(
                      l10n.analyticsConsentAccept,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _decide(false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(color: context.textMuted),
                      foregroundColor: context.textPrimary,
                    ),
                    child: Text(
                      l10n.analyticsConsentDecline,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bullet(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
