import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/services/discovery_prompt_service.dart';
import '../../../core/services/track_export_service.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/export_format_sheet.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../../presentation/widgets/interactive_track_map.dart';
import '../../../presentation/widgets/track_charts_widget.dart';
import '../../../presentation/widgets/lap_splits_widget.dart';
import '../../../presentation/widgets/track_segments_section.dart';
import '../../widgets/trail_pois_section.dart';
import '../../widgets/nearby_businesses_section.dart';
import '../../widgets/follow_button.dart';
import '../../../data/repositories/public_trails_repository.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/trails_cache_service.dart';
import '../../pages/profile/public_profile_page.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../widgets/share_card_widget.dart';
import '../../widgets/track_comments_section.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/models/recording_reference.dart';
import '../record/record_page.dart';
import '../../../core/extensions/theme_colors_extension.dart';

class CommunityTrackDetailPage extends StatefulWidget {
  final CommunityTrack track;

  const CommunityTrackDetailPage({super.key, required this.track});

  @override
  State<CommunityTrackDetailPage> createState() => _CommunityTrackDetailPageState();
}

class _CommunityTrackDetailPageState extends State<CommunityTrackDetailPage> {
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

  Future<void> _checkAdmin() async {
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    if (mounted) {
      setState(() => _isAdmin = isAdmin);
      if (_isAdmin) {
        _checkIfPromoted();
      }
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
                  poiTrackId: track.id,
                  poiIncludePrivate:
                      FirebaseAuth.instance.currentUser?.uid == track.ownerId,
                  loadOsmPois: true, // POI OSM lungo la traccia
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

                  // Segmenti cronometrati (solo pubblici, read-only)
                  TrackSegmentsSection(
                    trackId: track.id,
                    readOnly: true,
                  ),

                  const SizedBox(height: 16),

                  // POI community + POI OSM (rifugi, bivacchi, fontane,
                  // sorgenti, panorami) lungo la traccia.
                  TrailPoisSection(
                    trackId: track.id,
                    isOwner: FirebaseAuth.instance.currentUser?.uid ==
                        track.ownerId,
                    allowAdd: FirebaseAuth.instance.currentUser?.uid ==
                        track.ownerId,
                    defaultLatitude: track.points.isNotEmpty
                        ? track.points.first.latitude
                        : null,
                    defaultLongitude: track.points.isNotEmpty
                        ? track.points.first.longitude
                        : null,
                    polyline: track.points
                        .map((p) => LatLng(p.latitude, p.longitude))
                        .toList(),
                    loadOsmPois: true,
                  ),

                  const SizedBox(height: 16),

                  // Spazi Pro lungo il percorso (rifugi, noleggi,
                  // guide). Auto-nascosto se nessuno in zona.
                  if (track.points.length >= 2)
                    NearbyBusinessesSection(
                      polyline: track.points
                          .map(
                              (p) => LatLng(p.latitude, p.longitude))
                          .toList(),
                    ),

                  // Dettagli
                  _buildDetails(),

                  const SizedBox(height: 24),

                  // Azioni
                  _buildActions(),

                  const SizedBox(height: 28),

                  // Commenti community
                  TrackCommentsSection(
                    trackId: widget.track.id,
                    ownerId: widget.track.ownerId,
                  ),
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
                  colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.7)],
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.ownerUsername,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Pulsante "Segui" inline accanto al nome.
                      // Pattern Komoot/Strava: trasforma una scheda
                      // informativa in un punto di engagement
                      // community. Nascosto se l'autore sono io
                      // (segui te stesso non ha senso) o se non
                      // loggato.
                      if (track.ownerId.isNotEmpty &&
                          FirebaseAuth.instance.currentUser != null &&
                          FirebaseAuth.instance.currentUser!.uid !=
                              track.ownerId) ...[
                        const SizedBox(width: 8),
                        FollowButton(
                          targetUserId: track.ownerId,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                  if (track.sharedAt != null) ...[
                    SizedBox(height: 4),
                    Text(
                      context.l10n.sharedOnDate(_formatDate(track.sharedAt!)),
                      style: TextStyle(color: context.textSecondary, fontSize: 12),
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
                  color: AppColors.danger.withValues(alpha: 0.1),
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
            label: context.l10n.distanceLabel,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.trending_up,
            value: '+${track.elevationGain.toStringAsFixed(0)}',
            unit: 'm',
            label: context.l10n.elevationLabel,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.timer,
            value: _formatNormalizedDuration(track.duration, track.distance),
            unit: '',
            label: context.l10n.durationStatLabel,
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
                Icon(Icons.photo_library, size: 20, color: context.textSecondary),
                SizedBox(width: 8),
                Text(
                  context.l10n.photosWithCount(photoUrls.length),
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
            Text(
              context.l10n.descriptionLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              widget.track.description!,
              style: TextStyle(color: context.textSecondary),
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
            Text(
              context.l10n.detailsLabel,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Divider(height: 24),
            _buildDetailRow(Icons.directions_walk, context.l10n.activityLabel, '${track.activityIcon} ${track.activityType}'),
            if (track.difficulty != null)
              _buildDetailRow(Icons.signal_cellular_alt, context.l10n.difficultyLabel, '${track.difficultyIcon} ${track.difficulty}'),
            _buildDetailRow(Icons.location_on, context.l10n.gpsPoints, '${track.points.length}'),
            _buildDetailRow(Icons.source, context.l10n.sourceLabel, context.l10n.communitySource),
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
          Icon(icon, size: 18, color: context.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(color: context.textSecondary)),
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
              onShareLink: () => SharePlus.instance.share(ShareParams(
                text: '${widget.track.name}\nhttps://trailshare.app/track/${widget.track.id}',
                subject: widget.track.name,
              )),
            ),
            icon: Icon(Icons.share),
            label: Text(context.l10n.share),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Pulsante Segui traccia (registra + off-trail alert)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _followTrack,
            icon: Icon(Icons.navigation),
            label: Text(context.l10n.trackFollowAndRecord),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
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
                : Icon(Icons.download),
            label: Text(_isExporting ? context.l10n.exporting : context.l10n.downloadGpx),
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
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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
                          ? context.l10n.alreadyPromoted
                          : _isPromoting
                              ? context.l10n.promotionInProgress
                              : context.l10n.promoteToTrail,
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
        title: Text(context.l10n.promoteToTrail),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.promoteDialogDescription,
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 16),
            _promoteInfoRow(context.l10n.nameLabel, track.name),
            _promoteInfoRow(context.l10n.authorLabel, track.ownerUsername),
            _promoteInfoRow(context.l10n.distanceLabel, '${track.distanceKm.toStringAsFixed(1)} km'),
            _promoteInfoRow(context.l10n.elevationLabel, '+${track.elevationGain.toStringAsFixed(0)} m'),
            _promoteInfoRow(context.l10n.gpsPoints, '${track.points.length}'),
            const SizedBox(height: 12),
            // Warning qualità
            if (track.points.length < 50)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, size: 16, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.fewGpsPointsWarning,
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
            child: Text(context.l10n.cancel),
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
            child: Text(context.l10n.promote),
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
          SnackBar(
            content: Text(context.l10n.trackPromotedSuccess),
            backgroundColor: Color(0xFF388E3C),
          ),
        );
      } else {
        if (!mounted) return;
        throw Exception(context.l10n.promotionFailed);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPromoting = false);
        AppSnackBar.error(context, context.l10n.errorWithDetails(e.toString()));
      }
    }
  }

  /// Apre la pagina di registrazione in modalità guidata con la traccia
  /// della community come riferimento (polyline + alert off-trail).
  void _followTrack() {
    final points = widget.track.points;
    if (points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.trackTooShortToFollow)),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordPage(
          reference: RecordingReference.fromTrail(
            trailPoints: points
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList(),
            trailName: widget.track.name,
            totalDistance: widget.track.distance,
            totalElevationGain: widget.track.elevationGain,
          ),
          initialActivityType: widget.track.parsedActivityType,
        ),
      ),
    );
  }

  Future<void> _exportGpx() async {
    if (widget.track.points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noGpsPointsToExport)),
      );
      return;
    }

    final format = await ExportFormatSheet.show(context);
    if (format == null || !mounted) return;

    setState(() => _isExporting = true);

    try {
      final track = widget.track.toTrack();
      final filePath = await TrackExportService().exportToFile(track, format);
      if (format == ExportFormat.fit) {
        await DiscoveryPromptService.markFitExported();
      }

      if (!mounted) return;
      final shareText = context.l10n.gpxTrackName(widget.track.name);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(filePath)],
        subject: widget.track.name,
        text: shareText,
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.gpxExported),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.errorWithDetails(e.toString())),
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
                        color: color.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: context.textMuted),
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
              color: Colors.black.withValues(alpha: 0.1),
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: context.textMuted, size: 32),
                      SizedBox(height: 4),
                      Text(
                        context.l10n.errorLabel,
                        style: TextStyle(color: context.textMuted, fontSize: 10),
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
                      Colors.black.withValues(alpha: 0.6),
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
                  color: Colors.black.withValues(alpha: 0.5),
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
            icon: Icon(Icons.download, color: Colors.white, size: 28),
            tooltip: context.l10n.downloadTooltip,
            onPressed: () => _downloadPhoto(widget.photoUrls[_currentIndex]),
          ),
          // Condividi foto
          IconButton(
            icon: Icon(Icons.share, color: Colors.white, size: 28),
            tooltip: context.l10n.shareTooltip,
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
                    errorBuilder: (context, error, _) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.broken_image, color: Colors.white54, size: 64),
                          SizedBox(height: 16),
                          Text(
                            context.l10n.cannotLoadImage,
                            style: const TextStyle(color: Colors.white54),
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
                          : Colors.white.withValues(alpha: 0.4),
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
    SharePlus.instance.share(ShareParams(
      text: '${context.l10n.photoFrom(widget.trackName)}\n$url',
      subject: context.l10n.hikePhoto,
    ));
  }

  Future<void> _downloadPhoto(String url) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.downloadInProgress)),
      );

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        if (!mounted) throw Exception('Download error');
        throw Exception(context.l10n.downloadError);
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'trailshare_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      if (!mounted) return;

      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: context.l10n.photoFrom(widget.trackName),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorWithDetails(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }
}
