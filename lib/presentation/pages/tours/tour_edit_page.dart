import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../data/models/tour.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tours_repository.dart';
import '../../../data/repositories/tracks_repository.dart';

/// Crea o modifica un tour.
///
/// Flusso:
/// 1. Carica le tracce dell'utente.
/// 2. L'utente inserisce titolo/descrizione, seleziona le tracce, le ordina.
/// 3. Toggle pubblico/privato.
/// 4. Save → ToursRepository.
class TourEditPage extends StatefulWidget {
  final Tour? existing;

  const TourEditPage({super.key, this.existing});

  @override
  State<TourEditPage> createState() => _TourEditPageState();
}

class _TourEditPageState extends State<TourEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final TracksRepository _tracksRepo = TracksRepository();
  final ToursRepository _toursRepo = ToursRepository();

  List<Track> _availableTracks = [];
  List<String> _selectedIds = [];
  Set<String> _publicTrackIds = const {};
  bool _isPublic = false;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _titleCtrl.text = widget.existing!.title;
      _descCtrl.text = widget.existing!.description ?? '';
      _selectedIds = List.of(widget.existing!.trackIds);
      _isPublic = widget.existing!.isPublic;
    }
    _loadTracks();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTracks() async {
    final tracks = await _tracksRepo.getMyTracks();
    final ids = tracks.map((t) => t.id).whereType<String>().toList();
    final publicIds = await _toursRepo.getPublicTrackIds(ids);
    if (!mounted) return;
    setState(() {
      _availableTracks = tracks;
      _publicTrackIds = publicIds;
      _loading = false;
    });
  }

  void _toggleTrack(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _reorderSelected(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _selectedIds.removeAt(oldIndex);
      _selectedIds.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tourSelectAtLeastOne), backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await _toursRepo.createTour(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          trackIds: _selectedIds,
          isPublic: _isPublic,
        );
      } else {
        await _toursRepo.updateTour(
          widget.existing!.id,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          trackIds: _selectedIds,
          isPublic: _isPublic,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tourSaved), backgroundColor: AppColors.success),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.existing == null ? context.l10n.newTour : context.l10n.editTour;

    final selectedTracks = [
      for (final id in _selectedIds)
        _availableTracks.firstWhere(
          (t) => t.id == id,
          orElse: () => Track(
            id: id,
            name: '?',
            points: const [],
            createdAt: DateTime.now(),
          ),
        ),
    ];
    final unselectedTracks =
        _availableTracks.where((t) => t.id != null && !_selectedIds.contains(t.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.tourTitle,
                      hintText: context.l10n.tourTitleHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? context.l10n.tourTitleRequired : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.tourDescription,
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: _isPublic,
                    onChanged: (v) => setState(() => _isPublic = v),
                    title: Text(context.l10n.tourPublic),
                    subtitle: Text(context.l10n.tourPublicHint),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: 32),
                  Text(
                    context.l10n.tourSelectTracks,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.tourSelectTracksHint,
                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (selectedTracks.isNotEmpty) ...[
                    Text(
                      context.l10n.tourReorderHint,
                      style: TextStyle(color: context.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 8),
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorder: _reorderSelected,
                      children: [
                        for (var i = 0; i < selectedTracks.length; i++)
                          _SelectedTrackTile(
                            key: ValueKey('sel-${selectedTracks[i].id}'),
                            index: i + 1,
                            track: selectedTracks[i],
                            isPublic: _publicTrackIds.contains(selectedTracks[i].id),
                            onRemove: () => _toggleTrack(selectedTracks[i].id!),
                          ),
                      ],
                    ),
                    const Divider(height: 32),
                  ],
                  if (unselectedTracks.isNotEmpty)
                    ...unselectedTracks.map(
                      (t) => _AvailableTrackTile(
                        track: t,
                        isPublic: _publicTrackIds.contains(t.id),
                        onAdd: () => _toggleTrack(t.id!),
                      ),
                    ),
                  if (_availableTracks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          context.l10n.noTracksSaved,
                          style: TextStyle(color: context.textSecondary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

Widget _publicChip(BuildContext context) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.info.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.public, size: 12, color: AppColors.info),
        const SizedBox(width: 3),
        Text(
          context.l10n.publicLabel,
          style: TextStyle(fontSize: 10, color: AppColors.info, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}

class _SelectedTrackTile extends StatelessWidget {
  final int index;
  final Track track;
  final bool isPublic;
  final VoidCallback onRemove;

  const _SelectedTrackTile({
    super.key,
    required this.index,
    required this.track,
    required this.isPublic,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          child: Text('$index'),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (isPublic) ...[
              const SizedBox(width: 6),
              _publicChip(context),
            ],
          ],
        ),
        subtitle: Text(
          '${track.stats.distanceKm.toStringAsFixed(1)} km · +${track.stats.elevationGain.toStringAsFixed(0)} m',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          color: AppColors.danger,
          onPressed: onRemove,
        ),
      ),
    );
  }
}

class _AvailableTrackTile extends StatelessWidget {
  final Track track;
  final bool isPublic;
  final VoidCallback onAdd;

  const _AvailableTrackTile({
    required this.track,
    required this.isPublic,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.hiking),
        title: Row(
          children: [
            Expanded(
              child: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (isPublic) ...[
              const SizedBox(width: 6),
              _publicChip(context),
            ],
          ],
        ),
        subtitle: Text(
          '${track.stats.distanceKm.toStringAsFixed(1)} km · +${track.stats.elevationGain.toStringAsFixed(0)} m',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          color: AppColors.primary,
          onPressed: onAdd,
        ),
      ),
    );
  }
}
