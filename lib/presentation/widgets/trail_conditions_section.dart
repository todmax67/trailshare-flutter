import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/trail_condition.dart';
import '../../data/repositories/trail_conditions_repository.dart';
import 'report_condition_sheet.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../core/extensions/l10n_extension.dart';

/// Sezione "Condizioni sentiero" della pagina dettaglio sentiero.
///
/// Mostra un badge colorato dell'ultima segnalazione recente + CTA per
/// nuova segnalazione + storico delle ultime 5 segnalazioni degli ultimi
/// 14 giorni. Solo segnalazioni recenti sono rilevanti per l'escursionista.
class TrailConditionsSection extends StatefulWidget {
  final String trailId;

  const TrailConditionsSection({super.key, required this.trailId});

  @override
  State<TrailConditionsSection> createState() => _TrailConditionsSectionState();
}

class _TrailConditionsSectionState extends State<TrailConditionsSection> {
  final TrailConditionsRepository _repo = TrailConditionsRepository();
  List<TrailCondition> _reports = [];
  bool _loading = true;
  bool _error = false;

  static const _recencyThreshold = Duration(days: 14);
  static const _historyLimit = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final reports = await _repo.getReportsForTrail(widget.trailId, limit: 20);
      if (!mounted) return;

      // Filtra client-side per recency
      final now = DateTime.now();
      final recent = reports
          .where((r) => now.difference(r.reportedAt) <= _recencyThreshold)
          .toList();

      setState(() {
        _reports = recent;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _openReportSheet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.loginRequiredToReport),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    final result = await showReportConditionSheet(context, trailId: widget.trailId);
    if (result != null) {
      await _load();
    }
  }

  Future<void> _deleteReport(TrailCondition r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteReportQuestion),
        content: Text(context.l10n.reportWillBeRemoved),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await _repo.deleteReport(widget.trailId, r.id);
    if (!mounted) return;
    if (ok) {
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante l\'eliminazione'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_error)
              _buildError()
            else ...[
              if (_reports.isNotEmpty) ...[
                _buildLatestBadge(_reports.first),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openReportSheet,
                  icon: Icon(Icons.add_alert_outlined),
                  label: Text(context.l10n.reportCondition),
                ),
              ),
              if (_reports.isEmpty) ...[
                const SizedBox(height: 12),
                _buildEmpty(),
              ] else if (_reports.length > 1) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Altre segnalazioni recenti',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textMuted),
                ),
                const SizedBox(height: 8),
                ..._reports.skip(1).take(_historyLimit - 1).map((r) => _buildReportTile(r)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.warning_amber_outlined, size: 20, color: AppColors.warning),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Condizioni sentiero',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (!_loading && !_error && _reports.isNotEmpty)
          Text(
            '${_reports.length}',
            style: TextStyle(fontSize: 13, color: context.textMuted),
          ),
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: context.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Impossibile caricare le segnalazioni',
              style: TextStyle(color: context.textMuted, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _load,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        'Nessuna segnalazione recente. Sii il primo a segnalare.',
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildLatestBadge(TrailCondition r) {
    final s = r.status;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: s.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_relativeDate(r.reportedAt)} · ${r.username}',
                  style: TextStyle(fontSize: 12, color: context.textMuted),
                ),
                if (r.note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    r.note,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTile(TrailCondition r) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isMine = currentUid != null && currentUid == r.userId;
    final s = r.status;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: s.color.withValues(alpha: 0.18),
            backgroundImage: (r.avatarUrl != null && r.avatarUrl!.isNotEmpty)
                ? NetworkImage(r.avatarUrl!)
                : null,
            child: (r.avatarUrl == null || r.avatarUrl!.isEmpty)
                ? Text(
                    r.username.isNotEmpty ? r.username[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: s.color,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(s.emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${s.label} · ${r.username}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _relativeDate(r.reportedAt),
                      style: TextStyle(fontSize: 10, color: context.textMuted),
                    ),
                  ],
                ),
                if (r.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      r.note,
                      style: TextStyle(fontSize: 12, color: context.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          if (isMine)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: () => _deleteReport(r),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Elimina',
              color: context.textMuted,
            ),
        ],
      ),
    );
  }

  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} h fa';
    if (diff.inDays < 7) return '${diff.inDays} g fa';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} sett fa';
    return '${(diff.inDays / 30).floor()} mesi fa';
  }
}
