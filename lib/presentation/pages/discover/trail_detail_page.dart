import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/services/gpx_service.dart';
import '../../../core/utils/eta_estimator.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/public_trails_repository.dart';
import '../../../presentation/widgets/interactive_track_map.dart';
import '../../../presentation/widgets/track_charts_widget.dart';
import '../../widgets/weather_forecast_card.dart';
import '../../widgets/expandable_description.dart';
import '../../widgets/track_stats_bar.dart';
import '../../widgets/trail_reviews_section.dart';
import '../../widgets/trail_photos_section.dart';
import '../../widgets/trail_segments_section.dart';
import '../../widgets/trail_conditions_ai_card.dart';
import '../../widgets/trail_conditions_section.dart';
import '../../widgets/trail_pois_section.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io' show Platform;
import '../record/record_page.dart';
import '../../../data/models/recording_reference.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../core/extensions/theme_colors_extension.dart';

class TrailDetailPage extends StatefulWidget {
  final PublicTrail trail;

  const TrailDetailPage({super.key, required this.trail});

  @override
  State<TrailDetailPage> createState() => _TrailDetailPageState();
}

class _TrailDetailPageState extends State<TrailDetailPage> {
  final GpxService _gpxService = GpxService();
  final PublicTrailsRepository _trailsRepo = PublicTrailsRepository();
  bool _isExporting = false;
  bool _isDeleting = false;

  /// Punti completi con elevazione (caricati da Firebase)
  List<TrackPoint>? _fullPoints;
  bool _isLoadingFull = true;

  /// Indice punto selezionato (sync mappa↔grafico)
  int? _selectedPointIndex;

  bool _isAdmin = false;

  /// Descrizione del sentiero. Caricata direttamente dal doc Firestore:
  /// il modello PublicTrail arriva spesso dalla cache locale, che non
  /// trasporta la description (popolata dall'arricchimento AI/manuale).
  String? _trailDescription;

  @override
  void initState() {
    super.initState();
    _loadFullGeometry();
    _loadAdminStatus();
    _loadDescription();
  }

  Future<void> _loadDescription() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('public_trails')
          .doc(widget.trail.id)
          .get();
      final desc = doc.data()?['description']?.toString().trim();
      if (mounted && desc != null && desc.length >= 20) {
        setState(() => _trailDescription = desc);
      }
    } catch (e) {
      debugPrint('[TrailDetail] Errore caricamento descrizione: $e');
    }
  }

  Future<void> _loadAdminStatus() async {
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    if (mounted) setState(() => _isAdmin = isAdmin);
  }

  /// Carica geometria completa dal database (790 punti con elevazione)
  Future<void> _loadFullGeometry() async {
    try {
      final points = await _trailsRepo.getFullGeometry(widget.trail.id);
      if (mounted) {
        setState(() {
          _fullPoints = points;
          _isLoadingFull = false;
        });
      }
    } catch (e) {
      debugPrint('[TrailDetail] Errore caricamento geometria: $e');
      if (mounted) setState(() => _isLoadingFull = false);
    }
  }

  /// Punti da usare: completi se disponibili, altrimenti semplificati
  List<TrackPoint> get _displayPoints => _fullPoints ?? widget.trail.points;

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
            actions: [
              // 🗑 Pulsante elimina (solo admin)
              if (_isAdmin)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _isDeleting
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.delete_forever, color: Colors.white),
                    tooltip: context.l10n.deleteTrailAdmin,
                    onPressed: _isDeleting ? null : _confirmDeleteTrail,
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              // Titolo spostato nell'area contenuto sottostante (mappa pulita).
              background: _fullBleedMap(_buildMap()),
            ),
          ),

          // Contenuto
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titolo traccia — spostato qui dall'overlay mappa,
                  // valorizza la tipografia bold del design system.
                  Text(
                    trail.displayName,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),

                  // Riga meta: difficoltà (solo se nota — niente "N/D") +
                  // rete/gestore. Sostituisce la vecchia info card.
                  if (trail.difficulty != null ||
                      trail.networkName.isNotEmpty ||
                      trail.operator != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (trail.difficulty != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${trail.difficultyIcon} ${trail.difficultyName}',
                              style: const TextStyle(
                                color: AppColors.info,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            [
                              if (trail.networkName.isNotEmpty)
                                trail.networkName,
                              if (trail.operator != null) trail.operator!,
                            ].join(' · '),
                            style: TextStyle(
                                color: context.textMuted, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Descrizione (arricchimento AI revisionato o manuale)
                  if (_trailDescription != null) ...[
                    const SizedBox(height: 10),
                    ExpandableDescription(
                      text: _trailDescription!,
                      maxCollapsedLines: 4,
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Stat bar raggruppata: i numeri del giro in evidenza
                  _buildMainStats(),

                  // Profilo quota subito dopo i numeri: è IL dato di
                  // pianificazione (dove sono le salite), non un'appendice.
                  if (_displayPoints.length > 1) ...[
                    const SizedBox(height: 16),
                    _onSage(TrackChartsWidget(
                      points: _displayPoints,
                      height: 180,
                      onPointTap: (index, distance) {
                        setState(() => _selectedPointIndex = index);
                      },
                    )),
                    if (_isLoadingFull)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          context.l10n.loadingFullTrack,
                          style: TextStyle(fontSize: 11, color: context.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],

                  const SizedBox(height: 16),

                  // Sezioni contenuto — look minimalista "a lista":
                  // stesso sfondo salvia, niente cornici, separate da linea
                  // leggera. Gerarchia: visivo → lungo il percorso →
                  // "posso andarci?" → community → niche.
                  _onSage(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Foto community
                      TrailPhotosSection(trailId: widget.trail.id),

                      _sectionDivider(),

                      // POI community + POI OSM lungo il percorso
                      TrailPoisSection(
                        trailId: widget.trail.id,
                        allowAdd: true,
                        defaultLatitude: widget.trail.startLat,
                        defaultLongitude: widget.trail.startLng,
                        polyline: _displayPoints
                            .map((p) => LatLng(p.latitude, p.longitude))
                            .toList(),
                        loadOsmPois: true,
                      ),

                      _sectionDivider(),

                      // Condizioni sentiero — blocco unico: riassunto AI
                      // (quando c'è) sopra le segnalazioni community.
                      TrailConditionsAiCard(
                        trailId: widget.trail.id,
                        trailName: widget.trail.displayName,
                      ),
                      TrailConditionsSection(trailId: widget.trail.id),

                      _sectionDivider(),

                      // Previsioni meteo
                      WeatherForecastCard(
                        lat: widget.trail.startLat,
                        lng: widget.trail.startLng,
                      ),

                      _sectionDivider(),

                      // Recensioni e rating
                      TrailReviewsSection(trailId: widget.trail.id),

                      _sectionDivider(),

                      // Segmenti cronometrati
                      TrailSegmentsSection(
                        trail: widget.trail,
                        trailPoints: _displayPoints,
                      ),
                    ],
                  )),

                  const SizedBox(height: 16),
                  
                  // Dettagli
                  _onSage(_buildDetails()),

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

  Widget _buildMap() {
    if (_displayPoints.isEmpty) {
      return Container(
        color: AppColors.background,
        child: Center(child: Text(context.l10n.noGpsData)),
      );
    }

    // Crea un Track per abilitare TrackMapPage in fullscreen
    // (con grafico elevazione, scorrimento, colori pendenza)
    final track = Track(
      id: widget.trail.id,
      name: widget.trail.displayName,
      points: _displayPoints,
      activityType: ActivityType.trekking,
      createdAt: DateTime.now(),
      stats: TrackStats(
        distance: widget.trail.length?.toDouble() ?? 0,
        elevationGain: widget.trail.elevationGain ?? 0,
      ),
    );

    return InteractiveTrackMap(
      points: _displayPoints,
      height: 300,
      title: widget.trail.displayName,
      showUserLocation: true,
      highlightedPointIndex: _selectedPointIndex,
      poiTrailId: widget.trail.id, // mostra POI community pin sulla mappa
      loadOsmPois: true, // mostra anche POI OSM (rifugi, sorgenti, ecc.)
      onPointTap: (index) {
        setState(() => _selectedPointIndex = index);
      },
      track: track, // ⭐ Abilita TrackMapPage fullscreen con grafico elevazione
    );
  }

  /// Linea leggera che separa le sezioni nella vista "a lista".
  Widget _sectionDivider() => const Divider(
        height: 16,
        thickness: 1,
        color: Color(0xFFD6D9C5), // salvia leggermente più scuro dello sfondo
      );

  /// Avvolge una sezione perché sieda direttamente sullo sfondo salvia:
  /// card trasparente, e neutralizza anche `surface`/`outlineVariant` così i
  /// container basati sui ruoli tema (es. POI) perdono fondo bianco e cornice.
  Widget _onSage(Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        cardTheme: Theme.of(context).cardTheme.copyWith(
              color: Colors.transparent,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                side: BorderSide.none,
              ),
            ),
        colorScheme: cs.copyWith(
          surface: Colors.transparent,        // Container(surface) → salvia
          outlineVariant: Colors.transparent, // cornici sezioni → via
        ),
      ),
      child: child,
    );
  }

  /// Mappa a tutta larghezza: card senza margine, senza bordo, angoli vivi.
  Widget _fullBleedMap(Widget child) {
    return Theme(
      data: Theme.of(context).copyWith(
        cardTheme: Theme.of(context).cardTheme.copyWith(
              margin: EdgeInsets.zero,
              color: Colors.transparent,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide.none,
              ),
            ),
      ),
      child: child,
    );
  }

  Widget _buildMainStats() {
    final trail = widget.trail;

    // Durata stimata (Naismith) — molto più utile all'utente del conteggio
    // "Punti GPS" (dato tecnico). La tilde comunica che è una stima.
    String etaValue = '--';
    if (trail.length != null) {
      final eta = EtaEstimator.estimate(
        distanceMeters: trail.length!,
        elevationGainMeters: trail.elevationGain ?? 0,
        activityType: trail.parsedActivityType,
      );
      if (eta > Duration.zero) {
        final h = eta.inHours;
        final m = eta.inMinutes % 60;
        etaValue = h > 0 ? '~${h}h ${m}m' : '~${m}m';
      }
    }

    return TrackStatsBar(
      stats: [
        TrackStat(
          icon: Icons.straighten,
          value: trail.length != null
              ? trail.lengthKm.toStringAsFixed(1)
              : '--',
          unit: 'km',
          label: context.l10n.lengthLabel,
          color: AppColors.primary,
        ),
        TrackStat(
          icon: Icons.trending_up,
          value: trail.elevationGain != null
              ? '+${trail.elevationGain!.toStringAsFixed(0)}'
              : '--',
          unit: 'm',
          label: context.l10n.elevationLabel,
          color: AppColors.success,
        ),
        TrackStat(
          icon: Icons.timer,
          value: etaValue,
          label: context.l10n.durationStatLabel,
          color: AppColors.info,
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
            Text(
              context.l10n.informationLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(height: 24),
            if (trail.ref != null)
              _buildDetailRow(Icons.tag, context.l10n.trailNumber, trail.ref!),
            _buildDetailRow(Icons.terrain, context.l10n.difficultyLabel, trail.difficultyName),
            if (trail.activityType != null)
              _buildDetailRow(Icons.directions_walk, context.l10n.activityLabel, trail.activityType!),
            if (trail.operator != null)
              _buildDetailRow(Icons.business, context.l10n.managerLabel, trail.operator!),
            if (trail.networkName.isNotEmpty)
              _buildDetailRow(Icons.hub, context.l10n.networkLabel, trail.networkName),
            if (trail.region != null)
              _buildDetailRow(Icons.map, context.l10n.regionLabel, trail.region!),
            _buildDetailRow(Icons.source, context.l10n.sourceLabel, trail.source == 'community' ? context.l10n.communitySource : context.l10n.openStreetMapSource),
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
        // ⭐ Pulsante principale: Segui la traccia
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _displayPoints.length > 1 ? _followTrail : null,
            icon: const Icon(Icons.explore),
            label: Text(context.l10n.followTrail),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Scarica GPX
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
            label: Text(_isExporting ? context.l10n.exporting : context.l10n.downloadGpx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Naviga al punto di partenza
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _displayPoints.isNotEmpty ? _navigateToStart : null,
            icon: const Icon(Icons.navigation),
            label: Text(context.l10n.navigateToStart),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  /// 🗑 Conferma eliminazione sentiero (solo admin)
  Future<void> _confirmDeleteTrail() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: AppColors.danger),
            const SizedBox(width: 8),
            Text(context.l10n.deleteTrailTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.deleteTrailConfirmIntro,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('"${widget.trail.displayName}"'),
            const SizedBox(height: 4),
            Text('ID: ${widget.trail.id}', style: TextStyle(fontSize: 11, color: context.textMuted)),
            const SizedBox(height: 12),
            Text(
              context.l10n.deleteTrailIrreversible,
              style: const TextStyle(color: AppColors.danger),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: Text(context.l10n.deleteAction),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _deleteTrail();
    }
  }

  Future<void> _deleteTrail() async {
    setState(() => _isDeleting = true);

    try {
      await FirebaseFirestore.instance
          .collection('public_trails')
          .doc(widget.trail.id)
          .delete();

      debugPrint('[AdminDelete] ✅ Sentiero eliminato: ${widget.trail.id} - ${widget.trail.displayName}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.trailDeletedName(widget.trail.displayName)),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true); // true = sentiero eliminato (per refresh lista)
      }
    } catch (e) {
      debugPrint('[AdminDelete] ❌ Errore: $e');
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.deleteErrorWithDetails(e.toString())),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  /// Apre la pagina "Segui la traccia" con navigazione GPS in tempo reale
  void _followTrail() {
    if (_displayPoints.length <= 1) return;

    // Se la geometria completa non è ancora caricata, avvisa
    if (_isLoadingFull) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.loadingTrailWait)),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordPage(
          reference: RecordingReference.fromTrail(
            trailPoints: _displayPoints
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList(),
            trailName: widget.trail.displayName,
            totalDistance: widget.trail.length?.toDouble(),
            totalElevationGain: widget.trail.elevationGain,
          ),
          initialActivityType: widget.trail.parsedActivityType,
        ),
      ),
    );
  }

  /// Apre l'app di navigazione verso il punto di partenza del sentiero
  Future<void> _navigateToStart() async {
    if (_displayPoints.isEmpty) return;

    final start = _displayPoints.first;
    final lat = start.latitude;
    final lng = start.longitude;

    Uri uri;
    if (Platform.isIOS) {
      // Apple Maps con fallback a Google Maps
      uri = Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&dirflg=d&t=m');
    } else {
      // Google Maps navigation
      uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: URL generico Google Maps (funziona ovunque)
        final fallback = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.cannotOpenNavigation(e.toString())),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _exportGpx() async {
    if (_displayPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noGpsPointsToExport)),
      );
      return;
    }

    if (_isLoadingFull) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.loadingRetryLater)),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final trail = widget.trail;
      final track = Track(
        id: trail.id,
        name: trail.displayName,
        description: context.l10n.trailGpxName(trail.displayName),
        points: _displayPoints,
        activityType: ActivityType.trekking,
        createdAt: DateTime.now(),
        stats: const TrackStats(),
      );
      final filePath = await _gpxService.saveGpxToFile(track);

      if (!mounted) return;
      final shareText = context.l10n.trailGpxName(widget.trail.displayName);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(filePath)],
        subject: widget.trail.displayName,
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
}

