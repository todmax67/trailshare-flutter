import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/trail_condition.dart';
import '../../data/repositories/trail_conditions_repository.dart';
import '../../core/extensions/theme_colors_extension.dart';

/// Bottom sheet per segnalare le condizioni del sentiero.
/// Ritorna il [TrailCondition] creato in caso di successo.
Future<TrailCondition?> showReportConditionSheet(
  BuildContext context, {
  required String trailId,
}) {
  return showModalBottomSheet<TrailCondition>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReportConditionSheet(trailId: trailId),
  );
}

class _ReportConditionSheet extends StatefulWidget {
  final String trailId;

  const _ReportConditionSheet({required this.trailId});

  @override
  State<_ReportConditionSheet> createState() => _ReportConditionSheetState();
}

class _ReportConditionSheetState extends State<_ReportConditionSheet> {
  TrailConditionStatus? _selected;
  final _noteController = TextEditingController();
  final _repo = TrailConditionsRepository();
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    setState(() => _saving = true);

    final report = await _repo.createReport(
      trailId: widget.trailId,
      status: _selected!,
      note: _noteController.text,
    );

    if (!mounted) return;

    if (report != null) {
      Navigator.pop(context, report);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante la segnalazione'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const Text(
                'Segnala condizione',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Aiuta la community a conoscere lo stato attuale del sentiero',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),

              // Grid stati
              _buildStatusGrid(),

              const SizedBox(height: 16),

              // Nota
              TextField(
                controller: _noteController,
                enabled: !_saving,
                maxLength: 200,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nota (opzionale)',
                  hintText: 'Aggiungi dettagli: dove, quando, severità...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),

              const SizedBox(height: 8),

              // Azioni
              Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Annulla'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: (_selected == null || _saving) ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: const Text('Segnala'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: TrailConditionStatus.values.map((s) {
        final isSelected = _selected == s;
        return InkWell(
          onTap: _saving ? null : () => setState(() => _selected = s),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: (MediaQuery.of(context).size.width - 60) / 2,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? s.color.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? s.color : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Text(s.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.label,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? s.color : context.textPrimary,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
