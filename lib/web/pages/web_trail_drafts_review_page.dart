import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Coda di revisione delle bozze descrizione AI dei SENTIERI
/// (scripts/trail_ai_descriptions.cjs). A differenza delle schede business,
/// le bozze nascono SOLO dai nostri fatti strutturati (lunghezza, D+, ref
/// CAI, rifugi vicini) — niente fonti esterne.
class WebTrailDraftsReviewPage extends StatelessWidget {
  const WebTrailDraftsReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('public_trails')
        .where('aiDraft.status', isEqualTo: 'pending')
        .limit(100);

    return Scaffold(
      appBar: AppBar(title: const Text('Bozze AI — Sentieri')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('Nessuna bozza sentiero in attesa.',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: docs.length,
                itemBuilder: (context, i) => _TrailDraftCard(
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

class _TrailDraftCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _TrailDraftCard({super.key, required this.doc});

  @override
  State<_TrailDraftCard> createState() => _TrailDraftCardState();
}

class _TrailDraftCardState extends State<_TrailDraftCard> {
  late final TextEditingController _ctrl;
  bool _busy = false;

  Map<String, dynamic> get _data => widget.doc.data();
  Map<String, dynamic> get _draft =>
      Map<String, dynamic>.from(_data['aiDraft'] as Map? ?? {});

  @override
  void initState() {
    super.initState();
    _ctrl =
        TextEditingController(text: _draft['description']?.toString() ?? '');
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
      await widget.doc.reference.update({
        'description': text,
        'descriptionSource': 'ai_facts_reviewed',
        'aiDraft': FieldValue.delete(),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await widget.doc.reference.update({'aiDraft.status': 'rejected'});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _data['name']?.toString() ?? '';
    final ref = _data['ref']?.toString();
    final region = _data['region']?.toString();
    final km = (_data['distance'] as num?) != null
        ? ((_data['distance'] as num) / 1000).toStringAsFixed(1)
        : null;
    final dPlus = (_data['elevationGain'] as num?)?.round();
    final difficulty = _data['difficulty']?.toString();
    final rifugi = (_draft['nearbyRifugi'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (ref != null && ref.isNotEmpty) _chip('Sent. $ref'),
                if (km != null) _chip('$km km'),
                if (dPlus != null) _chip('D+ $dPlus m'),
                if (difficulty != null && difficulty.isNotEmpty)
                  _chip(difficulty),
                if (region != null && region.isNotEmpty) _chip(region),
                ...rifugi.map((r) => _chip('🏔 $r')),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              maxLines: 6,
              minLines: 3,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
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

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );
}
