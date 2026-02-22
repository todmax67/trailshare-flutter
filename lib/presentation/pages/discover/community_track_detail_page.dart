import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/gpx_service.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../../presentation/widgets/charts/elevation_chart.dart';
import '../../../presentation/widgets/interactive_track_map.dart';
import '../../../presentation/widgets/track_charts_widget.dart';
import '../../../presentation/widgets/lap_splits_widget.dart';
import '../../../data/repositories/public_trails_repository.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/trails_cache_service.dart';
import '../../pages/profile/public_profile_page.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../widgets/share_card_widget.dart';

class CommunityTrackDetailPage extends StatefulWidget {
  final CommunityTrack track;

  const CommunityTrackDetailPage({super.key, required this.track});

  @override
  State<CommunityTrackDetailPage> createState() => _CommunityTrackDetailPageState();
}

class _CommunityTrackDetailPageState extends State<CommunityTrackDetailPage> {
  final GpxService _gpxService = GpxService();
  bool _isExporting = false;
  
  /// Indice del punto attualmente selezionato (sincronizzazione mappa-grafico)
  int? _selectedPointIndex;

  bool _isPromoting = false;
  bool _isAlreadyPromoted = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  void _checkAdmin() {
    final email = FirebaseAuth.instance.currentUser?.email;
    _isAdmin = email == 'admin@trailshare.app' || email == 'todde.massimiliano@gmail.com';
    if (_isAdmin) {
      _checkIfPromoted();
    }
  }

  Future<void> _checkIfPromoted() async {
    final promoted = await PublicTrailsRepository().isAlreadyPromoted(widget.track.id);
    if (mounted) {
      setState(() => _isAlreadyPromoted = promoted);
    }
  }

  /// Costruisce la mappa dei marker foto (url -> posizione)
  /// Per ora le foto community non hanno posizione GPS, quindi ritorna null
  Map<String, LatLng>? _buildPhotoMarkers() {
    // Le foto community sono solo URL, non hanno coordinate
    // In futuro si potrebbe estendere CommunityTrack per includere coordinate foto
    return null;
  }

  /// Normalizza la durata gestendo vari formati di salvataggio
  /// - Vecchie tracce JS potrebbero avere duration in millisecondi
  /// - Alcune tracce potrebbero avere valori corrotti
  /// - Fallback: stima dalla distanza con velocità tipica
  Duration _normalizeDuration(int rawDuration, double distanceMeters) {
    // Se duration è 0 o negativo, stima dalla distanza
    if (rawDuration <= 0) {
      return _estimateDurationFromDistance(distanceMeters);
    }
    
    // Converti in secondi per valutazione
    int durationSeconds = rawDuration;
    
    // Calcola velocità implicita per verificare se il valore ha senso
    // Velocità in km/h = (distanza in km) / (tempo in ore)
    double impliedSpeedKmh = (distanceMeters / 1000) / (durationSeconds / 3600);
    
    debugPrint('[Duration] Raw: $rawDuration, Distanza: ${distanceMeters.toStringAsFixed(0)}m');
    debugPrint('[Duration] Velocità implicita (come secondi): ${impliedSpeedKmh.toStringAsFixed(2)} km/h');
    
    // Se la velocità implicita è ragionevole (1-25 km/h per escursionismo), usa il valore
    if (impliedSpeedKmh >= 1 && impliedSpeedKmh <= 25) {
      debugPrint('[Duration] ✓ Usando valore raw come secondi: ${durationSeconds}s');
      return Duration(seconds: durationSeconds);
    }
    
    // Prova a interpretare come millisecondi
    int durationFromMs = (rawDuration / 1000).round();
    double impliedSpeedFromMs = (distanceMeters / 1000) / (durationFromMs / 3600);
    debugPrint('[Duration] Velocità implicita (come ms): ${impliedSpeedFromMs.toStringAsFixed(2)} km/h');
    
    if (impliedSpeedFromMs >= 1 && impliedSpeedFromMs <= 25) {
      debugPrint('[Duration] ✓ Usando valore raw come millisecondi: ${durationFromMs}s');
      return Duration(seconds: durationFromMs);
    }
    
    // Se nessuna interpretazione ha senso, stima dalla distanza
    debugPrint('[Duration] ✗ Valori non validi, stimo dalla distanza');
    return _estimateDurationFromDistance(distanceMeters);
  }
  
  /// Stima la durata basandosi sulla distanza e una velocità tipica
  Duration _estimateDurationFromDistance(double distanceMeters) {
    // Velocità media tipica per escursionismo: 4 km/h
    // Con dislivello significativo potrebbe essere più lento
    const avgSpeedKmh = 4.0;
    final hours = (distanceMeters / 1000) / avgSpeedKmh;
    final seconds = (hours * 3600).round();
    debugPrint('[Duration] Stimato da distanza: ${seconds}s (${(seconds/60).toStringAsFixed(0)} min)');
    return Duration(seconds: seconds);
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar con mappa interattiva
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                track.name,
                style: const TextStyle(
                  fontSize: 16,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
              background: Padding(
                padding: const EdgeInsets.only(bottom: 48), // Spazio per il titolo
                child: InteractiveTrackMap(
                  points: track.points,
                  height: 300,
                  photoMarkers: _buildPhotoMarkers(),
                  title: track.name,
                  showUserLocation: true,
                  highlightedPointIndex: _selectedPointIndex,
                  onPointTap: (index) {
                    setState(() => _selectedPointIndex = index);
                  },
                  communityTrack: track, // ⭐ Per fullscreen con TrackMapPage
                ),
              ),
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

                  // ⭐ STEP 1: Galleria foto
                  if (track.photoUrls.isNotEmpty) ...[
                    _buildPhotoGallery(),
                    const SizedBox(height: 16),
                  ],

                  // Descrizione
                  if (track.description != null && track.description!.isNotEmpty)
                    _buildDescription(),

                  // ⭐ Grafici (elevazione, velocità)
                  if (track.points.length > 1) ...[
                    TrackChartsWidget(
                      points: track.points,
                      height: 180,
                      totalDuration: _normalizeDuration(track.duration, track.distance),
                      onPointTap: (index, distance) {
                        setState(() => _selectedPointIndex = index);
                        debugPrint('[CommunityTrackDetail] Grafico tap punto $index a ${(distance/1000).toStringAsFixed(2)} km');
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // ⭐ Statistiche per Km (Lap Splits)
                  if (track.points.length > 1 && track.distance > 500) ...[
                    LapSplitsWidget(
                      points: track.points,
                      totalDuration: _normalizeDuration(track.duration, track.distance),
                      onLapTap: (startIndex, endIndex) {
                        setState(() => _selectedPointIndex = startIndex);
                        debugPrint('[CommunityTrackDetail] Lap tap: $startIndex - $endIndex');
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

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

  Widget _buildAuthorCard() {
    final track = widget.track;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () {
            if (track.ownerId.isNotEmpty) {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => PublicProfilePage(
                  userId: track.ownerId,
                  username: track.ownerUsername,
                ),
              ));
            }
          },
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
            value: _formatNormalizedDuration(track.duration, track.distance),
            unit: '',
            label: 'Durata',
            color: AppColors.info,
          ),
        ),
      ],
    );
  }
  
  /// Formatta la durata normalizzata per la visualizzazione
  String _formatNormalizedDuration(int rawDuration, double distance) {
    final duration = _normalizeDuration(rawDuration, distance);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ⭐ STEP 1: GALLERIA FOTO
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPhotoGallery() {
    final photoUrls = widget.track.photoUrls;
    
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
                  'Foto (${photoUrls.length})',
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
                itemCount: photoUrls.length,
                itemBuilder: (context, index) {
                  return _PhotoThumbnail(
                    url: photoUrls[index],
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
          photoUrls: widget.track.photoUrls,
          initialIndex: initialIndex,
          trackName: widget.track.name,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════

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
        // Pulsante Condividi Social
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => ShareCardGenerator.showSharePreview(
              context: context,
              name: widget.track.name,
              points: widget.track.points,
              distanceKm: widget.track.distanceKm,
              elevationGain: widget.track.elevationGain,
              durationFormatted: widget.track.durationFormatted,
              activityEmoji: widget.track.activityIcon,
              activityName: widget.track.activityType,
              username: widget.track.ownerUsername,
              onExportGpx: _exportGpx,
            ),
            icon: const Icon(Icons.share),
            label: const Text('Condividi'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Pulsante Scarica GPX (esistente)
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

        // --- ADMIN: Promuovi a Sentiero ---
        if (_isAdmin) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.admin_panel_settings, size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text(
                      'ADMIN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange[700],
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAlreadyPromoted || _isPromoting
                        ? null
                        : _showPromoteDialog,
                    icon: _isPromoting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_isAlreadyPromoted ? Icons.check_circle : Icons.arrow_upward),
                    label: Text(
                      _isAlreadyPromoted
                          ? 'Già promossa a Sentiero ✓'
                          : _isPromoting
                              ? 'Promozione in corso...'
                              : 'Promuovi a Sentiero',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAlreadyPromoted
                          ? Colors.grey[400]
                          : Colors.orange[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showPromoteDialog() {
    final track = widget.track;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Promuovi a Sentiero'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Questa traccia verrà aggiunta ai sentieri pubblici e sarà visibile a tutti gli utenti nella sezione Scopri.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            _promoteInfoRow('Nome', track.name),
            _promoteInfoRow('Autore', track.ownerUsername),
            _promoteInfoRow('Distanza', '${track.distanceKm.toStringAsFixed(1)} km'),
            _promoteInfoRow('Dislivello', '+${track.elevationGain.toStringAsFixed(0)} m'),
            _promoteInfoRow('Punti GPS', '${track.points.length}'),
            const SizedBox(height: 12),
            // Warning qualità
            if (track.points.length < 50)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, size: 16, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pochi punti GPS — la traccia potrebbe essere imprecisa',
                        style: TextStyle(fontSize: 12, color: Colors.amber),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _promoteTrack();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Promuovi'),
          ),
        ],
      ),
    );
  }

  Widget _promoteInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _promoteTrack() async {
    setState(() => _isPromoting = true);

    try {
      final track = widget.track;
      final repo = PublicTrailsRepository();

      final trailId = await repo.promoteFromCommunityTrack(
        communityTrackId: track.id,
        name: track.name,
        activityType: track.activityType,
        points: track.points,
        distance: track.distance,
        elevationGain: track.elevationGain,
        durationSeconds: track.duration,
        ownerUsername: track.ownerUsername,
        description: track.description,
      );

      if (trailId != null && mounted) {
        setState(() {
          _isPromoting = false;
          _isAlreadyPromoted = true;
        });
        trailsCacheService.invalidateAll();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Traccia promossa a sentiero pubblico!'),
            backgroundColor: Color(0xFF388E3C),
          ),
        );
      } else {
        throw Exception('Promozione fallita');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPromoting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Errore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET: Stat Card
// ═══════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════
// ⭐ WIDGET: Photo Thumbnail
// ═══════════════════════════════════════════════════════════════════════════

class _PhotoThumbnail extends StatelessWidget {
  final String url;
  final VoidCallback onTap;

  const _PhotoThumbnail({
    required this.url,
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
                      Text(
                        'Errore',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                      ),
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
// ⭐ PAGE: Photo Viewer (fullscreen con swipe)
// ═══════════════════════════════════════════════════════════════════════════

class _PhotoViewerPage extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;
  final String trackName;

  const _PhotoViewerPage({
    required this.photoUrls,
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
          '${_currentIndex + 1} / ${widget.photoUrls.length}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          // Scarica foto
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white, size: 28),
            tooltip: 'Scarica',
            onPressed: () => _downloadPhoto(widget.photoUrls[_currentIndex]),
          ),
          // Condividi foto
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white, size: 28),
            tooltip: 'Condividi',
            onPressed: () => _sharePhoto(widget.photoUrls[_currentIndex]),
          ),
        ],
      ),
      body: Stack(
        children: [
          // PageView per swipe
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photoUrls.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final url = widget.photoUrls[index];
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (_, error, __) {
                      return const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, color: Colors.white54, size: 64),
                          SizedBox(height: 16),
                          Text(
                            'Impossibile caricare l\'immagine',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
          
          // Indicatore pagina (dots)
          if (widget.photoUrls.length > 1)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.photoUrls.length,
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
        ],
      ),
    );
  }

  void _sharePhoto(String url) {
    Share.share(
      'Foto da ${widget.trackName}\n$url',
      subject: 'Foto escursione',
    );
  }

  Future<void> _downloadPhoto(String url) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download in corso...')),
      );

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) throw Exception('Errore download');

      final tempDir = await getTemporaryDirectory();
      final fileName = 'trailshare_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Foto da ${widget.trackName}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
