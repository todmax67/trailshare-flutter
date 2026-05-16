import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/business_repository.dart';
import 'business_recommended_tracks_picker_page.dart';
import 'recommended_track_navigator.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Pagina di gestione dei percorsi consigliati per uno Spazio Pro.
/// L'owner può:
/// - aggiungerne di nuovi (apre il picker)
/// - rimuoverli
/// - modificarne la nota
/// - riordinarli (drag & drop) per controllare l'ordine sul profilo pubblico.
class BusinessRecommendedTracksManagerPage extends StatefulWidget {
  final Business business;
  const BusinessRecommendedTracksManagerPage({
    super.key,
    required this.business,
  });

  @override
  State<BusinessRecommendedTracksManagerPage> createState() =>
      _BusinessRecommendedTracksManagerPageState();
}

class _BusinessRecommendedTracksManagerPageState
    extends State<BusinessRecommendedTracksManagerPage> {
  final _repo = BusinessRepository();
  bool _isPlatformAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadPlatformAdminFlag();
  }

  Future<void> _loadPlatformAdminFlag() async {
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    if (mounted) setState(() => _isPlatformAdmin = isAdmin);
  }

  @override
  Widget build(BuildContext context) {
    // isOwner include il platform admin TrailShare per il flow
    // 'team gestisce per conto del cliente non tech-savvy'.
    final isOwner = widget.business.isOwnerOrAdmin(
      FirebaseAuth.instance.currentUser?.uid,
      isPlatformAdmin: _isPlatformAdmin,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Percorsi consigliati'),
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Aggiungi',
              onPressed: () => _openPicker(),
            ),
        ],
      ),
      body: StreamBuilder<List<RecommendedTrack>>(
        stream: _repo.watchRecommendedTracks(widget.business.id!),
        builder: (context, snap) {
          final tracks = snap.data ?? [];
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (tracks.isEmpty) return _buildEmpty(isOwner);
          return _buildList(tracks, isOwner);
        },
      ),
    );
  }

  Widget _buildEmpty(bool isOwner) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_outlined,
                size: 64, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              isOwner
                  ? 'Non hai ancora consigliato percorsi'
                  : 'Nessun percorso consigliato',
              textAlign: TextAlign.center,
            ),
            if (isOwner) ...[
              const SizedBox(height: 8),
              const Text(
                'Cura una selezione per i tuoi clienti: percorsi tuoi o della community.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _openPicker,
                icon: const Icon(Icons.add),
                label: const Text('Aggiungi primo percorso'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<RecommendedTrack> tracks, bool isOwner) {
    if (!isOwner) {
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _RecommendedCard(track: tracks[i]),
      );
    }
    // Owner: riordino drag&drop
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tracks.length,
      onReorder: (oldIdx, newIdx) async {
        if (newIdx > oldIdx) newIdx--;
        final list = List<RecommendedTrack>.from(tracks);
        final item = list.removeAt(oldIdx);
        list.insert(newIdx, item);
        await _repo.reorderRecommendedTracks(
          widget.business.id!,
          list.map((r) => r.trackId).toList(),
        );
      },
      itemBuilder: (_, i) {
        final t = tracks[i];
        return Padding(
          key: ValueKey(t.trackId),
          padding: const EdgeInsets.only(bottom: 8),
          child: _RecommendedCard(
            track: t,
            isOwner: true,
            onEditNote: () => _editNote(t),
            onRemove: () => _confirmRemove(t),
          ),
        );
      },
    );
  }

  Future<void> _openPicker() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessRecommendedTracksPickerPage(
          business: widget.business,
        ),
      ),
    );
  }

  Future<void> _editNote(RecommendedTrack track) async {
    final ctrl = TextEditingController(text: track.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nota'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          maxLength: 200,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Es. "Adatto a famiglie"',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = ctrl.text.trim();
    await _repo.updateRecommendedTrackNote(
      widget.business.id!,
      track.trackId,
      n.isEmpty ? null : n,
    );
  }

  Future<void> _confirmRemove(RecommendedTrack track) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovi percorso?'),
        content: Text(
            '"${track.trackName}" non sarà più nella lista consigliati.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.removeRecommendedTrack(widget.business.id!, track.trackId);
  }
}

class _RecommendedCard extends StatelessWidget {
  final RecommendedTrack track;
  final bool isOwner;
  final VoidCallback? onEditNote;
  final VoidCallback? onRemove;

  const _RecommendedCard({
    required this.track,
    this.isOwner = false,
    this.onEditNote,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openRecommendedTrackDetail(context, track),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 80,
                  child: track.trackPhotoUrl != null
                      ? CachedNetworkImage(
                          imageUrl: track.trackPhotoUrl!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          alignment: Alignment.center,
                          child: const Icon(Icons.route,
                              size: 32, color: AppColors.primary),
                        ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.trackName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${track.distanceKmFormatted} · ${track.elevationFormatted}'
                          '${track.sourceType == RecommendedTrackSource.communityTrack && track.trackOwnerUsername != null ? " · @${track.trackOwnerUsername}" : ""}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isOwner)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'note') onEditNote?.call();
                      if (v == 'remove') onRemove?.call();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'note',
                        child: Row(
                          children: [
                            Icon(Icons.note_alt_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Modifica nota'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                size: 18, color: AppColors.danger),
                            SizedBox(width: 8),
                            Text('Rimuovi',
                                style: TextStyle(color: AppColors.danger)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (track.note != null && track.note!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                border: Border(
                  top: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.format_quote,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      track.note!,
                      style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
        ),
      ),
    );
  }
}
