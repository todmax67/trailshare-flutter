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
import '../track_detail/track_detail_page.dart';
import 'tour_edit_page.dart';

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
          SizedBox(height: 280, child: _buildMap(tour)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tour.description != null && tour.description!.isNotEmpty) ...[
                  Text(tour.description!, style: TextStyle(color: context.textSecondary)),
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
                    _stat(Icons.calendar_month, context.l10n.tourDays(tour.daysCount)),
                    _stat(Icons.format_list_numbered, context.l10n.tourStages(tour.trackIds.length)),
                    _stat(Icons.straighten, '${tour.totalDistanceKm.toStringAsFixed(1)} km'),
                    _stat(Icons.trending_up, '+${tour.totalElevationGain.toStringAsFixed(0)} m', AppColors.success),
                    if (tour.totalDuration.inMinutes > 0) _stat(Icons.schedule, durStr),
                  ],
                ),
                const SizedBox(height: 24),
                Text(context.l10n.tourStagesTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 8),
                for (var i = 0; i < _tracks.length; i++)
                  _StageTile(
                    index: i + 1,
                    track: _tracks[i],
                    color: _stageColors[i % _stageColors.length],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TrackDetailPage(track: _tracks[i])),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
