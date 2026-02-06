import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/gpx_service.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../widgets/interactive_track_map.dart';
import '../../widgets/track_charts_widget.dart';
import '../../widgets/lap_splits_widget.dart';

class TrackDetailPage extends StatefulWidget {
  final Track track;

  const TrackDetailPage({super.key, required this.track});

  @override
  State<TrackDetailPage> createState() => _TrackDetailPageState();
}

class _TrackDetailPageState extends State<TrackDetailPage> {
  late Track _track;
  final TracksRepository _tracksRepository = TracksRepository();
  final CommunityTracksRepository _communityRepository = CommunityTracksRepository();
  
  @override
  void initState() {
    super.initState();
    _track = widget.track;
  }
  
  /// Indice del punto attualmente selezionato (sincronizzazione mappa-grafico)
  int? _selectedPointIndex;

  /// Costruisce la mappa dei marker foto (url -> posizione)
  Map<String, LatLng>? _buildPhotoMarkers() {
    if (_track.photos.isEmpty) return null;
    
    final markers = <String, LatLng>{};
    for (final photo in _track.photos) {
      if (photo.latitude != null && photo.longitude != null) {
        markers[photo.url] = LatLng(photo.latitude!, photo.longitude!);
      }
    }
    
    return markers.isNotEmpty ? markers : null;
  }

  /// Apre il viewer foto all'indice corrispondente all'URL
  void _onPhotoMarkerTap(String url) {
    final index = _track.photos.indexWhere((p) => p.url == url);
    if (index >= 0) {
      _openPhotoViewer(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(_track.name, style: const TextStyle(fontSize: 16)),
              background: Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: InteractiveTrackMap(
                  points: _track.points,
                  height: 300,
                  photoMarkers: _buildPhotoMarkers(),
                  onPhotoMarkerTap: _onPhotoMarkerTap,
                  title: _track.name,
                  showUserLocation: true,
                  highlightedPointIndex: _selectedPointIndex,
                  onPointTap: (index) {
                    setState(() => _selectedPointIndex = index);
                  },
                  track: _track, // ⭐ Per fullscreen con TrackMapPage
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => _exportGpx(context),
                tooltip: 'Esporta GPX',
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _showEditDialog();
                      break;
                    case 'publish':
                      _showPublishDialog();
                      break;
                    case 'unpublish':
                      _showUnpublishDialog();
                      break;
                    case 'delete':
                      _showDeleteDialog();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit),
                      title: Text('Modifica'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _track.isPublic ? 'unpublish' : 'publish',
                    child: ListTile(
                      leading: Icon(_track.isPublic ? Icons.public_off : Icons.public),
                      title: Text(_track.isPublic ? 'Rimuovi dalla community' : 'Pubblica nella community'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: AppColors.danger),
                      title: Text('Elimina', style: TextStyle(color: AppColors.danger)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
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
                  
                  // ⭐ Galleria foto
                  if (_track.photos.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildPhotoGallery(),
                  ],
                  
                  // ⭐ Grafici (elevazione, velocità, battito)
                  if (_track.points.length > 1) ...[
                    const SizedBox(height: 24),
                    TrackChartsWidget(
                      points: _track.points,
                      height: 180,
                      totalDuration: _track.stats.duration,
                      onPointTap: (index, distance) {
                        setState(() => _selectedPointIndex = index);
                        debugPrint('[TrackDetail] Grafico tap punto $index a ${(distance/1000).toStringAsFixed(2)} km');
                      },
                    ),
                  ],
                  
                  // ⭐ Statistiche per Km (Lap Splits)
                  if (_track.points.length > 1 && _track.stats.distance > 500) ...[
                    const SizedBox(height: 16),
                    LapSplitsWidget(
                      points: _track.points,
                      totalDuration: _track.stats.duration,
                      onLapTap: (startIndex, endIndex) {
                        setState(() => _selectedPointIndex = startIndex);
                        debugPrint('[TrackDetail] Lap tap: $startIndex - $endIndex');
                      },
                    ),
                  ],
                  
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

  Widget _buildMainStats() {
    final stats = _track.stats;
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

  // ═══════════════════════════════════════════════════════════════════════════
  // ⭐ GALLERIA FOTO
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPhotoGallery() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.photo_library, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'Foto (${_track.photos.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Galleria orizzontale scrollabile
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _track.photos.length,
                itemBuilder: (context, index) {
                  final photo = _track.photos[index];
                  return _PhotoThumbnail(
                    url: photo.url,
                    elevation: photo.elevation,
                    onTap: () => _openPhotoViewer(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPhotoViewer(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoViewerPage(
          photos: _track.photos,
          initialIndex: initialIndex,
          trackName: _track.name,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetails() {
    final stats = _track.stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Dettagli', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_track.isPublic)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.public, size: 14, color: AppColors.success),
                        SizedBox(width: 4),
                        Text('Pubblica', style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Descrizione (se presente)
            if (_track.description != null && _track.description!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _track.description!,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _detailRow(Icons.sports, 'Attività', _track.activityType.displayName),
            _detailRow(Icons.calendar_today, 'Data', _formatDate(_track.createdAt)),
            _detailRow(Icons.location_on, 'Punti GPS', '${_track.points.length}'),
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
      final filePath = await gpxService.saveGpxToFile(_track);
      await Share.shareXFiles([XFile(filePath)], subject: _track.name);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore export: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    // Normalizza: se la durata sembra in millisecondi (> 24 ore per una traccia normale)
    // verifica con la velocità implicita
    Duration normalizedDuration = d;
    
    if (d.inHours > 24 && _track.stats.distance > 0) {
      // Verifica se ha senso come secondi
      final speedAsSeconds = (_track.stats.distance / 1000) / (d.inSeconds / 3600);
      
      // Se velocità < 1 km/h, probabilmente è in millisecondi
      if (speedAsSeconds < 1) {
        final durationFromMs = Duration(seconds: (d.inMilliseconds / 1000).round());
        final speedAsMs = (_track.stats.distance / 1000) / (durationFromMs.inSeconds / 3600);
        
        // Se la velocità come ms è ragionevole (1-25 km/h), usa quella
        if (speedAsMs >= 1 && speedAsMs <= 25) {
          normalizedDuration = durationFromMs;
        }
      }
    }
    
    final h = normalizedDuration.inHours;
    final m = normalizedDuration.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  // ═══════════════════════════════════════════════════════════════════════════
  // DIALOGS: Modifica, Pubblica, Elimina
  // ═══════════════════════════════════════════════════════════════════════════

  void _showEditDialog() {
    final nameController = TextEditingController(text: _track.name);
    final descriptionController = TextEditingController(text: _track.description ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifica traccia'),
        content: SingleChildScrollView(
          child: Column(
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
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrizione',
                  border: OutlineInputBorder(),
                  hintText: 'Aggiungi una descrizione...',
                ),
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              final newDescription = descriptionController.text.trim();
              
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Il nome non può essere vuoto')),
                );
                return;
              }

              Navigator.pop(context);
              
              try {
                await _tracksRepository.updateTrack(
                  _track.id!,
                  name: newName,
                  description: newDescription.isNotEmpty ? newDescription : null,
                );
                
                setState(() {
                  _track = _track.copyWith(
                    name: newName,
                    description: newDescription.isNotEmpty ? newDescription : null,
                  );
                });
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Traccia aggiornata!'), backgroundColor: AppColors.success),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  void _showPublishDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pubblica nella community'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('La tua traccia sarà visibile a tutti gli utenti nella sezione "Scopri".'),
            const SizedBox(height: 16),
            _buildSummaryRow('Nome', _track.name),
            _buildSummaryRow('Distanza', '${_track.stats.distanceKm.toStringAsFixed(1)} km'),
            _buildSummaryRow('Dislivello', '+${_track.stats.elevationGain.toStringAsFixed(0)} m'),
            if (_track.description != null && _track.description!.isNotEmpty)
              _buildSummaryRow('Descrizione', _track.description!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => _publishTrack(),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Pubblica'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Future<void> _publishTrack() async {
    Navigator.pop(context); // Chiudi dialog
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Devi essere loggato'), backgroundColor: AppColors.danger),
      );
      return;
    }

    try {
      final success = await _communityRepository.publishTrack(
        trackId: _track.id!,
        name: _track.name,
        description: _track.description,
        activityType: _track.activityType.name,
        distance: _track.stats.distance,
        elevationGain: _track.stats.elevationGain,
        durationSeconds: _track.stats.duration.inSeconds,
        points: _track.points,
        ownerId: user.uid,
        ownerUsername: user.displayName ?? user.email ?? 'Utente',
        photoUrls: _track.photos.map((p) => p.url).toList(),
      );

      if (success) {
        await _tracksRepository.updateTrack(_track.id!, isPublic: true);
        setState(() {
          _track = _track.copyWith(isPublic: true);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Traccia pubblicata nella community!'), backgroundColor: AppColors.success),
          );
        }
      } else {
        throw Exception('Pubblicazione fallita');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _showUnpublishDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovi dalla community'),
        content: const Text('La traccia non sarà più visibile nella sezione "Scopri". Puoi ripubblicarla in qualsiasi momento.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => _unpublishTrack(),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: Colors.white),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
  }

  Future<void> _unpublishTrack() async {
    Navigator.pop(context);
    
    try {
      final success = await _communityRepository.unpublishTrack(_track.id!);
      
      if (success) {
        await _tracksRepository.updateTrack(_track.id!, isPublic: false);
        setState(() {
          _track = _track.copyWith(isPublic: false);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Traccia rimossa dalla community'), backgroundColor: AppColors.info),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina traccia'),
        content: const Text('Questa azione è irreversibile. La traccia verrà eliminata definitivamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => _deleteTrack(),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTrack() async {
    Navigator.pop(context); // Chiudi dialog
    
    try {
      // Se pubblica, rimuovi prima dalla community
      if (_track.isPublic) {
        await _communityRepository.unpublishTrack(_track.id!);
      }
      
      await _tracksRepository.deleteTrack(_track.id!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Traccia eliminata'), backgroundColor: AppColors.info),
        );
        Navigator.pop(context); // Torna indietro
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

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET: Stat Card
// ═══════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET: Photo Thumbnail
// ═══════════════════════════════════════════════════════════════════════════

class _PhotoThumbnail extends StatelessWidget {
  final String url;
  final double? elevation;
  final VoidCallback onTap;

  const _PhotoThumbnail({
    required this.url,
    this.elevation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Immagine
            Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: AppColors.background,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: AppColors.background,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: AppColors.textMuted, size: 32),
                      SizedBox(height: 4),
                      Text('Errore', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ],
                  ),
                );
              },
            ),
            
            // Overlay gradiente
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.6),
                    ],
                  ),
                ),
              ),
            ),
            
            // Info quota
            if (elevation != null)
              Positioned(
                bottom: 8,
                left: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.terrain, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '${elevation!.toStringAsFixed(0)} m',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            
            // Icona espandi
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.fullscreen, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE: Photo Viewer (fullscreen con swipe)
// ═══════════════════════════════════════════════════════════════════════════

class _PhotoViewerPage extends StatefulWidget {
  final List<TrackPhotoMetadata> photos;
  final int initialIndex;
  final String trackName;

  const _PhotoViewerPage({
    required this.photos,
    required this.initialIndex,
    required this.trackName,
  });

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.photos.length}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showPhotoInfo(widget.photos[_currentIndex]),
          ),
        ],
      ),
      body: Stack(
        children: [
          // PageView per swipe
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final photo = widget.photos[index];
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    photo.url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder: (_, error, __) {
                      return const Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 64,
                      );
                    },
                  ),
                ),
              );
            },
          ),
          
          // Indicatore pagina (dots)
          if (widget.photos.length > 1)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.photos.length,
                  (index) => Container(
                    width: index == _currentIndex ? 12 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index == _currentIndex
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          
          // Info foto in basso
          Positioned(
            bottom: 50,
            left: 16,
            right: 16,
            child: _buildPhotoMetadata(widget.photos[_currentIndex]),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoMetadata(TrackPhotoMetadata photo) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          if (photo.elevation != null)
            _metadataItem(Icons.terrain, '${photo.elevation!.toStringAsFixed(0)} m', 'Quota'),
          if (photo.latitude != null && photo.longitude != null)
            _metadataItem(Icons.location_on, 'GPS', 'Posizione'),
          _metadataItem(
            Icons.access_time,
            '${photo.timestamp.hour.toString().padLeft(2, '0')}:${photo.timestamp.minute.toString().padLeft(2, '0')}',
            'Ora',
          ),
        ],
      ),
    );
  }

  Widget _metadataItem(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }

  void _showPhotoInfo(TrackPhotoMetadata photo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informazioni Foto',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _infoRow('Data', '${photo.timestamp.day}/${photo.timestamp.month}/${photo.timestamp.year}'),
            _infoRow('Ora', '${photo.timestamp.hour.toString().padLeft(2, '0')}:${photo.timestamp.minute.toString().padLeft(2, '0')}'),
            if (photo.latitude != null)
              _infoRow('Latitudine', photo.latitude!.toStringAsFixed(6)),
            if (photo.longitude != null)
              _infoRow('Longitudine', photo.longitude!.toStringAsFixed(6)),
            if (photo.elevation != null)
              _infoRow('Quota', '${photo.elevation!.toStringAsFixed(0)} m'),
            if (photo.caption != null && photo.caption!.isNotEmpty)
              _infoRow('Descrizione', photo.caption!),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
