import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/groups_repository.dart';
import '../groups/group_detail_page.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/extensions/l10n_extension.dart';

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
    _initAdmin();
  }

  Future<void> _initAdmin() async {
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    if (!isAdmin) {
      if (mounted) Navigator.pop(context);
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
            _buildAdminClaimsSection(),
            const SizedBox(height: 24),
            _buildPendingSelfClaimSection(),
            const SizedBox(height: 24),
            _buildStatsSection(),
            const SizedBox(height: 24),
            _buildUsersSection(),
            const SizedBox(height: 24),
            _buildBusinessGroupsSection(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ADMIN CUSTOM CLAIMS (single source of truth platform admin)
  // ═══════════════════════════════════════════════════════════════════════

  // Super-admin UID hardcoded (allineato a functions/index.js +
  // firestore.rules → isSuperAdmin). Solo questo uid può fare
  // bootstrap iniziale dei claim degli altri admin.
  static const String _superAdminUid = 'g4uPvD3VQcMiYb4dDTWs7kJgm4u1';

  bool _bootstrapBusy = false;
  bool _promoteBusy = false;
  final TextEditingController _promoteUidCtrl = TextEditingController();

  Widget _buildAdminClaimsSection() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isSuperAdmin = currentUid == _superAdminUid;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_user, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'Gestione admin (Custom Claims)',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sistema admin basato su custom claims JWT — '
              'single source of truth, niente più liste hardcoded '
              'duplicate tra rules e Cloud Functions.',
              style: TextStyle(
                  fontSize: 12, color: context.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),

            // Bootstrap (visibile solo super-admin)
            if (isSuperAdmin) ...[
              const Text(
                'Bootstrap iniziale',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Setta admin: true come custom claim agli admin storici '
                '(definiti in ADMIN_EMAILS). Idempotente, eseguibile '
                'più volte senza danni.',
                style: TextStyle(
                    fontSize: 11, color: context.textSecondary),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _bootstrapBusy ? null : _runBootstrap,
                icon: _bootstrapBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.rocket_launch, size: 18),
                label: Text(_bootstrapBusy
                    ? 'In corso…'
                    : 'Esegui bootstrap admin'),
              ),
              const Divider(height: 32),
            ],

            // Promote per UID (visibile tutti gli admin)
            const Text(
              'Promuovi admin via UID',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Incolla l\'UID Firebase Auth di un utente (da Firebase '
              'Console → Authentication) e premi Promuovi. L\'utente '
              'target deve fare logout/login (oppure attendere 1h) per '
              'avere i privilegi attivi.',
              style:
                  TextStyle(fontSize: 11, color: context.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _promoteUidCtrl,
              decoration: const InputDecoration(
                labelText: 'UID Firebase Auth',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _promoteBusy
                      ? null
                      : () => _setClaim(true),
                  icon: const Icon(Icons.add_moderator, size: 18),
                  label: const Text('Promuovi admin'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _promoteBusy
                      ? null
                      : () => _setClaim(false),
                  icon: const Icon(Icons.remove_moderator, size: 18),
                  label: const Text('Rimuovi'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runBootstrap() async {
    setState(() => _bootstrapBusy = true);
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('bootstrapAdminClaims')
          .call();
      final data = result.data as Map;
      _showResultDialog('Bootstrap completato',
          'Processati: ${data['totalProcessed']}\n\n${data['results']}');
    } catch (e) {
      _snack('Errore bootstrap: $e', error: true);
    } finally {
      if (mounted) setState(() => _bootstrapBusy = false);
    }
  }

  Future<void> _setClaim(bool isAdmin) async {
    final uid = _promoteUidCtrl.text.trim();
    if (uid.isEmpty) {
      _snack('UID mancante', error: true);
      return;
    }
    setState(() => _promoteBusy = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('setAdminClaim')
          .call({'uid': uid, 'isAdmin': isAdmin});
      _snack(
        isAdmin
            ? 'Promosso ad admin. L\'utente deve fare logout/login per '
                'vedere i privilegi.'
            : 'Privilegi admin rimossi.',
        error: false,
      );
      _promoteUidCtrl.clear();
    } catch (e) {
      _snack('Errore setClaim: $e', error: true);
    } finally {
      if (mounted) setState(() => _promoteBusy = false);
    }
  }

  void _snack(String msg, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : AppColors.success,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showResultDialog(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(body, style: const TextStyle(fontSize: 12)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SELF-CLAIM PENDING (Epic 7.H1)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Lista live degli Spazi Pro inseriti dal team per conto di terzi
  // (pendingSelfManagement=true). Per ciascuno l'admin può generare
  // un link self-claim da inviare al rifugista via WhatsApp. Il link
  // ha TTL 30gg, rigenerarlo invalida quello precedente.

  Widget _buildPendingSelfClaimSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.send_to_mobile,
                    color: Colors.amber.shade700, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Schede in attesa di self-claim',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Spazi Pro inseriti dal team per conto del gestore. Genera un '
              'link da inviare via WhatsApp/email: chi lo apre diventa owner.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('businesses')
                  .where('pendingSelfManagement', isEqualTo: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Text('Errore: ${snap.error}',
                      style: const TextStyle(color: AppColors.danger));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nessuna scheda in attesa. Le schede inserite con la '
                      'spunta "per conto del proprietario" appariranno qui.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                  );
                }
                return Column(
                  children: docs
                      .map((d) => _PendingClaimTile(
                            businessId: d.id,
                            data: d.data(),
                            onGenerate: () => _generateSelfClaimLink(d.id),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateSelfClaimLink(String businessId) async {
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable('generateSelfClaimToken')
              .call({'businessId': businessId});
      final data = Map<String, dynamic>.from(result.data as Map);
      final url = data['url']?.toString() ?? '';
      final expiresInDays = data['expiresInDays'] ?? 30;
      if (!mounted) return;
      _showSelfClaimLinkDialog(url, expiresInDays);
    } catch (e) {
      _snack('Errore generazione link: $e', error: true);
    }
  }

  void _showSelfClaimLinkDialog(String url, dynamic expiresInDays) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link self-claim'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scade tra $expiresInDays giorni. Rigenerare invalida il link '
              'attuale.',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Mandalo via WhatsApp al gestore. Quando lo apre, fa login e '
              'diventa owner della scheda. Tu rimani nei co-admin.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await Clipboard.setData(ClipboardData(text: url));
              if (!mounted) return;
              nav.pop();
              _snack('Link copiato negli appunti', error: false);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copia'),
          ),
        ],
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
            childAspectRatio: 0.95,
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const Spacer(),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.8)),
            overflow: TextOverflow.ellipsis,
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
                color: AppColors.primary.withValues(alpha: 0.1),
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
    final isSuperAdmin = user.isAdmin;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: user.isSuspended ? Colors.red.withValues(alpha: 0.05) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isSuperAdmin
              ? Colors.amber
              : user.isSuspended
                  ? Colors.red.withValues(alpha: 0.2)
                  : AppColors.primary.withValues(alpha: 0.1),
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

  // ═══════════════════════════════════════════════════════════════════════
  // GESTIONE GRUPPI BUSINESS (super admin)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildBusinessGroupsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gruppi Business',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Marca un gruppo come Business per sbloccare la personalizzazione '
          'visiva (logo, badge verificato). Per ora gratis al primo cliente; '
          'in futuro autoset al pagamento del piano.',
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.search),
          label: const Text('Cerca e gestisci gruppo'),
          onPressed: _showGroupSearchDialog,
        ),
      ],
    );
  }

  Future<void> _showGroupSearchDialog() async {
    final groupsRepo = GroupsRepository();
    final controller = TextEditingController();
    Group? foundGroup;
    bool searching = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Gruppo Business'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Group ID',
                    hintText: 'es. f4EkwhGPpPEx4ehEXTgP',
                  ),
                ),
                const SizedBox(height: 12),
                if (searching)
                  const CircularProgressIndicator()
                else if (foundGroup != null) ...[
                  ListTile(
                    leading: const Icon(Icons.group),
                    title: Text(foundGroup!.name),
                    subtitle: Text(
                      'Stato: ${foundGroup!.businessTierLabel}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Picker tier: assegna manualmente prima dell'integrazione
                  // Stripe (clienti seed, demo, override commerciale).
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tier in const [
                        ('trial', 'Trial 14gg'),
                        ('verified', 'Verified'),
                        ('pro', 'Pro'),
                        ('enterprise', 'Enterprise'),
                      ])
                        FilledButton.tonal(
                          onPressed: () async {
                            final ok = await groupsRepo.setBusinessTier(
                              foundGroup!.id,
                              tier.$1,
                            );
                            if (ok && ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Tier impostato: ${tier.$2}'),
                                ),
                              );
                              Navigator.of(ctx).pop();
                            }
                          },
                          child: Text(tier.$2),
                        ),
                      if (foundGroup!.isBusinessGroup)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.block, size: 18),
                          label: const Text('Disattiva Business'),
                          onPressed: () async {
                            final ok = await groupsRepo.clearBusinessTier(
                              foundGroup!.id,
                            );
                            if (ok && ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Gruppo non più Business'),
                                ),
                              );
                              Navigator.of(ctx).pop();
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.l10n.close),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Cerca'),
              onPressed: () async {
                if (controller.text.trim().isEmpty) return;
                setStateDialog(() {
                  searching = true;
                  foundGroup = null;
                });
                final g = await groupsRepo.getGroup(controller.text.trim());
                setStateDialog(() {
                  searching = false;
                  foundGroup = g;
                });
                if (g == null && ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Nessun gruppo con questo ID')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
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
    final isSuperAdmin = user.isAdmin;

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
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
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
                      Text(user.bio!, style: TextStyle(color: context.textSecondary)),
                    Text(
                      'Lv. ${user.level} • ${user.xp} XP',
                      style: TextStyle(fontSize: 13, color: context.textMuted),
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
                Icon(Icons.fingerprint, size: 16, color: context.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.uid,
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: context.textMuted),
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
                      Icon(Icons.chevron_right, size: 16, color: context.textMuted),
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
          Icon(icon, size: 18, color: context.textMuted),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: context.textSecondary)),
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
            child: Text(context.l10n.cancel),
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

/// Riga di una scheda Spazio Pro con `pendingSelfManagement=true`
/// nella sezione admin "Schede in attesa di self-claim".
class _PendingClaimTile extends StatelessWidget {
  final String businessId;
  final Map<String, dynamic> data;
  final VoidCallback onGenerate;

  const _PendingClaimTile({
    required this.businessId,
    required this.data,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name']?.toString() ?? '—';
    final city = (data['location'] is Map)
        ? (data['location']['city']?.toString() ?? '')
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  city.isEmpty ? businessId : '$city  ·  $businessId',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onGenerate,
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Genera link'),
          ),
        ],
      ),
    );
  }
}
