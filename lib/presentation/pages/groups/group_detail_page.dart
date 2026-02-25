import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../data/repositories/groups_repository.dart';
import 'group_chat_tab.dart';
import 'group_events_tab.dart';
import 'group_challenges_tab.dart';
import 'group_members_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GroupDetailPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupDetailPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> with TickerProviderStateMixin {
  final _repo = GroupsRepository();
  late TabController _tabController;
  Group? _group;
  bool _isAdmin = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingRequests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadGroup();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGroup() async {
    setState(() => _isLoading = true);

    final group = await _repo.getGroup(widget.groupId);
    final isAdmin = await _repo.isAdmin(widget.groupId);

    if (mounted) {
      setState(() {
        _group = group;
        _isAdmin = isAdmin;
        _isLoading = false;
      });
    }

    // Carica richieste pendenti (solo admin)
    if (isAdmin) {
      final requests = await _repo.getPendingRequests(widget.groupId);
      if (mounted) {
        setState(() => _pendingRequests = requests);
      }
    }

    // Assicura che il gruppo abbia un codice invito
      if (group != null && group.inviteCode == null) {
        await _repo.ensureInviteCode(widget.groupId);
        // Ricarica per avere il codice
        final updated = await _repo.getGroup(widget.groupId);
        if (mounted && updated != null) {
          setState(() => _group = updated);
        }
      }

    // Carica richieste pendenti (solo admin)
    if (isAdmin) {
      final requests = await _repo.getPendingRequests(widget.groupId);
      if (mounted) {
        setState(() => _pendingRequests = requests);
      }
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.leaveGroupTitle),
        content: Text(context.l10n.leaveGroupConfirm(_group?.name ?? widget.groupName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.exitAction),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _repo.leaveGroup(widget.groupId);
      if (mounted && success) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteGroup),
        content: Text(
          context.l10n.deleteGroupConfirm(_group?.name ?? widget.groupName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.deleteAction),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _repo.deleteGroup(widget.groupId);
      if (mounted && success) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_group?.name ?? widget.groupName),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          // Membri
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: context.l10n.membersLabel,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupMembersPage(
                    groupId: widget.groupId,
                    groupName: _group?.name ?? widget.groupName,
                    isAdmin: _isAdmin,
                  ),
                ),
              );
            },
          ),
          // Menu
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'leave':
                  _leaveGroup();
                  break;
                case 'delete':
                  _deleteGroup();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    const Icon(Icons.exit_to_app, color: AppColors.danger, size: 20),
                    const SizedBox(width: 8),
                    Text(context.l10n.leaveGroupTitle),
                  ],
                ),
              ),
              if (_isAdmin)
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, color: AppColors.danger, size: 20),
                      const SizedBox(width: 8),
                      Text(context.l10n.deleteGroupMenu, style: const TextStyle(color: AppColors.danger)),
                    ],
                  ),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(icon: const Icon(Icons.chat_bubble_outline), text: context.l10n.chatTab),
            Tab(icon: const Icon(Icons.event), text: context.l10n.eventsTab),
            Tab(icon: const Icon(Icons.emoji_events), text: context.l10n.challengesTab),
            Tab(icon: const Icon(Icons.info_outline), text: context.l10n.infoTab),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab Chat
                GroupChatTab(groupId: widget.groupId),

                // Tab Eventi
                GroupEventsTab(
                  groupId: widget.groupId,
                  isAdmin: _isAdmin,
                ),

                // Tab Sfide
                GroupChallengesTab(
                  groupId: widget.groupId,
                  isAdmin: _isAdmin,
                ),

                // Tab Info
                _buildInfoTab(),
              ],
            ),
    );
  }

  Widget _buildInviteCodeSection() {
    final code = _group?.inviteCode ?? '';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                context.l10n.inviteCodeTitle,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  color: AppColors.textMuted,
                  tooltip: context.l10n.regenerateCode,
                  onPressed: _regenerateInviteCode,
                ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Codice grande e copiabile
          GestureDetector(
            onTap: () => _copyInviteCode(code),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: AppColors.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.copy, size: 20, color: AppColors.primary.withOpacity(0.6)),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Bottoni azioni
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyInviteCode(code),
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(context.l10n.copy),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _shareInviteCode(code),
                  icon: const Icon(Icons.share, size: 18),
                  label: Text(context.l10n.share),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          Text(
            context.l10n.shareInviteCodeDesc,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilitySelector(Group group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.groupVisibility,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        _buildVisibilityTile(
          group: group,
          value: 'public',
          icon: Icons.public,
          title: context.l10n.publicLabel,
          subtitle: context.l10n.publicVisibilityDesc,
          color: AppColors.success,
        ),
        const SizedBox(height: 8),
        _buildVisibilityTile(
          group: group,
          value: 'private',
          icon: Icons.lock_open,
          title: context.l10n.privateLabel,
          subtitle: context.l10n.privateVisibilityDesc,
          color: AppColors.primary,
        ),
        const SizedBox(height: 8),
        _buildVisibilityTile(
          group: group,
          value: 'secret',
          icon: Icons.lock,
          title: context.l10n.secretLabel,
          subtitle: context.l10n.secretVisibilityDesc,
          color: Colors.grey,
        ),
      ],
    );
  }

  Widget _buildPendingRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person_add, size: 20, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              context.l10n.accessRequests,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_pendingRequests.length}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._pendingRequests.map((req) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage: req['avatarUrl'] != null && req['avatarUrl'].toString().isNotEmpty
                  ? NetworkImage(req['avatarUrl'])
                  : null,
              child: req['avatarUrl'] == null || req['avatarUrl'].toString().isEmpty
                  ? Text(
                      (req['username'] ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                    )
                  : null,
            ),
            title: Text(req['username'] ?? context.l10n.userLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              req['requestedAt'] != null
                  ? context.l10n.requestedOnDate(_formatDate((req['requestedAt'] as Timestamp).toDate()))
                  : context.l10n.pendingStatus,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: AppColors.success),
                  onPressed: () async {
                    final success = await _repo.approveJoinRequest(widget.groupId, req['uid']);
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.userApproved(req['username'] ?? '')),
                          backgroundColor: AppColors.success,
                        ),
                      );
                      _loadGroup();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  onPressed: () async {
                    final success = await _repo.rejectJoinRequest(widget.groupId, req['uid']);
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.requestRejected),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      _loadGroup();
                    }
                  },
                ),
              ],
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildVisibilityTile({
    required Group group,
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final isSelected = group.visibility == value;

    return InkWell(
      onTap: isSelected ? null : () => _changeVisibility(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? color.withOpacity(0.05) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? color : null,
                  )),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 22),
          ],
        ),
      ),
    );
  }

  Future<void> _changeVisibility(String newVisibility) async {
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update({
        'visibility': newVisibility,
        'isPublic': newVisibility == 'public',
      });

      await _loadGroup();

      if (mounted) {
        final labels = {
          'public': context.l10n.publicLabel,
          'private': context.l10n.privateLabel,
          'secret': context.l10n.secretLabel,
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.groupNowIs(labels[newVisibility] ?? '')),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _copyInviteCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.codeCopied),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareInviteCode(String code) {
    final groupName = _group?.name ?? widget.groupName;
    Share.share(
      context.l10n.inviteShareText(groupName, code),
      subject: context.l10n.inviteShareSubject,
    );
  }

  Future<void> _regenerateInviteCode() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.regenerateCodeTitle),
        content: Text(
          context.l10n.regenerateCodeDesc,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(context.l10n.regenerateAction),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final newCode = await _repo.regenerateInviteCode(widget.groupId);
      if (newCode != null && mounted) {
        _loadGroup(); // Ricarica per aggiornare il codice
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.newCodeSnack(newCode)),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Widget _buildInfoTab() {
    final group = _group;
    if (group == null) return const SizedBox();

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header gruppo
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primary.withOpacity(0.6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: Text(
                      group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  group.name,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      group.isPublic ? Icons.public : group.isPrivate ? Icons.lock_open : Icons.lock,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      group.isPublic ? context.l10n.publicLabel : group.isPrivate ? context.l10n.privateLabel : context.l10n.secretLabel,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.people, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      context.l10n.memberCountPlural(group.memberCount),
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.l10n.descriptionLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  color: AppColors.primary,
                  tooltip: context.l10n.editAction,
                  onPressed: () => _showEditGroupDialog(group),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (group.description != null && group.description!.isNotEmpty)
                ? group.description!
                : context.l10n.noDescriptionHint,
            style: TextStyle(
              color: (group.description != null && group.description!.isNotEmpty)
                  ? AppColors.textSecondary
                  : AppColors.textMuted,
              fontSize: 14,
              height: 1.5,
              fontStyle: (group.description != null && group.description!.isNotEmpty)
                  ? FontStyle.normal
                  : FontStyle.italic,
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ⭐ Codice Invito
          if (_group?.inviteCode != null) ...[
            const SizedBox(height: 16),
            _buildInviteCodeSection(),
            const SizedBox(height: 16),
            const Divider(),
          ],

          // ⭐ Richieste di accesso (solo admin)
          if (_isAdmin && _pendingRequests.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildPendingRequestsSection(),
            const SizedBox(height: 16),
            const Divider(),
          ],

          // ⭐ Visibilità (solo admin)
          if (_isAdmin) ...[
            const SizedBox(height: 16),
            _buildVisibilitySelector(group),
            const SizedBox(height: 16),
            const Divider(),
          ],

          // Info dettagli
          _buildInfoRow(Icons.calendar_today, context.l10n.createdOnLabel, _formatDate(group.createdAt)),
          const SizedBox(height: 12),
          _buildInfoRow(
            Icons.admin_panel_settings,
            context.l10n.yourRole,
            _isAdmin ? context.l10n.administratorRole : context.l10n.memberRole,
          ),
          if (currentUserId == group.createdBy) ...[
            const SizedBox(height: 12),
            _buildInfoRow(Icons.star, context.l10n.founderLabel, context.l10n.youCreatedThisGroup),
          ],
        ],
      ),
    );
  }

  Future<void> _showEditGroupDialog(Group group) async {
    final nameController = TextEditingController(text: group.name);
    final descController = TextEditingController(text: group.description ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.editGroup),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: context.l10n.groupNameLabel,
                border: const OutlineInputBorder(),
              ),
              maxLength: 30,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                labelText: context.l10n.descriptionLabel,
                hintText: context.l10n.descriptionHint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 4,
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.length < 3) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.nameMinThreeChars)),
                );
                return;
              }
              final success = await _repo.updateGroup(
                widget.groupId,
                name: newName,
                description: descController.text.trim(),
              );
              if (success && context.mounted) {
                Navigator.pop(context, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );

    if (result == true) {
      _loadGroup();
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      context.l10n.monthLowerGen, context.l10n.monthLowerFeb, context.l10n.monthLowerMar,
      context.l10n.monthLowerApr, context.l10n.monthLowerMag, context.l10n.monthLowerGiu,
      context.l10n.monthLowerLug, context.l10n.monthLowerAgo, context.l10n.monthLowerSet,
      context.l10n.monthLowerOtt, context.l10n.monthLowerNov, context.l10n.monthLowerDic,
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}