import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/config/app_config.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../track_detail/track_detail_page.dart';
import '../map/track_map_page.dart';
import 'import_gpx_page.dart';
import 'planner_tab.dart';

class TracksPage extends StatefulWidget {
  const TracksPage({super.key});

  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TracksRepository _repository = TracksRepository();
  
  List<Track>? _tracks;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTracks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTracks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _error = 'Effettua il login per vedere le tue tracce';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tracks = await _repository.getUserTracks(user.uid);
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Errore caricamento: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteTrack(Track track) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina traccia'),
        content: Text('Sei sicuro di voler eliminare "${track.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirm == true && track.id != null) {
      try {
        await _repository.deleteTrack(track.id!);
        _loadTracks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Traccia eliminata'), backgroundColor: AppColors.success),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
          );
        }
      }
    }
  }

  void _openImportPage() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ImportGpxPage()),
    );
    
    if (result == true) {
      _loadTracks();
    }
  }

  void _openTrackOnMap(Track track) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackMapPage(track: track),
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

  /// Callback quando il planner salva una traccia
  void _onTrackSaved() {
    _loadTracks();
    _tabController.animateTo(0); // Torna alla lista
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Le mie tracce'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Lista'),
            Tab(icon: Icon(Icons.edit_location_alt), text: 'Pianifica'),
          ],
        ),
        actions: [
          // Importa GPX (solo nel tab lista)
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _openImportPage,
            tooltip: 'Importa GPX',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(), // Evita swipe accidentale sulla mappa
        children: [
          // Tab 1: Lista tracce
          _buildTracksListTab(),
          
          // Tab 2: Pianifica
          user != null
              ? PlannerTab(
                  orsApiKey: AppConfig.orsApiKey,
                  onTrackSaved: _onTrackSaved,
                )
              : _buildLoginRequired(),
        ],
      ),
    );
  }

  Widget _buildTracksListTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTracks,
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          ],
        ),
      );
    }

    if (_tracks == null || _tracks!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.route, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text('Nessuna traccia salvata', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            const Text(
              'Registra un\'escursione, importa un GPX\no pianifica un nuovo percorso',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _openImportPage,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Importa'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _tabController.animateTo(1),
                  icon: const Icon(Icons.edit_location_alt),
                  label: const Text('Pianifica'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTracks,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tracks!.length,
        itemBuilder: (context, index) {
          final track = _tracks![index];
          return _TrackCard(
            track: track,
            onTap: () => _openTrackDetail(track),
            onOpenMap: () => _openTrackOnMap(track),
            onDelete: () => _deleteTrack(track),
          );
        },
      ),
    );
  }

  Widget _buildLoginRequired() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 64, color: AppColors.textMuted),
          SizedBox(height: 16),
          Text('Effettua il login per pianificare percorsi'),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK CARD
// ═══════════════════════════════════════════════════════════════════════════

class _TrackCard extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onOpenMap;
  final VoidCallback onDelete;

  const _TrackCard({
    required this.track,
    required this.onTap,
    required this.onOpenMap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final stats = track.stats;
    final isPlanned = track.isPlanned;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icona attività
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isPlanned 
                      ? AppColors.info.withOpacity(0.1)
                      : AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isPlanned
                      ? const Icon(Icons.edit_location_alt, color: AppColors.info)
                      : Text(track.activityType.icon, style: const TextStyle(fontSize: 22)),
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
                        Expanded(
                          child: Text(
                            track.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPlanned)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.info.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'PIANIFICATA',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.info,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDate(track.createdAt)} • ${track.activityType.displayName}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _StatChip(Icons.straighten, '${(stats.distance / 1000).toStringAsFixed(1)} km'),
                        const SizedBox(width: 12),
                        _StatChip(Icons.trending_up, '+${stats.elevationGain.toStringAsFixed(0)} m'),
                        if (stats.duration.inMinutes > 0) ...[
                          const SizedBox(width: 12),
                          _StatChip(Icons.schedule, _formatDuration(stats.duration)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              
              // Azioni
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Apri in mappa
                  IconButton(
                    icon: const Icon(Icons.map_outlined),
                    onPressed: onOpenMap,
                    tooltip: 'Apri in mappa',
                    color: AppColors.primary,
                    iconSize: 22,
                  ),
                  // Menu
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                      if (value == 'map') onOpenMap();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'map',
                        child: Row(
                          children: [
                            Icon(Icons.map, color: AppColors.primary, size: 20),
                            SizedBox(width: 8),
                            Text('Apri in mappa'),
                          ],
                        ),
                      ),
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
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
  
  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _StatChip(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}
