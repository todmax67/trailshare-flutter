import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/extensions/l10n_extension.dart';
import '../../data/models/segment.dart';
import '../../data/models/track.dart';
import '../../data/repositories/segments_repository.dart';
import '../pages/segments/segment_detail_page.dart';
import '../pages/segments/segment_editor_page.dart';
import '../../core/extensions/theme_colors_extension.dart';

/// Sezione segmenti per una traccia specifica.
///
/// Usata in due modalità:
/// - **Editable** (default): nella `track_detail_page` della propria traccia
///   personale. Mostra tutti i segmenti (pubblici + privati) creati dalla
///   traccia, con bottone "+" per crearne di nuovi e delete inline.
/// - **Read-only**: nella `community_track_detail_page` o quando un altro
///   utente visualizza la pagina. Mostra solo i segmenti pubblici, senza
///   bottoni di modifica.
class TrackSegmentsSection extends StatefulWidget {
  final String trackId;

  /// Punti della traccia sorgente, necessari per aprire l'editor.
  /// Richiesto solo se non `readOnly`.
  final List<TrackPoint>? trackPoints;

  /// UID del proprietario della traccia sorgente (per check ownership).
  final String? trackOwnerId;

  /// Tipo attività default per nuovi segmenti.
  final String? activityType;

  /// Se true, nasconde "+" e delete e filtra solo segmenti pubblici.
  final bool readOnly;

  /// Titolo override (default: "I miei segmenti" o "Segmenti" in readOnly).
  final String? title;

  const TrackSegmentsSection({
    super.key,
    required this.trackId,
    this.trackPoints,
    this.trackOwnerId,
    this.activityType,
    this.readOnly = false,
    this.title,
  });

  @override
  State<TrackSegmentsSection> createState() => _TrackSegmentsSectionState();
}

class _TrackSegmentsSectionState extends State<TrackSegmentsSection> {
  final SegmentsRepository _repo = SegmentsRepository();
  List<Segment> _segments = [];
  Map<String, SegmentEffort?> _champions = {};
  bool _loading = true;

  String get _trackId => widget.trackId;

  bool get _isOwner {
    if (widget.readOnly) return false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && uid == widget.trackOwnerId;
  }

  bool get _canCreate =>
      _isOwner && widget.trackPoints != null && widget.trackPoints!.length >= 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final segments = await _repo.getSegmentsCreatedFromTrack(
      _trackId,
      publicOnly: widget.readOnly,
    );
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
    final points = widget.trackPoints;
    if (points == null || points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.trackNoPointsForSegment)),
      );
      return;
    }
    final created = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SegmentEditorPage(
          sourcePoints: points,
          isOfficial: false,
          sourceTrackId: _trackId,
          defaultActivityType: widget.activityType,
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
        title: Text(context.l10n.deleteSegmentQuestion),
        content: Text('"${s.name}" verrà eliminato insieme alla sua classifica.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.delete),
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
        SnackBar(
          content: Text(context.l10n.deleteError),
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
    final title = widget.title ?? (widget.readOnly ? 'Segmenti' : 'I miei segmenti');
    return Row(
      children: [
        const Icon(Icons.timer_outlined, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (!_loading && _segments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              '${_segments.length}',
              style: TextStyle(fontSize: 13, color: context.textMuted),
            ),
          ),
        if (_canCreate)
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
        widget.readOnly
            ? 'Nessun segmento su questa traccia.'
            : (_canCreate
                ? 'Nessun segmento creato da questa traccia. Tocca "+" per crearne uno.'
                : 'Nessun segmento creato da questa traccia.'),
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
                          Icon(Icons.lock_outline, size: 13, color: context.textMuted),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.straighten, size: 12, color: context.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          '${(s.distance / 1000).toStringAsFixed(2)} km',
                          style: TextStyle(fontSize: 11, color: context.textMuted),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.trending_up, size: 12, color: context.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          '+${s.elevationGain.round()} m',
                          style: TextStyle(fontSize: 11, color: context.textMuted),
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
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textSecondary,
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
                  tooltip: context.l10n.delete,
                  color: context.textMuted,
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
