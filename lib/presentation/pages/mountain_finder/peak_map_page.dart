import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/map_styles.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/offline_tile_provider.dart';
import '../../../core/services/peaks_dataset_service.dart';
import '../../../data/models/mountain_peak.dart';

/// Pagina mappa centrata su una cima specifica.
///
/// Mostra:
/// - Marker prominente sulla cima target
/// - Marker più piccoli sulle cime vicine (entro 15 km) come contesto
/// - Card in basso con info della cima target
/// - Pulsante per cambiare stile mappa
class PeakMapPage extends StatefulWidget {
  final MountainPeak peak;

  const PeakMapPage({super.key, required this.peak});

  @override
  State<PeakMapPage> createState() => _PeakMapPageState();
}

class _PeakMapPageState extends State<PeakMapPage> {
  final MapController _mapController = MapController();
  int _currentMapStyle = 1; // default a Topo (più adatto per cime)
  List<MountainPeak> _nearbyPeaks = const [];

  @override
  void initState() {
    super.initState();
    _loadNearby();
  }

  Future<void> _loadNearby() async {
    final ds = PeaksDatasetService();
    if (!ds.isLoaded) await ds.ensureLoaded();
    final all = ds.findWithinRadius(
      widget.peak.latitude,
      widget.peak.longitude,
      radiusKm: 15,
    );
    if (!mounted) return;
    setState(() {
      _nearbyPeaks = all.where((p) => p.id != widget.peak.id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.peak.latitude, widget.peak.longitude);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peak.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.layers_outlined),
            tooltip: context.l10n.mapStyleTooltip,
            onPressed: () {
              setState(() {
                _currentMapStyle = (_currentMapStyle + 1) % mapStyles.length;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
              minZoom: 7,
              maxZoom: 17,
            ),
            children: [
              TileLayer(
                urlTemplate: mapStyles[_currentMapStyle].urlTemplate,
                subdomains: mapStyles[_currentMapStyle].subdomains,
                userAgentPackageName: 'com.trailshare.app',
                tileProvider: OfflineFallbackTileProvider(),
                tileBuilder:
                    mapStyles[_currentMapStyle].tileColorFilter != null
                        ? (context, tileWidget, tile) => ColorFiltered(
                              colorFilter: mapStyles[_currentMapStyle]
                                  .tileColorFilter!,
                              child: tileWidget,
                            )
                        : null,
              ),
              // Marker delle cime vicine (contesto)
              if (_nearbyPeaks.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final p in _nearbyPeaks)
                      Marker(
                        point: LatLng(p.latitude, p.longitude),
                        width: 28,
                        height: 28,
                        child: const Icon(
                          Icons.terrain,
                          color: Colors.white,
                          size: 18,
                          shadows: [
                            Shadow(
                                blurRadius: 4,
                                color: Colors.black54),
                          ],
                        ),
                      ),
                  ],
                ),
              // Marker prominente della cima target (sopra agli altri)
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 80,
                    height: 80,
                    alignment: Alignment.bottomCenter,
                    child: const _TargetPeakMarker(),
                  ),
                ],
              ),
            ],
          ),
          // Card info in basso
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + MediaQuery.of(context).padding.bottom,
            child: _buildInfoCard(context),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final p = widget.peak;
    final isVolcano = p.type == 'volcano';
    final accent = isVolcano ? AppColors.danger : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.themedBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isVolcano ? Icons.local_fire_department : Icons.terrain,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (p.elevation != null) ...[
                      Text(
                        '${p.elevation!.round()} m',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textMuted,
                          fontFeatures:
                              const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
                if (p.region != null && p.region!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.region!,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetPeakMarker extends StatelessWidget {
  const _TargetPeakMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 6,
              ),
            ],
          ),
          child: Icon(
            Icons.terrain,
            color: AppColors.primary,
            size: 24,
          ),
        ),
        // "Stelo" del marker
        Container(
          width: 2,
          height: 18,
          color: AppColors.primary,
        ),
      ],
    );
  }
}
