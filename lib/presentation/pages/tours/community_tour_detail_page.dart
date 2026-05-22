import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../data/models/tour.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../../data/repositories/tours_repository.dart';
import '../discover/community_track_detail_page.dart';
import 'widgets/expandable_description.dart';
import 'widgets/multi_stage_elevation_chart.dart';
import 'widgets/tour_hero.dart';
import 'widgets/tour_rich_sections.dart';

/// Vista community (read-only) di un tour pubblico.
///
/// Usa le [TourStageSummary] denormalizzate nel mirror `community_tours` per
/// renderizzare la mappa multi-polyline e la lista tappe senza accedere alle
/// tracce private dell'autore. Le tappe con traccia pubblicata in
/// `community_tracks` sono tappabili e aprono la detail community ricca.
class CommunityTourDetailPage extends StatefulWidget {
  final String tourId;

  const CommunityTourDetailPage({super.key, required this.tourId});

  @override
  State<CommunityTourDetailPage> createState() => _CommunityTourDetailPageState();
}

class _CommunityTourDetailPageState extends State<CommunityTourDetailPage> {
  final ToursRepository _repo = ToursRepository();
  final CommunityTracksRepository _communityTracksRepo = CommunityTracksRepository();
  Tour? _tour;
  bool _loading = true;

  /// Mapping live `privateTrackId -> communityDocId`.
  /// Prevale sul denorm `communityTrackId` del tour (che può essere stale se
  /// l'autore ha pubblicato una tappa DOPO aver pubblicato il tour).
  Map<String, String> _liveCommunityIds = const {};

  static const _stageColors = <Color>[
    Color(0xFF1976D2),
    Color(0xFFD32F2F),
    Color(0xFF388E3C),
    Color(0xFFF57C00),
    Color(0xFF7B1FA2),
    Color(0xFF0097A7),
    Color(0xFFC2185B),
    Color(0xFF5D4037),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tour = await _repo.getPublicTourById(widget.tourId);
    Map<String, String> liveMap = const {};
    if (tour != null) {
      final stages = tour.stages ?? const <TourStageSummary>[];
      // Ricostruisce Track "shallow" dai dati denormalizzati per risolvere
      // il mapping via nome+distanza (fallback legacy JS).
      final shallowTracks = <Track>[
        for (final s in stages)
          if (s.trackId.isNotEmpty)
            Track(
              id: s.trackId,
              name: s.name,
              points: const [],
              createdAt: DateTime.now(),
              stats: TrackStats(
                distance: s.distance,
                elevationGain: s.elevationGain,
                duration: s.duration,
              ),
            ),
      ];
      debugPrint(
        '[CommunityTourDetail] Tour ${tour.id} — ${stages.length} stages, owner ${tour.ownerId}',
      );
      liveMap = await _repo.resolvePublicTrackMap(shallowTracks, tour.ownerId);
      debugPrint('[CommunityTourDetail] Mapping live: $liveMap');
    }
    if (!mounted) return;
    setState(() {
      _tour = tour;
      _liveCommunityIds = liveMap;
      _loading = false;
    });
  }

  /// Restituisce il doc id in `community_tracks` per [stage] se esiste,
  /// combinando live-resolve e denorm cached.
  String? _resolveCommunityId(TourStageSummary stage) {
    if (stage.trackId.isEmpty) return null;
    final live = _liveCommunityIds[stage.trackId];
    if (live != null) return live;
    if (stage.isTrackPublic) {
      return stage.communityTrackId ?? stage.trackId;
    }
    return null;
  }

  bool _isStageTappable(TourStageSummary stage) =>
      _resolveCommunityId(stage) != null;

  Future<void> _openStage(TourStageSummary stage) async {
    final communityId = _resolveCommunityId(stage);
    if (communityId == null) return;
    final track = await _communityTracksRepo.getTrackById(communityId);
    if (!mounted || track == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CommunityTrackDetailPage(track: track)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_tour == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(context.l10n.loadingError)),
      );
    }

    final tour = _tour!;
    final stages = tour.stages ?? const <TourStageSummary>[];
    final hours = tour.totalDuration.inHours;
    final mins = tour.totalDuration.inMinutes % 60;
    final durStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Scaffold(
      appBar: AppBar(
        title: Text(tour.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => SharePlus.instance.share(ShareParams(
              text: '${tour.title}\nhttps://trailshare.app/tour/${tour.id}',
              subject: tour.title,
            )),
          ),
        ],
      ),
      body: ListView(
        children: [
          TourHero(
            coverPhotoUrl: tour.coverPhotoUrl,
            title: tour.title,
            subtitle:
                '${tour.type == TourType.consecutive ? "${tour.daysCount} giorni" : "${tour.trackIds.length} tracce"} · '
                '${tour.totalDistanceKm.toStringAsFixed(1)} km · '
                '+${tour.totalElevationGain.toStringAsFixed(0)} m',
            map: _buildMap(tour, stages),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: tour.ownerPhotoUrl != null
                          ? NetworkImage(tour.ownerPhotoUrl!)
                          : null,
                      child: tour.ownerPhotoUrl == null
                          ? const Icon(Icons.person, size: 18)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tour.ownerName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (tour.description != null && tour.description!.isNotEmpty) ...[
                  ExpandableDescription(
                    text: tour.description!,
                    style: TextStyle(
                        color: context.textSecondary, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(context.l10n.tourTotals, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (tour.type == TourType.consecutive)
                      _stat(Icons.calendar_month, context.l10n.tourDays(tour.daysCount)),
                    _stat(
                      tour.type == TourType.consecutive
                          ? Icons.format_list_numbered
                          : Icons.collections_bookmark_outlined,
                      tour.type == TourType.consecutive
                          ? context.l10n.tourStages(tour.trackIds.length)
                          : '${tour.trackIds.length} tracce',
                    ),
                    _stat(Icons.straighten, '${tour.totalDistanceKm.toStringAsFixed(1)} km'),
                    _stat(Icons.trending_up, '+${tour.totalElevationGain.toStringAsFixed(0)} m', AppColors.success),
                    if (tour.totalDuration.inMinutes > 0) _stat(Icons.schedule, durStr),
                  ],
                ),
                const SizedBox(height: 20),
                // Grafico altimetrico cumulativo: solo per cammini
                // consecutivi (per le collezioni le tracce sono
                // indipendenti, sommarle sarebbe fuorviante).
                if (tour.type == TourType.consecutive &&
                    stages.isNotEmpty) ...[
                  MultiStageElevationChart.fromStageSummaries(stages),
                  const SizedBox(height: 20),
                ],
                // Epic 11 — sezioni ricche: chip difficoltà/periodo,
                // gallery, equipaggiamento, note storiche.
                TourRichHeaderSections(tour: tour),
                if (stages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    tour.type == TourType.consecutive
                        ? context.l10n.tourStagesTitle
                        : 'Tracce',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < stages.length; i++) ...[
                    _StageTile(
                      index: i + 1,
                      stage: stages[i],
                      color: _stageColors[i % _stageColors.length],
                      onTap: _isStageTappable(stages[i]) ? () => _openStage(stages[i]) : null,
                    ),
                    if (stages[i].accommodationBusinessId != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(60, 0, 0, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StageAccommodationBadge(
                            businessId:
                                stages[i].accommodationBusinessId!,
                            businessName: stages[i].accommodationName,
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(Tour tour, List<TourStageSummary> stages) {
    final polylines = <Polyline>[];
    LatLng? firstPoint;
    for (var i = 0; i < stages.length; i++) {
      if (stages[i].points.isEmpty) continue;
      firstPoint ??= stages[i].points.first;
      polylines.add(Polyline(
        points: stages[i].points,
        strokeWidth: 4,
        color: _stageColors[i % _stageColors.length],
      ));
    }

    final b = tour.bounds;
    final center = firstPoint ??
        (b != null
            ? LatLng((b.north + b.south) / 2, (b.east + b.west) / 2)
            : const LatLng(45.0, 10.0));

    double zoom = 10;
    if (b != null) {
      final dLat = (b.north - b.south).abs();
      final dLon = (b.east - b.west).abs();
      final maxSpan = dLat > dLon ? dLat : dLon;
      if (maxSpan > 2) {
        zoom = 7;
      } else if (maxSpan > 1) {
        zoom = 8;
      } else if (maxSpan > 0.5) {
        zoom = 9;
      } else if (maxSpan > 0.2) {
        zoom = 10;
      } else if (maxSpan > 0.1) {
        zoom = 11;
      } else if (maxSpan > 0.05) {
        zoom = 12;
      } else {
        zoom = 13;
      }
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.trailshare.app',
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
      ],
    );
  }

  Widget _stat(IconData icon, String value, [Color? color]) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color ?? context.textSecondary),
        const SizedBox(width: 6),
        Text(value, style: TextStyle(color: color ?? context.textPrimary, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _StageTile extends StatelessWidget {
  final int index;
  final TourStageSummary stage;
  final Color color;
  final VoidCallback? onTap;

  const _StageTile({
    required this.index,
    required this.stage,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTappable = onTap != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Text('$index'),
        ),
        title: Text(stage.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${stage.distanceKm.toStringAsFixed(1)} km · +${stage.elevationGain.toStringAsFixed(0)} m',
        ),
        trailing: isTappable ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}
