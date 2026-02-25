import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../data/repositories/groups_repository.dart';

class CreateEventPage extends StatefulWidget {
  final String groupId;

  const CreateEventPage({super.key, required this.groupId});

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = GroupsRepository();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _meetingPointController = TextEditingController();
  final _distanceController = TextEditingController();
  final _elevationController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  String? _difficulty;
  int? _maxParticipants;
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _meetingPointController.dispose();
    _distanceController.dispose();
    _elevationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  DateTime get _eventDateTime => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

  /// Mappa valore Firestore → label localizzata
  Map<String, String> _difficultyLabels(BuildContext context) => {
    'Facile': context.l10n.easy,
    'Medio': context.l10n.mediumDifficulty,
    'Difficile': context.l10n.hard,
    'Esperto': context.l10n.expertDifficulty,
  };

  Future<void> _createEvent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    final distance = _distanceController.text.isNotEmpty
        ? double.tryParse(_distanceController.text)
        : null;
    final elevation = _elevationController.text.isNotEmpty
        ? double.tryParse(_elevationController.text)
        : null;

    final eventId = await _repo.createEvent(
      widget.groupId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      date: _eventDateTime,
      meetingPointName: _meetingPointController.text.trim().isEmpty
          ? null
          : _meetingPointController.text.trim(),
      maxParticipants: _maxParticipants,
      difficulty: _difficulty,
      estimatedDistance: distance != null ? distance * 1000 : null, // km → m
      estimatedElevation: elevation,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    if (mounted) {
      setState(() => _isCreating = false);

      if (eventId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.eventCreatedSnack),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.creationError),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = [
      context.l10n.monthLowerGen, context.l10n.monthLowerFeb, context.l10n.monthLowerMar,
      context.l10n.monthLowerApr, context.l10n.monthLowerMag, context.l10n.monthLowerGiu,
      context.l10n.monthLowerLug, context.l10n.monthLowerAgo, context.l10n.monthLowerSet,
      context.l10n.monthLowerOtt, context.l10n.monthLowerNov, context.l10n.monthLowerDic,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.newEvent),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titolo
              Text(context.l10n.titleRequired, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: context.l10n.eventTitleHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.event),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return context.l10n.enterTitle;
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Data e Ora
              Text(context.l10n.dateAndTime, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _selectDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[400]!),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(
                              '${_selectedDate.day} ${months[_selectedDate.month - 1]} ${_selectedDate.year}',
                              style: const TextStyle(fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: _selectTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[400]!),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Descrizione
              Text(context.l10n.descriptionLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: context.l10n.outingDetails,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // Punto di ritrovo
              Text(context.l10n.meetingPoint, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _meetingPointController,
                decoration: InputDecoration(
                  hintText: context.l10n.meetingPointHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 20),

              // Dettagli percorso
              Text(context.l10n.routeDetails, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _distanceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: context.l10n.distanceHintShort,
                        suffixText: 'km',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.straighten, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _elevationController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: context.l10n.elevationHintShort,
                        suffixText: 'm',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.terrain, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Difficoltà
              Text(context.l10n.difficultyLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _difficultyLabels(context).entries.map((entry) {
                  final isSelected = _difficulty == entry.key;
                  return ChoiceChip(
                    label: Text(entry.value),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _difficulty = selected ? entry.key : null);
                    },
                    selectedColor: AppColors.primary.withOpacity(0.2),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Max partecipanti
              Text(context.l10n.maxParticipantsLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [null, 5, 10, 15, 20].map((n) {
                  final isSelected = _maxParticipants == n;
                  return ChoiceChip(
                    label: Text(n == null ? context.l10n.noLimit : '$n'),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _maxParticipants = selected ? n : null);
                    },
                    selectedColor: AppColors.primary.withOpacity(0.2),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Note
              Text(context.l10n.notesLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: context.l10n.notesHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.note),
                ),
              ),
              const SizedBox(height: 32),

              // Bottone crea
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCreating ? null : _createEvent,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          context.l10n.createEvent,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
