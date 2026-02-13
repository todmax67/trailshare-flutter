import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/groups_repository.dart';
import '../profile/public_profile_page.dart';

class GroupMembersPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final bool isAdmin;

  const GroupMembersPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.isAdmin = false,
  });

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  final _repo = GroupsRepository();
  List<GroupMember> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    final members = await _repo.getMembers(widget.groupId);
    if (mounted) {
      setState(() {
        _members = members;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Membri (${_members.length})'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMembers,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _members.length,
                itemBuilder: (context, index) => _buildMemberTile(_members[index]),
              ),
            ),
    );
  }

  Widget _buildMemberTile(GroupMember member) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isMe = member.userId == currentUserId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () {
          if (!isMe) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PublicProfilePage(
                  userId: member.userId,
                  username: member.username,
                ),
              ),
            );
          }
        },
        leading: CircleAvatar(
          backgroundColor: member.isAdmin
              ? AppColors.warning.withOpacity(0.2)
              : AppColors.primary.withOpacity(0.1),
          backgroundImage: member.avatarUrl != null ? NetworkImage(member.avatarUrl!) : null,
          child: member.avatarUrl == null
              ? Text(
                  member.username.isNotEmpty ? member.username[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: member.isAdmin ? AppColors.warning : AppColors.primary,
                  ),
                )
              : null,
        ),
        title: Row(
          children: [
            Text(
              member.username,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isMe ? AppColors.primary : null,
              ),
            ),
            if (isMe)
              const Text(' (tu)', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
        subtitle: Text(
          member.isAdmin ? '👑 Amministratore' : 'Membro',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: widget.isAdmin && !isMe && !member.isAdmin
            ? IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                onPressed: () => _confirmRemoveMember(member),
              )
            : null,
      ),
    );
  }

  Future<void> _confirmRemoveMember(GroupMember member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovi membro'),
        content: Text('Vuoi rimuovere ${member.username} dal gruppo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _repo.removeMember(widget.groupId, member.userId);
      _loadMembers();
    }
  }
}