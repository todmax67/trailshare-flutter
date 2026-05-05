import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../data/models/osm_poi.dart';

/// Bottom sheet read-only per un POI proveniente da OpenStreetMap.
///
/// Differente da [PoiDetailSheet] (community) perché:
/// - Niente upvote/downvote/comments (è un dato pubblico, non social)
/// - Niente edit/delete (è bundlato nell'app, non nel DB utente)
/// - Mostra attribuzione "© OpenStreetMap contributors" come da licenza ODbL
/// - Espone link al sito web ufficiale (rifugi gestiti) e azione "Apri in
///   maps" per indicazioni stradali
Future<void> showOsmPoiDetailSheet(
  BuildContext context, {
  required OsmPoi poi,
  double? distanceFromTrackMeters,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _OsmPoiDetailSheet(
      poi: poi,
      distanceFromTrackMeters: distanceFromTrackMeters,
    ),
  );
}

class _OsmPoiDetailSheet extends StatelessWidget {
  final OsmPoi poi;
  final double? distanceFromTrackMeters;

  const _OsmPoiDetailSheet({
    required this.poi,
    this.distanceFromTrackMeters,
  });

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openInMaps() {
    // Geo URI standard: funziona con Google Maps / Apple Maps / Waze.
    // Fallback con coords decimali nel caso il geo: non sia gestito.
    final url = 'geo:${poi.latitude},${poi.longitude}'
        '?q=${poi.latitude},${poi.longitude}(${Uri.encodeComponent(poi.name)})';
    _openExternal(url);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icona tipo + nome + categoria
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(poi.type.icon, color: AppColors.info, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poi.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      poi.type.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Quick facts: elevazione + distanza dalla traccia se disponibili
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (poi.elevation != null)
                _Chip(
                  icon: Icons.terrain,
                  label: '${poi.elevation!.round()} m',
                ),
              if (distanceFromTrackMeters != null)
                _Chip(
                  icon: Icons.alt_route,
                  label: distanceFromTrackMeters! < 1000
                      ? '${distanceFromTrackMeters!.round()} m dal tracciato'
                      : '${(distanceFromTrackMeters! / 1000).toStringAsFixed(1)} km dal tracciato',
                ),
              _Chip(
                icon: Icons.public,
                label: 'OpenStreetMap',
              ),
            ],
          ),

          if (poi.operatorName != null) ...[
            const SizedBox(height: 16),
            _InfoRow(
              icon: Icons.business,
              label: 'Gestito da',
              value: poi.operatorName!,
            ),
          ],

          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Coordinate',
            value:
                '${poi.latitude.toStringAsFixed(5)}, ${poi.longitude.toStringAsFixed(5)}',
          ),

          const SizedBox(height: 20),

          // CTA: indicazioni + sito web (se disponibile)
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openInMaps,
                  icon: const Icon(Icons.directions, size: 18),
                  label: const Text('Indicazioni'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ),
              if (poi.website != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openExternal(poi.website!),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Sito web'),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 14),

          // Attribuzione obbligatoria ODbL
          Center(
            child: Text(
              'Dati © OpenStreetMap contributors (ODbL)',
              style: TextStyle(
                fontSize: 10,
                color: context.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.textMuted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: context.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: context.textMuted,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
