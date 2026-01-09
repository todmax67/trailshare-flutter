import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/gpx_service.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../../presentation/widgets/charts/elevation_chart.dart';
import 'package:share_plus/share_plus.dart';

class CommunityTrackDetailPage extends StatefulWidget {
  final CommunityTrack track;

  const CommunityTrackDetailPage({super.key, required this.track});

  @override
  State<CommunityTrackDetailPage> createState() => _CommunityTrackDetailPageState();
}

class _CommunityTrackDetailPageState extends State<CommunityTrackDetailPage> {
  final GpxService _gpxService = GpxService();
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar con mappa
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                track.name,
                style: const TextStyle(
                  fontSize: 16,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
              background: _buildMap(),
            ),
          ),

          // Contenuto
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info autore
                  _buildAuthorCard(),

                  const SizedBox(height: 16),

                  // Stats principali
                  _buildMainStats(),

                  const SizedBox(height: 16),

                  // Descrizione
                  if (track.description != null && track.description!.isNotEmpty)
                    _buildDescription(),

                  // Grafico elevazione
                  if (_hasElevationData())
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ElevationChart(points: track.points),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Dettagli
                  _buildDetails(),

                  const SizedBox(height: 24),

                  // Azioni
                  _buildActions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasElevationData() {
    return widget.track.points.any((p) => p.elevation != null);
  }

  Widget _buildMap() {
    final track = widget.track;

    if (track.points.isEmpty) {
      return Container(
        color: AppColors.background,
        child: const Center(child: Text('Nessun dato GPS')),
      );
    }

    final points = track.points.map((p) => LatLng(p.latitude, p.longitude)).toList();

    // Calcola centro
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    // Calcola zoom
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    double zoom = 14.0;
    if (maxDiff > 0.5) zoom = 10;
    else if (maxDiff > 0.2) zoom = 11;
    else if (maxDiff > 0.1) zoom = 12;
    else if (maxDiff > 0.05) zoom = 13;

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.trailshare.app',
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
              width: 28,
              height: 28,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
              ),
            ),
            Marker(
              point: points.last,
              width: 28,
              height: 28,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.flag, color: Colors.white, size: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAuthorCard() {
    final track = widget.track;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  track.ownerUsername.isNotEmpty 
                      ? track.ownerUsername[0].toUpperCase() 
                      : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.ownerUsername,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (track.sharedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Condiviso il ${_formatDate(track.sharedAt!)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),

            // Like count
            if (track.cheerCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: AppColors.danger, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${track.cheerCount}',
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStats() {
    final track = widget.track;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.straighten,
            value: track.distanceKm.toStringAsFixed(1),
            unit: 'km',
            label: 'Distanza',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.trending_up,
            value: '+${track.elevationGain.toStringAsFixed(0)}',
            unit: 'm',
            label: 'Dislivello',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.timer,
            value: track.durationFormatted,
            unit: '',
            label: 'Durata',
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _buildDescription() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Descrizione',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              widget.track.description!,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails() {
    final track = widget.track;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dettagli',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(height: 24),
            _buildDetailRow(Icons.directions_walk, 'Attività', '${track.activityIcon} ${track.activityType}'),
            if (track.difficulty != null)
              _buildDetailRow(Icons.signal_cellular_alt, 'Difficoltà', '${track.difficultyIcon} ${track.difficulty}'),
            _buildDetailRow(Icons.location_on, 'Punti GPS', '${track.points.length}'),
            _buildDetailRow(Icons.source, 'Fonte', 'Community'),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isExporting ? null : _exportGpx,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download),
            label: Text(_isExporting ? 'Esportazione...' : 'Scarica GPX'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportGpx() async {
    if (widget.track.points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun punto GPS da esportare')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final track = widget.track.toTrack();
      final filePath = await _gpxService.saveGpxToFile(track);

      await Share.shareXFiles(
        [XFile(filePath)],
        subject: widget.track.name,
        text: 'Traccia GPX: ${widget.track.name}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ GPX esportato!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                        fontSize: 12,
                        color: color.withOpacity(0.7),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
