import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
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

  String get _targetHint {
    switch (_type) {
      case 'distance': return 'Es. 50 (km)';
      case 'elevation': return 'Es. 2000 (metri)';
      case 'tracks': return 'Es. 10 (tracce)';
      case 'streak': return 'Es. 7 (giorni)';
      default: return '';
    }
  }

  String get _targetSuffix {
    switch (_type) {
      case 'distance': return 'km';
      case 'elevation': return 'm';
      case 'tracks': return 'tracce';
      case 'streak': return 'giorni';
      default: return '';
    }
  }

  Future<void> _createChallenge() async {
    if (!_formKey.currentState!.validate()) return;

    final targetValue = double.tryParse(_targetController.text);
    if (targetValue == null || targetValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un obiettivo valido'), backgroundColor: AppColors.danger),
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
          const SnackBar(content: Text('Sfida creata!'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore nella creazione'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuova Sfida'),
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
              const Text('Titolo sfida *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: 'Es. Chi fa più km questa settimana?',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.emoji_events),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Inserisci un titolo';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Tipo sfida
              const Text('Tipo di sfida *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              _buildTypeSelector(),
              const SizedBox(height: 24),

              // Obiettivo
              const Text('Obiettivo *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: _targetHint,
                  suffixText: _targetSuffix,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.flag),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Inserisci un obiettivo';
                  if (double.tryParse(value) == null) return 'Inserisci un numero valido';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Durata
              const Text('Durata *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  {'days': 3, 'label': '3 giorni'},
                  {'days': 7, 'label': '1 settimana'},
                  {'days': 14, 'label': '2 settimane'},
                  {'days': 30, 'label': '1 mese'},
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
                        'La sfida inizia oggi e dura $_durationDays giorni. '
                        'I progressi vengono calcolati automaticamente dalle tracce registrate.',
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
                      : const Text(
                          'Lancia la Sfida!',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
      {'type': 'distance', 'icon': '🏃', 'label': 'Distanza', 'desc': 'Chi percorre più km'},
      {'type': 'elevation', 'icon': '⛰️', 'label': 'Dislivello', 'desc': 'Chi accumula più metri'},
      {'type': 'tracks', 'icon': '🗺️', 'label': 'Tracce', 'desc': 'Chi registra più uscite'},
      {'type': 'streak', 'icon': '🔥', 'label': 'Costanza', 'desc': 'Più giorni consecutivi'},
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
