import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../core/services/pro_gate_service.dart';
import '../../core/services/trail_conditions_ai_service.dart';
import '../../data/repositories/trail_conditions_repository.dart';
import 'paywall_sheet.dart';

/// Killer feature Pro 6.6: card AI summary delle condizioni sentiero
/// community. Mostrata in cima alle pagine dettaglio trail/track con
/// almeno una segnalazione recente.
///
/// Stato:
/// - **Free**: tile teaser ("Riassunto AI delle condizioni") che apre
///   la PaywallSheet con trigger `discoveryUpsell`.
/// - **Pro**: chiama la Cloud Function al primo tap "Genera riassunto"
///   e mostra il testo (cache 24h server-side).
class TrailConditionsAiCard extends StatefulWidget {
  /// ID del trail community OSM o dell'ID custom usato per le segnalazioni.
  final String trailId;

  /// Nome del sentiero (passato al prompt per contesto).
  final String trailName;

  const TrailConditionsAiCard({
    super.key,
    required this.trailId,
    required this.trailName,
  });

  @override
  State<TrailConditionsAiCard> createState() => _TrailConditionsAiCardState();
}

class _TrailConditionsAiCardState extends State<TrailConditionsAiCard> {
  /// Soglia minima di segnalazioni community per cui ha senso
  /// generare un riassunto AI. Sotto questo valore l'output sarebbe
  /// solo una parafrasi della singola nota (zero valore aggiunto) e
  /// confonderebbe l'utente che pensa "raddoppia la mia segnalazione".
  /// Sopra questa soglia la sintesi inizia ad avere significato.
  static const int _minReportsForSummary = 2;

  TrailConditionsSummary? _summary;
  bool _loading = false;
  String? _error;

  // Report count caricato dal repo. Se 0 la card resta hidden.
  int? _communityReportsCount;

  @override
  void initState() {
    super.initState();
    _loadReportsCount();
  }

  Future<void> _loadReportsCount() async {
    try {
      final reports = await TrailConditionsRepository()
          .getReportsForTrail(widget.trailId, limit: 20);
      if (!mounted) return;
      debugPrint('[TrailConditionsAi] trail=${widget.trailId} '
          'community reports=${reports.length}');
      setState(() => _communityReportsCount = reports.length);
    } catch (e) {
      debugPrint('[TrailConditionsAi] loadReportsCount error: $e');
      if (mounted) setState(() => _communityReportsCount = 0);
    }
  }

  Future<void> _generate({bool forceRefresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await TrailConditionsAiService().summarize(
        trailId: widget.trailId,
        trailName: widget.trailName,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _summary = result;
        _loading = false;
      });
    } on TrailConditionsAiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _onProTap() async {
    final isPro = ProGateService().isPro;
    if (!isPro) {
      await showPaywallSheet(
        context,
        trigger: PaywallTrigger.discoveryUpsell,
      );
      // Se l'utente compra durante il sheet, ProGate notifica e
      // possiamo continuare. Altrimenti restiamo sul teaser.
      if (!mounted || !ProGateService().isPro) return;
    }
    await _generate();
  }

  @override
  Widget build(BuildContext context) {
    final count = _communityReportsCount;
    // Loading state — non disegniamo nulla finché non sappiamo il count.
    if (count == null) return const SizedBox.shrink();

    // Sotto la soglia minima per un riassunto utile:
    // - Free: nascondiamo completamente. Mostrare il teaser PRO
    //   sopra un trail con 0 o 1 segnalazione (già visibile sotto
    //   nella sezione "Condizioni sentiero") sembrerebbe ridondante
    //   o promettere valore che l'AI non può davvero fornire.
    // - Pro: mostriamo la card con stato "in attesa" così la feature
    //   è discoverable. Il summary parte da 2+ segnalazioni.
    if (count < _minReportsForSummary && !ProGateService().isPro) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.06),
            AppColors.info.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Condizioni sentiero · AI',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                if (!ProGateService().isPro)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final reportsCount = _communityReportsCount ?? 0;
    final isPro = ProGateService().isPro;

    // Pro + sotto la soglia → stato "in attesa" educativo. Il
    // riassunto non parte finché non ci sono almeno 2 segnalazioni
    // community: con 1 sola, l'AI parafraserebbe la stessa nota
    // visibile sotto nella sezione "Condizioni sentiero" — zero
    // valore aggiunto.
    if (isPro && reportsCount < _minReportsForSummary) {
      final remaining = _minReportsForSummary - reportsCount;
      return Row(
        children: [
          Icon(Icons.hourglass_empty, size: 16, color: context.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reportsCount == 0
                  ? 'Nessuna segnalazione community su questo sentiero. '
                      'Quando ci saranno almeno $_minReportsForSummary '
                      'segnalazioni potrò generarti un riassunto.'
                  : 'C\'è $reportsCount segnalazione su questo sentiero. '
                      'Servon$remaining segnalazion${remaining == 1 ? 'e' : 'i'} '
                      'in più per generare un riassunto AI utile.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    // Free + nessun summary → teaser
    if (!isPro && _summary == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sblocca con TrailShare Pro un riassunto AI delle '
            '${(_communityReportsCount ?? 0)} segnalazion${(_communityReportsCount ?? 0) == 1 ? 'e' : 'i'} '
            'recenti su questo sentiero. In 3 secondi sai se il '
            'percorso è praticabile, dove c\'è fango, neve o tratti '
            'chiusi.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _onProTap,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Genera riassunto'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ),
        ],
      );
    }

    // Loading
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Sto leggendo le segnalazioni…',
                style: TextStyle(fontSize: 13)),
          ],
        ),
      );
    }

    // Error
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 16, color: AppColors.danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_error!,
                    style: TextStyle(
                        fontSize: 13, color: context.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _generate(forceRefresh: true),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Riprova'),
          ),
        ],
      );
    }

    // Pro + nessun summary ancora → bottone "Genera"
    if (_summary == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${(_communityReportsCount ?? 0)} segnalazion${(_communityReportsCount ?? 0) == 1 ? 'e' : 'i'} '
            'recenti disponibil${(_communityReportsCount ?? 0) == 1 ? 'e' : 'i'} '
            'per questo sentiero.',
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Genera riassunto AI'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ),
        ],
      );
    }

    // Summary disponibile
    final s = _summary!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.hasCriticalReports)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.warning_amber,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 4),
                Text(
                  'Segnalazioni critiche recenti',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
        Text(
          s.summary ?? '—',
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.people, size: 12, color: context.textMuted),
            const SizedBox(width: 4),
            Text(
              '${s.reportsCount} segnalazion${s.reportsCount == 1 ? 'e' : 'i'}',
              style: TextStyle(fontSize: 11, color: context.textMuted),
            ),
            if (s.generatedAt != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.schedule, size: 12, color: context.textMuted),
              const SizedBox(width: 4),
              Text(
                _ageString(s.generatedAt!),
                style: TextStyle(fontSize: 11, color: context.textMuted),
              ),
            ],
            const Spacer(),
            InkWell(
              onTap: () => _generate(forceRefresh: true),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, size: 12, color: context.textMuted),
                    const SizedBox(width: 2),
                    Text(
                      'Aggiorna',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _ageString(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours}h fa';
    return '${diff.inDays}g fa';
  }
}
