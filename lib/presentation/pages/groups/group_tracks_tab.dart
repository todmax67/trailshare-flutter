import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../track_detail/track_detail_page.dart';
import '../discover/community_track_detail_page.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Tab "Percorsi" del gruppo. Mostra le tracce condivise dai membri
/// admin del gruppo (vedi `Track.groupIds`).
///
/// I clienti del noleggio ebike / hotel scorrono questi percorsi e ne
/// scelgono uno per pianificare la giornata. Tap su una traccia apre
/// il dettaglio in modalità "community" (sola lettura) se non è loro,
/// oppure il dettaglio normale se l'hanno creata loro.
///
/// L'admin del gruppo vede in alto un suggerimento per condividere
/// nuove tracce dalla sezione "Le mie tracce".
class GroupTracksTab extends StatefulWidget {
  final String groupId;
  final bool isAdmin;

  const GroupTracksTab({
    super.key,
    required this.groupId,
    required this.isAdmin,
  });

  @override
  State<GroupTracksTab> createState() => _GroupTracksTabState();
}

class _GroupTracksTabState extends State<GroupTracksTab> {
  final _tracksRepo = TracksRepository();
  bool _loading = true;
  List<Track> _tracks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tracks = await _tracksRepo.getGroupTracks(widget.groupId);
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _loading = false;
    });
  }

  void _openTrack(Track track) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isMine = track.userId != null && track.userId == myUid;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isMine
            ? TrackDetailPage(track: track)
            : CommunityTrackDetailPage(track: track),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: _tracks.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [_buildEmpty(context)],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: _tracks.length + (widget.isAdmin ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                if (widget.isAdmin && i == 0) {
                  return _buildAdminHint(context);
                }
                final idx = widget.isAdmin ? i - 1 : i;
                return _TrackCard(
                  track: _tracks[idx],
                  onTap: () => _openTrack(_tracks[idx]),
                );
              },
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      child: Column(
        children: [
          Icon(
            Icons.route_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Nessun percorso ancora',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.isAdmin
                ? 'Vai in "Le mie tracce", apri una traccia, e usa il '
                    'menu ⋮ → "Condividi nel gruppo" per aggiungerla qui.'
                : 'Quando l\'admin condividerà i percorsi consigliati, '
                    'compariranno in questa lista.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAdminHint(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 20,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aggiungi percorsi consigliati dal menu ⋮ di una traccia in '
              '"Le mie tracce".',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;

  const _TrackCard({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distanceKm = track.stats.distance / 1000;
    final elev = track.stats.elevationGain.round();

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  track.activityType.icon,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            track.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (track.isPlanned)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'PIANIFICATO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.straighten,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${distanceKm.toStringAsFixed(1)} km',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.terrain,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${elev}m D+',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
