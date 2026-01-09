import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/track_repository.dart';

class TrackDetailPage extends StatefulWidget {
  final Track track;

  const TrackDetailPage({super.key, required this.track});

  @override
  State<TrackDetailPage> createState() => _TrackDetailPageState();
}

class _TrackDetailPageState extends State<TrackDetailPage> {
  final TrackRepository _repository = TrackRepository();
  late Track _track;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _track = widget.track;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar con mappa
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _track.name,
                style: const TextStyle(
                  fontSize: 16,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
              background: _buildMap(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _showEditDialog,
              ),
            ],
          ),

          // Contenuto
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info traccia
                  _buildInfoCard(),
                  
                  const SizedBox(height: 16),
                  
                  // Stats principali
                  _buildMainStats(),
                  
                  const SizedBox(height: 16),
                  
                  // Stats secondarie
                  _buildSecondaryStats(),

                  const SizedBox(height: 24),

                  // Pulsanti azione
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_track.points.isEmpty) {
      return Container(
        color: AppColors.background,
        child: const Center(child: Text('Nessun punto GPS')),
      );
    }

    // Calcola bounds
    final points = _track.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final bounds = LatLngBounds.fromPoints(points);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: bounds.center,
        initialZoom: 14,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none, // Disabilita interazione in app bar
        ),
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
            // Start
            Marker(
              point: points.first,
              width: 24,
              height: 24,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.flag, color: Colors.white, size: 12),
              ),
            ),
            // End
            Marker(
              point: points.last,
              width: 24,
              height: 24,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.flag, color: Colors.white, size: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _track.activityType.icon,
                style: const TextStyle(fontSize: 28),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _track.activityType.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFullDate(_track.createdAt),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  if (_track.description != null && _track.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _track.description!,
                      style: const TextStyle(color: AppColors.textSecondary),
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
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.straighten,
            value: '${_track.stats.distanceKm.toStringAsFixed(2)}',
            unit: 'km',
            label: 'Distanza',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.trending_up,
            value: '+${_track.stats.elevationGain.toStringAsFixed(0)}',
            unit: 'm',
            label: 'Dislivello +',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.timer,
            value: _track.stats.durationFormatted,
            unit: '',
            label: 'Durata',
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryStats() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Statistiche',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            _buildStatRow('Dislivello -', '-${_track.stats.elevationLoss.toStringAsFixed(0)} m'),
            _buildStatRow('Velocità media', '${_track.stats.avgSpeedKmh.toStringAsFixed(1)} km/h'),
            _buildStatRow('Velocità max', '${(_track.stats.maxSpeed * 3.6).toStringAsFixed(1)} km/h'),
            _buildStatRow('Passo medio', _track.stats.avgPace),
            _buildStatRow('Punti GPS', '${_track.points.length}'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              // TODO: Esporta GPX
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export GPX - Coming soon!')),
              );
            },
            icon: const Icon(Icons.download),
            label: const Text('Esporta GPX'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete, color: AppColors.danger),
            label: const Text('Elimina traccia', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.danger),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  void _showEditDialog() {
    final nameController = TextEditingController(text: _track.name);
    final descController = TextEditingController(text: _track.description ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifica traccia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nome',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Descrizione',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _updateTrack(nameController.text, descController.text);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateTrack(String name, String description) async {
    if (_track.id == null) return;

    try {
      await _repository.updateTrack(
        _track.id!,
        name: name,
        description: description,
      );
      
      setState(() {
        _track = _track.copyWith(name: name, description: description);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Traccia aggiornata')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare traccia?'),
        content: const Text('Questa azione non può essere annullata.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteTrack();
            },
            child: const Text('Elimina', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTrack() async {
    if (_track.id == null) return;

    try {
      await _repository.deleteTrack(_track.id!);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Traccia eliminata')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    }
  }

  String _formatFullDate(DateTime date) {
    final weekdays = ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'];
    final months = ['Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
                    'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'];
    return '${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]} ${date.year}';
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
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
