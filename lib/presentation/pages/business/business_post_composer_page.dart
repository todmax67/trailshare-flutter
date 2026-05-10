import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/business_repository.dart';

class BusinessPostComposerPage extends StatefulWidget {
  final String businessId;
  const BusinessPostComposerPage({super.key, required this.businessId});

  @override
  State<BusinessPostComposerPage> createState() =>
      _BusinessPostComposerPageState();
}

class _BusinessPostComposerPageState extends State<BusinessPostComposerPage> {
  final _ctrl = TextEditingController();
  final _repo = BusinessRepository();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _repo.createPost(businessId: widget.businessId, text: text);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuovo aggiornamento'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Pubblica'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cosa vuoi comunicare ai tuoi follower?',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                maxLength: 5000,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText:
                      'Es. "Sentiero al rifugio innevato sopra 2200m, raccomandiamo ramponi..."',
                ),
              ),
            ),
            // TODO: aggiunta foto in iterazione successiva
          ],
        ),
      ),
    );
  }
}
