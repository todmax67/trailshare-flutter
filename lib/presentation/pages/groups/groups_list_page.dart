import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/groups_repository.dart';
import 'create_group_page.dart';
import 'group_detail_page.dart';

class GroupsListPage extends StatefulWidget {
  const GroupsListPage({super.key});

  @override
  State<GroupsListPage> createState() => _GroupsListPageState();
}

class _GroupsListPageState extends State<GroupsListPage> with SingleTickerProviderStateMixin {
  final _repo = GroupsRepository();
  List<Group> _myGroups = [];
  List<Group> _publicGroups = [];
  bool _isLoadingMy = true;
  bool _isLoadingPublic = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _isLoadingPublic) {
        _loadPublicGroups();
      }
    });
    _loadMyGroups();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMyGroups() async {
    setState(() => _isLoadingMy = true);
    final groups = await _repo.getMyGroups();
    if (mounted) {
      setState(() {
        _myGroups = groups;
        _isLoadingMy = false;
      });
    }
  }

  Future<void> _loadPublicGroups() async {
    setState(() => _isLoadingPublic = true);
    final groups = await _repo.getDiscoverableGroups();
    if (mounted) {
      setState(() {
        _publicGroups = groups;
        _isLoadingPublic = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gruppi'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'I miei Gruppi'),
            Tab(text: 'Scopri'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const CreateGroupPage()),
          );
          if (created == true) {
            _loadMyGroups();
            _loadPublicGroups();
          }
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuovo Gruppo'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: I miei Gruppi
          _isLoadingMy
              ? const Center(child: CircularProgressIndicator())
              : _myGroups.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadMyGroups,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _myGroups.length,
                        itemBuilder: (context, index) => _buildGroupCard(_myGroups[index], isMember: true),
                      ),
                    ),

          // Tab 2: Scopri
          _isLoadingPublic
              ? const Center(child: CircularProgressIndicator())
              : _publicGroups.isEmpty
                  ? _buildEmptyDiscover()
                  : RefreshIndicator(
                      onRefresh: _loadPublicGroups,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _publicGroups.length,
                        itemBuilder: (context, index) => _buildGroupCard(_publicGroups[index], isMember: false),
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.groups_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            const Text(
              'Nessun gruppo',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Crea un gruppo per organizzare uscite, lanciare sfide e chattare con i tuoi compagni di avventura!',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateGroupPage()),
                );
                if (created == true) _loadMyGroups();
              },
              icon: const Icon(Icons.add),
              label: const Text('Crea il tuo primo gruppo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDiscover() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            const Text(
              'Nessun gruppo disponibile',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Non ci sono gruppi pubblici a cui unirti al momento. Creane uno tu!',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(Group group, {required bool isMember}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isMember
            ? () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupDetailPage(groupId: group.id, groupName: group.name),
                  ),
                );
                _loadMyGroups();
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar gruppo
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primary.withOpacity(0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (group.description != null && group.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.people, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          '${group.memberCount} ${group.memberCount == 1 ? "membro" : "membri"}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                        if (group.isPublic) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.public, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Pubblico',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Bottone unisciti o freccia
              if (isMember)
                const Icon(Icons.chevron_right, color: AppColors.textMuted)
              else
                ElevatedButton(
                  onPressed: () async {
                    final success = await _repo.joinGroup(group.id);
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Ti sei unito a "${group.name}"!'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                      _loadMyGroups();
                      _loadPublicGroups();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Unisciti', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}