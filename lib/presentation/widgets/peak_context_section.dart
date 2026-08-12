import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../core/services/peak_context_service.dart';
import '../../data/models/hut_opening.dart';
import '../../data/models/mountain_peak.dart';

/// Cosa c'è attorno a una vetta: rifugi con le loro aperture, e i sentieri che
/// ci passano.
///
/// È l'unica parte del Peak Finder che i concorrenti non possono replicare.
/// Riconoscere una montagna lo sanno fare tutti — dire *«il Rifugio Curò è 300
/// metri più in basso, e in questa stagione è aperto»* lo sa fare solo un'app
/// che conosce già i rifugi e i sentieri.
///
/// Carica in sottofondo e non blocca mai la scheda: se manca la rete restano i
/// rifugi, che vivono in un asset locale.
class PeakContextSection extends StatefulWidget {
  final MountainPeak peak;

  const PeakContextSection({super.key, required this.peak});

  @override
  State<PeakContextSection> createState() => _PeakContextSectionState();
}

class _PeakContextSectionState extends State<PeakContextSection> {
  List<PeakShelter>? _shelters;
  List<PeakTrail>? _trails;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = PeakContextService();
    // I due caricamenti sono indipendenti e si mostrano appena pronti: i
    // rifugi arrivano da un asset locale in millisecondi, i sentieri possono
    // dover interrogare la cache. Aspettare il secondo per mostrare il primo
    // sarebbe un'attesa gratuita.
    service.sheltersNear(widget.peak).then((v) {
      if (mounted) setState(() => _shelters = v);
    });
    service.trailsNear(widget.peak).then((v) {
      if (mounted) setState(() => _trails = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shelters = _shelters ?? const <PeakShelter>[];
    final trails = _trails ?? const <PeakTrail>[];
    final loading = _shelters == null || _trails == null;

    if (!loading && shelters.isEmpty && trails.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shelters.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionTitle(
            icon: Icons.cabin,
            label: 'Ricoveri vicini',
          ),
          const SizedBox(height: 8),
          for (final s in shelters) _ShelterRow(shelter: s, peak: widget.peak),
        ],
        if (trails.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionTitle(
            icon: Icons.hiking,
            label: 'Sentieri che ci passano',
          ),
          const SizedBox(height: 8),
          for (final t in trails) _TrailRow(item: t),
        ],
        if (loading) ...[
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.textMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.textSecondary),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ShelterRow extends StatelessWidget {
  final PeakShelter shelter;
  final MountainPeak peak;

  const _ShelterRow({required this.shelter, required this.peak});

  @override
  Widget build(BuildContext context) {
    final opening = openingLabel(shelter.opening);
    final delta = shelter.elevationDeltaFrom(peak);

    final details = <String>[
      formatShortDistance(shelter.distanceMeters),
      if (delta != null) formatElevationDelta(delta),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(shelter.poi.type.icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shelter.poi.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  details.join(' · '),
                  style: TextStyle(fontSize: 12, color: context.textMuted),
                ),
              ],
            ),
          ),
          // Lo stato compare solo quando c'è qualcosa di vero da dire: un dato
          // di stagioni passate non diventa "aperto", resta silenzio.
          if (opening != null) _OpeningChip(status: shelter.opening!, label: opening),
        ],
      ),
    );
  }
}

class _OpeningChip extends StatelessWidget {
  final OpeningStatus status;
  final String label;

  const _OpeningChip({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final canSayOpen = status.canSayOpen;
    final needsCaveat = status.needsCaveat;
    final color = canSayOpen ? AppColors.success : context.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          // Un punto interrogativo accanto a "di solito aperto": il verdetto
          // non va mai mostrato da solo quando è una stima.
          if (needsCaveat && !canSayOpen) ...[
            const SizedBox(width: 3),
            Icon(Icons.help_outline, size: 11, color: color),
          ],
        ],
      ),
    );
  }
}

class _TrailRow extends StatelessWidget {
  final PeakTrail item;
  const _TrailRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = item.trail;
    final details = <String>[
      if (t.difficulty != null && t.difficulty!.isNotEmpty) t.difficulty!,
      if (item.lengthLabel != null) item.lengthLabel!,
      if (item.elevationGainRounded != null) '${item.elevationGainRounded} m D+',
      if (t.tempoLeggibile != null) t.tempoLeggibile!,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.reachesSummit ? Icons.flag : Icons.route,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.ref != null && t.ref!.isNotEmpty
                      ? '${t.ref} · ${t.name}'
                      : t.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: TextStyle(fontSize: 12, color: context.textMuted),
                  ),
                // Si dice come stanno le cose: "tocca la vetta" oppure "passa
                // a 300 m". La geometria del catalogo è semplificata, e
                // spacciarla per precisa al metro sarebbe inventare.
                Text(
                  item.reachesSummit
                      ? 'arriva in vetta'
                      : 'passa a ${formatShortDistance(item.closestMeters)} dalla vetta',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
