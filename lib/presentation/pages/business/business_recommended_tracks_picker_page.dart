import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/business.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/business_repository.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Picker per scegliere quali tracce consigliare sul profilo Spazio Pro.
/// Due tab: "Le mie tracce" (private dell'owner) e "Community recenti".
/// Tap su una traccia → dialog opzionale per nota → salva sul business.
class BusinessRecommendedTracksPickerPage extends StatefulWidget {
  final Business business;
  const BusinessRecommendedTracksPickerPage({
    super.key,
    required this.business,
  });

  @override
  State<BusinessRecommendedTracksPickerPage> createState() =>
      _BusinessRecommendedTracksPickerPageState();
}

class _BusinessRecommendedTracksPickerPageState
    extends State<BusinessRecommendedTracksPickerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _myRepo = TracksRepository();
  final _communityRepo = CommunityTracksRepository();
  final _businessRepo = BusinessRepository();

  bool _loading = true;
  List<Track> _myTracks = [];
  List<CommunityTrackPreview> _communityTracks = [];
  Set<String> _alreadyRecommended = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Community: filtra near business (50 km), preview lightweight
      // (no GPS points → memory friendly).
      // bypassCache: evita decoding della cache locale Firestore satura
      // (i doc tracks contengono points embedded, OOM su 256MB heap).
      final results = await Future.wait([
        _myRepo.getMyTracksLightweight(limit: 50, bypassCache: true),
        _communityRepo.getRecentTracksPreview(
          limit: 30,
          nearLat: widget.business.location.lat,
          nearLng: widget.business.location.lng,
          radiusKm: 50,
          bypassCache: true,
        ),
        _businessRepo.getRecommendedTracks(widget.business.id!),
      ]);
      if (!mounted) return;
      setState(() {
        _myTracks = results[0] as List<Track>;
        _communityTracks = results[1] as List<CommunityTrackPreview>;
        _alreadyRecommended =
            (results[2] as List<RecommendedTrack>).map((r) => r.trackId).toSet();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento: $e')),
      );
    }
  }

  // ─── ADD ────────────────────────────────────────────────────────────

  Future<void> _addPrivate(Track track) async {
    if (track.id == null) return;
    final note = await _askNote();
    if (note == _AskNoteResult.cancelled) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? widget.business.ownerId;
    final order = _alreadyRecommended.length;
    final rec = RecommendedTrack(
      trackId: track.id!,
      sourceType: RecommendedTrackSource.privateTrack,
      trackOwnerId: track.userId ?? uid,
      addedBy: uid,
      addedAt: DateTime.now(),
      order: order,
      note: note.value,
      trackName: track.name,
      trackDistance: track.stats.distance,
      trackElevationGain: track.stats.elevationGain,
      trackActivityType: track.activityType.name,
      trackDurationSec: track.stats.duration.inSeconds,
      trackPhotoUrl: track.photos.isNotEmpty ? track.photos.first.url : null,
      // 7.D3 — denormalizziamo il punto di partenza per il marker sulla
      // landing pubblica senza dover fetchare la traccia originale.
      trackStartLat:
          track.points.isNotEmpty ? track.points.first.latitude : null,
      trackStartLng:
          track.points.isNotEmpty ? track.points.first.longitude : null,
    );
    await _businessRepo.addRecommendedTrack(widget.business.id!, rec);
    if (!mounted) return;
    setState(() => _alreadyRecommended.add(track.id!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${track.name}" aggiunto')),
    );
  }

  Future<void> _addCommunity(CommunityTrackPreview track) async {
    final note = await _askNote();
    if (note == _AskNoteResult.cancelled) return;
    final uid =
        FirebaseAuth.instance.currentUser?.uid ?? widget.business.ownerId;
    final order = _alreadyRecommended.length;
    final rec = RecommendedTrack(
      trackId: track.id,
      sourceType: RecommendedTrackSource.communityTrack,
      trackOwnerId: track.ownerId,
      trackOwnerUsername: track.ownerUsername,
      addedBy: uid,
      addedAt: DateTime.now(),
      order: order,
      note: note.value,
      trackName: track.name,
      trackDistance: track.distance,
      trackElevationGain: track.elevationGain,
      trackActivityType: track.activityType,
      trackDurationSec: track.duration,
      trackPhotoUrl: track.photoUrls.isNotEmpty ? track.photoUrls.first : null,
      trackStartLat: track.startLat,
      trackStartLng: track.startLng,
    );
    await _businessRepo.addRecommendedTrack(widget.business.id!, rec);
    if (!mounted) return;
    setState(() => _alreadyRecommended.add(track.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${track.name}" aggiunto')),
    );
  }

  Future<_AskNoteResult> _askNote() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nota (opzionale)'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText:
                'Es. "Adatto a famiglie", "Possibile neve sopra 2200m fino a maggio"',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Senza nota'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );
    if (ok != true) return _AskNoteResult.cancelled;
    final n = ctrl.text.trim();
    return _AskNoteResult.confirmed(n.isEmpty ? null : n);
  }

  // ─── BUILD ───────────────────────────────────────────────────────────

  List<Track> get _filteredMyTracks {
    if (_searchQuery.isEmpty) return _myTracks;
    final q = _searchQuery.toLowerCase();
    return _myTracks.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  List<CommunityTrackPreview> get _filteredCommunityTracks {
    if (_searchQuery.isEmpty) return _communityTracks;
    final q = _searchQuery.toLowerCase();
    return _communityTracks
        .where((t) =>
            t.name.toLowerCase().contains(q) ||
            (t.description?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aggiungi percorso'),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.person), text: 'Le mie tracce'),
            Tab(icon: Icon(Icons.public), text: 'Community vicine'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cerca per nome',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tab,
                    children: [
                      _buildMyTracksList(),
                      _buildCommunityTracksList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyTracksList() {
    final tracks = _filteredMyTracks;
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searchQuery.isEmpty
                ? 'Non hai tracce registrate. Vai alla scheda Community per scegliere percorsi pubblici.'
                : 'Nessun risultato per "$_searchQuery"',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final t = tracks[i];
        final added = _alreadyRecommended.contains(t.id);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(t.activityType.icon),
          ),
          title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${(t.stats.distance / 1000).toStringAsFixed(1)} km · '
            '+${t.stats.elevationGain.toStringAsFixed(0)} m',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: added
              ? const Icon(Icons.check_circle, color: AppColors.success)
              : const Icon(Icons.add_circle_outline,
                  color: AppColors.primary),
          onTap: added ? null : () => _addPrivate(t),
        );
      },
    );
  }

  Widget _buildCommunityTracksList() {
    final tracks = _filteredCommunityTracks;
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searchQuery.isEmpty
                ? 'Nessuna traccia community entro 50 km da questo Spazio Pro'
                : 'Nessun risultato per "$_searchQuery"',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final t = tracks[i];
        final added = _alreadyRecommended.contains(t.id);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(t.activityIcon),
          ),
          title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${t.distanceKm.toStringAsFixed(1)} km · '
            '+${t.elevationGain.toStringAsFixed(0)} m · '
            '@${t.ownerUsername}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: added
              ? const Icon(Icons.check_circle, color: AppColors.success)
              : const Icon(Icons.add_circle_outline,
                  color: AppColors.primary),
          onTap: added ? null : () => _addCommunity(t),
        );
      },
    );
  }
}

class _AskNoteResult {
  final bool _cancelled;
  final String? value;
  const _AskNoteResult._(this._cancelled, this.value);

  factory _AskNoteResult.confirmed(String? note) =>
      _AskNoteResult._(false, note);
  static const _AskNoteResult cancelled = _AskNoteResult._(true, null);

  @override
  bool operator ==(Object other) =>
      other is _AskNoteResult && other._cancelled == _cancelled;

  @override
  int get hashCode => _cancelled.hashCode;
}
