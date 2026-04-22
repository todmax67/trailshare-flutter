import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/l10n_extension.dart';
import '../../core/services/weekly_challenges_service.dart';
import '../../data/models/discovery_prompt.dart';
import '../pages/dashboard/dashboard_page.dart';
import '../pages/settings/emergency_contacts_page.dart';
import '../pages/tours/tour_edit_page.dart';

/// Registry dei [DiscoveryPrompt] locali (hard-coded).
///
/// Costruito on-demand con un [BuildContext] così le callback `onCta` possono
/// usare `Navigator.push` e i testi sono localizzati.
///
/// Aggiungere nuove card qui. La priorità è puramente indicativa; il service
/// ordinerà DESC e prenderà le prime 5.
class DiscoveryPromptsRegistry {
  static List<DiscoveryPrompt> all(BuildContext context) {
    final l10n = context.l10n;

    return [
      // ─── 0. Sfida settimanale (priority max: questa e' la feature
      //      headline di v1.9.0, la vogliamo sempre top). Il service
      //      garantisce che esista una sfida; qui non verifichiamo
      //      direttamente — la card scompare quando l'utente apre la
      //      Dashboard (la sfida non e' nuova, e' gia' stata vista)? No:
      //      teniamo il prompt sempre utile finche' non dismissato.
      DiscoveryPrompt(
        id: 'weekly_challenge_current',
        title: l10n.discoveryChallengeTitle,
        description: l10n.discoveryChallengeDesc,
        icon: Icons.flag_outlined,
        accentColor: const Color(0xFFE07B4C),
        ctaLabel: l10n.discoveryChallengeCta,
        priority: 100,
        condition: (_) {
          // Visibile solo se esiste una sfida attiva non completata.
          final c = WeeklyChallengesService().cached;
          return c != null && c.isActive && !c.isCompleted;
        },
        onCta: (ctx) {
          Navigator.push(
            ctx,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
          );
        },
      ),

      // ─── 1. Attiva Lifeline (sicurezza) ────────────────────────────
      DiscoveryPrompt(
        id: 'lifeline_setup',
        title: l10n.discoveryLifelineTitle,
        description: l10n.discoveryLifelineDesc,
        icon: Icons.shield_outlined,
        accentColor: const Color(0xFFEF5350),
        ctaLabel: l10n.discoveryLifelineCta,
        priority: 95,
        condition: (s) => !s.hasLifelineContacts && s.trackCount >= 2,
        onCta: (ctx) {
          Navigator.push(
            ctx,
            MaterialPageRoute(builder: (_) => const EmergencyContactsPage()),
          );
        },
      ),

      // ─── 2. Crea il primo tour multi-giorno ────────────────────────
      DiscoveryPrompt(
        id: 'first_tour',
        title: l10n.discoveryTourTitle,
        description: l10n.discoveryTourDesc,
        icon: Icons.map_outlined,
        accentColor: AppColors.primary,
        ctaLabel: l10n.discoveryTourCta,
        priority: 70,
        condition: (s) => s.trackCount >= 5 && s.tourCount == 0,
        onCta: (ctx) {
          Navigator.push(
            ctx,
            MaterialPageRoute(builder: (_) => const TourEditPage()),
          );
        },
      ),

      // ─── 3. Condividi con link web ─────────────────────────────────
      DiscoveryPrompt(
        id: 'web_sharing',
        title: l10n.discoveryShareTitle,
        description: l10n.discoveryShareDesc,
        icon: Icons.link,
        accentColor: const Color(0xFF1976D2),
        ctaLabel: l10n.discoveryShareCta,
        priority: 55,
        condition: (s) => s.hasPublishedTrack,
        onCta: (ctx) {
          // Spiegazione + suggerimento: apri la detail di una tua traccia
          // pubblica e usa il pulsante share. Non apriamo automaticamente
          // una traccia per non "scegliere" al posto dell'utente.
          _showInfoDialog(
            ctx,
            title: l10n.discoveryShareTitle,
            body: l10n.discoveryShareInfo,
          );
        },
      ),

      // ─── 4. Esporta in FIT per Garmin Connect ─────────────────────
      DiscoveryPrompt(
        id: 'fit_export',
        title: l10n.discoveryFitTitle,
        description: l10n.discoveryFitDesc,
        icon: Icons.watch_outlined,
        accentColor: const Color(0xFF388E3C),
        ctaLabel: l10n.discoveryFitCta,
        priority: 45,
        condition: (s) => s.trackCount >= 8 && !s.hasExportedFit,
        onCta: (ctx) {
          _showInfoDialog(
            ctx,
            title: l10n.discoveryFitTitle,
            body: l10n.discoveryFitInfo,
          );
        },
      ),

      // ─── 5. Pianifica un percorso ──────────────────────────────────
      DiscoveryPrompt(
        id: 'planner_intro',
        title: l10n.discoveryPlannerTitle,
        description: l10n.discoveryPlannerDesc,
        icon: Icons.edit_location_alt_outlined,
        accentColor: const Color(0xFFF57C00),
        ctaLabel: l10n.discoveryPlannerCta,
        priority: 40,
        condition: (s) => s.trackCount >= 3 && !s.hasUsedPlanner,
        onCta: (ctx) {
          _showInfoDialog(
            ctx,
            title: l10n.discoveryPlannerTitle,
            body: l10n.discoveryPlannerInfo,
          );
        },
      ),
    ];
  }

  static void _showInfoDialog(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.gotItAction),
          ),
        ],
      ),
    );
  }
}
