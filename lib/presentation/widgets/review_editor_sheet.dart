import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/trail_review.dart';
import 'star_rating.dart';
import '../../core/extensions/l10n_extension.dart';

/// Bottom sheet per scrivere o modificare una recensione.
///
/// Restituisce true se è stata salvata/eliminata una modifica, altrimenti null.
///
/// ```dart
/// final changed = await showModalBottomSheet<bool>(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => ReviewEditorSheet(
///     existing: userReview,
///     onSave: (rating, text) => repo.saveReview(...),
///     onDelete: () => repo.deleteReview(...),
///   ),
/// );
/// ```
class ReviewEditorSheet extends StatefulWidget {
  final TrailReview? existing;
  final Future<ReviewResult> Function(int rating, String text) onSave;
  final Future<ReviewResult> Function()? onDelete;

  const ReviewEditorSheet({
    super.key,
    this.existing,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<ReviewEditorSheet> createState() => _ReviewEditorSheetState();
}

class _ReviewEditorSheetState extends State<ReviewEditorSheet> {
  late int _rating;
  late TextEditingController _textController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.existing?.rating ?? 0;
    _textController = TextEditingController(text: widget.existing?.text ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_rating == 0) return;
    setState(() => _isSaving = true);

    final result = await widget.onSave(_rating, _textController.text);
    if (!mounted) return;

    if (result.success) {
      Navigator.pop(context, true);
    } else {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Errore sconosciuto'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare recensione?'),
        content: Text('Questa azione non può essere annullata.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    final result = await widget.onDelete!();
    if (!mounted) return;

    if (result.success) {
      Navigator.pop(context, true);
    } else {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Errore sconosciuto'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isEditing ? 'Modifica recensione' : 'Scrivi una recensione',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Stelle
              const Text(
                'Il tuo giudizio',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Center(
                child: StarRating(
                  value: _rating.toDouble(),
                  readOnly: false,
                  size: 40,
                  onChanged: _isSaving ? null : (v) => setState(() => _rating = v),
                ),
              ),
              const SizedBox(height: 16),

              // Testo
              const Text(
                'Commento (opzionale)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _textController,
                enabled: !_isSaving,
                maxLength: 500,
                maxLines: 4,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Come è stato il sentiero? Cosa consiglieresti?',
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 8),

              // Azioni
              Row(
                children: [
                  if (isEditing && widget.onDelete != null) ...[
                    TextButton.icon(
                      onPressed: _isSaving ? null : _delete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Elimina'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    ),
                    const Spacer(),
                  ] else
                    const Spacer(),
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_rating == 0 || _isSaving) ? null : _save,
                    child: _isSaving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(context.l10n.save),
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
