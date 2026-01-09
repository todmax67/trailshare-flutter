import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/track_repository.dart';
import 'track_detail_page.dart';

class TracksPage extends StatefulWidget {
  const TracksPage({super.key});

  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  final TrackRepository _repository = TrackRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Le Mie Tracce'),
      ),
      body: StreamBuilder<List<Track>>(
        stream: _repository.watchMyTracks(),
        builder: (context, snapshot) {
          // Loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Errore
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                  const SizedBox(height: 16),
                  Text('Errore: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Riprova'),
                  ),
                ],
              ),
            );
          }

          final tracks = snapshot.data ?? [];

          // Lista vuota
          if (tracks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route, size: 80, color: AppColors.textMuted.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text(
                    'Nessuna traccia salvata',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Vai su "Registra" per iniziare',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            );
          }

          // Lista tracce
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                return _TrackCard(
                  track: tracks[index],
                  onTap: () => _openTrackDetail(tracks[index]),
                  onDelete: () => _deleteTrack(tracks[index]),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _openTrackDetail(Track track) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackDetailPage(track: track),
      ),
    );
  }

  Future<void> _deleteTrack(Track track) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare traccia?'),
        content: Text('Vuoi eliminare "${track.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirm == true && track.id != null) {
      try {
        await _repository.deleteTrack(track.id!);
        if (mounted) {
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
  }
}

/// Card per visualizzare una traccia nella lista
class _TrackCard extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TrackCard({
    required this.track,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: nome e menu
              Row(
                children: [
                  // Icona attività
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      track.activityType.icon,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Nome e data
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatDate(track.createdAt),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Menu
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: AppColors.danger, size: 20),
                            SizedBox(width: 8),
                            Text('Elimina'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatColumn(
                    icon: Icons.straighten,
                    value: '${track.stats.distanceKm.toStringAsFixed(2)} km',
                    label: 'Distanza',
                  ),
                  _StatColumn(
                    icon: Icons.trending_up,
                    value: '+${track.stats.elevationGain.toStringAsFixed(0)} m',
                    label: 'Dislivello',
                    valueColor: AppColors.success,
                  ),
                  _StatColumn(
                    icon: Icons.timer,
                    value: track.stats.durationFormatted,
                    label: 'Durata',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu', 
                    'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic'];
    return '${date.day} ${months[date.month - 1]} ${date.year}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _StatColumn extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;

  const _StatColumn({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
