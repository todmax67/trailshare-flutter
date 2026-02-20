import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/admin_repository.dart';
import '../groups/group_detail_page.dart';
import '../follow/follow_list_page.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final AdminRepository _adminRepo = AdminRepository();
  final TextEditingController _searchController = TextEditingController();

  // Stato
  AppStats _stats = const AppStats();
  List<AppUser> _users = [];
  bool _isLoadingStats = true;
  bool _isLoadingUsers = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    // Verifica accesso
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!AdminRepository.isSuperAdmin(uid)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
      });
      return;
    }

    _loadStats();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoadingStats = true);
    final stats = await _adminRepo.getAppStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoadingStats = false;
      });
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    final users = await _adminRepo.getUsers(limit: 100);
    if (mounted) {
      setState(() {
        _users = users;
        _isLoadingUsers = false;
      });
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      _loadUsers();
      return;
    }
    setState(() => _isLoadingUsers = true);
    final users = await _adminRepo.searchUsers(query);
    if (mounted) {
      setState(() {
        _users = users;
        _isLoadingUsers = false;
      });
    }
  }

  List<AppUser> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    final q = _searchQuery.toLowerCase();
    return _users.where((u) =>
        u.username.toLowerCase().contains(q) ||
        (u.email?.toLowerCase().contains(q) ?? false) ||
        u.uid.toLowerCase().contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, size: 24),
            SizedBox(width: 8),
            Text('Pannello Admin'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadStats();
              _loadUsers();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadStats();
          await _loadUsers();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatsSection(),
            const SizedBox(height: 24),
            _buildUsersSection(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DASHBOARD STATISTICHE
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dashboard',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_isLoadingStats)
          const Center(child: CircularProgressIndicator())
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _buildStatCard(
                icon: Icons.people,
                label: 'Utenti',
                value: '${_stats.totalUsers}',
                color: AppColors.primary,
              ),
              _buildStatCard(
                icon: Icons.public,
                label: 'Community',
                value: '${_stats.totalCommunityTracks}',
                color: AppColors.success,
              ),
              _buildStatCard(
                icon: Icons.groups,
                label: 'Gruppi',
                value: '${_stats.totalGroups}',
                color: Colors.purple,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LISTA UTENTI
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildUsersSection() {
    final users = _filteredUsers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Utenti',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${users.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Barra di ricerca
        TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() => _searchQuery = value);
          },
          decoration: InputDecoration(
            hintText: 'Cerca per username, email o UID...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
        const SizedBox(height: 12),

        // Lista
        if (_isLoadingUsers)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (users.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.person_off, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text(
                    _searchQuery.isEmpty ? 'Nessun utente' : 'Nessun risultato',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          )
        else
          ...users.map((user) => _buildUserTile(user)),
      ],
    );
  }

  Widget _buildUserTile(AppUser user) {
    final isSuperAdmin = user.uid == superAdminUid;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: user.isSuspended ? Colors.red.withOpacity(0.05) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isSuperAdmin
              ? Colors.amber
              : user.isSuspended
                  ? Colors.red.withOpacity(0.2)
                  : AppColors.primary.withOpacity(0.1),
          backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
              ? NetworkImage(user.avatarUrl!)
              : null,
          child: user.avatarUrl == null || user.avatarUrl!.isEmpty
              ? Text(
                  user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSuperAdmin ? Colors.white : AppColors.primary,
                  ),
                )
              : null,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                user.username,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSuperAdmin) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'ADMIN',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
            if (user.isSuspended) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SOSPESO',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${user.email ?? "UID: ${user.uid.substring(0, 10)}..."}'
          ' • Lv. ${user.level}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showUserDetail(user),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DETTAGLIO UTENTE
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _showUserDetail(AppUser user) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _UserDetailSheet(
        user: user,
        adminRepo: _adminRepo,
        onAction: () {
          _loadUsers();
          _loadStats();
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET DETTAGLIO UTENTE
// ═══════════════════════════════════════════════════════════════════════════

class _UserDetailSheet extends StatefulWidget {
  final AppUser user;
  final AdminRepository adminRepo;
  final VoidCallback onAction;

  const _UserDetailSheet({
    required this.user,
    required this.adminRepo,
    required this.onAction,
  });

  @override
  State<_UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<_UserDetailSheet> {
  Map<String, dynamic>? _details;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final details = await widget.adminRepo.getUserDetails(widget.user.uid);
    if (mounted) {
      setState(() {
        _details = details;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isSuperAdmin = user.uid == superAdminUid;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Avatar e nome
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                    ? Text(
                        user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.username,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    if (user.bio != null && user.bio!.isNotEmpty)
                      Text(user.bio!, style: const TextStyle(color: AppColors.textSecondary)),
                    Text(
                      'Lv. ${user.level} • ${user.xp} XP',
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // UID
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.fingerprint, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.uid,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Statistiche
          if (_isLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ))
          else if (_details != null) ...[
            _buildDetailRow(Icons.route, 'Tracce salvate', '${_details!['tracksCount'] ?? 0}'),
            _buildDetailRow(Icons.public, 'Tracce community', '${_details!['communityTracksCount'] ?? 0}'),

            // Gruppi
            if (_details!['groups'] != null && (_details!['groups'] as List).isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Gruppi:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...(_details!['groups'] as List).map((g) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupDetailPage(
                          groupId: g['id'],
                          groupName: g['name'],
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.groups, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(g['name'], style: const TextStyle(color: AppColors.primary)),
                      const Spacer(),
                      const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                    ],
                  ),
                ),
              )),
            ],

            // Date
            if (user.createdAt != null) ...[
              const SizedBox(height: 12),
              _buildDetailRow(Icons.calendar_today, 'Iscritto il', _formatDate(user.createdAt!)),
            ],
            if (user.lastActive != null)
              _buildDetailRow(Icons.access_time, 'Ultimo accesso', _formatDate(user.lastActive!)),
          ],

          const SizedBox(height: 24),

          // Azioni admin (non su se stesso)
          if (!isSuperAdmin) ...[
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Azioni Admin',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 12),

            // Sospendi / Riattiva
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _toggleSuspend(user),
                icon: Icon(user.isSuspended ? Icons.check_circle : Icons.block),
                label: Text(user.isSuspended ? 'Riattiva utente' : 'Sospendi utente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: user.isSuspended ? AppColors.success : Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _toggleSuspend(AppUser user) async {
    final action = user.isSuspended ? 'riattivare' : 'sospendere';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${user.isSuspended ? "Riattiva" : "Sospendi"} utente'),
        content: Text('Vuoi $action "${user.username}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: user.isSuspended ? AppColors.success : Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(user.isSuspended ? 'Riattiva' : 'Sospendi'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await widget.adminRepo.toggleSuspendUser(user.uid, !user.isSuspended);
      if (success && mounted) {
        widget.onAction();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Utente ${!user.isSuspended ? "sospeso" : "riattivato"}'),
            backgroundColor: !user.isSuspended ? Colors.orange : AppColors.success,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
