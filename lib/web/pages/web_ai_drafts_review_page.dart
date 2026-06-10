import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';

/// Coda di revisione delle bozze descrizione generate dall'AI
/// (scripts/business_ai_drafts.cjs — Fase B arricchimento schede).
///
/// Ogni bozza è in `businesses/{id}.aiDraft` (status 'pending'). Il
/// revisore può modificare il testo, poi:
/// - **Approva** → description = testo (modificato), descriptionSource =
///   'ai_reviewed', merge di telefono/email estratti (solo se mancanti),
///   aiDraft rimossa.
/// - **Scarta** → aiDraft marcata 'rejected' (lo script non la rigenera).
class WebAiDraftsReviewPage extends StatelessWidget {
  const WebAiDraftsReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('businesses')
        .where('aiDraft.status', isEqualTo: 'pending')
        .limit(100);

    return Scaffold(
      appBar: AppBar(title: const Text('Bozze AI da rivedere')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('Nessuna bozza in attesa. Tutto revisionato!',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: docs.length,
                itemBuilder: (context, i) => _DraftCard(
                  key: ValueKey(docs[i].id),
                  doc: docs[i],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DraftCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _DraftCard({super.key, required this.doc});

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  late final TextEditingController _ctrl;
  bool _busy = false;

  Map<String, dynamic> get _data => widget.doc.data();
  Map<String, dynamic> get _draft =>
      Map<String, dynamic>.from(_data['aiDraft'] as Map? ?? {});
  Map<String, dynamic> get _facts =>
      Map<String, dynamic>.from(_draft['facts'] as Map? ?? {});

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _draft['description']?.toString() ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    final text = _ctrl.text.trim();
    if (text.length < 20) return;
    setState(() => _busy = true);
    try {
      final upd = <String, dynamic>{
        'description': text,
        'descriptionSource': 'ai_reviewed',
        'aiDraft': FieldValue.delete(),
      };
      final contacts = Map<String, dynamic>.from(_data['contacts'] as Map? ?? {});
      final tel = _facts['telefono']?.toString();
      final mail = _facts['email']?.toString();
      // Artefatti anti-spam (es. "[email protected]") non devono mai
      // finire nei contatti: valida prima di applicare.
      final emailOk = mail != null &&
          RegExp(r'^[^\s@]+@[^\s@]+\.[a-z]{2,}$', caseSensitive: false)
              .hasMatch(mail) &&
          !mail.toLowerCase().contains('protected');
      final phoneDigits = tel?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
      final phoneOk =
          phoneDigits.length >= 8 && phoneDigits.length <= 15;
      if (phoneOk && contacts['phone'] == null) {
        upd['contacts.phone'] = tel;
      }
      if (emailOk && contacts['email'] == null) {
        upd['contacts.email'] = mail;
      }
      final periodo = _facts['periodoApertura']?.toString();
      if (periodo != null && periodo.isNotEmpty && _data['openingHoursOsm'] == null) {
        upd['openingHoursOsm'] = periodo;
      }
      await widget.doc.reference.update(upd);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await widget.doc.reference.update({
        'aiDraft.status': 'rejected',
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _data['name']?.toString() ?? '';
    final type = _data['type']?.toString() ?? '';
    final loc = Map<String, dynamic>.from(_data['location'] as Map? ?? {});
    final place = [loc['city'], loc['region']]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
    final sourceUrl = _draft['sourceUrl']?.toString();
    final note = _draft['note']?.toString();
    final servizi = (_facts['servizi'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final periodo = _facts['periodoApertura']?.toString();
    final tel = _facts['telefono']?.toString();
    final mail = _facts['email']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('$name${place.isNotEmpty ? ' · $place' : ''}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Chip(
                  label: Text(type, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
                if (sourceUrl != null)
                  IconButton(
                    tooltip: 'Apri il sito',
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: () => launchUrl(Uri.parse(sourceUrl),
                        mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              maxLines: 7,
              minLines: 3,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (periodo != null && periodo.isNotEmpty)
                  _factChip('Apertura: $periodo'),
                if (tel != null && tel.isNotEmpty) _factChip('Tel: $tel'),
                if (mail != null && mail.isNotEmpty) _factChip('Email: $mail'),
                ...servizi.map(_factChip),
              ],
            ),
            if (note != null && note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Nota AI: $note',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.warning)),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _approve,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approva e pubblica'),
                ),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: _busy ? null : _reject,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Scarta'),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.danger),
                ),
                const Spacer(),
                if (_busy)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _factChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );
}
