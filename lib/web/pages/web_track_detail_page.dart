import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/gpx_service.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/web_layout.dart';
import '../../data/models/track.dart';

/// Detail web di una traccia: versione "consultativa" leggera.
///
/// Mostra: mappa con polyline, stats principali, download GPX.
/// **Non** usa il TrackDetailPage mobile (troppe dipendenze
/// `dart:io` su upload/share/health-sync che non servono qui e
/// rischiano runtime errors su web).
class WebTrackDetailPage extends StatelessWidget {
  final Track track;

  const WebTrackDetailPage({super.key, required this.track});

  Future<void> _downloadGpx(BuildContext context) async {
    try {
      final gpx = GpxService().generateGpx(track);
      final safe = track.name
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
          .toLowerCase();
      final filename = '${safe.isEmpty ? 'track' : safe}.gpx';
      await downloadString(gpx, filename, 'application/gpx+xml');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore export: $e')),
      );
    }
  }

  String _fmtDate(DateTime d) {
    const months = [
      'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
      'lug', 'ago', 'set', 'ott', 'nov', 'dic',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final stats = track.stats;
    final points = track.points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
    final hasPoints = points.isNotEmpty;
    final bounds = hasPoints ? LatLngBounds.fromPoints(points) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(track.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Scarica GPX',
            onPressed: () => _downloadGpx(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: WebContentWrapper(
        maxWidth: 1000,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Mappa
            Container(
              height: 420,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasPoints
                  ? FlutterMap(
                      options: MapOptions(
                        initialCameraFit: CameraFit.bounds(
                          bounds: bounds!,
                          padding: const EdgeInsets.all(40),
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'app.trailshare',
                          maxZoom: 19,
                        ),
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: points,
                              strokeWidth: 4,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: points.first,
                              width: 24,
                              height: 24,
                              child: _StartEndDot(color: AppColors.success),
                            ),
                            Marker(
                              point: points.last,
                              width: 24,
                              height: 24,
                              child: _StartEndDot(color: AppColors.danger),
                            ),
                          ],
                        ),
                      ],
                    )
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Questa traccia non ha punti GPS registrati.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 20),
            // Header info
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    track.activityType.displayName,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _fmtDate(track.recordedAt ?? track.createdAt),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            if (track.description != null &&
                track.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                track.description!,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Stats grid
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatCard(
                  label: 'Distanza',
                  value: '${(stats.distance / 1000).toStringAsFixed(2)} km',
                  icon: Icons.straighten,
                ),
                _StatCard(
                  label: 'Durata',
                  value: _fmtDuration(stats.duration),
                  icon: Icons.timer_outlined,
                ),
                _StatCard(
                  label: 'D+',
                  value: '${stats.elevationGain.toStringAsFixed(0)} m',
                  icon: Icons.trending_up,
                ),
                _StatCard(
                  label: 'D-',
                  value: '${stats.elevationLoss.toStringAsFixed(0)} m',
                  icon: Icons.trending_down,
                ),
                if (stats.duration.inSeconds > 0)
                  _StatCard(
                    label: 'Velocità media',
                    value:
                        '${(stats.distance / 1000 / (stats.duration.inSeconds / 3600)).toStringAsFixed(1)} km/h',
                    icon: Icons.speed,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _downloadGpx(context),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Scarica GPX'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Su web la dashboard è consultativa. La registrazione e '
              'l\'editing delle tracce restano nell\'app mobile.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartEndDot extends StatelessWidget {
  final Color color;
  const _StartEndDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
