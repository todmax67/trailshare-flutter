import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../data/repositories/groups_repository.dart';
import '../profile/public_profile_page.dart';
import '../../../data/repositories/follow_repository.dart';

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
        title: Text(context.l10n.membersWithCount(_members.length)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: context.l10n.inviteTooltip,
              onPressed: _showInviteDialog,
            ),
        ],
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
              Text(context.l10n.youSuffix, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
        subtitle: Text(
          member.isAdmin ? context.l10n.adminWithCrown : context.l10n.memberRole,
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
        title: Text(context.l10n.removeMember),
        content: Text(context.l10n.removeMemberConfirm(member.username)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.removeAction),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _repo.removeMember(widget.groupId, member.userId);
      _loadMembers();
    }
  }

  Future<void> _showInviteDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final followRepo = FollowRepository();
    final following = await followRepo.getFollowingWithProfiles(user.uid);

    // Filtra chi è già membro
    final memberIds = _members.map((m) => m.userId).toSet();
    final invitable = following.where((u) => !memberIds.contains(u.id)).toList();

    if (!mounted) return;

    if (invitable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.allContactsInGroup)),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.inviteContact,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: invitable.length,
                itemBuilder: (context, index) {
                  final profile = invitable[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      backgroundImage: profile.avatarUrl != null
                          ? NetworkImage(profile.avatarUrl!)
                          : null,
                      child: profile.avatarUrl == null
                          ? Text(
                              profile.username.isNotEmpty
                                  ? profile.username[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            )
                          : null,
                    ),
                    title: Text(profile.username),
                    subtitle: Text(context.l10n.levelLabel(profile.level), style: const TextStyle(fontSize: 12)),
                    trailing: ElevatedButton(
                      onPressed: () async {
                        final success = await _repo.addMember(widget.groupId, profile.id);
                        if (success && mounted) {
                          Navigator.pop(context);
                          _loadMembers();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.l10n.addedToGroup(profile.username)),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(context.l10n.inviteAction, style: const TextStyle(fontSize: 13)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
