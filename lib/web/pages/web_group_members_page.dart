// Web-only file (compilato solo per lib/main_web.dart). Usiamo
// dart:html per il download CSV via Blob+anchor; va bene qui.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import '../utils/csv_downloader.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/group_brand.dart';
import '../../data/repositories/follow_repository.dart';
import '../../data/repositories/groups_repository.dart';

/// Versione **web-native** della gestione membri di un gruppo Business.
///
/// Differenze rispetto alla versione mobile riusata in precedenza:
/// - Tabella desktop con colonne ordinabili (membro / ruolo / data)
/// - Search bar e filter chips (Tutti / Admin / Member)
/// - Azioni inline (promote, demote, remove) — niente dialog mobile
/// - Export CSV scaricabile (download via Blob + anchor)
/// - Invite picker dei follower in dialog desktop
///
/// Usa GroupsRepository.{promoteToAdmin,demoteToMember,removeMember}
/// senza override server-side: stesse regole del mobile (solo founder
/// può gestire ruoli, cap admin tier-aware lato repo).
class WebGroupMembersPage extends StatefulWidget {
  final Group group;
  const WebGroupMembersPage({super.key, required this.group});

  @override
  State<WebGroupMembersPage> createState() => _WebGroupMembersPageState();
}

enum _RoleFilter { all, admin, member }

extension _RoleFilterX on _RoleFilter {
  String get label {
    switch (this) {
      case _RoleFilter.all:
        return 'Tutti';
      case _RoleFilter.admin:
        return 'Admin';
      case _RoleFilter.member:
        return 'Member';
    }
  }

  bool matches(GroupMember m) {
    switch (this) {
      case _RoleFilter.all:
        return true;
      case _RoleFilter.admin:
        return m.isAdmin;
      case _RoleFilter.member:
        return !m.isAdmin;
    }
  }
}

enum _SortColumn { name, role, joined }

class _WebGroupMembersPageState extends State<WebGroupMembersPage> {
  final _repo = GroupsRepository();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<GroupMember> _all = [];

  String _query = '';
  _RoleFilter _filter = _RoleFilter.all;
  _SortColumn _sort = _SortColumn.joined;
  bool _ascending = false;

  /// Cache: l'utente loggato è il founder (solo lui può
  /// promuovere/degradare admin). Il founder è il `createdBy`
  /// del gruppo; lo capiamo confrontando l'uid corrente.
  bool get _amFounder =>
      FirebaseAuth.instance.currentUser?.uid == widget.group.createdBy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final members = await _repo.getMembers(widget.group.id);
    if (!mounted) return;
    setState(() {
      _all = members;
      _loading = false;
    });
  }

  List<GroupMember> get _filtered {
    final q = _query.trim().toLowerCase();
    Iterable<GroupMember> out = _all.where(_filter.matches);
    if (q.isNotEmpty) {
      out = out.where((m) => m.username.toLowerCase().contains(q));
    }
    final list = out.toList();
    list.sort((a, b) {
      int c;
      switch (_sort) {
        case _SortColumn.name:
          c = a.username.toLowerCase().compareTo(b.username.toLowerCase());
          break;
        case _SortColumn.role:
          // admin first se descending, altrimenti member first
          c = (a.isAdmin ? 0 : 1).compareTo(b.isAdmin ? 0 : 1);
          break;
        case _SortColumn.joined:
          c = a.joinedAt.compareTo(b.joinedAt);
          break;
      }
      return _ascending ? c : -c;
    });
    return list;
  }

  void _toggleSort(_SortColumn col) {
    setState(() {
      if (_sort == col) {
        _ascending = !_ascending;
      } else {
        _sort = col;
        _ascending = col == _SortColumn.name;
      }
    });
  }

  // ────────────────────────────────────────────────────────────
  // ROLE MANAGEMENT
  // ────────────────────────────────────────────────────────────

  Future<void> _promote(GroupMember m) async {
    final res = await _repo.promoteToAdmin(widget.group.id, m.userId);
    if (!mounted) return;
    if (res['success'] == true) {
      _showSnack('${m.username} promosso ad admin', success: true);
      _load();
    } else {
      _showSnack(res['error']?.toString() ?? 'Errore', success: false);
    }
  }

  Future<void> _demote(GroupMember m) async {
    final res = await _repo.demoteToMember(widget.group.id, m.userId);
    if (!mounted) return;
    if (res['success'] == true) {
      _showSnack('${m.username} riportato a member', success: true);
      _load();
    } else {
      _showSnack(res['error']?.toString() ?? 'Errore', success: false);
    }
  }

  Future<void> _remove(GroupMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovi membro'),
        content: Text(
          'Vuoi rimuovere ${m.username} dal gruppo?\n'
          'L\'utente non vedrà più contenuti del gruppo, ma potrà '
          'rientrare con il codice invito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.12),
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = await _repo.removeMember(widget.group.id, m.userId);
    if (!mounted) return;
    if (success) {
      _showSnack('${m.username} rimosso', success: true);
      _load();
    } else {
      _showSnack('Rimozione fallita', success: false);
    }
  }

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            success ? const Color(0xFF2E7D5B) : Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // CSV EXPORT
  // ────────────────────────────────────────────────────────────

  void _exportCsv() {
    final list = _filtered;
    final buf = StringBuffer();
    buf.writeln('Username,Ruolo,Iscritto il (UTC)');
    for (final m in list) {
      final user = _csvEscape(m.username);
      final role = m.isAdmin ? 'admin' : 'member';
      final joined = m.joinedAt.toUtc().toIso8601String();
      buf.writeln('$user,$role,$joined');
    }
    _downloadFile(
      content: buf.toString(),
      filename: 'membri-${widget.group.name.replaceAll(' ', '_')}.csv',
      mime: 'text/csv;charset=utf-8',
    );
    _showSnack('Esportati ${list.length} membri', success: true);
  }

  String _csvEscape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  void _downloadFile({
    required String content,
    required String filename,
    required String mime,
  }) {
    // Helper con conditional import — funziona su web, no-op su
    // mobile (il chiamante è UI esclusiva della shell web).
    downloadCsv(filename, content, mime: mime);
  }

  // ────────────────────────────────────────────────────────────
  // INVITE
  // ────────────────────────────────────────────────────────────

  Future<void> _showInviteDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final followRepo = FollowRepository();
    final following = await followRepo.getFollowingWithProfiles(user.uid);
    final memberIds = _all.map((m) => m.userId).toSet();
    final invitable =
        following.where((u) => !memberIds.contains(u.id)).toList();

    if (!mounted) return;

    if (invitable.isEmpty) {
      _showSnack(
        'Tutti i tuoi follower sono già nel gruppo. '
        'Condividi il codice invito dalla Panoramica.',
        success: false,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Invita un follower',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: invitable.length,
                  itemBuilder: (_, i) {
                    final p = invitable[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.15),
                        backgroundImage: p.avatarUrl != null
                            ? NetworkImage(p.avatarUrl!)
                            : null,
                        child: p.avatarUrl == null
                            ? Text(
                                p.username.isNotEmpty
                                    ? p.username[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              )
                            : null,
                      ),
                      title: Text(p.username),
                      subtitle: Text('Liv. ${p.level}'),
                      trailing: FilledButton(
                        onPressed: () async {
                          final ok = await _repo.addMember(
                              widget.group.id, p.id);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (ok) {
                            _showSnack(
                                '${p.username} aggiunto al gruppo',
                                success: true);
                            _load();
                          } else {
                            _showSnack('Aggiunta fallita',
                                success: false);
                          }
                        },
                        child: const Text('Invita'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = groupAccentColor(widget.group);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('${widget.group.name} · Membri')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildToolbar(accent),
                  const SizedBox(height: 12),
                  _buildCounter(),
                  const SizedBox(height: 8),
                  Expanded(child: _buildTable(accent)),
                ],
              ),
            ),
    );
  }

  Widget _buildToolbar(Color accent) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Cerca per username…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        for (final f in _RoleFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f.label),
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
              selectedColor: accent.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight:
                    _filter == f ? FontWeight.w700 : FontWeight.w500,
                color: _filter == f ? accent : AppColors.textPrimary,
              ),
              side: BorderSide(
                color: _filter == f
                    ? accent.withValues(alpha: 0.4)
                    : AppColors.border,
              ),
              showCheckmark: false,
            ),
          ),
        const SizedBox(width: 4),
        OutlinedButton.icon(
          onPressed: _filtered.isEmpty ? null : _exportCsv,
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('CSV'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _showInviteDialog,
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('Invita'),
          style: FilledButton.styleFrom(backgroundColor: accent),
        ),
      ],
    );
  }

  Widget _buildCounter() {
    final total = _all.length;
    final admins = _all.where((m) => m.isAdmin).length;
    final shown = _filtered.length;
    return Row(
      children: [
        Text(
          shown == total
              ? '$total membri · $admins admin'
              : '$shown di $total membri · $admins admin',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTable(Color accent) {
    if (_filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline,
                  size: 48,
                  color: AppColors.textMuted.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              const Text(
                'Nessun membro corrisponde ai filtri',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderRow(),
            const Divider(height: 1),
            for (int i = 0; i < _filtered.length; i++) ...[
              _buildMemberRow(_filtered[i], accent),
              if (i < _filtered.length - 1)
                const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: _SortHeader(
              label: 'Membro',
              active: _sort == _SortColumn.name,
              ascending: _ascending,
              onTap: () => _toggleSort(_SortColumn.name),
            ),
          ),
          Expanded(
            flex: 2,
            child: _SortHeader(
              label: 'Ruolo',
              active: _sort == _SortColumn.role,
              ascending: _ascending,
              onTap: () => _toggleSort(_SortColumn.role),
            ),
          ),
          Expanded(
            flex: 3,
            child: _SortHeader(
              label: 'Iscritto il',
              active: _sort == _SortColumn.joined,
              ascending: _ascending,
              onTap: () => _toggleSort(_SortColumn.joined),
            ),
          ),
          const SizedBox(
            width: 140,
            child: Text(
              'Azioni',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberRow(GroupMember m, Color accent) {
    final isFounder = m.userId == widget.group.createdBy;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: accent.withValues(alpha: 0.15),
                  backgroundImage: m.avatarUrl != null
                      ? NetworkImage(m.avatarUrl!)
                      : null,
                  child: m.avatarUrl == null
                      ? Text(
                          m.username.isNotEmpty
                              ? m.username[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: accent,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    m.username,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isFounder) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Founder del gruppo',
                    child: Icon(
                      Icons.workspace_premium,
                      size: 16,
                      color: accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _RoleBadge(isAdmin: m.isAdmin, accent: accent),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatDate(m.joinedAt),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: 140,
            child: _buildActions(m, isFounder, accent),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(GroupMember m, bool isFounder, Color accent) {
    // Founder non può essere demoteato/rimosso da nessuno (regola repo).
    if (isFounder) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        if (_amFounder)
          if (m.isAdmin)
            Tooltip(
              message: 'Rimuovi privilegi admin',
              child: IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: () => _demote(m),
              ),
            )
          else
            Tooltip(
              message: 'Promuovi ad admin',
              child: IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                color: accent,
                onPressed: () => _promote(m),
              ),
            ),
        const Spacer(),
        Tooltip(
          message: 'Rimuovi dal gruppo',
          child: IconButton(
            icon: const Icon(Icons.person_remove_outlined, size: 18),
            color: Colors.red.shade700,
            onPressed: () => _remove(m),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
      'lug', 'ago', 'set', 'ott', 'nov', 'dic',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _SortHeader extends StatelessWidget {
  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;
  const _SortHeader({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.textPrimary : AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            if (active)
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: AppColors.textPrimary,
              ),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final bool isAdmin;
  final Color accent;
  const _RoleBadge({required this.isAdmin, required this.accent});

  @override
  Widget build(BuildContext context) {
    final color = isAdmin ? accent : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAdmin ? Icons.shield : Icons.person,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isAdmin ? 'Admin' : 'Member',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
