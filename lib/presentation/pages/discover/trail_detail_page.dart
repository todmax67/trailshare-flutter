import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/gpx_service.dart';
import '../../../data/repositories/public_trails_repository.dart';
import '../../../presentation/widgets/charts/elevation_chart.dart';
import 'package:share_plus/share_plus.dart';

class TrailDetailPage extends StatefulWidget {
  final PublicTrail trail;

  const TrailDetailPage({super.key, required this.trail});

  @override
  State<TrailDetailPage> createState() => _TrailDetailPageState();
}

class _TrailDetailPageState extends State<TrailDetailPage> {
  final GpxService _gpxService = GpxService();
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final trail = widget.trail;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar con mappa
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                trail.displayName,
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
                  // Info card
                  _buildInfoCard(),
                  
                  const SizedBox(height: 16),
                  
                  // Stats principali
                  _buildMainStats(),
                  
                  const SizedBox(height: 16),
                  
                  // Grafico elevazione
                  if (_hasElevationData())
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ElevationChart(points: trail.points),
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
    return widget.trail.points.any((p) => p.elevation != null);
  }

  Widget _buildMap() {
    final trail = widget.trail;
    
    if (trail.points.isEmpty) {
      return Container(
        color: AppColors.background,
        child: const Center(child: Text('Nessun dato GPS')),
      );
    }

    final points = trail.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    
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
              color: AppColors.info,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            // Start
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
            // End
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

  Widget _buildInfoCard() {
    final trail = widget.trail;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icona difficoltà
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  trail.difficultyIcon,
                  style: const TextStyle(fontSize: 32),
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.info.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          trail.difficultyName,
                          style: const TextStyle(
                            color: AppColors.info,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (trail.networkName.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          trail.networkName,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (trail.operator != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.business, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          trail.operator!,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStats() {
    final trail = widget.trail;
    
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.straighten,
            value: trail.length != null 
                ? '${trail.lengthKm.toStringAsFixed(1)}' 
                : '--',
            unit: 'km',
            label: 'Lunghezza',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.trending_up,
            value: trail.elevationGain != null 
                ? '+${trail.elevationGain!.toStringAsFixed(0)}' 
                : '--',
            unit: 'm',
            label: 'Dislivello',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.location_on,
            value: '${trail.points.length}',
            unit: '',
            label: 'Punti GPS',
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    final trail = widget.trail;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informazioni',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(height: 24),
            if (trail.ref != null)
              _buildDetailRow(Icons.tag, 'Numero sentiero', trail.ref!),
            _buildDetailRow(Icons.terrain, 'Difficoltà', trail.difficultyName),
            if (trail.operator != null)
              _buildDetailRow(Icons.business, 'Gestore', trail.operator!),
            if (trail.networkName.isNotEmpty)
              _buildDetailRow(Icons.hub, 'Rete', trail.networkName),
            if (trail.region != null)
              _buildDetailRow(Icons.map, 'Regione', trail.region!),
            _buildDetailRow(Icons.source, 'Fonte', 'OpenStreetMap'),
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
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              // TODO: Naviga su Google Maps / app navigazione
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Navigazione - Coming soon!')),
              );
            },
            icon: const Icon(Icons.navigation),
            label: const Text('Naviga al punto di partenza'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportGpx() async {
    if (widget.trail.points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun punto GPS da esportare')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      // Converte in Track per usare il servizio GPX
      final track = widget.trail.toTrack();
      final filePath = await _gpxService.saveGpxToFile(track);
      
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: widget.trail.displayName,
        text: 'Sentiero GPX: ${widget.trail.displayName}',
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
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
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
