import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/services/discovery_prompt_service.dart';
import '../../../core/services/pro_gate_service.dart';
import '../../../core/services/strava_service.dart';
import '../../../data/models/recording_reference.dart';
import '../record/record_page.dart';
import '../../../core/services/track_export_service.dart';
import '../../../core/services/track_photos_service.dart';
import '../../../core/utils/difficulty_calculator.dart';
import '../track_3d/track_3d_page.dart';
import '../../widgets/difficulty_badge.dart';
import '../../widgets/paywall_sheet.dart';
import '../../widgets/expandable_description.dart';
import '../../widgets/export_format_sheet.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../widgets/interactive_track_map.dart';
import '../../widgets/track_charts_widget.dart';
import '../../widgets/lap_splits_widget.dart';
import '../../widgets/personal_records_card.dart';
import '../../widgets/track_tags_editor.dart';
import '../../widgets/nearby_businesses_section.dart';
import '../../widgets/track_segments_section.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../widgets/share_card_widget.dart';
import '../../widgets/share_track_to_group_sheet.dart';
import '../../../presentation/widgets/heart_rate_zones_widget.dart';
import '../../../core/services/health_service.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../widgets/flat_section.dart';

class TrackDetailPage extends StatefulWidget {
  final Track track;

  /// Modalità "percorso illustrativo / da seguire": la traccia viene
  /// presentata come documentazione di un sentiero, non come diario
  /// personale dell'autore.
  ///
  /// Quando true (es. aperta dal tab Percorsi di un gruppo Business)
  /// si nascondono:
  /// - Heart rate (chart battito, zone cardio, refresh HR button)
  /// - Personal Records confronto
  ///
  /// E si forza la visibilità del pulsante "Segui questa traccia".
  /// Le sezioni utili al fruitore (mappa, lap splits con dislivelli
  /// per km, foto, segmenti, POI, commenti) restano visibili.
  final bool illustrative;

  const TrackDetailPage({
    super.key,
    required this.track,
    this.illustrative = false,
  });

  @override
  State<TrackDetailPage> createState() => _TrackDetailPageState();
}

class _TrackDetailPageState extends State<TrackDetailPage> {
  late Track _track;
  final TracksRepository _tracksRepository = TracksRepository();
  final CommunityTracksRepository _communityRepository = CommunityTracksRepository();
  final TrackPhotosService _photosService = TrackPhotosService();
  final GlobalKey _mapKey = GlobalKey();
  bool _isRetryingStrava = false;

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
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              // Titolo spostato nell'area contenuto sotto (mappa pulita, full-bleed).
              background: FullBleedCard(
                child: RepaintBoundary(
                  key: _mapKey,
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
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => ShareCardGenerator.showSharePreview(
                  context: context,
                  name: _track.name,
                  points: _track.points,
                  distanceKm: _track.stats.distance / 1000,
                  elevationGain: _track.stats.elevationGain,
                  durationFormatted: _formatDuration(_track.stats.duration),
                  activityEmoji: _track.activityType.icon,
                  activityName: _track.activityType.displayName,
                  onExportGpx: () => _exportGpx(context),
                  onShareLink: (_track.isPublic && _track.id != null)
                      ? () => _shareWebLink()
                      : null,
                ),
                tooltip: context.l10n.shareTooltip,
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
                    case 'shareToGroup':
                      showShareTrackToGroupSheet(context, track: _track);
                      break;
                    case 'split':
                      _showSplitDialog();
                      break;
                    case 'merge':
                      _showMergeDialog();
                      break;
                    case 'delete':
                      _showDeleteDialog();
                      break;
                    case 'correctElevations':
                      _showCorrectElevationsDialog();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: const Icon(Icons.edit),
                      title: Text(context.l10n.editMenu),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _track.isPublic ? 'unpublish' : 'publish',
                    child: ListTile(
                      leading: Icon(_track.isPublic ? Icons.public_off : Icons.public),
                      title: Text(_track.isPublic ? context.l10n.removeFromCommunity : context.l10n.publishToCommunity),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'shareToGroup',
                    child: ListTile(
                      leading: Icon(Icons.group_add),
                      title: Text('Condividi nel gruppo'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  // 5.4 — Split / Merge solo se sei l'owner
                  if (_track.userId != null &&
                      _track.userId ==
                          FirebaseAuth.instance.currentUser?.uid) ...[
                    const PopupMenuDivider(),
                    // 2026-05-27 — correzione DEM quote. Sempre visibile
                    // per permettere ri-correzione con fonti DEM più
                    // accurate (es. switch Mapzen → EU-DEM 25m).
                    PopupMenuItem(
                      value: 'correctElevations',
                      child: ListTile(
                        leading: const Icon(Icons.terrain),
                        title: Text(
                          _track.elevationCorrectedFromDem
                              ? 'Ricalcola quote (EU-DEM 25m)'
                              : 'Correggi quote dal DEM',
                        ),
                        subtitle: Text(
                          _track.elevationCorrectedFromDem
                              ? 'Ri-applica correzione con DEM più recente'
                              : 'Quote più precise da EU-DEM 25m',
                          style: const TextStyle(fontSize: 11),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'split',
                      child: ListTile(
                        leading: Icon(Icons.content_cut),
                        title: Text('Spezza in due tracce'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'merge',
                      child: ListTile(
                        leading: Icon(Icons.merge_type),
                        title: Text("Unisci con un'altra traccia"),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: const Icon(Icons.delete, color: AppColors.danger),
                      title: Text(context.l10n.deleteAction, style: const TextStyle(color: AppColors.danger)),
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
              child: SageSurface(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titolo traccia — spostato qui dall'overlay mappa.
                  Text(
                    _track.name,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),

                  const SizedBox(height: 16),

                  _buildMainStats(),

                  // Komoot K1a Step 2 — badge difficoltà computata.
                  // Per tracce legacy senza valore persistito, calcolo
                  // al volo dal fallback (stats + activity) per
                  // mostrare comunque il T-grade.
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Badge tappabile (solo per owner): apre dialog
                      // dedicato alla selezione difficoltà manuale.
                      if (_isOwner)
                        InkWell(
                          onTap: _showDifficultyDialog,
                          borderRadius: BorderRadius.circular(14),
                          child: DifficultyBadge(
                            difficultyKey: _track.computedDifficulty,
                            manualDifficultyKey: _track.manualDifficulty,
                            compact: false,
                            fallbackStats: _track.stats,
                            fallbackActivity: _track.activityType,
                          ),
                        )
                      else
                        DifficultyBadge(
                          difficultyKey: _track.computedDifficulty,
                          manualDifficultyKey: _track.manualDifficulty,
                          compact: false,
                          fallbackStats: _track.stats,
                          fallbackActivity: _track.activityType,
                        ),
                      const Spacer(),
                      // Vedi in 3D (Pro) — visibile se la traccia ha
                      // abbastanza punti per un fly-through sensato.
                      if (_track.points.length >= 2)
                        _build3DButton(),
                    ],
                  ),

                  // ⭐ Galleria foto — visibile sempre al proprietario
                  // (anche se vuota) per permettere add post-import
                  // (Garmin / Strava / Health / planner).
                  if (_track.photos.isNotEmpty || _isOwner) ...[
                    const SizedBox(height: 24),
                    _buildPhotoGallery(),
                  ],
                  
                  // ⭐ Pulsante "Segui questa traccia" — visibile per
                  // tracce pianificate (anche del proprietario, è il
                  // loro scopo), per tracce di altri condivise in un
                  // gruppo (utente non-owner), e per qualsiasi traccia
                  // aperta come percorso illustrativo del gruppo.
                  if (_track.points.length >= 2 &&
                      (_track.isPlanned ||
                          !_isOwner ||
                          widget.illustrative)) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _followTrack,
                        icon: const Icon(Icons.navigation),
                        label: const Text('Segui questa traccia'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],

                  // ⭐ Grafici (elevazione, velocità, battito).
                  // PRIVACY: il battito è personale → passato al chart
                  // solo se l'utente è il proprietario AND la pagina
                  // non è in modalità illustrativa (percorso di
                  // gruppo: anche al proprietario non interessa
                  // mostrare il proprio HR in un contesto di
                  // documentazione del trail).
                  if (_track.points.length > 1) ...[
                    const SizedBox(height: 24),
                    TrackChartsWidget(
                      points: _track.points,
                      heartRateData: (_isOwner && !widget.illustrative)
                          ? _track.heartRateData
                          : null,
                      height: 180,
                      totalDuration: _track.stats.duration,
                      onPointTap: (index, distance) {
                        setState(() => _selectedPointIndex = index);
                        debugPrint('[TrackDetail] Grafico tap punto $index a ${(distance/1000).toStringAsFixed(2)} km');
                      },
                    ),
                  ],

                  // ❤️ Zone Cardio (solo proprietario, non illustrative)
                  if (_isOwner &&
                      !widget.illustrative &&
                      _track.heartRateData != null &&
                      _track.heartRateData!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    HeartRateZonesWidget(
                      heartRateData: _track.heartRateData!,
                    ),
                  ],

                  // ❤️ Pulsante aggiorna HR (solo proprietario, non
                  // illustrative — in vista percorso non si gestisce
                  // il dato personale)
                  if (_isOwner &&
                      !widget.illustrative &&
                      (_track.heartRateData == null ||
                          _track.heartRateData!.isEmpty) &&
                      _track.id != null) ...[
                    const SizedBox(height: 16),
                    _buildRefreshHRButton(),
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

                  // Epic 4.7 — Confronto con Personal Records (stesso
                  // activityType). Mostrata solo se l'utente è owner
                  // della traccia AND non in modalità illustrativa
                  // (un percorso "da seguire" non è un risultato
                  // personale da confrontare con PR — è
                  // documentazione del trail).
                  if (_isOwner && !widget.illustrative) ...[
                    const SizedBox(height: 16),
                    PersonalRecordsCard(current: _track),
                    // 5.5 — Editor tag personalizzati (solo owner)
                    if (_track.id != null) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TrackTagsEditor(
                          trackId: _track.id!,
                          initialTags: _track.tags,
                          onChanged: (tags) {
                            setState(() {
                              _track = _track.copyWith(tags: tags);
                            });
                          },
                        ),
                      ),
                    ],
                  ],

                  // Segmenti creati da questa traccia
                  if (_track.id != null && _track.points.length > 1) ...[
                    const SizedBox(height: 16),
                    TrackSegmentsSection(
                      trackId: _track.id!,
                      trackPoints: _track.points,
                      trackOwnerId: _track.userId,
                      activityType: _track.activityType.name,
                    ),
                  ],

                  // 🏔️ Spazi Pro lungo il percorso — discovery
                  // contestuale di rifugi/noleggi/guide visibile per
                  // QUALSIASI traccia con polyline, anche le proprie.
                  // Anche su una propria traccia gia' percorsa e' utile
                  // sapere che spazi commerciali ci sono in zona (es.
                  // "c'e' un noleggio bici 2 km dal mio punto di
                  // partenza prossima volta ci passo"). Auto-hide se
                  // nessuno in zona.
                  if (_track.points.length >= 2) ...[
                    const SizedBox(height: 16),
                    NearbyBusinessesSection(
                      polyline: _track.points
                          .map((p) =>
                              LatLng(p.latitude, p.longitude))
                          .toList(),
                    ),
                  ],

                  const SizedBox(height: 24),
                  _buildDetails(),
                  _buildStravaBadge(),
                ],
              )),
            ),
          ),
        ],
      ),
    );
  }

  /// Badge Strava: visibile solo all'owner della traccia. Mostra lo stato
  /// di upload (processing → done con link / error). I campi
  /// `stravaActivityId` / `stravaUploadStatus` sono scritti dalla Cloud
  /// Function `stravaUploadActivity` dopo il salvataggio.
  Widget _buildStravaBadge() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || _track.id == null) return const SizedBox.shrink();
    if (_track.userId != currentUid) return const SizedBox.shrink();

    final docRef = FirebaseFirestore.instance
        .collection('users').doc(currentUid)
        .collection('tracks').doc(_track.id);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        if (data == null) return const SizedBox.shrink();
        final activityId = data['stravaActivityId']?.toString();
        final status = data['stravaUploadStatus']?.toString();
        if (activityId == null && status == null) return const SizedBox.shrink();

        const stravaOrange = Color(0xFFFC4C02);
        Widget tile;

        if (activityId != null) {
          final url = 'https://www.strava.com/activities/$activityId';
          final imported = data['importedFromStrava'] == true;
          tile = ListTile(
            leading: const Icon(Icons.directions_run, color: stravaOrange),
            title: Text(imported ? context.l10n.stravaTrackImported : context.l10n.stravaTrackUploaded),
            subtitle: Text(imported
                ? context.l10n.stravaTrackImportedSubtitle
                : context.l10n.stravaTrackUploadedSubtitle),
            trailing: const Icon(Icons.open_in_new, size: 18, color: stravaOrange),
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          );
        } else if (status == 'processing' || status == 'pending') {
          tile = ListTile(
            leading: const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: stravaOrange),
            ),
            title: Text(context.l10n.stravaUploading),
            subtitle: Text(context.l10n.stravaUploadingSubtitle),
          );
        } else if (status == 'error' || status == 'pending') {
          final isError = status == 'error';
          final err = data['stravaError']?.toString();
          tile = ListTile(
            leading: Icon(
              isError ? Icons.error_outline : Icons.schedule,
              color: isError ? AppColors.danger : Colors.orange,
            ),
            title: Text(isError ? context.l10n.stravaUploadFailed : context.l10n.stravaUploadPending),
            subtitle: Text(
              isError
                  ? (err ?? context.l10n.stravaUnknownError)
                  : context.l10n.stravaUploadPendingSubtitle,
            ),
            trailing: _isRetryingStrava
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton.icon(
                    onPressed: () => _retryStravaUpload(_track.id!),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(context.l10n.retry),
                  ),
          );
        } else {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Card(child: tile),
        );
      },
    );
  }

  Future<void> _retryStravaUpload(String trackId) async {
    if (_isRetryingStrava) return;
    setState(() => _isRetryingStrava = true);

    // Pulisci lo stato di errore prima del retry: la function controlla
    // `stravaActivityId` per idempotenza, gli altri campi servono solo all'UI.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users').doc(uid)
            .collection('tracks').doc(trackId)
            .update({
          'stravaUploadStatus': 'processing',
          'stravaError': FieldValue.delete(),
        });
      } catch (_) {}
    }

    final activityId = await StravaService().uploadTrack(trackId);
    if (!mounted) return;
    setState(() => _isRetryingStrava = false);

    final messenger = ScaffoldMessenger.of(context);
    if (activityId != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(context.l10n.stravaUploadedOk),
        backgroundColor: AppColors.success,
      ));
    } else {
      messenger.showSnackBar(const SnackBar(
        content: Text('Upload non riuscito. Riprova più tardi.'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  /// Pulsante "3D" — apre il fly-through 3D (Pro). Per i non-Pro mostra
  /// il paywall con trigger dedicato.
  Widget _build3DButton() {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _open3D,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.threed_rotation,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                '3D',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              if (!ProGateService().isPro) ...[
                const SizedBox(width: 4),
                const Icon(Icons.lock, size: 12, color: AppColors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _open3D() {
    if (!ProGateService().isPro) {
      showPaywallSheet(context, trigger: PaywallTrigger.flythrough3d);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Track3DPage.single(
          trackName: _track.name,
          points: _track.points,
        ),
      ),
    );
  }

  Widget _buildMainStats() {
    final stats = _track.stats;
    return Row(
      children: [
        _StatCard(icon: Icons.straighten, value: (stats.distance / 1000).toStringAsFixed(1), unit: 'km', label: context.l10n.distanceLabel, color: AppColors.primary),
        const SizedBox(width: 8),
        _StatCard(icon: Icons.trending_up, value: '+${stats.elevationGain.toStringAsFixed(0)}', unit: 'm', label: context.l10n.elevationGainLabel, color: AppColors.success),
        const SizedBox(width: 8),
        _StatCard(icon: Icons.timer, value: _formatDuration(stats.duration), unit: '', label: context.l10n.durationStatLabel, color: AppColors.info),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ⭐ GALLERIA FOTO
  // ═══════════════════════════════════════════════════════════════════════════

  bool get _isOwner =>
      _track.userId != null &&
      _track.userId == FirebaseAuth.instance.currentUser?.uid;

  bool _addingPhotos = false;

  Widget _buildPhotoGallery() {
    final hasPhotos = _track.photos.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con bottone aggiungi (solo proprietario)
            Row(
              children: [
                Icon(Icons.photo_library,
                    size: 20, color: context.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.photosCount(_track.photos.length),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_isOwner)
                  TextButton.icon(
                    onPressed: _addingPhotos ? null : _addPhotos,
                    icon: _addingPhotos
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_a_photo, size: 18),
                    label: Text(
                      _addingPhotos ? 'Caricamento…' : 'Aggiungi',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (hasPhotos)
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
                      onLongPress: _isOwner
                          ? () => _showPhotoActions(index)
                          : null,
                    );
                  },
                ),
              )
            else
              // Empty state per proprietario — guida l'uso post-import
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined,
                        size: 28,
                        color: context.textSecondary.withValues(alpha: 0.5)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Aggiungi foto del percorso. Utile per tracce '
                        'importate da Garmin/Strava o pianificate, '
                        'dove non hai scattato durante la registrazione.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                          height: 1.4,
                        ),
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

  /// Limite foto per traccia per utenti **free** (non-Pro).
  /// Pro: illimitato.
  static const int _freePhotosPerTrack = 3;

  /// Aggiunge foto da galleria a una traccia esistente.
  ///
  /// Usa `pickFromGalleryWithExif`: legge i tag EXIF di ogni foto
  /// (GPS lat/lng/altitude + DateTimeOriginal) così le foto si
  /// posizionano automaticamente al punto giusto sulla mappa, senza
  /// che l'utente debba taggarle a mano.
  ///
  /// **Gating Pro:** utenti free hanno cap a [_freePhotosPerTrack].
  /// Se superato → dialog upgrade.
  Future<void> _addPhotos() async {
    final trackId = _track.id;
    if (trackId == null) return;

    final isPro = ProGateService().isPro;
    final current = _track.photos.length;
    if (!isPro && current >= _freePhotosPerTrack) {
      _showPhotoLimitDialog();
      return;
    }

    final picked = await _photosService.pickFromGalleryWithExif(
      maxImages: 10,
    );
    if (picked.isEmpty) return;

    // Gating: tronca alle prime N che entrano nel cap free.
    List<TrackPhoto> toUpload = picked;
    if (!isPro) {
      final remaining = _freePhotosPerTrack - current;
      if (picked.length > remaining) {
        toUpload = picked.take(remaining).toList();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Limite gratuito: solo le prime $remaining foto verranno '
              'caricate. Passa a Pro per illimitate.',
            ),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
    }

    setState(() => _addingPhotos = true);
    try {
      final result = await _photosService.uploadPhotos(
        photos: toUpload,
        trackId: trackId,
      );
      if (!mounted) return;

      if (result.uploaded.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload fallito (${result.failed.length} foto)'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }

      final newMetadata = result.uploaded.map((u) => TrackPhotoMetadata(
            url: u.url,
            latitude: u.latitude,
            longitude: u.longitude,
            elevation: u.elevation,
            timestamp: u.timestamp,
          ));
      final merged = [..._track.photos, ...newMetadata];

      await _tracksRepository.updateTrackPhotos(trackId, merged);
      if (!mounted) return;
      setState(() {
        _track = _track.copyWith(photos: merged);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.uploaded.length} foto aggiunte'
            '${result.hasFailures ? " (${result.failed.length} fallite)" : ""}',
          ),
          backgroundColor: const Color(0xFF2E7D5B),
        ),
      );
    } finally {
      if (mounted) setState(() => _addingPhotos = false);
    }
  }

  /// Mostra azioni su una foto esistente: edit caption / delete.
  void _showPhotoActions(int index) {
    final photo = _track.photos[index];
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Modifica didascalia'),
              subtitle: photo.caption != null && photo.caption!.isNotEmpty
                  ? Text(photo.caption!,
                      maxLines: 1, overflow: TextOverflow.ellipsis)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _editCaption(index);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
              title: Text('Elimina foto',
                  style: TextStyle(color: Colors.red.shade700)),
              onTap: () {
                Navigator.pop(ctx);
                _deletePhoto(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCaption(int index) async {
    final trackId = _track.id;
    if (trackId == null) return;
    final photo = _track.photos[index];
    final ctrl = TextEditingController(text: photo.caption ?? '');
    final newCaption = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Didascalia'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 140,
          decoration: const InputDecoration(
            hintText: 'Es. "Bivio per il rifugio"',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (newCaption == null) return;
    final trimmed = newCaption.trim();
    final updated = [..._track.photos];
    updated[index] = TrackPhotoMetadata(
      url: photo.url,
      latitude: photo.latitude,
      longitude: photo.longitude,
      elevation: photo.elevation,
      timestamp: photo.timestamp,
      caption: trimmed.isEmpty ? null : trimmed,
    );
    await _tracksRepository.updateTrackPhotos(trackId, updated);
    if (!mounted) return;
    setState(() => _track = _track.copyWith(photos: updated));
  }

  Future<void> _deletePhoto(int index) async {
    final trackId = _track.id;
    if (trackId == null) return;
    final photo = _track.photos[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina foto'),
        content:
            const Text('Vuoi eliminare definitivamente questa foto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.12),
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Best-effort delete dello Storage poi update Firestore.
    await _photosService.deletePhoto(photo.url);
    final updated = [..._track.photos]..removeAt(index);
    await _tracksRepository.updateTrackPhotos(trackId, updated);
    if (!mounted) return;
    setState(() => _track = _track.copyWith(photos: updated));
  }

  /// Apre RecordPage in modalità guidata con la traccia corrente
  /// come riferimento (polyline + alert off-trail + voce TTS svolte).
  ///
  /// Disponibile per tracce pianificate (anche dell'utente: il loro
  /// scopo è essere seguite) e per tracce condivise da altri utenti
  /// in un gruppo (l'utente non è owner ma vuole percorrerle).
  void _followTrack() {
    final points = _track.points;
    if (points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Traccia troppo corta da seguire')),
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
            trailName: _track.name,
            totalDistance: _track.stats.distance,
            totalElevationGain: _track.stats.elevationGain,
          ),
          initialActivityType: _track.activityType,
        ),
      ),
    );
  }

  /// Dialog mostrato quando un utente free raggiunge il cap foto.
  /// Spiega il limite e linka all'upgrade Pro. Niente push diretto al
  /// paywall qui per non interrompere il flow — l'utente può aprirlo
  /// dal tab Pro nelle Impostazioni.
  void _showPhotoLimitDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limite foto raggiunto'),
        content: Text(
          'Le tracce gratuite supportano fino a $_freePhotosPerTrack '
          'foto. Passa a TrailShare Pro per foto illimitate per '
          'traccia e altre feature avanzate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Capito'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              // Navigazione al paywall: la rotta '/pro' è registrata
              // dal main mobile. Se non esiste cade nel default
              // unknown route handler.
              Navigator.of(context).pushNamed('/pro');
            },
            icon: const Icon(Icons.workspace_premium, size: 18),
            label: const Text('Scopri Pro'),
          ),
        ],
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
                Text(context.l10n.detailsHeader, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_track.isPublic)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.public, size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(context.l10n.publishedBadge, style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w500)),
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ExpandableDescription(
                  text: _track.description!,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _buildEditableActivityRow(),
            _detailRow(Icons.calendar_today, context.l10n.dateLabel, _formatDate(_track.createdAt)),
            _detailRow(Icons.location_on, context.l10n.gpsPoints, '${_track.points.length}'),
            if (stats.elevationLoss > 0)
              _detailRow(Icons.trending_down, context.l10n.elevationLossLabel, '-${stats.elevationLoss.toStringAsFixed(0)} m'),
            if (stats.maxElevation > 0)
              _detailRow(Icons.landscape, context.l10n.maxElevation, '${stats.maxElevation.toStringAsFixed(0)} m'),
            if (stats.minElevation > 0)
              _detailRow(Icons.terrain, context.l10n.minElevation, '${stats.minElevation.toStringAsFixed(0)} m'),
            if (_track.healthCalories != null)
              _detailRow(Icons.local_fire_department, context.l10n.caloriesLabel, '${_track.healthCalories!.round()} kcal'),
            if (_track.healthSteps != null)
              _detailRow(Icons.directions_walk, context.l10n.stepsLabel, '${_track.healthSteps}'),  
          ],
        ),
      ),
    );
  }

  /// Riga attività tappabile per cambiare sport
  Widget _buildEditableActivityRow() {
    return InkWell(
      onTap: _showChangeActivityType,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.sports, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Text(context.l10n.activityLabel, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            const Spacer(),
            Text(
              '${_track.activityType.icon} ${_track.activityType.displayName}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet per cambiare tipo attività
  void _showChangeActivityType() {
    // Raggruppa per categoria
    final grouped = <String, List<ActivityType>>{};
    for (final type in ActivityType.values) {
      grouped.putIfAbsent(type.category, () => []).add(type);
    }

    /// Mappa categoria Firestore → emoji
    String categoryIcon(String cat) {
      switch (cat) {
        case 'A piedi': return '🚶';
        case 'In bicicletta': return '🚴';
        case 'Sport invernali': return '❄️';
        default: return '🏃';
      }
    }

    /// Mappa categoria Firestore → label localizzata
    String categoryLabel(String cat) {
      switch (cat) {
        case 'A piedi': return context.l10n.onFoot;
        case 'In bicicletta': return context.l10n.byBicycle;
        case 'Sport invernali': return context.l10n.winterSports;
        default: return cat;
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Titolo
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                context.l10n.changeActivity,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            // Lista sport per categoria
            ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: grouped.entries.map((entry) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8, left: 4),
                      child: Row(
                        children: [
                          Text(categoryIcon(entry.key), style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text(
                            categoryLabel(entry.key),
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: entry.value.map((type) {
                        final isSelected = type == _track.activityType;
                        return GestureDetector(
                          onTap: () async {
                            Navigator.pop(context);
                            if (type == _track.activityType) return;
                            
                            // Salva su Firestore
                            final realId = _track.id;
                            if (realId == null) return;
                            await TracksRepository().updateTrack(
                              realId,
                              activityType: type,
                            );

                            // Se la traccia è pubblica, aggiorna anche quella nella community
                              if (_track.isPublic) {
                                await FirebaseFirestore.instance
                                    .collection('published_tracks')
                                    .doc(realId)
                                    .update({'activityType': type.name});
                              }
                            
                            // Aggiorna UI
                            setState(() {
                              _track = Track(
                                id: _track.id,
                                name: _track.name,
                                description: _track.description,
                                points: _track.points,
                                activityType: type,
                                createdAt: _track.createdAt,
                                stats: _track.stats,
                                isPublic: _track.isPublic,
                                photos: _track.photos,
                              );
                            });
                            
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(context.l10n.activityChangedTo(type.displayName)),
                                  backgroundColor: const Color(0xFF388E3C),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF4CAF50)
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF388E3C)
                                    : Theme.of(context).colorScheme.outlineVariant,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(type.icon, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 6),
                                Text(
                                  type.displayName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                );
              }).toList(),
            ),
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
          Icon(icon, size: 18, color: context.textMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: context.textSecondary))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _exportGpx(BuildContext context) async {
    final format = await ExportFormatSheet.show(context);
    if (format == null || !context.mounted) return;
    try {
      final filePath = await TrackExportService().exportToFile(_track, format);
      if (format == ExportFormat.fit) {
        await DiscoveryPromptService.markFitExported();
      }
      await SharePlus.instance.share(ShareParams(
        files: [XFile(filePath)],
        subject: _track.name,
      ));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.exportError(e.toString())), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  /// Condivide il link web pubblico della traccia (`https://trailshare.app/track/{id}`).
  /// Richiede che la traccia sia pubblicata in community (controllato dal chiamante).
  Future<void> _shareWebLink() async {
    if (_track.id == null) return;
    final url = 'https://trailshare.app/track/${_track.id}';
    final message = '${_track.name}\n$url';
    await SharePlus.instance.share(ShareParams(
      text: message,
      subject: _track.name,
    ));
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

  /// Dialog dedicato alla selezione della difficoltà T1-T5 (override
  /// manuale). Apribile direttamente tappando il badge difficoltà sulla
  /// scheda traccia: più discoverable rispetto allo scrollare fino al
  /// dropdown nel dialog generico "Modifica".
  void _showDifficultyDialog() {
    ComputedDifficulty? selected =
        ComputedDifficulty.fromKey(_track.manualDifficulty);
    final autoLevel =
        ComputedDifficulty.fromKey(_track.computedDifficulty);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Difficoltà'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<ComputedDifficulty?>(
                value: null,
                groupValue: selected,
                onChanged: (v) => setDialogState(() => selected = v),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  autoLevel != null
                      ? 'Automatica (${autoLevel.code} · ${autoLevel.label})'
                      : 'Automatica',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Calcolata da distanza, dislivello e attività',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const Divider(height: 1),
              ...ComputedDifficulty.values.map(
                (d) => RadioListTile<ComputedDifficulty?>(
                  value: d,
                  groupValue: selected,
                  onChanged: (v) => setDialogState(() => selected = v),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: d.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${d.code} · ${d.label}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                final manualToSave = selected?.firestoreKey ?? '';
                try {
                  await _tracksRepository.updateTrack(
                    _track.id!,
                    manualDifficulty: manualToSave,
                  );
                  if (!mounted) return;
                  setState(() {
                    _track = _track.copyWith(
                      manualDifficulty: selected?.firestoreKey,
                      clearManualDifficulty: selected == null,
                    );
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(selected == null
                          ? 'Difficoltà tornata ad automatica'
                          : 'Difficoltà impostata: ${selected!.code} · ${selected!.label}'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Errore: $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog che chiede conferma e poi lancia la correzione DEM delle
  /// quote di questa traccia. Mostra progress + risultato (Δ medio,
  /// max). Aggiorna lo stato locale e ricarica i dati da Firestore.
  void _showCorrectElevationsDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correggi quote dal DEM'),
        content: const Text(
          'Le quote GPS dello smartphone possono avere errori di '
          '30-100 metri. La correzione usa un modello digitale del '
          'terreno (AWS Open Terrain) per quote più precise.\n\n'
          'Verranno aggiornati i grafici altimetrici, il dislivello '
          'totale e la difficoltà calcolata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Correggi'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // Mostra progress dialog non-dismissible.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scarico DEM e correggo quote…'),
          ],
        ),
      ),
    );

    try {
      final result = await _tracksRepository
          .correctTrackElevationsFromDem(_track.id!);
      if (!mounted) return;
      Navigator.pop(context); // chiude progress

      if (result == null || !result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Correzione non riuscita — controlla la connessione e riprova'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      // Ricarica la traccia dal Firestore per avere i nuovi valori.
      final fresh = await _tracksRepository.getTrackById(_track.id!);
      if (!mounted) return;
      if (fresh != null) {
        setState(() => _track = fresh);
      }

      final sourceTag = result.sourceLabel.isNotEmpty
          ? ' (${result.sourceLabel})'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Quote corrette$sourceTag: Δ medio ${result.avgDeltaMeters.toStringAsFixed(0)}m, '
              'max ${result.maxDeltaMeters.toStringAsFixed(0)}m'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  void _showEditDialog() {
    final nameController = TextEditingController(text: _track.name);
    final descriptionController = TextEditingController(text: _track.description ?? '');

    // Selezione corrente difficoltà: null = "Automatica" (no override),
    // altrimenti uno dei livelli T1..T5.
    ComputedDifficulty? selectedDifficulty =
        ComputedDifficulty.fromKey(_track.manualDifficulty);
    final autoDifficulty =
        ComputedDifficulty.fromKey(_track.computedDifficulty);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.editTrack),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: context.l10n.nameLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: context.l10n.descriptionLabel,
                    border: const OutlineInputBorder(),
                    hintText: context.l10n.addDescription,
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 20),
                // ───── Difficoltà manuale (2026-05-27) ─────
                Text(
                  'Difficoltà',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ComputedDifficulty?>(
                  initialValue: selectedDifficulty,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem<ComputedDifficulty?>(
                      value: null,
                      child: Text(
                        autoDifficulty != null
                            ? 'Automatica (${autoDifficulty.code} · ${autoDifficulty.label})'
                            : 'Automatica',
                      ),
                    ),
                    ...ComputedDifficulty.values.map(
                      (d) => DropdownMenuItem<ComputedDifficulty?>(
                        value: d,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: d.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${d.code} · ${d.label}'),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => selectedDifficulty = v),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedDifficulty == null
                      ? 'La difficoltà sarà calcolata automaticamente da distanza, dislivello e attività.'
                      : 'Override manuale: questa difficoltà sostituisce il calcolo automatico.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                final newDescription = descriptionController.text.trim();

                if (newName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.nameCannotBeEmpty)),
                  );
                  return;
                }

                Navigator.pop(context);

                // Per manualDifficulty: stringa non vuota = imposta,
                // stringa vuota = rimuovi (FieldValue.delete), null
                // implicito = non passare (no-op).
                final manualToSave = selectedDifficulty?.firestoreKey ?? '';

                try {
                  await _tracksRepository.updateTrack(
                    _track.id!,
                    name: newName,
                    description:
                        newDescription.isNotEmpty ? newDescription : null,
                    manualDifficulty: manualToSave,
                  );

                  setState(() {
                    _track = _track.copyWith(
                      name: newName,
                      description:
                          newDescription.isNotEmpty ? newDescription : null,
                      manualDifficulty: selectedDifficulty?.firestoreKey,
                      clearManualDifficulty: selectedDifficulty == null,
                    );
                  });

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(context.l10n.trackUpdated),
                          backgroundColor: AppColors.success),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              context.l10n.errorWithDetails(e.toString())),
                          backgroundColor: AppColors.danger),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  void _showPublishDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.publishToCommunity),
        // Wrap in SingleChildScrollView: senza, una descrizione lunga
        // sforava verticalmente il dialog (overflow). Constrain max
        // height per evitare di "schiacciare" gli action buttons.
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
            maxWidth: 400,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.publishDialogContent),
                const SizedBox(height: 16),
                _buildSummaryRow(context.l10n.nameLabel, _track.name),
                _buildSummaryRow(context.l10n.distanceLabel,
                    '${_track.stats.distanceKm.toStringAsFixed(1)} km'),
                _buildSummaryRow(context.l10n.elevationGainLabel,
                    '+${_track.stats.elevationGain.toStringAsFixed(0)} m'),
                if (_track.description != null &&
                    _track.description!.isNotEmpty)
                  _buildSummaryRow(
                      context.l10n.descriptionLabel, _track.description!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => _publishTrack(),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: Text(context.l10n.publishAction),
          ),
        ],
      ),
    );
  }

  // ❤️ Pulsante per recuperare dati HR da Health Connect
  Widget _buildRefreshHRButton() {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _refreshHeartRateData,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.favorite_outline, color: AppColors.danger.withValues(alpha: 0.7)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.heartRateDataTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.tapToSearchHR,
                      style: TextStyle(fontSize: 13, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.refresh, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshHeartRateData() async {
    if (_track.id == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.searchingHR)),
    );

    try {
      final healthService = HealthService();
      final startTime = _track.createdAt;
      final endTime = startTime.add(_track.stats.duration);

      final hrData = await healthService.getHeartRateForTimeRange(
        start: startTime,
        end: endTime,
      );

      if (hrData.isNotEmpty) {
        final repo = TracksRepository();
        await repo.updateTrackHeartRate(_track.id!, hrData);

        setState(() {
          _track = _track.copyWith(heartRateData: hrData);
        });

        // 🔥 Recupera anche calorie
        final calories = await healthService.getCaloriesForTimeRange(
          start: startTime,
          end: endTime,
        );
        if (calories != null) {
          final repo = TracksRepository();
          await repo.updateTrackField(_track.id!, 'healthCalories', calories);
          setState(() {
            _track = _track.copyWith(healthCalories: calories);
          });
        }
        // 👣 Recupera anche passi
        final steps = await healthService.getStepsForTimeRange(
          start: startTime,
          end: endTime,
        );
        if (steps != null) {
          final repo = TracksRepository();
          await repo.updateTrackField(_track.id!, 'healthSteps', steps);
          setState(() {
            _track = _track.copyWith(healthSteps: steps);
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.hrSamplesFound(hrData.length))),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.noHRData),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[TrackDetail] Errore refresh HR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.hrRetrievalError)),
        );
      }
    }
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: TextStyle(color: context.textSecondary))),
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
        SnackBar(content: Text(context.l10n.mustBeLoggedIn), backgroundColor: AppColors.danger),
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
        ownerUsername: await _getUsername(user.uid),
        photoUrls: _track.photos.map((p) => p.url).toList(),
        computedDifficulty: _track.computedDifficulty,
        manualDifficulty: _track.manualDifficulty,
      );

      if (success) {
        await _tracksRepository.updateTrack(_track.id!, isPublic: true);
        setState(() {
          _track = _track.copyWith(isPublic: true);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.trackPublished), backgroundColor: AppColors.success),
          );
        }
      } else {
        if (!mounted) throw Exception('Publish failed');
        throw Exception(context.l10n.publishFailed);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorWithDetails(e.toString())), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _showUnpublishDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.removeFromCommunity),
        content: Text(context.l10n.unpublishContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => _unpublishTrack(),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: Colors.white),
            child: Text(context.l10n.removeAction),
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
            SnackBar(content: Text(context.l10n.trackUnpublished), backgroundColor: AppColors.info),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorWithDetails(e.toString())), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  /// 5.4 — Dialog Spezza traccia. Slider sceglie il punto di split,
  /// con preview live km/% del primo segmento. Conferma → 2 nuove
  /// tracce + delete originale → torna alla lista.
  void _showSplitDialog() {
    final total = _track.points.length;
    if (total < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.l10n.trackTooShortToSplit)),
      );
      return;
    }
    double sliderValue = 0.5;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final splitIndex =
                (total * sliderValue).round().clamp(2, total - 2);
            // Approssimazione veloce: la frazione del distance totale è
            // ragionevolmente vicina alla split-distance reale per UX.
            final firstDistKm =
                (_track.stats.distance / 1000) * sliderValue;
            final secondDistKm =
                (_track.stats.distance / 1000) - firstDistKm;
            return AlertDialog(
              title: const Text('Spezza traccia'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scegli dove dividere la traccia in due. Le due parti '
                    'verranno salvate come tracce separate e questa verrà '
                    'cancellata.',
                    style: TextStyle(
                        fontSize: 12, color: context.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: sliderValue,
                    min: 0.1,
                    max: 0.9,
                    divisions: 16,
                    label: '${(sliderValue * 100).toStringAsFixed(0)}%',
                    onChanged: (v) => setSt(() => sliderValue = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${firstDistKm.toStringAsFixed(2)} km',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${secondDistKm.toStringAsFixed(2)} km',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Punto $splitIndex / $total',
                    style: TextStyle(
                        fontSize: 11, color: context.textMuted),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _doSplit(splitIndex);
                  },
                  child: const Text('Spezza'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _doSplit(int splitIndex) async {
    final repo = TracksRepository();
    final result = await repo.splitTrack(_track, splitIndex);
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.l10n.trackSplitError)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.trackSplitOk)),
    );
    Navigator.pop(context); // torna alla lista
  }

  /// 5.4 — Dialog Unisci tracce. Mostra picker con le altre tracce
  /// dell'utente; selezionata una, esegue il merge e chiude verso la
  /// lista (la nuova traccia compare in cima per `createdAt`).
  Future<void> _showMergeDialog() async {
    final repo = TracksRepository();
    final all = await repo.getMyTracksLightweight(limit: 100);
    if (!mounted) return;
    final candidates = all
        .where((t) => t.id != null && t.id != _track.id)
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.l10n.trackMergeNoOther)),
      );
      return;
    }
    final picked = await showModalBottomSheet<Track>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Scegli la traccia da unire',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: candidates.length,
                  itemBuilder: (_, i) {
                    final t = candidates[i];
                    final d = t.recordedAt ?? t.createdAt;
                    return ListTile(
                      leading: const Icon(Icons.route),
                      title: Text(t.name),
                      subtitle: Text(
                          '${(t.stats.distance / 1000).toStringAsFixed(2)} km · '
                          '${d.day}/${d.month}/${d.year}'),
                      onTap: () => Navigator.pop(ctx, t),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unire le tracce?'),
        content: Text(
            'Verrà creata una nuova traccia con i punti concatenati di '
            '"${_track.name}" e "${picked.name}". Le due originali '
            'verranno cancellate.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unisci'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final newId = await repo.mergeTracks(_track, picked);
    if (!mounted) return;
    if (newId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.trackMergeError)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tracce unite con successo')),
    );
    Navigator.pop(context); // torna alla lista
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteTrack),
        content: Text(context.l10n.deleteTrackContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => _deleteTrack(),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            child: Text(context.l10n.deleteAction),
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
          SnackBar(content: Text(context.l10n.trackDeleted), backgroundColor: AppColors.info),
        );
        Navigator.pop(context); // Torna indietro
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorWithDetails(e.toString())), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<String> _getUsername(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(uid)
          .get();
      if (!mounted) return 'User';
      return doc.data()?['username'] ?? context.l10n.userLabel;
    } catch (_) {
      if (!mounted) return 'User';
      return context.l10n.userLabel;
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
                  if (unit.isNotEmpty) TextSpan(text: ' $unit', style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
                ]),
              ),
              Text(label, style: TextStyle(fontSize: 10, color: context.textMuted)),
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
  final VoidCallback? onLongPress;

  const _PhotoThumbnail({
    required this.url,
    this.elevation,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: context.textMuted, size: 32),
                      const SizedBox(height: 4),
                      Text(context.l10n.errorLabel, style: TextStyle(color: context.textMuted, fontSize: 10)),
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
          // Scarica foto
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white, size: 28),
            tooltip: context.l10n.downloadTooltip,
            onPressed: () => _downloadPhoto(widget.photos[_currentIndex].url),
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
                    errorBuilder: (_, error, _) {
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
                          : Colors.white.withValues(alpha: 0.4),
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
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          if (photo.elevation != null)
            _metadataItem(Icons.terrain, '${photo.elevation!.toStringAsFixed(0)} m', context.l10n.quotaMetadata),
          if (photo.latitude != null && photo.longitude != null)
            _metadataItem(Icons.location_on, 'GPS', context.l10n.positionMetadata),
          _metadataItem(
            Icons.access_time,
            '${photo.timestamp.hour.toString().padLeft(2, '0')}:${photo.timestamp.minute.toString().padLeft(2, '0')}',
            context.l10n.timeMetadata,
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
