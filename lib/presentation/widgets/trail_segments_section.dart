import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/segment.dart';
import '../../data/models/track.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/public_trails_repository.dart';
import '../../data/repositories/segments_repository.dart';
import '../pages/segments/segment_detail_page.dart';
import '../pages/segments/segment_editor_page.dart';

/// Sezione "Segmenti" nella pagina dettaglio sentiero.
///
/// Mostra la lista dei segmenti cronometrati creati per questo sentiero con
/// anteprima del primatista. L'admin vede un bottone "+" per crearne di nuovi.
class TrailSegmentsSection extends StatefulWidget {
  final PublicTrail trail;
  final List<TrackPoint> trailPoints;

  const TrailSegmentsSection({
    super.key,
    required this.trail,
    required this.trailPoints,
  });

  @override
  State<TrailSegmentsSection> createState() => _TrailSegmentsSectionState();
}

class _TrailSegmentsSectionState extends State<TrailSegmentsSection> {
  final SegmentsRepository _repo = SegmentsRepository();
  List<Segment> _segments = [];
  Map<String, SegmentEffort?> _champions = {};
  bool _loading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final adminFuture = AdminRepository.isCurrentUserAdmin();
    final segsFuture = _repo.getSegmentsForTrail(widget.trail.id);
    final results = await Future.wait([adminFuture, segsFuture]);
    if (!mounted) return;

    final isAdmin = results[0] as bool;
    final segments = results[1] as List<Segment>;

    // Carica il primatista di ogni segmento in parallelo
    final championFutures = segments.map((s) => _repo.getTopEffort(s.id));
    final champs = await Future.wait(championFutures);
    if (!mounted) return;

    setState(() {
      _isAdmin = isAdmin;
      _segments = segments;
      _champions = {
        for (var i = 0; i < segments.length; i++) segments[i].id: champs[i],
      };
      _loading = false;
    });
  }

  Future<void> _openEditor() async {
    final created = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SegmentEditorPage(
          trail: widget.trail,
          trailPoints: widget.trailPoints,
        ),
      ),
    );
    if (created != null) {
      // Ricarica
      await _init();
    }
  }

  Future<void> _openSegment(Segment s) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => SegmentDetailPage(segment: s)),
    );
    if (result == 'deleted') {
      await _init();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_segments.isEmpty)
              _buildEmpty()
            else
              ..._segments.map((s) => _buildSegmentTile(s)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.timer_outlined, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Segmenti',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (!_loading && _segments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              '${_segments.length}',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
        if (_isAdmin)
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: widget.trailPoints.length >= 2 ? _openEditor : null,
            tooltip: 'Crea segmento',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        _isAdmin
            ? 'Nessun segmento ancora. Tocca "+" per crearne uno.'
            : 'Nessun segmento disponibile su questo sentiero.',
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildSegmentTile(Segment s) {
    final champion = _champions[s.id];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: () => _openSegment(s),
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.flag, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.straighten, size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Text(
                        '${(s.distance / 1000).toStringAsFixed(2)} km',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.trending_up, size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Text(
                        '+${s.elevationGain.round()} m',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  if (champion != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.emoji_events, size: 12, color: Colors.amber),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${champion.username} · ${champion.durationFormatted}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
