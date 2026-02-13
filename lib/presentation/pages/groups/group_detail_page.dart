import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/groups_repository.dart';
import 'group_chat_tab.dart';
import 'group_events_tab.dart';
import 'group_challenges_tab.dart';
import 'group_members_page.dart';

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
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Esci dal gruppo'),
        content: Text('Vuoi uscire da "${_group?.name ?? widget.groupName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Esci'),
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
        title: const Text('Elimina gruppo'),
        content: Text(
          'Vuoi eliminare "${_group?.name ?? widget.groupName}"?\n\nQuesta azione è irreversibile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Elimina'),
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
            tooltip: 'Membri',
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
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app, color: AppColors.danger, size: 20),
                    SizedBox(width: 8),
                    Text('Esci dal gruppo'),
                  ],
                ),
              ),
              if (_isAdmin)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: AppColors.danger, size: 20),
                      SizedBox(width: 8),
                      Text('Elimina gruppo', style: TextStyle(color: AppColors.danger)),
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
          tabs: const [
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
            Tab(icon: Icon(Icons.event), text: 'Eventi'),
            Tab(icon: Icon(Icons.emoji_events), text: 'Sfide'),
            Tab(icon: Icon(Icons.info_outline), text: 'Info'),
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
                      group.isPublic ? Icons.public : Icons.lock,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      group.isPublic ? 'Gruppo pubblico' : 'Gruppo privato',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.people, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${group.memberCount} ${group.memberCount == 1 ? "membro" : "membri"}',
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
              const Text(
                'Descrizione',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  color: AppColors.primary,
                  tooltip: 'Modifica',
                  onPressed: () => _showEditGroupDialog(group),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (group.description != null && group.description!.isNotEmpty)
                ? group.description!
                : 'Nessuna descrizione. Tocca modifica per aggiungerne una.',
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

          // Info dettagli
          _buildInfoRow(Icons.calendar_today, 'Creato il', _formatDate(group.createdAt)),
          const SizedBox(height: 12),
          _buildInfoRow(
            Icons.admin_panel_settings,
            'Il tuo ruolo',
            _isAdmin ? 'Amministratore' : 'Membro',
          ),
          if (currentUserId == group.createdBy) ...[
            const SizedBox(height: 12),
            _buildInfoRow(Icons.star, 'Fondatore', 'Tu hai creato questo gruppo'),
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
        title: const Text('Modifica gruppo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nome gruppo',
                border: OutlineInputBorder(),
              ),
              maxLength: 30,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Descrizione',
                hintText: 'Descrivi il tuo gruppo...',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.length < 3) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Il nome deve avere almeno 3 caratteri')),
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
            child: const Text('Salva'),
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
    final months = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}