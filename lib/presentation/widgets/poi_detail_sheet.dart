import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/trail_poi.dart';
import '../../data/repositories/poi_repository.dart';
import 'poi_editor_sheet.dart';
import '../../core/extensions/theme_colors_extension.dart';

/// Risultato della sheet di dettaglio POI, utilizzato dal chiamante per
/// sapere se deve ricaricare la lista/mappa.
enum PoiDetailResult {
  /// Niente è cambiato (solo lettura)
  none,
  /// POI è stato aggiornato (edit, vote, toggle public)
  updated,
  /// POI è stato eliminato
  deleted,
}

Future<PoiDetailResult?> showPoiDetailSheet(
  BuildContext context, {
  required TrailPoi poi,
}) {
  return showModalBottomSheet<PoiDetailResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PoiDetailSheet(poi: poi),
  );
}

class _PoiDetailSheet extends StatefulWidget {
  final TrailPoi poi;
  const _PoiDetailSheet({required this.poi});

  @override
  State<_PoiDetailSheet> createState() => _PoiDetailSheetState();
}

class _PoiDetailSheetState extends State<_PoiDetailSheet> {
  final _repo = PoiRepository();
  late TrailPoi _poi;
  String? _myVote;
  bool _voting = false;

  @override
  void initState() {
    super.initState();
    _poi = widget.poi;
    _loadMyVote();
  }

  Future<void> _loadMyVote() async {
    final v = await _repo.getUserVote(_poi.id);
    if (mounted) setState(() => _myVote = v);
  }

  bool get _isMine =>
      FirebaseAuth.instance.currentUser?.uid == _poi.createdBy;

  Future<void> _vote(bool isUp) async {
    if (_voting) return;
    setState(() => _voting = true);
    final target = isUp ? 'up' : 'down';
    bool ok;
    if (_myVote == target) {
      // toggle off
      ok = await _repo.removeVote(_poi.id);
      if (ok && mounted) {
        setState(() {
          _myVote = null;
          if (isUp) {
            _poi = _poi.copyWith(upvotes: _poi.upvotes - 1);
          } else {
            _poi = _poi.copyWith(downvotes: _poi.downvotes - 1);
          }
        });
      }
    } else {
      ok = await _repo.vote(_poi.id, isUp);
      if (ok && mounted) {
        setState(() {
          final wasOpposite = _myVote != null && _myVote != target;
          _myVote = target;
          _poi = _poi.copyWith(
            upvotes: isUp
                ? _poi.upvotes + 1
                : (wasOpposite ? _poi.upvotes - 1 : _poi.upvotes),
            downvotes: !isUp
                ? _poi.downvotes + 1
                : (wasOpposite ? _poi.downvotes - 1 : _poi.downvotes),
          );
        });
      }
    }
    if (mounted) setState(() => _voting = false);
  }

  Future<void> _edit() async {
    final updated = await showPoiEditorSheet(
      context,
      latitude: _poi.latitude,
      longitude: _poi.longitude,
      relatedTrailId: _poi.relatedTrailId,
      relatedTrackId: _poi.relatedTrackId,
      initialPoi: _poi,
    );
    if (updated != null && mounted) {
      setState(() => _poi = updated);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare POI?'),
        content: Text('"${_poi.title}" verrà rimosso definitivamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _repo.deletePoi(_poi.id);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, PoiDetailResult.deleted);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore eliminazione POI')),
      );
    }
  }

  Future<void> _togglePublic() async {
    final newValue = !_poi.isPublic;
    final ok = await _repo.setPoiPublic(_poi.id, newValue);
    if (!mounted) return;
    if (ok) {
      setState(() => _poi = _poi.copyWith(isPublic: newValue));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header: icona + titolo + tipo
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _poi.type.pinColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _poi.type.pinColor.withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(_poi.type.emoji,
                          style: const TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _poi.title,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: [
                              Text(
                                _poi.type.displayName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _poi.type.pinColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (!_poi.isPublic) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.lock_outline,
                                    size: 13, color: context.textMuted),
                                Text(' Privato',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: context.textMuted)),
                              ],
                              if (_poi.verifiedByAdmin) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.verified,
                                    size: 13, color: AppColors.info),
                                const Text(' Verificato',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.info)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Menu per autore
                    if (_isMine)
                      PopupMenuButton<String>(
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('Modifica')),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(_poi.isPublic
                                ? 'Rendi privato'
                                : 'Rendi pubblico'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Elimina',
                                style: TextStyle(color: AppColors.danger)),
                          ),
                        ],
                        onSelected: (v) {
                          if (v == 'edit') _edit();
                          if (v == 'toggle') _togglePublic();
                          if (v == 'delete') _delete();
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Foto
                if (_poi.photoUrl != null && _poi.photoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      _poi.photoUrl!,
                      fit: BoxFit.cover,
                      height: 180,
                      width: double.infinity,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          height: 180,
                          alignment: Alignment.center,
                          color: Colors.grey.shade200,
                          child: const CircularProgressIndicator(),
                        );
                      },
                      errorBuilder: (_, _, _) => Container(
                        height: 180,
                        alignment: Alignment.center,
                        color: Colors.grey.shade200,
                        child: Icon(Icons.broken_image,
                            color: context.textMuted),
                      ),
                    ),
                  ),
                if (_poi.photoUrl != null) const SizedBox(height: 12),

                // Descrizione
                if (_poi.description != null &&
                    _poi.description!.isNotEmpty) ...[
                  Text(
                    _poi.description!,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                ],

                // Autore + data
                Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 14,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(
                      _poi.createdByUsername ?? 'Utente',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_poi.createdAt != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.schedule,
                          size: 13,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 3),
                      Text(
                        _formatDate(_poi.createdAt!),
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Sezione voti — visibile a tutti tranne l'autore (non
                // può votare i propri POI)
                if (!_isMine) _buildVoteRow() else _buildOwnerStatsRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoteRow() {
    return Row(
      children: [
        Text(
          'Questo POI è utile?',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        _buildVoteButton(
          isUp: true,
          count: _poi.upvotes,
          selected: _myVote == 'up',
        ),
        const SizedBox(width: 10),
        _buildVoteButton(
          isUp: false,
          count: _poi.downvotes,
          selected: _myVote == 'down',
        ),
      ],
    );
  }

  Widget _buildOwnerStatsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ownerStat(
          Icons.thumb_up_outlined,
          AppColors.success,
          'Positivi',
          _poi.upvotes,
        ),
        _ownerStat(
          Icons.thumb_down_outlined,
          AppColors.danger,
          'Negativi',
          _poi.downvotes,
        ),
      ],
    );
  }

  Widget _ownerStat(IconData icon, Color color, String label, int n) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text('$n',
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(
                fontSize: 10, color: context.textMuted)),
      ],
    );
  }

  Widget _buildVoteButton({
    required bool isUp,
    required int count,
    required bool selected,
  }) {
    final color = isUp ? AppColors.success : AppColors.danger;
    return InkWell(
      onTap: _voting ? null : () => _vote(isUp),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isUp ? Icons.thumb_up : Icons.thumb_down,
              size: 16,
              color: selected ? Colors.white : color,
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0) return 'oggi';
    if (diff.inDays == 1) return 'ieri';
    if (diff.inDays < 30) return '${diff.inDays} giorni fa';
    if (diff.inDays < 365) {
      return '${(diff.inDays / 30).floor()} mesi fa';
    }
    return '${d.day}/${d.month}/${d.year}';
  }
}
