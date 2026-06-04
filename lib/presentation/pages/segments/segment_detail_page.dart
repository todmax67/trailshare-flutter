import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/segment.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/segments_repository.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Pagina dettaglio segmento con classifica Top 10 + tempo personale.
class SegmentDetailPage extends StatefulWidget {
  final Segment segment;

  const SegmentDetailPage({super.key, required this.segment});

  @override
  State<SegmentDetailPage> createState() => _SegmentDetailPageState();
}

class _SegmentDetailPageState extends State<SegmentDetailPage> {
  final SegmentsRepository _repo = SegmentsRepository();
  List<SegmentEffort> _leaderboard = [];
  SegmentEffort? _myBest;
  int? _myRank; // 1-based
  bool _loading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final a = await AdminRepository.isCurrentUserAdmin();
    if (mounted) setState(() => _isAdmin = a);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final board = await _repo.getLeaderboard(widget.segment.id);
    SegmentEffort? mine;
    int? myRank;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      mine = await _repo.getUserBestEffort(widget.segment.id, uid);
      if (mine != null) {
        final pos = board.indexWhere((e) => e.userId == uid);
        if (pos >= 0) myRank = pos + 1;
      }
    }
    if (!mounted) return;
    setState(() {
      _leaderboard = board;
      _myBest = mine;
      _myRank = myRank;
      _loading = false;
    });
  }

  Future<void> _deleteSegment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare segmento?'),
        content: Text('Classifica e tentativi verranno persi. Questa azione non può essere annullata.'),
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
    final ok = await _repo.deleteSegment(widget.segment.id);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, 'deleted');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore durante l\'eliminazione')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final seg = widget.segment;

    return Scaffold(
      appBar: AppBar(
        title: Text(seg.name),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteSegment,
              tooltip: 'Elimina segmento',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStats(seg),
                  const SizedBox(height: 16),
                  _buildMap(seg),
                  if (seg.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(seg.description, style: const TextStyle(fontSize: 14)),
                  ],
                  const SizedBox(height: 20),
                  _buildMyPerformance(),
                  const SizedBox(height: 16),
                  _buildLeaderboard(),
                ],
              ),
            ),
    );
  }

  Widget _buildStats(Segment seg) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _stat(Icons.straighten, '${(seg.distance / 1000).toStringAsFixed(2)} km', 'Distanza'),
            const SizedBox(width: 12),
            _stat(Icons.trending_up, '+${seg.elevationGain.round()} m', 'Dislivello'),
            const SizedBox(width: 12),
            _stat(Icons.people, '${_leaderboard.length}', 'Tentativi'),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: context.textMuted)),
        ],
      ),
    );
  }

  Widget _buildMap(Segment seg) {
    final bounds = seg.polyline.isNotEmpty
        ? LatLngBounds.fromPoints(seg.polyline)
        : null;
    return SizedBox(
      height: 180,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IgnorePointer(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: seg.polyline.isNotEmpty ? seg.polyline.first : const LatLng(45, 10),
              initialZoom: 14,
              initialCameraFit: bounds != null
                  ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(30))
                  : null,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.trailshare.app',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: seg.polyline,
                    strokeWidth: 5,
                    color: AppColors.primary,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: seg.startPoint,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                  Marker(
                    point: seg.endPoint,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyPerformance() {
    final mine = _myBest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'La tua performance',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        if (mine == null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Non hai ancora completato questo segmento',
              style: TextStyle(color: context.textMuted, fontSize: 13),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _myRank != null ? '$_myRank°' : '–',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Il tuo miglior tempo',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      Text(
                        mine.durationFormatted,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${mine.averageSpeedKmh.toStringAsFixed(1)} km/h',
                        style: TextStyle(fontSize: 12, color: context.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLeaderboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Classifica',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        if (_leaderboard.isEmpty)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Nessun tentativo registrato ancora.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13, fontStyle: FontStyle.italic),
            ),
          )
        else
          Card(
            elevation: 1,
            child: Column(
              children: _leaderboard
                  .asMap()
                  .entries
                  .map((e) => _buildLeaderboardRow(e.key + 1, e.value))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildLeaderboardRow(int rank, SegmentEffort effort) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isMe = effort.userId == currentUid;
    final isChampion = rank == 1;

    Color? rankBg;
    if (isChampion) {
      rankBg = Colors.amber;
    } else if (rank == 2) {
      rankBg = Colors.grey;
    } else if (rank == 3) {
      rankBg = const Color(0xFFCD7F32);
    }

    return Container(
      color: isMe ? AppColors.primary.withValues(alpha: 0.08) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rankBg ?? Colors.grey.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: isChampion
                ? const Icon(Icons.emoji_events, size: 16, color: Colors.white)
                : Text(
                    '$rank',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: rankBg != null ? Colors.white : Colors.black87,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            backgroundImage: (effort.avatarUrl != null && effort.avatarUrl!.isNotEmpty)
                ? NetworkImage(effort.avatarUrl!)
                : null,
            child: (effort.avatarUrl == null || effort.avatarUrl!.isEmpty)
                ? Text(
                    effort.username.isNotEmpty ? effort.username[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  effort.username + (isMe ? ' (tu)' : ''),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${effort.averageSpeedKmh.toStringAsFixed(1)} km/h',
                  style: TextStyle(fontSize: 11, color: context.textMuted),
                ),
              ],
            ),
          ),
          Text(
            effort.durationFormatted,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
