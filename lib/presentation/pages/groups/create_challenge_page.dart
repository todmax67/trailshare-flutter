import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../data/repositories/groups_repository.dart';

class CreateChallengePage extends StatefulWidget {
  final String groupId;

  const CreateChallengePage({super.key, required this.groupId});

  @override
  State<CreateChallengePage> createState() => _CreateChallengePageState();
}

class _CreateChallengePageState extends State<CreateChallengePage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = GroupsRepository();
  final _titleController = TextEditingController();
  final _targetController = TextEditingController();

  String _type = 'distance';
  int _durationDays = 7;
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  String _targetHint(BuildContext context) {
    switch (_type) {
      case 'distance': return context.l10n.distanceHint;
      case 'elevation': return context.l10n.elevationHint;
      case 'tracks': return context.l10n.tracksHint;
      case 'streak': return context.l10n.streakHint;
      default: return '';
    }
  }

  String _targetSuffix(BuildContext context) {
    switch (_type) {
      case 'distance': return 'km';
      case 'elevation': return 'm';
      case 'tracks': return context.l10n.suffixTracks;
      case 'streak': return context.l10n.suffixDays;
      default: return '';
    }
  }

  Future<void> _createChallenge() async {
    if (!_formKey.currentState!.validate()) return;

    final targetValue = double.tryParse(_targetController.text);
    if (targetValue == null || targetValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.enterValidGoal), backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => _isCreating = true);

    // Converti km in metri per distance
    final target = _type == 'distance' ? targetValue * 1000 : targetValue;

    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day); // Mezzanotte oggi
    final endDate = startDate.add(Duration(days: _durationDays));

    final challengeId = await _repo.createChallenge(
      widget.groupId,
      title: _titleController.text.trim(),
      type: _type,
      target: target,
      startDate: startDate,
      endDate: endDate,
    );

    if (mounted) {
      setState(() => _isCreating = false);

      if (challengeId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.challengeCreatedShort), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.challengeCreationError), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.newChallenge),
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
              // Icona
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: Text('🏆', style: TextStyle(fontSize: 40)),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Titolo
              Text(context.l10n.challengeTitleRequired, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: context.l10n.challengeTitleHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.emoji_events),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return context.l10n.enterTitle;
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Tipo sfida
              Text(context.l10n.challengeTypeRequired, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              _buildTypeSelector(),
              const SizedBox(height: 24),

              // Obiettivo
              Text(context.l10n.goalRequired, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: _targetHint(context),
                  suffixText: _targetSuffix(context),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.flag),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return context.l10n.enterGoal;
                  if (double.tryParse(value) == null) return context.l10n.enterValidNumber;
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Durata
              Text(context.l10n.durationRequired, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  {'days': 3, 'label': context.l10n.threeDays},
                  {'days': 7, 'label': context.l10n.oneWeek},
                  {'days': 14, 'label': context.l10n.twoWeeks},
                  {'days': 30, 'label': context.l10n.oneMonth},
                ].map((option) {
                  final days = option['days'] as int;
                  final label = option['label'] as String;
                  final isSelected = _durationDays == days;
                  return ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) setState(() => _durationDays = days);
                    },
                    selectedColor: AppColors.primary.withOpacity(0.2),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.challengeInfoText(_durationDays),
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Bottone crea
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCreating ? null : _createChallenge,
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
                          context.l10n.launchChallenge,
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

  Widget _buildTypeSelector() {
    final types = [
      {'type': 'distance', 'icon': '🏃', 'label': context.l10n.distanceLabel, 'desc': context.l10n.distanceDesc},
      {'type': 'elevation', 'icon': '⛰️', 'label': context.l10n.elevationLabel, 'desc': context.l10n.elevationDesc},
      {'type': 'tracks', 'icon': '🗺️', 'label': context.l10n.tracksLabel, 'desc': context.l10n.tracksDesc},
      {'type': 'streak', 'icon': '🔥', 'label': context.l10n.consistencyLabel, 'desc': context.l10n.consistencyDesc},
    ];

    return Column(
      children: types.map((t) {
        final isSelected = _type == t['type'];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
            color: isSelected ? AppColors.primary.withOpacity(0.05) : null,
          ),
          child: ListTile(
            onTap: () => setState(() => _type = t['type'] as String),
            leading: Text(t['icon'] as String, style: const TextStyle(fontSize: 28)),
            title: Text(
              t['label'] as String,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.primary : null,
              ),
            ),
            subtitle: Text(
              t['desc'] as String,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: AppColors.primary)
                : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }).toList(),
    );
  }
}
