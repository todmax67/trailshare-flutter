import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/business_funnel_tracker.dart';
import '../../data/models/business.dart';

/// Epic 7.H4 — Banner mostrato sopra una scheda Spazio Pro quando la
/// scheda è `unclaimed` (pre-popolata da TrailShare, non ancora
/// rivendicata dal vero gestore) oppure quando `disclaimerVisible`
/// è true.
///
/// CTA primaria: "Rivendica" → apre la pagina del form claim.
/// CTA secondaria: "Segnala errore / Rimuovi" → mailto precompilato
/// (Epic 7.H9 — opt-out GDPR per dati pubblici aziendali).
///
/// Volutamente NON si auto-nasconde se l'utente loggato è già owner:
/// quel caso non si verifica per design (chi è owner di una scheda
/// significa che è già stata claimata, quindi tier != unclaimed e
/// disclaimerVisible = false).
class BusinessClaimBanner extends StatefulWidget {
  final Business business;

  /// Callback che apre la pagina di richiesta claim. Lascia che sia
  /// il chiamante (mobile vs web) a decidere come navigare —
  /// `Navigator.push` su mobile, route nominata `/b/{slug}/claim` su
  /// web ad esempio.
  final VoidCallback onClaimPressed;

  const BusinessClaimBanner({
    super.key,
    required this.business,
    required this.onClaimPressed,
  });

  /// Decide se il banner deve essere mostrato per il business dato.
  /// Comodo come gate in cima al builder del chiamante.
  static bool shouldShow(Business b) =>
      b.tier == BusinessTier.unclaimed || b.disclaimerVisible;

  @override
  State<BusinessClaimBanner> createState() => _BusinessClaimBannerState();
}

class _BusinessClaimBannerState extends State<BusinessClaimBanner> {
  @override
  void initState() {
    super.initState();
    // 7.H12 — fire-and-forget view tracking. Il tracker dedup per
    // (businessId, session) quindi evita doppi hit se il widget
    // rebuilda.
    final id = widget.business.id;
    if (id != null && BusinessClaimBanner.shouldShow(widget.business)) {
      BusinessFunnelTracker().trackUnclaimedView(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!BusinessClaimBanner.shouldShow(widget.business)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.warning.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.flag_outlined,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Scheda non ancora rivendicata',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Questa scheda è stata generata da TrailShare a partire da '
            'fonti pubbliche. Se sei il gestore, rivendicala per '
            'aggiornarla con foto, orari, listino e ricevere statistiche '
            'delle visite.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
          if (widget.business.sourceUrl != null) ...[
            const SizedBox(height: 6),
            Text(
              'Fonte: ${widget.business.sourceUrl}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    // 7.H12 — track click prima della navigation; il
                    // tracker è fire-and-forget, non aspetta.
                    final id = widget.business.id;
                    if (id != null) {
                      BusinessFunnelTracker().trackClaimStarted(id);
                    }
                    widget.onClaimPressed();
                  },
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Rivendica la scheda'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _openReportMailto(context),
                icon: const Icon(Icons.report_problem_outlined),
                tooltip: 'Segnala errore / chiedi rimozione',
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 7.H9 — Opt-out GDPR: mailto precompilato a info@trailshare.app.
  /// La gestione manuale entro 48h è descritta in
  /// docs/gtm/PRESEEDING_PRIVACY_UPDATE.md.
  Future<void> _openReportMailto(BuildContext context) async {
    final subject = Uri.encodeComponent(
      'Segnalazione/Rimozione scheda: ${widget.business.name}',
    );
    final body = Uri.encodeComponent(
      'Buongiorno team TrailShare,\n\n'
      'Vi segnalo un problema con la seguente scheda:\n'
      '- Nome: ${widget.business.name}\n'
      '- ID: ${widget.business.id}\n'
      '- URL: https://trailshare.app/b/${widget.business.slug}\n\n'
      'Motivo (errore nei dati / richiesta rimozione / altro):\n\n'
      'Grazie.',
    );
    final uri = Uri.parse(
      'mailto:info@trailshare.app?subject=$subject&body=$body',
    );
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SelectableText(
            'Scrivi a info@trailshare.app citando ID scheda: ${widget.business.id}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }
}
