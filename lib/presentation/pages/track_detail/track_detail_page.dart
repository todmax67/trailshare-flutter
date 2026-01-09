import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/gpx_service.dart';
import '../../../data/models/track.dart';

class TrackDetailPage extends StatelessWidget {
  final Track track;

  const TrackDetailPage({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(track.name, style: const TextStyle(fontSize: 16)),
              background: _buildMap(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => _exportGpx(context),
                tooltip: 'Esporta GPX',
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMainStats(),
                  const SizedBox(height: 24),
                  _buildDetails(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (track.points.isEmpty) {
      return Container(color: AppColors.background);
    }

    final points = track.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final maxDiff = (maxLat - minLat) > (maxLng - minLng) ? (maxLat - minLat) : (maxLng - minLng);
    double zoom = maxDiff > 0.5 ? 10 : maxDiff > 0.2 ? 11 : maxDiff > 0.1 ? 12 : maxDiff > 0.05 ? 13 : 14;

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.trailshare.app'),
        PolylineLayer(polylines: [Polyline(points: points, strokeWidth: 4, color: AppColors.primary)]),
        MarkerLayer(markers: [
          Marker(point: points.first, width: 28, height: 28,
            child: Container(
              decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
            ),
          ),
          Marker(point: points.last, width: 28, height: 28,
            child: Container(
              decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.flag, color: Colors.white, size: 14),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildMainStats() {
    final stats = track.stats;
    return Row(
      children: [
        _StatCard(icon: Icons.straighten, value: '${(stats.distance / 1000).toStringAsFixed(1)}', unit: 'km', label: 'Distanza', color: AppColors.primary),
        const SizedBox(width: 8),
        _StatCard(icon: Icons.trending_up, value: '+${stats.elevationGain.toStringAsFixed(0)}', unit: 'm', label: 'Dislivello +', color: AppColors.success),
        const SizedBox(width: 8),
        _StatCard(icon: Icons.timer, value: _formatDuration(stats.duration), unit: '', label: 'Durata', color: AppColors.info),
      ],
    );
  }

  Widget _buildDetails() {
    final stats = track.stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dettagli', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _detailRow(Icons.sports, 'Attività', track.activityType.displayName),
            _detailRow(Icons.calendar_today, 'Data', _formatDate(track.createdAt)),
            _detailRow(Icons.location_on, 'Punti GPS', '${track.points.length}'),
            if (stats.elevationLoss > 0)
              _detailRow(Icons.trending_down, 'Dislivello -', '-${stats.elevationLoss.toStringAsFixed(0)} m'),
            if (stats.maxElevation > 0)
              _detailRow(Icons.landscape, 'Quota max', '${stats.maxElevation.toStringAsFixed(0)} m'),
            if (stats.minElevation > 0)
              _detailRow(Icons.terrain, 'Quota min', '${stats.minElevation.toStringAsFixed(0)} m'),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _exportGpx(BuildContext context) async {
    try {
      final gpxService = GpxService();
      final filePath = await gpxService.saveGpxToFile(track);
      await Share.shareXFiles([XFile(filePath)], subject: track.name);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore export: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final Color color;

  const _StatCard({required this.icon, required this.value, required this.unit, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(children: [
                  TextSpan(text: value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                  if (unit.isNotEmpty) TextSpan(text: ' $unit', style: TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
                ]),
              ),
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
