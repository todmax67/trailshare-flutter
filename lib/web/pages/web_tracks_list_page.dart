import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/web_layout.dart';
import '../../data/models/track.dart';
import '../../data/repositories/tracks_repository.dart';
import 'web_track_detail_page.dart';

/// Sezione "Le mie tracce" della dashboard web. Lista paginata
/// con tap su tile per aprire il detail web.
///
/// Volutamente leggera (no edit, no upload, no foreground service):
/// la registrazione GPS resta solo su mobile, il web è
/// "consultativo" — vedi tracce, scarica GPX, condividi link.
class WebTracksListPage extends StatefulWidget {
  const WebTracksListPage({super.key});

  @override
  State<WebTracksListPage> createState() => _WebTracksListPageState();
}

class _WebTracksListPageState extends State<WebTracksListPage> {
  final _repo = TracksRepository();
  final _scrollController = ScrollController();

  List<Track> _tracks = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;

  @override
  void initState() {
    super.initState();
    _loadFirst();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    setState(() => _loading = true);
    final result = await _repo.getMyTracksPaginated(limit: 20);
    if (!mounted) return;
    setState(() {
      _tracks = result.tracks;
      _lastDoc = result.lastDocument;
      _hasMore = result.hasMore;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_lastDoc == null) return;
    setState(() => _loadingMore = true);
    final result = await _repo.getMyTracksPaginated(
      limit: 20,
      lastDocument: _lastDoc,
    );
    if (!mounted) return;
    setState(() {
      _tracks = [..._tracks, ...result.tracks];
      _lastDoc = result.lastDocument;
      _hasMore = result.hasMore;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: WebContentWrapper(
        maxWidth: 880,
        child: RefreshIndicator(
          onRefresh: _loadFirst,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_tracks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        if (i >= _tracks.length) {
                          return _loadingMore
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : const SizedBox(height: 16);
                        }
                        return _TrackTile(track: _tracks[i]);
                      },
                      childCount: _tracks.length + (_hasMore ? 1 : 0),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final user = FirebaseAuth.instance.currentUser;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Le mie tracce',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.displayName != null
                ? 'Tracce di ${user!.displayName}'
                : 'Tutte le tracce registrate dal tuo account TrailShare',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined,
                size: 56, color: AppColors.textMuted.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            const Text(
              'Nessuna traccia ancora',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Apri TrailShare sul telefono e registra la tua prima traccia. '
              'Una volta registrata la troverai qui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final Track track;
  const _TrackTile({required this.track});

  String _formatDate(DateTime d) {
    const months = [
      'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
      'lug', 'ago', 'set', 'ott', 'nov', 'dic',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final stats = track.stats;
    final km = (stats.distance / 1000).toStringAsFixed(1);
    final ele = stats.elevationGain.toStringAsFixed(0);
    final duration = _formatDuration(stats.duration);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WebTrackDetailPage(track: track),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.route,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.activityType.displayName} · '
                      '${_formatDate(track.recordedAt ?? track.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _Metric(label: 'km', value: km),
              const SizedBox(width: 16),
              _Metric(label: 'D+', value: '${ele}m'),
              const SizedBox(width: 16),
              _Metric(label: 'tempo', value: duration),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
