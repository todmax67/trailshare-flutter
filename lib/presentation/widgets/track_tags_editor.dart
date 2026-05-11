import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../data/repositories/tracks_repository.dart';
import 'app_snackbar.dart';

/// 5.5 — Editor inline di tag personalizzati per una traccia.
///
/// Mostra i tag attuali come Chip con X per rimuovere; al tap "+ Aggiungi"
/// apre un bottom sheet con input + suggerimenti dai tag già usati
/// dall'utente (autocomplete).
class TrackTagsEditor extends StatefulWidget {
  final String trackId;
  final List<String> initialTags;
  final ValueChanged<List<String>>? onChanged;

  const TrackTagsEditor({
    super.key,
    required this.trackId,
    required this.initialTags,
    this.onChanged,
  });

  @override
  State<TrackTagsEditor> createState() => _TrackTagsEditorState();
}

class _TrackTagsEditorState extends State<TrackTagsEditor> {
  final _repo = TracksRepository();
  late List<String> _tags;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.initialTags);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await _repo.updateTrackTags(widget.trackId, _tags);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      AppSnackBar.error(context, 'Errore nel salvataggio tag');
      return;
    }
    widget.onChanged?.call(_tags);
  }

  Future<void> _addTag() async {
    // Suggerimenti dai tag già usati dall'utente.
    final allTags = await _repo.getAllUserTags();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _AddTagSheet(
        existingTags: _tags,
        suggestions: allTags,
      ),
    );
    if (picked == null || picked.trim().isEmpty) return;
    final normalized = picked.trim().toLowerCase();
    if (_tags.contains(normalized)) return; // dedup
    setState(() => _tags = [..._tags, normalized]);
    await _save();
  }

  Future<void> _removeTag(String tag) async {
    setState(() => _tags = _tags.where((t) => t != tag).toList());
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.label_outline, size: 18, color: context.textMuted),
            const SizedBox(width: 6),
            Text(
              'Tag',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (_saving)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in _tags)
              Chip(
                label: Text(tag),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onDeleted: _saving ? null : () => _removeTag(tag),
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.08),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Aggiungi'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onPressed: _saving ? null : _addTag,
              labelStyle: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _AddTagSheet extends StatefulWidget {
  final List<String> existingTags;
  final List<String> suggestions;
  const _AddTagSheet({
    required this.existingTags,
    required this.suggestions,
  });

  @override
  State<_AddTagSheet> createState() => _AddTagSheetState();
}

class _AddTagSheetState extends State<_AddTagSheet> {
  final _controller = TextEditingController();
  String _input = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lowerInput = _input.trim().toLowerCase();
    final available = widget.suggestions
        .where((t) => !widget.existingTags.contains(t))
        .where((t) => lowerInput.isEmpty || t.contains(lowerInput))
        .take(20)
        .toList();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aggiungi tag',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 30,
                textInputAction: TextInputAction.done,
                onChanged: (v) => setState(() => _input = v),
                onSubmitted: (v) =>
                    Navigator.pop(context, v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'es. vacanze 2026, scarpe nuove…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (available.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Tag già usati:',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in available)
                      ActionChip(
                        label: Text(t),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(context, t),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _input.trim().isEmpty
                        ? null
                        : () => Navigator.pop(
                              context,
                              _input.trim().toLowerCase(),
                            ),
                    child: const Text('Aggiungi'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
