import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../data/models/tour.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tours_repository.dart';
import 'widgets/expandable_description.dart';
import 'widgets/multi_stage_elevation_chart.dart';
import 'widgets/tour_hero.dart';
import 'widgets/tour_rich_sections.dart';
import '../track_detail/track_detail_page.dart';
import '../track_3d/track_3d_page.dart';
import '../../widgets/paywall_sheet.dart';
import '../../../core/services/pro_gate_service.dart';
import 'tour_edit_page.dart';
import '../../widgets/flat_section.dart';

/// Pagina di dettaglio di un tour: mappa aggregata con una polyline per tappa
/// + totali + lista tappe tappabili.
class TourDetailPage extends StatefulWidget {
  final String tourId;

  const TourDetailPage({super.key, required this.tourId});

  @override
  State<TourDetailPage> createState() => _TourDetailPageState();
}

class _TourDetailPageState extends State<TourDetailPage> {
  final ToursRepository _repo = ToursRepository();
  Tour? _tour;
  List<Track> _tracks = [];
  bool _loading = true;

  // Palette di colori per differenziare le tappe sulla mappa.
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
    setState(() => _loading = true);
    final tour = await _repo.getTourById(widget.tourId);
    if (tour == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final tracks = await _repo.loadTourTracks(tour);
    if (!mounted) return;
    setState(() {
      _tour = tour;
      _tracks = tracks;
      _loading = false;
    });
  }

  Future<void> _shareWebLink(Tour tour) async {
    final url = 'https://trailshare.app/tour/${tour.id}';
    await SharePlus.instance.share(ShareParams(
      text: '${tour.title}\n$url',
      subject: tour.title,
    ));
  }

  Future<void> _edit() async {
    if (_tour == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TourEditPage(existing: _tour)),
    );
    if (changed == true) _load();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteAction),
        content: Text(context.l10n.deleteTourConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirm != true || _tour == null) return;

    await _repo.deleteTour(_tour!.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tourDeleted), backgroundColor: AppColors.success),
    );
    Navigator.pop(context, true);
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
    final hours = tour.totalDuration.inHours;
    final mins = tour.totalDuration.inMinutes % 60;
    final durStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Scaffold(
      appBar: AppBar(
        title: Text(tour.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (tour.isPublic)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => _shareWebLink(tour),
            ),
          IconButton(icon: const Icon(Icons.edit), onPressed: _edit),
          IconButton(icon: const Icon(Icons.delete_outline), color: AppColors.danger, onPressed: _delete),
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
            map: _buildMap(tour),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tour.description != null && tour.description!.isNotEmpty) ...[
                  ExpandableDescription(
                    text: tour.description!,
                    style: TextStyle(
                        color: context.textSecondary, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    if (tour.isPublic)
                      Chip(
                        avatar: Icon(Icons.public, size: 16, color: AppColors.info),
                        label: Text(context.l10n.tourPublic),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 16),
                _build3DButton(),
                const SizedBox(height: 20),
                // Epic 11 — chart altimetria multistage (solo owner
                // detail: ha accesso alle tracce private con TrackPoint
                // elevation).
                // Per le collezioni le tracce sono indipendenti: il
                // grafico cumulativo sarebbe fuorviante.
                if (_tracks.isNotEmpty && tour.type == TourType.consecutive) ...[
                  MultiStageElevationChart.fromTracks(_tracks),
                  const SizedBox(height: 20),
                ],
                // Epic 11 — sezioni ricche: chip difficoltà/periodo,
                // gallery, equipaggiamento, note storiche.
                TourRichHeaderSections(tour: tour),
                Text(
                  tour.type == TourType.consecutive
                      ? context.l10n.tourStagesTitle
                      : 'Tracce',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _tracks.length; i++) ...[
                  if (i > 0) const SectionDivider(),
                  SageSurface(
                    child: _StageTile(
                      index: i + 1,
                      track: _tracks[i],
                      color: _stageColors[i % _stageColors.length],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TrackDetailPage(track: _tracks[i])),
                      ),
                    ),
                  ),
                  if (tour.stageAccommodations[_tracks[i].id] != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(60, 0, 0, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _AccommodationBadgeLoader(
                          businessId:
                              tour.stageAccommodations[_tracks[i].id]!,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pulsante "Vedi in 3D" del tour privato: unisce i punti (con quota
  /// reale) di tutte le tracce in un unico fly-through. Pro-gated.
  Widget _build3DButton() {
    final total = _tracks.fold<int>(0, (n, t) => n + t.points.length);
    if (total < 2) return const SizedBox.shrink();
    final isPro = ProGateService().isPro;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _open3D,
        icon: const Icon(Icons.threed_rotation, size: 20),
        label: Text(isPro ? 'Vedi in 3D' : 'Vedi in 3D (Pro)'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
    // Le tracce del tour privato hanno quota reale (DEM).
    // Ogni traccia è un segmento con il suo nome. Il viewer 3D decide
    // salto volante (raccolta) vs continuità liscia (cammino) dal gap.
    final valid = _tracks.where((t) => t.points.length >= 2).toList();
    if (valid.isEmpty) return;
    final segments = [for (final t in valid) t.points];
    final names = [for (final t in valid) t.name];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Track3DPage(
          trackName: _tour?.title ?? 'Tour',
          segments: segments,
          segmentNames: names,
        ),
      ),
    );
  }

  Widget _buildMap(Tour tour) {
    final polylines = <Polyline>[];
    LatLng? firstPoint;

    for (var i = 0; i < _tracks.length; i++) {
      final pts = _tracks[i]
          .points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();
      if (pts.isEmpty) continue;
      firstPoint ??= pts.first;
      polylines.add(Polyline(
        points: pts,
        strokeWidth: 4,
        color: _stageColors[i % _stageColors.length],
      ));
    }

    final center = firstPoint ??
        (tour.bounds != null
            ? LatLng(
                (tour.bounds!.north + tour.bounds!.south) / 2,
                (tour.bounds!.east + tour.bounds!.west) / 2,
              )
            : const LatLng(45.0, 10.0));

    // Zoom approssimativo dal bbox.
    double zoom = 10;
    final b = tour.bounds;
    if (b != null) {
      final dLat = (b.north - b.south).abs();
      final dLon = (b.east - b.west).abs();
      final maxSpan = dLat > dLon ? dLat : dLon;
      if (maxSpan > 0) {
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
        PolylineLayer(polylines: polylines),
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

/// Carica async name+slug del business accommodation e mostra il
/// badge cliccabile. Cache repository minima — per ora 1 fetch
/// per render. Il community_tours mirror denormalizza già il name
/// nelle stages, quindi solo la detail owner ha bisogno di questo
/// loader.
class _AccommodationBadgeLoader extends StatefulWidget {
  final String businessId;
  const _AccommodationBadgeLoader({required this.businessId});

  @override
  State<_AccommodationBadgeLoader> createState() =>
      _AccommodationBadgeLoaderState();
}

class _AccommodationBadgeLoaderState extends State<_AccommodationBadgeLoader> {
  String? _name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.businessId)
          .get();
      if (!mounted) return;
      setState(() => _name = doc.data()?['name']?.toString());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StageAccommodationBadge(
      businessId: widget.businessId,
      businessName: _name,
    );
  }
}

class _StageTile extends StatelessWidget {
  final int index;
  final Track track;
  final Color color;
  final VoidCallback onTap;

  const _StageTile({
    required this.index,
    required this.track,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Text('$index'),
        ),
        title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${track.stats.distanceKm.toStringAsFixed(1)} km · +${track.stats.elevationGain.toStringAsFixed(0)} m',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
