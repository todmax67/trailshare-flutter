import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/segment.dart';
import '../../data/models/track.dart';
import '../../data/repositories/segments_repository.dart';
import '../pages/segments/segment_detail_page.dart';
import '../pages/segments/segment_editor_page.dart';

/// Sezione "I miei segmenti" visibile nella pagina dettaglio di una traccia
/// personale.
///
/// Mostra i segmenti user-created ritagliati da questa specifica traccia.
/// Il proprietario della traccia può crearne di nuovi e eliminare i propri.
class TrackSegmentsSection extends StatefulWidget {
  final Track track;

  const TrackSegmentsSection({super.key, required this.track});

  @override
  State<TrackSegmentsSection> createState() => _TrackSegmentsSectionState();
}

class _TrackSegmentsSectionState extends State<TrackSegmentsSection> {
  final SegmentsRepository _repo = SegmentsRepository();
  List<Segment> _segments = [];
  Map<String, SegmentEffort?> _champions = {};
  bool _loading = true;

  String? get _trackId => widget.track.id;

  bool get _isOwner {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && uid == widget.track.userId;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final trackId = _trackId;
    if (trackId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);

    final segments = await _repo.getSegmentsCreatedFromTrack(trackId);
    final champs = await Future.wait(segments.map((s) => _repo.getTopEffort(s.id)));
    if (!mounted) return;

    setState(() {
      _segments = segments;
      _champions = {
        for (var i = 0; i < segments.length; i++) segments[i].id: champs[i],
      };
      _loading = false;
    });
  }

  Future<void> _openEditor() async {
    if (widget.track.points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Traccia senza punti: impossibile creare un segmento')),
      );
      return;
    }
    final created = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SegmentEditorPage(
          sourcePoints: widget.track.points,
          isOfficial: false,
          sourceTrackId: _trackId,
          defaultActivityType: widget.track.activityType.name,
        ),
      ),
    );
    if (created != null) {
      await _load();
    }
  }

  Future<void> _openSegment(Segment s) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => SegmentDetailPage(segment: s)),
    );
    if (result == 'deleted') {
      await _load();
    }
  }

  Future<void> _deleteSegment(Segment s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare segmento?'),
        content: Text('"${s.name}" verrà eliminato insieme alla sua classifica.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await _repo.deleteSegment(s.id);
    if (!mounted) return;

    if (ok) {
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante l\'eliminazione'),
          backgroundColor: AppColors.danger,
        ),
      );
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
            'I miei segmenti',
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
        if (_isOwner)
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: _openEditor,
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
        _isOwner
            ? 'Nessun segmento creato da questa traccia. Tocca "+" per crearne uno.'
            : 'Nessun segmento creato da questa traccia.',
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
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: () => _openSegment(s),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!s.isPublic) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.lock_outline, size: 13, color: AppColors.textMuted),
                        ],
                      ],
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
              if (_isOwner)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _deleteSegment(s),
                  tooltip: 'Elimina',
                  color: AppColors.textMuted,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
