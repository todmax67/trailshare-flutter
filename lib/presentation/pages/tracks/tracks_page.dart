import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  
  // ⭐ PAGINAZIONE
  List<Track>? _tracks;
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scrollController.addListener(_onScroll); // ⭐ Listener per lazy load
    _loadTracks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose(); // ⭐ Dispose del controller
    super.dispose();
  }

  /// Helper per ottenere il colore dell'attività
  Color _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.trekking:
        return AppColors.success;
      case ActivityType.trailRunning:
        return AppColors.warning;
      case ActivityType.cycling:
        return AppColors.info;
      case ActivityType.walking:
        return AppColors.primary;
    }
  }

  /// Helper per ottenere l'icona dell'attività
  IconData _getActivityIconData(ActivityType type) {
    switch (type) {
      case ActivityType.trekking:
        return Icons.hiking;
      case ActivityType.trailRunning:
        return Icons.directions_run;
      case ActivityType.cycling:
        return Icons.directions_bike;
      case ActivityType.walking:
        return Icons.directions_walk;
    }
  }

  /// ⭐ Listener per caricare più tracce quando si raggiunge il fondo
  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreTracks();
    }
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
      _tracks = null;
      _lastDocument = null; // ⭐ Reset paginazione
      _hasMore = true;
    });

    try {
      // ⭐ Usa il metodo paginato
      final result = await _repository.getUserTracksPaginated(
        user.uid,
        limit: 10, // Carica solo 10 alla volta
      );
      
      setState(() {
        _tracks = result.tracks;
        _lastDocument = result.lastDocument;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Errore caricamento: $e';
        _isLoading = false;
      });
    }
  }

  /// ⭐ Carica altre tracce (paginazione)
  Future<void> _loadMoreTracks() async {
    // Non caricare se già in corso, non ci sono più dati, o non c'è un cursore
    if (_isLoadingMore || !_hasMore || _lastDocument == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final result = await _repository.getUserTracksPaginated(
        user.uid,
        limit: 10,
        lastDocument: _lastDocument,
      );

      setState(() {
        _tracks = [...?_tracks, ...result.tracks];
        _lastDocument = result.lastDocument;
        _hasMore = result.hasMore;
        _isLoadingMore = false;
      });
      
      print('[TracksPage] Caricate altre ${result.tracks.length} tracce. Totale: ${_tracks?.length}');
    } catch (e) {
      print('[TracksPage] Errore caricamento altre tracce: $e');
      setState(() => _isLoadingMore = false);
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

  Widget _buildLoginRequired() {
    return const Center(
      child: Text('Accedi per pianificare tracce'),
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
            Icon(Icons.error_outline, size: 64, color: AppColors.danger.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTracks,
              child: const Text('Riprova'),
            ),
          ],
        ),
      );
    }

    if (_tracks == null || _tracks!.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadTracks,
        child: ListView(
          children: [
            const SizedBox(height: 100),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hiking, size: 80, color: AppColors.primary.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  const Text(
                    'Nessuna traccia salvata',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Inizia a registrare le tue avventure!',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTracks,
      child: ListView.builder(
        controller: _scrollController, // ⭐ Controller per scroll
        padding: const EdgeInsets.all(16),
        itemCount: _tracks!.length + (_hasMore ? 1 : 0), // ⭐ +1 per il loader
        itemBuilder: (context, index) {
          // ⭐ Se siamo all'ultimo item e ci sono altre pagine, mostra loader
          if (index >= _tracks!.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          final track = _tracks![index];
          return _TrackCard(
            track: track,
            onTap: () => _openTrackDetail(track),
            onMapTap: () => _openTrackOnMap(track),
            onDelete: () => _deleteTrack(track),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK CARD WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class _TrackCard extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onMapTap;
  final VoidCallback onDelete;

  const _TrackCard({
    required this.track,
    required this.onTap,
    required this.onMapTap,
    required this.onDelete,
  });

  Color _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.trekking:
        return AppColors.success;
      case ActivityType.trailRunning:
        return AppColors.warning;
      case ActivityType.cycling:
        return AppColors.info;
      case ActivityType.walking:
        return AppColors.primary;
    }
  }

  IconData _getActivityIconData(ActivityType type) {
    switch (type) {
      case ActivityType.trekking:
        return Icons.hiking;
      case ActivityType.trailRunning:
        return Icons.directions_run;
      case ActivityType.cycling:
        return Icons.directions_bike;
      case ActivityType.walking:
        return Icons.directions_walk;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getActivityColor(track.activityType);
    final iconData = _getActivityIconData(track.activityType);
    
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
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      iconData,
                      color: color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(track.createdAt),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Badge foto
                  if (track.photos.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_camera, size: 14, color: AppColors.info),
                          const SizedBox(width: 4),
                          Text(
                            '${track.photos.length}',
                            style: TextStyle(fontSize: 12, color: AppColors.info),
                          ),
                        ],
                      ),
                    ),
                  // Badge pianificata
                  if (track.isPlanned)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'PIANIFICATA',
                        style: TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatChip(
                    icon: Icons.straighten,
                    value: '${track.stats.distanceKm.toStringAsFixed(1)} km',
                  ),
                  _StatChip(
                    icon: Icons.trending_up,
                    value: '+${track.stats.elevationGain.toStringAsFixed(0)} m',
                    color: AppColors.success,
                  ),
                  if (track.stats.duration.inMinutes > 0)
                    _StatChip(
                      icon: Icons.schedule,
                      value: track.stats.durationFormatted,
                    ),
                  _StatChip(
                    icon: Icons.location_on,
                    value: '${track.points.length} pt',
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.map, size: 18),
                    label: const Text('Mappa'),
                    onPressed: onMapTap,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Elimina'),
                    onPressed: onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
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
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'Oggi ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Ieri';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} giorni fa';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;

  const _StatChip({
    required this.icon,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: color ?? AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
