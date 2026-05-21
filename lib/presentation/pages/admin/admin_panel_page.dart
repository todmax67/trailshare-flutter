import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/groups_repository.dart';
import '../../../web/pages/web_outreach_pdf_page.dart';
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
            _buildPublicClaimRequestsSection(),
            const SizedBox(height: 24),
            _buildOsmImportSection(),
            const SizedBox(height: 24),
            _buildOutreachKitSection(),
            const SizedBox(height: 24),
            _buildOutreachCampaignSection(),
            const SizedBox(height: 24),
            _buildNewsletterSection(),
            const SizedBox(height: 24),
            _buildTerrainEnrichmentSection(),
            const SizedBox(height: 24),
            _buildQualityFlagsSection(),
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

  // 7.H2 — Import OSM state
  String _osmRegion = 'lombardia';
  String _osmBusinessType = 'rifugio';
  bool _osmBusy = false;
  Map<String, dynamic>? _osmLastResult;

  // 7.H10 — Outreach kit state
  final TextEditingController _outreachIdCtrl = TextEditingController();

  // 7.H10b — Outreach campaign batch state
  String? _campaignRegion;
  String _campaignType = '__all__';
  bool _campaignBusy = false;
  Map<String, dynamic>? _campaignPreview;
  Map<String, dynamic>? _campaignSendResult;

  // Newsletter v2.5.1 — service-update email agli utenti registrati
  final TextEditingController _newsletterCampaignIdCtrl =
      TextEditingController(text: 'v2.5.1-launch');
  final TextEditingController _newsletterSubjectCtrl = TextEditingController(
      text: 'TrailShare è cresciuto. Le novità che ti sei perso.');
  final TextEditingController _newsletterMaxEmailsCtrl =
      TextEditingController(text: '50');
  final TextEditingController _newsletterTestEmailCtrl =
      TextEditingController();
  bool _newsletterBusy = false;
  Map<String, dynamic>? _newsletterPreview;
  Map<String, dynamic>? _newsletterSendResult;

  // K1b — Terrain enrichment per public_trails
  final TextEditingController _terrainTrailIdCtrl = TextEditingController();
  final TextEditingController _terrainMaxTrailsCtrl =
      TextEditingController(text: '20');
  bool _terrainBusy = false;
  Map<String, dynamic>? _terrainResult;

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
            // Wrap su mobile: i due bottoni vanno a capo se non
            // c'entrano su una riga (icona+label "Promuovi admin"
            // + icona+label "Rimuovi" sforano su schermi < ~360px).
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _promoteBusy
                      ? null
                      : () => _setClaim(true),
                  icon: const Icon(Icons.add_moderator, size: 18),
                  label: const Text('Promuovi admin'),
                ),
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
                  .limit(200)
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

                // Ordinamento per priorità operativa:
                // 1. Manuali (no email outreach) → azione: generare link
                // 2. Email outreach stale (>7gg, no claim) → azione: follow-up
                // 3. Email outreach recente → in attesa naturale
                final sortedDocs = docs.toList()
                  ..sort((a, b) {
                    final aSent = a.data()['outreachEmailSentAt'];
                    final bSent = b.data()['outreachEmailSentAt'];
                    if (aSent == null && bSent != null) return -1;
                    if (aSent != null && bSent == null) return 1;
                    if (aSent == null && bSent == null) return 0;
                    if (aSent is Timestamp && bSent is Timestamp) {
                      return aSent.compareTo(bSent); // più vecchi prima
                    }
                    return 0;
                  });

                // Conta sottocategorie per il summary
                int manualCount = 0;
                int outreachCount = 0;
                int staleCount = 0;
                final now = DateTime.now();
                for (final d in sortedDocs) {
                  final sent = d.data()['outreachEmailSentAt'];
                  if (sent == null) {
                    manualCount++;
                  } else {
                    outreachCount++;
                    if (sent is Timestamp) {
                      if (now.difference(sent.toDate()).inDays >= 7) {
                        staleCount++;
                      }
                    }
                  }
                }

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                            '${sortedDocs.length} totali',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '$manualCount manuali (link da generare)',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.primary),
                          ),
                          Text(
                            '$outreachCount email inviate',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.info),
                          ),
                          if (staleCount > 0)
                            Text(
                              '$staleCount stale (>7gg, follow-up?)',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...sortedDocs.map((d) => _PendingClaimTile(
                          businessId: d.id,
                          data: d.data(),
                          onGenerate: () => _generateSelfClaimLink(d.id),
                          onOpenOutreach: () => _openOutreachFor(d.id),
                        )),
                  ],
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
  // CLAIM REQUESTS PUBBLICHE (Epic 7.H6 — review claims)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Stream live di `business_claim_requests` where status==pending.
  // Per ognuna: card con dati richiedente + bottoni Approva / Rifiuta.
  // Approva chiama Cloud Function approveClaimRequest (ownership transfer
  // + email all'utente). Rifiuta chiede motivazione + chiama rejectClaimRequest.

  Widget _buildPublicClaimRequestsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_ind_outlined,
                    color: Colors.deepPurple.shade400, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Claim requests in attesa',
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
              'Richieste di rivendicazione inviate dal pubblico dalla landing '
              'di una scheda unclaimed. Verifica i dati e approva o rifiuta.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('business_claim_requests')
                  .where('status', isEqualTo: 'pending')
                  .orderBy('createdAt', descending: true)
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
                      'Nessuna claim request pendente.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                  );
                }
                return Column(
                  children: docs
                      .map((d) => _ClaimRequestTile(
                            requestId: d.id,
                            data: d.data(),
                            onApprove: () => _approveClaim(d.id),
                            onReject: () => _promptRejectClaim(d.id),
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

  Future<void> _approveClaim(String requestId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approvare la richiesta?'),
        content: const Text(
          'Confermando, il richiedente diventerà subito owner della scheda. '
          'Il vecchio owner (team) resterà nei co-admin per supporto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approva'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable('approveClaimRequest')
              .call({'requestId': requestId});
      final data = Map<String, dynamic>.from(result.data as Map);
      _snack('Approvata: ${data['businessName']}', error: false);
    } catch (e) {
      _snack('Errore approve: $e', error: true);
    }
  }

  Future<void> _promptRejectClaim(String requestId) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rifiutare la richiesta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Motivo del rifiuto (verrà inviato via email al richiedente).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Es. P.IVA non corrisponde, email non aziendale...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rifiuta'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('rejectClaimRequest')
          .call({
        'requestId': requestId,
        'reason': reasonCtrl.text.trim(),
      });
      _snack('Richiesta rifiutata', error: false);
    } catch (e) {
      _snack('Errore reject: $e', error: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OSM IMPORT (Epic 7.H2)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Form per pre-popolare schede unclaimed da OpenStreetMap.
  // Selettore regione + tipo + bottone dryRun (preview) + bottone
  // Importa. Mostra l'esito (created, skipped, errors, samples).

  static const _osmRegions = <String, String>{
    'lombardia': 'Lombardia',
    'piemonte': 'Piemonte',
    'veneto': 'Veneto',
    'trentino': 'Trentino',
    'altoadige': 'Alto Adige',
    'valleaosta': 'Valle d\'Aosta',
    'liguria': 'Liguria',
    'emiliaromagna': 'Emilia-Romagna',
    'toscana': 'Toscana',
    'marche': 'Marche',
    'umbria': 'Umbria',
    'lazio': 'Lazio',
    'abruzzo': 'Abruzzo',
    'molise': 'Molise',
    'campania': 'Campania',
    'puglia': 'Puglia',
    'basilicata': 'Basilicata',
    'calabria': 'Calabria',
    'sicilia': 'Sicilia',
    'sardegna': 'Sardegna',
    'italia': 'Tutta Italia (lenta!)',
  };

  static const _osmTypes = <String, String>{
    'rifugio': 'Rifugi (alpine_hut)',
    'noleggio': 'Noleggio bici/sci',
    'guidaAlpina': 'Guide alpine / arrampicata',
    'shop': 'Negozi outdoor',
  };

  Widget _buildOsmImportSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_download_outlined,
                    color: Colors.teal.shade400, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Import OSM → schede unclaimed',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pre-popola Spazi Pro da OpenStreetMap per una regione. '
              'Le schede nascono con tier=unclaimed, banner claim attivo. '
              'Dedup automatico via sourceUrl: rilanciare è idempotente.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            // Layout responsive: su mobile (largo < 500) stack verticale,
            // su desktop affiancati. Evita overflow horizontale sui
            // dropdown lunghi tipo "Emilia-Romagna" e "Guide alpine /
            // arrampicata".
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 500;
                final regionField = DropdownButtonFormField<String>(
                  initialValue: _osmRegion,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Regione',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _osmRegions.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: _osmBusy
                      ? null
                      : (v) => setState(() => _osmRegion = v ?? 'lombardia'),
                );
                final typeField = DropdownButtonFormField<String>(
                  initialValue: _osmBusinessType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _osmTypes.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: _osmBusy
                      ? null
                      : (v) =>
                          setState(() => _osmBusinessType = v ?? 'rifugio'),
                );
                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: regionField),
                      const SizedBox(width: 12),
                      Expanded(child: typeField),
                    ],
                  );
                }
                return Column(
                  children: [
                    regionField,
                    const SizedBox(height: 12),
                    typeField,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Wrap su mobile: i bottoni vanno a capo se lo spazio
            // non basta (es. quando "Preview (dry-run)" è il primo
            // e "Importa" non sta).
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _osmBusy ? null : () => _runOsmImport(dryRun: true),
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('Preview (dry-run)'),
                ),
                FilledButton.icon(
                  onPressed: _osmBusy ? null : () => _confirmOsmImport(),
                  icon: _osmBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_download, size: 18),
                  label: Text(_osmBusy ? 'In corso...' : 'Importa'),
                ),
              ],
            ),
            if (_osmLastResult != null) ...[
              const SizedBox(height: 16),
              _buildOsmResultBlock(_osmLastResult!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOsmResultBlock(Map<String, dynamic> r) {
    final dryRun = r['dryRun'] == true;
    final fetched = r['fetched'] ?? 0;
    final created = r['created'] ?? 0;
    final skipped = r['skipped'] ?? 0;
    final errors = (r['errors'] as List?) ?? const [];
    final samples = (r['samples'] as List?) ?? const [];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dryRun ? 'Risultato preview' : 'Import completato',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Fetched da OSM: $fetched  ·  '
            '${dryRun ? "Da creare" : "Creati"}: $created  ·  '
            'Skippati (già esistenti): $skipped'
            '${errors.isNotEmpty ? "  ·  Errori: ${errors.length}" : ""}',
            style: const TextStyle(fontSize: 12),
          ),
          if (dryRun && samples.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Primi 5 sample:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted),
            ),
            ...samples.map((s) {
              final m = Map<String, dynamic>.from(s as Map);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${m['name']} '
                  '${m['city'] != null ? "(${m['city']})" : ""}',
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Errori (primi 3): ${errors.take(3).join("; ")}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmOsmImport() async {
    final regionLabel = _osmRegions[_osmRegion] ?? _osmRegion;
    final typeLabel = _osmTypes[_osmBusinessType] ?? _osmBusinessType;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confermi import?'),
        content: Text(
          'Sto per creare schede `unclaimed` per $typeLabel in $regionLabel.\n\n'
          'Suggerimento: lancia prima Preview per stimare il volume.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importa'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _runOsmImport(dryRun: false);
  }

  Future<void> _runOsmImport({required bool dryRun}) async {
    setState(() {
      _osmBusy = true;
      _osmLastResult = null;
    });
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable(
                'importOsmBusinesses',
                options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 120)),
              )
              .call({
        'region': _osmRegion,
        'businessType': _osmBusinessType,
        'dryRun': dryRun,
      });
      if (!mounted) return;
      setState(() {
        _osmLastResult = Map<String, dynamic>.from(result.data as Map);
      });
      _snack(
        dryRun
            ? 'Preview pronta. Controlla risultato sotto.'
            : 'Import completato.',
        error: false,
      );
    } catch (e) {
      _snack('Errore import OSM: $e', error: true);
    } finally {
      if (mounted) setState(() => _osmBusy = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OUTREACH KIT (Epic 7.H10)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // L'admin inserisce ID o slug della scheda → apre nuova tab con la
  // pagina printable. Da lì Cmd+P / Ctrl+P salva PDF.

  Widget _buildOutreachKitSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.picture_as_pdf_outlined,
                    color: Colors.indigo.shade400, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Outreach Kit (PDF stampabile)',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Genera un kit PDF da consegnare al gestore di una scheda: '
              'stats funnel, mappa zona, competitor. Apri la pagina, premi '
              '⌘P / Ctrl+P e salva PDF.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _outreachIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Business ID',
                hintText: 'es. ABC123xyz...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _openOutreachPdf,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Apri Outreach PDF'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Suggerimento: copia l\'ID dalla sezione "Schede in attesa di '
              'self-claim" sopra, oppure dalla pagina pubblica della scheda.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _openOutreachPdf() {
    final id = _outreachIdCtrl.text.trim();
    if (id.isEmpty) {
      _snack('Inserisci un Business ID', error: true);
      return;
    }
    _openOutreachFor(id);
  }

  /// Apre la pagina outreach PDF. Su web usa la route nominata (così
  /// l'URL aggiorna e l'utente può fare ⌘P sul browser). Su mobile
  /// la TrailShareApp non registra `/admin/outreach/...`, quindi
  /// facciamo un push diretto con MaterialPageRoute. Sul cellulare
  /// vedi l'anteprima ma per stampare/condividere PDF passa al web.
  void _openOutreachFor(String businessId) {
    if (kIsWeb) {
      Navigator.of(context).pushNamed('/admin/outreach/$businessId');
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WebOutreachPdfPage(businessId: businessId),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OUTREACH CAMPAIGN BATCH (Epic 7.H10b)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Invio email automatico alle schede unclaimed con email pubblica.
  // Filtri: regione (bbox) + tipo. Preview prima per stimare volume,
  // poi Invia (cap 50 email per batch). Idempotente: skippa schede
  // già contattate.

  static const _campaignTypeOptions = <String, String>{
    '__all__': 'Tutti i tipi',
    'rifugio': 'Rifugi (alpine_hut)',
    'noleggio': 'Noleggio bici/sci',
    'guidaAlpina': 'Guide alpine / arrampicata',
    'shop': 'Negozi outdoor',
  };

  Widget _buildOutreachCampaignSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.send_outlined,
                    color: Colors.deepOrange.shade400, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Campagna outreach email',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Invio email automatico alle schede unclaimed con email '
              'aziendale pubblica. Esclude email personali (gmail/hotmail). '
              'Genera link self-claim individuale + tracking. Cap 50/giorno.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 500;
                final regionField = DropdownButtonFormField<String?>(
                  initialValue: _campaignRegion,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Regione',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tutte le regioni'),
                    ),
                    ..._osmRegions.entries
                        .where((e) => e.key != 'italia')
                        .map((e) => DropdownMenuItem<String?>(
                              value: e.key,
                              child: Text(e.value,
                                  overflow: TextOverflow.ellipsis),
                            )),
                  ],
                  onChanged: _campaignBusy
                      ? null
                      : (v) => setState(() => _campaignRegion = v),
                );
                final typeField = DropdownButtonFormField<String>(
                  initialValue: _campaignType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _campaignTypeOptions.entries
                      .map((e) => DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: _campaignBusy
                      ? null
                      : (v) => setState(() => _campaignType = v ?? '__all__'),
                );
                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: regionField),
                      const SizedBox(width: 12),
                      Expanded(child: typeField),
                    ],
                  );
                }
                return Column(
                  children: [
                    regionField,
                    const SizedBox(height: 12),
                    typeField,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _campaignBusy ? null : _previewCampaign,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('Preview candidati'),
                ),
                FilledButton.icon(
                  onPressed: (_campaignBusy || _campaignPreview == null)
                      ? null
                      : _confirmSendCampaign,
                  icon: _campaignBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send, size: 18),
                  label: Text(_campaignBusy
                      ? 'Invio...'
                      : 'Invia campagna (max 50)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepOrange.shade400,
                  ),
                ),
              ],
            ),
            if (_campaignPreview != null) ...[
              const SizedBox(height: 16),
              _buildCampaignPreviewBlock(_campaignPreview!),
            ],
            if (_campaignSendResult != null) ...[
              const SizedBox(height: 16),
              _buildCampaignSendResultBlock(_campaignSendResult!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCampaignPreviewBlock(Map<String, dynamic> r) {
    final found = r['found'] ?? 0;
    final foundBeforeDns = r['foundBeforeDns'] ?? found;
    final skipped = r['skippedNoMx'] ?? 0;
    final samples = (r['samples'] as List?) ?? const [];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Candidati pronti per invio: $found',
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Filtro: tier=unclaimed, email business pubblica, mai contattate, '
            'dominio con MX record valido. '
            '${skipped > 0 ? "$skipped scartati per DNS fail (dominio inesistente)." : ""}',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textMuted),
          ),
          if (foundBeforeDns != found) ...[
            const SizedBox(height: 2),
            Text(
              'Pre-DNS: $foundBeforeDns · Post-DNS: $found '
              '(${((skipped / foundBeforeDns) * 100).toStringAsFixed(0)}% scartati)',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textMuted),
            ),
          ],
          if (samples.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Primi 5 sample:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted),
            ),
            ...samples.map((s) {
              final m = Map<String, dynamic>.from(s as Map);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${m['name']} ${m['city'] != null ? "(${m['city']})" : ""} → ${m['email']}',
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildCampaignSendResultBlock(Map<String, dynamic> r) {
    final sent = r['sent'] ?? 0;
    final candidates = r['candidates'] ?? 0;
    final errors = (r['errors'] as List?) ?? const [];
    final dryRun = r['dryRun'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dryRun
                ? 'Dry-run completato: $sent/$candidates email simulate'
                : 'Invio completato: $sent/$candidates email accodate',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700),
          ),
          if (errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Errori: ${errors.length} (primi 3: ${errors.take(3).join("; ")})',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Trigger Email Extension manda le email via SendGrid in '
            'pochi secondi. Vedi stato real-time in Firestore Console '
            '→ collection mail/.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _previewCampaign() async {
    setState(() {
      _campaignBusy = true;
      _campaignPreview = null;
      _campaignSendResult = null;
    });
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable('previewOutreachBatch')
              .call({
        'region': _campaignRegion,
        'businessType':
            _campaignType == '__all__' ? null : _campaignType,
      });
      if (!mounted) return;
      setState(() => _campaignPreview =
          Map<String, dynamic>.from(result.data as Map));
    } catch (e) {
      _snack('Errore preview: $e', error: true);
    } finally {
      if (mounted) setState(() => _campaignBusy = false);
    }
  }

  Future<void> _confirmSendCampaign() async {
    final found = _campaignPreview?['found'] ?? 0;
    if (found == 0) {
      _snack('Nessun candidato da inviare.', error: true);
      return;
    }
    final toSend = found > 50 ? 50 : found;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confermi invio campagna?'),
        content: Text(
          'Sto per inviare $toSend email a schede unclaimed '
          '(su $found candidati). Ogni email contiene un link self-claim '
          'unico. Le schede contattate saranno marcate come "sent" e '
          'non più ricontattate.\n\n'
          'Procedere?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.deepOrange.shade400),
            child: const Text('Invia'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _campaignBusy = true;
      _campaignSendResult = null;
    });
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable(
                'sendOutreachBatch',
                options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 300)),
              )
              .call({
        'region': _campaignRegion,
        'businessType':
            _campaignType == '__all__' ? null : _campaignType,
        'maxEmails': 50,
        'dryRun': false,
      });
      if (!mounted) return;
      setState(() {
        _campaignSendResult =
            Map<String, dynamic>.from(result.data as Map);
        _campaignPreview = null; // dopo l'invio i candidati sono stati ridotti
      });
      _snack(
        'Campagna inviata: ${_campaignSendResult!['sent']} email',
        error: false,
      );
    } catch (e) {
      _snack('Errore invio campagna: $e', error: true);
    } finally {
      if (mounted) setState(() => _campaignBusy = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // NEWSLETTER UTENTI (service update v2.5.1+)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Email di aggiornamento prodotto a tutti gli utenti registrati.
  // Base legale: legittimo interesse art. 6.1.f GDPR (vedi privacy.html).
  // Backend: previewNewsletterBatch + sendNewsletterBatch + unsubscribeNewsletter.

  Widget _buildNewsletterSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_outlined,
                    color: Colors.purple.shade400, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Newsletter utenti (service update)',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Email informativa sulle novità del prodotto a tutti gli utenti '
              'registrati (emailVerified). Skip automatico di chi ha fatto '
              'opt-out o è già stato contattato per questa campagna. Base '
              'legale: legittimo interesse art. 6.1.f GDPR. Cap di sicurezza '
              'configurabile.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            // ─── Email di prova ─────────────────────────────────────
            // Manda l'email rendering completo a un singolo indirizzo,
            // bypassando Auth/dedup. Utile per controllare aspetto e
            // deliverability prima del rollout.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.purple.shade200.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Email di prova',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.purple.shade700),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Invia il template a un indirizzo specifico per '
                    'controllare il rendering. Subject prefissato con [TEST]. '
                    'Non legge Auth, non aggiorna user_profiles, non blocca i batch.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newsletterTestEmailCtrl,
                          enabled: !_newsletterBusy,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'tua@email.com',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _newsletterBusy ? null : _sendTestNewsletter,
                        icon: const Icon(Icons.outgoing_mail, size: 18),
                        label: const Text('Invia prova'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.purple.shade700,
                          side: BorderSide(color: Colors.purple.shade300),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newsletterCampaignIdCtrl,
              enabled: !_newsletterBusy,
              decoration: const InputDecoration(
                labelText: 'Campaign ID',
                helperText:
                    'ID univoco campagna (es. "v2.5.1-launch"). Usato per dedup: '
                    'gli utenti con questo ID già impostato vengono skippati.',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newsletterSubjectCtrl,
              enabled: !_newsletterBusy,
              decoration: const InputDecoration(
                labelText: 'Oggetto email',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newsletterMaxEmailsCtrl,
              enabled: !_newsletterBusy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max email per batch',
                helperText: 'Default 50, max 500. Riesegui per fare i batch successivi.',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _newsletterBusy ? null : _previewNewsletter,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('Preview destinatari'),
                ),
                OutlinedButton.icon(
                  onPressed: (_newsletterBusy || _newsletterPreview == null)
                      ? null
                      : () => _sendNewsletter(dryRun: true),
                  icon: const Icon(Icons.science_outlined, size: 18),
                  label: const Text('Dry-run'),
                ),
                FilledButton.icon(
                  onPressed: (_newsletterBusy || _newsletterPreview == null)
                      ? null
                      : _confirmSendNewsletter,
                  icon: _newsletterBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send, size: 18),
                  label: Text(_newsletterBusy ? 'Invio...' : 'Invia batch'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.purple.shade400,
                  ),
                ),
              ],
            ),
            if (_newsletterPreview != null) ...[
              const SizedBox(height: 16),
              _buildNewsletterPreviewBlock(_newsletterPreview!),
            ],
            if (_newsletterSendResult != null) ...[
              const SizedBox(height: 16),
              _buildNewsletterSendResultBlock(_newsletterSendResult!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNewsletterPreviewBlock(Map<String, dynamic> r) {
    final total = r['totalAuthUsers'] ?? 0;
    final eligible = r['eligible'] ?? 0;
    final skipped = (r['skipped'] as Map?) ?? const {};
    final samples = (r['samples'] as List?) ?? const [];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Destinatari eleggibili: $eligible (su $total totali Auth)',
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Skippati: no-email=${skipped['noEmail'] ?? 0} · '
            'opt-out=${skipped['optOut'] ?? 0} · '
            'già-inviata=${skipped['alreadySent'] ?? 0} · '
            'disabled=${skipped['disabled'] ?? 0}',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textMuted),
          ),
          if (samples.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Primi 5 sample:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted),
            ),
            ...samples.map((s) {
              final m = Map<String, dynamic>.from(s as Map);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${m['displayName'] ?? "(nessun nome)"} → ${m['email']}',
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildNewsletterSendResultBlock(Map<String, dynamic> r) {
    final sent = r['sent'] ?? 0;
    final skipped = r['skipped'] ?? 0;
    final errors = (r['errors'] as List?) ?? const [];
    final dryRun = r['dryRun'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dryRun
                ? 'Dry-run completato: $sent email simulate (skippati $skipped)'
                : 'Invio completato: $sent email accodate (skippati $skipped)',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700),
          ),
          if (errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Errori: ${errors.length}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Trigger Email Extension manda le email via SendGrid in pochi '
            'secondi. Stato real-time in Firestore → collection mail/.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _previewNewsletter() async {
    final cid = _newsletterCampaignIdCtrl.text.trim();
    if (cid.isEmpty) {
      _snack('Inserisci un Campaign ID.', error: true);
      return;
    }
    setState(() {
      _newsletterBusy = true;
      _newsletterPreview = null;
      _newsletterSendResult = null;
    });
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable('previewNewsletterBatch')
              .call({'campaignId': cid});
      if (!mounted) return;
      setState(() => _newsletterPreview =
          Map<String, dynamic>.from(result.data as Map));
    } catch (e) {
      _snack('Errore preview newsletter: $e', error: true);
    } finally {
      if (mounted) setState(() => _newsletterBusy = false);
    }
  }

  Future<void> _sendNewsletter({required bool dryRun}) async {
    final cid = _newsletterCampaignIdCtrl.text.trim();
    final subject = _newsletterSubjectCtrl.text.trim();
    final maxEmails = int.tryParse(_newsletterMaxEmailsCtrl.text.trim()) ?? 50;
    if (cid.isEmpty) {
      _snack('Campaign ID mancante.', error: true);
      return;
    }
    setState(() {
      _newsletterBusy = true;
      _newsletterSendResult = null;
    });
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable(
                'sendNewsletterBatch',
                options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 540)),
              )
              .call({
        'campaignId': cid,
        'subject': subject.isEmpty ? null : subject,
        'maxEmails': maxEmails,
        'dryRun': dryRun,
      });
      if (!mounted) return;
      setState(() {
        _newsletterSendResult =
            Map<String, dynamic>.from(result.data as Map);
      });
      _snack(
        dryRun
            ? 'Dry-run: ${_newsletterSendResult!['sent']} email simulate'
            : 'Inviate: ${_newsletterSendResult!['sent']} email',
        error: false,
      );
    } catch (e) {
      _snack('Errore invio newsletter: $e', error: true);
    } finally {
      if (mounted) setState(() => _newsletterBusy = false);
    }
  }

  Future<void> _sendTestNewsletter() async {
    final email = _newsletterTestEmailCtrl.text.trim();
    final cid = _newsletterCampaignIdCtrl.text.trim();
    final subject = _newsletterSubjectCtrl.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      _snack('Inserisci una email valida.', error: true);
      return;
    }
    if (cid.isEmpty) {
      _snack('Campaign ID mancante.', error: true);
      return;
    }
    setState(() => _newsletterBusy = true);
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable('sendNewsletterBatch')
              .call({
        'campaignId': cid,
        'subject': subject.isEmpty ? null : subject,
        'testEmail': email,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['sent'] == 1) {
        _snack('Email di prova inviata a $email', error: false);
      } else {
        _snack('Esito inatteso: ${data.toString()}', error: true);
      }
    } catch (e) {
      _snack('Errore invio prova: $e', error: true);
    } finally {
      if (mounted) setState(() => _newsletterBusy = false);
    }
  }

  Future<void> _confirmSendNewsletter() async {
    final eligible = _newsletterPreview?['eligible'] ?? 0;
    if (eligible == 0) {
      _snack('Nessun destinatario eleggibile.', error: true);
      return;
    }
    final maxEmails = int.tryParse(_newsletterMaxEmailsCtrl.text.trim()) ?? 50;
    final toSend = eligible > maxEmails ? maxEmails : eligible;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confermi invio newsletter?'),
        content: Text(
          'Sto per inviare $toSend email agli utenti registrati '
          '(su $eligible eleggibili). Ogni email contiene il link di '
          'disiscrizione individuale. Gli utenti contattati saranno '
          'marcati per la campagna "${_newsletterCampaignIdCtrl.text.trim()}" '
          'e non più ricontattati con lo stesso ID.\n\n'
          'Procedere?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.purple.shade400),
            child: const Text('Invia'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _sendNewsletter(dryRun: false);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TERRAIN ENRICHMENT — Surface profile public_trails (K1b)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Lancia le Cloud Function di arricchimento OSM tag per i sentieri
  // pubblici (Waymarked Trails). Pre-elabora terrainSegments
  // denormalizzati per ogni public_trail_geometries.

  Widget _buildTerrainEnrichmentSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.landscape_outlined,
                    color: Colors.brown.shade400, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Terrain enrichment (K1b)',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pre-elabora i tag OSM way per ogni public_trail e salva un '
              'array di TerrainSegment denormalizzato in '
              'public_trail_geometries. Permette di colorare la mappa per '
              'tipo terreno (asfalto/sterrato/sentiero/roccia/ferrata) '
              'senza chiamate Overpass dal client.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),

            // ─── Test su singolo trail ──────────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.brown.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.brown.shade200.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Test singolo trail',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.brown.shade700),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Trail ID del formato wmt_relation_<numero>. '
                    'Prima fai dry-run per controllare l\'output, poi '
                    'esegui senza dryRun per scrivere su Firestore.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _terrainTrailIdCtrl,
                    enabled: !_terrainBusy,
                    decoration: const InputDecoration(
                      hintText: 'es. wmt_relation_12345678',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _terrainBusy
                            ? null
                            : () => _enrichSingleTrail(dryRun: true),
                        icon: const Icon(Icons.science_outlined, size: 16),
                        label: const Text('Dry-run',
                            style: TextStyle(fontSize: 12)),
                      ),
                      FilledButton.icon(
                        onPressed: _terrainBusy
                            ? null
                            : () => _enrichSingleTrail(dryRun: false),
                        icon: const Icon(Icons.upload, size: 16),
                        label: const Text('Arricchisci',
                            style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.brown.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ─── Batch tutti i trails ───────────────────────────────
            Text(
              'Batch enrichment',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _terrainMaxTrailsCtrl,
              enabled: !_terrainBusy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max trails per batch',
                helperText:
                    'Default 20, max 200. Skippa automaticamente i trail '
                    'già arricchiti (terrainEnrichedAt). Rate limit 1.1s/trail '
                    'per Overpass: 200 trail = ~4 min.',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: _terrainBusy
                      ? null
                      : () => _enrichBatch(dryRun: true),
                  icon: const Icon(Icons.science_outlined, size: 16),
                  label: const Text('Dry-run batch',
                      style: TextStyle(fontSize: 12)),
                ),
                FilledButton.icon(
                  onPressed: _terrainBusy
                      ? null
                      : () => _enrichBatch(dryRun: false),
                  icon: _terrainBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.batch_prediction, size: 16),
                  label: Text(_terrainBusy ? 'Lavoro...' : 'Esegui batch',
                      style: const TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.brown.shade600,
                  ),
                ),
              ],
            ),

            if (_terrainResult != null) ...[
              const SizedBox(height: 12),
              _buildTerrainResultBlock(_terrainResult!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTerrainResultBlock(Map<String, dynamic> r) {
    final isBatch = r.containsKey('processed');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isBatch ? 'Batch completato' : 'Trail elaborato',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          if (isBatch) ...[
            Text(
              'Processed: ${r['processed']} · '
              'Enriched: ${r['enriched']} · '
              'Skipped: ${r['skipped']} · '
              'Errors: ${(r['errors'] as List?)?.length ?? 0}',
              style: const TextStyle(fontSize: 11),
            ),
            if ((r['samples'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              const Text('Primi sample:',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted)),
              for (final s in (r['samples'] as List).cast<Map>())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    '• ${s['trailId']}: ${s['segments']} segmenti · '
                    '${(s['types'] as List?)?.join(',') ?? '—'}',
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ] else ...[
            Text(
              'Trail: ${r['trailId']} · '
              'Punti: ${r['totalPoints']} · '
              'Ways analizzate: ${r['waysAnalyzed']} · '
              'Segmenti: ${r['segmentCount']}',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              'Tipi terreno trovati: '
              '${(r['typesFound'] as List?)?.join(', ') ?? '—'}',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
          if (r['dryRun'] == true) ...[
            const SizedBox(height: 4),
            const Text(
              '⚠️ Modalità dry-run: nessuna scrittura su Firestore.',
              style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _enrichSingleTrail({required bool dryRun}) async {
    final trailId = _terrainTrailIdCtrl.text.trim();
    if (trailId.isEmpty) {
      _snack('Inserisci un trail ID.', error: true);
      return;
    }
    setState(() {
      _terrainBusy = true;
      _terrainResult = null;
    });
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable(
                'enrichTrailWithTerrain',
                options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 120)),
              )
              .call({'trailId': trailId, 'dryRun': dryRun});
      if (!mounted) return;
      final data = Map<String, dynamic>.from(result.data as Map);
      setState(() => _terrainResult = data);
      if (data['success'] == true) {
        _snack(
          dryRun
              ? 'Dry-run completato: ${data['segmentCount']} segmenti'
              : 'Trail arricchito: ${data['segmentCount']} segmenti scritti',
          error: false,
        );
      } else {
        _snack('Esito: ${data['reason'] ?? "fail"}', error: true);
      }
    } catch (e) {
      _snack('Errore: $e', error: true);
    } finally {
      if (mounted) setState(() => _terrainBusy = false);
    }
  }

  Future<void> _enrichBatch({required bool dryRun}) async {
    final maxTrails =
        int.tryParse(_terrainMaxTrailsCtrl.text.trim()) ?? 20;
    setState(() {
      _terrainBusy = true;
      _terrainResult = null;
    });
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable(
                'enrichAllTrailsTerrain',
                options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 540)),
              )
              .call({
        'maxTrails': maxTrails,
        'dryRun': dryRun,
        'skipAlreadyEnriched': true,
      });
      if (!mounted) return;
      final data = Map<String, dynamic>.from(result.data as Map);
      setState(() => _terrainResult = data);
      _snack(
        dryRun
            ? 'Dry-run batch: ${data['enriched']}/${data['processed']}'
            : 'Batch: ${data['enriched']} arricchiti, '
                '${data['skipped']} skip',
        error: false,
      );
    } catch (e) {
      _snack('Errore batch: $e', error: true);
    } finally {
      if (mounted) setState(() => _terrainBusy = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // QUALITY FLAGS (Epic 7.H11)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Segnalazioni community su schede unclaimed con info errate
  // (chiusa, posizione sbagliata, duplicato, ecc). Admin marca come
  // risolto o ignorato.

  Widget _buildQualityFlagsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined,
                    color: Colors.red.shade400, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Flag qualità da revisionare',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Segnalazioni utenti su info errate, schede duplicate, '
              'chiusure. Verifica e marca risolto o ignora.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('business_quality_flags')
                  .where('status', isEqualTo: 'pending')
                  .orderBy('createdAt', descending: true)
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
                      'Nessun flag pendente.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                  );
                }
                return Column(
                  children: docs
                      .map((d) => _QualityFlagTile(
                            flagId: d.id,
                            data: d.data(),
                            onResolve: () => _resolveQualityFlag(
                                d.id, 'resolved'),
                            onIgnore: () => _resolveQualityFlag(
                                d.id, 'ignored'),
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

  Future<void> _resolveQualityFlag(String flagId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('business_quality_flags')
          .doc(flagId)
          .update({
        'status': status,
        'processedAt': FieldValue.serverTimestamp(),
        'processedByUid': FirebaseAuth.instance.currentUser?.uid,
      });
      _snack(
        status == 'resolved'
            ? 'Flag marcato come risolto'
            : 'Flag ignorato',
        error: false,
      );
    } catch (e) {
      _snack('Errore: $e', error: true);
    }
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
  final VoidCallback onOpenOutreach;

  const _PendingClaimTile({
    required this.businessId,
    required this.data,
    required this.onGenerate,
    required this.onOpenOutreach,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name']?.toString() ?? '—';
    final city = (data['location'] is Map)
        ? (data['location']['city']?.toString() ?? '')
        : '';
    final email = (data['contacts'] is Map)
        ? (data['contacts']['email']?.toString())
        : null;
    // outreach status badge
    final sentAt = data['outreachEmailSentAt'];
    final outreachStatus = data['outreachStatus']?.toString();
    Widget? statusBadge;
    if (sentAt != null) {
      // Calcola "X giorni fa" dal Timestamp Firestore
      DateTime? sentDate;
      if (sentAt is Timestamp) {
        sentDate = sentAt.toDate();
      }
      final daysAgo = sentDate != null
          ? DateTime.now().difference(sentDate).inDays
          : 0;
      final stale = daysAgo >= 7;
      statusBadge = _statusPill(
        icon: Icons.mark_email_read_outlined,
        label: daysAgo == 0
            ? 'Email inviata oggi'
            : daysAgo == 1
                ? 'Email inviata ieri'
                : 'Email inviata ${daysAgo}gg fa',
        color: stale ? AppColors.warning : AppColors.info,
        tooltip: stale
            ? 'Più di 7 giorni senza claim — considera follow-up manuale'
            : 'Email outreach automatica inviata. In attesa di click sul link Rivendica.',
      );
    } else {
      statusBadge = _statusPill(
        icon: Icons.person_add_outlined,
        label: 'Manuale',
        color: AppColors.primary,
        tooltip: 'Scheda creata manualmente dal team. Genera link self-claim per inviarlo via WhatsApp.',
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      [
                        if (city.isNotEmpty) city,
                        if (email != null) email,
                        businessId,
                      ].join('  ·  '),
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
              Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    onPressed: onOpenOutreach,
                    tooltip: 'Apri Outreach PDF',
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                  TextButton.icon(
                    onPressed: onGenerate,
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Genera link'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              statusBadge,
              if (outreachStatus != null &&
                  outreachStatus != 'sent' &&
                  outreachStatus != 'pending') ...[
                const SizedBox(width: 6),
                _statusPill(
                  icon: outreachStatus == 'replied'
                      ? Icons.reply
                      : outreachStatus == 'bounced'
                          ? Icons.error_outline
                          : Icons.info_outline,
                  label: outreachStatus,
                  color: outreachStatus == 'replied'
                      ? AppColors.success
                      : outreachStatus == 'bounced'
                          ? AppColors.danger
                          : AppColors.textMuted,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill({
    required IconData icon,
    required String label,
    required Color color,
    String? tooltip,
  }) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
    if (tooltip == null) return pill;
    return Tooltip(message: tooltip, child: pill);
  }
}

/// Riga di una claim request pendente nella sezione admin
/// "Claim requests in attesa". Mostra preview dati + 2 bottoni
/// (Approva / Rifiuta) che chiamano le Cloud Function.
class _ClaimRequestTile extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ClaimRequestTile({
    required this.requestId,
    required this.data,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final businessName = data['businessName']?.toString() ?? '—';
    final name = data['requesterName']?.toString() ?? '—';
    final role = data['requesterRole']?.toString() ?? '';
    final email = data['requesterEmail']?.toString() ?? '';
    final phone = data['requesterPhone']?.toString() ?? '';
    final vat = data['requesterVat']?.toString() ?? '';
    final website = data['requesterWebsite']?.toString() ?? '';
    final notes = data['notes']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            businessName,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _kv('Richiedente', '$name${role.isNotEmpty ? ' · $role' : ''}'),
          _kv('Email', email),
          if (phone.isNotEmpty) _kv('Telefono', phone),
          if (vat.isNotEmpty) _kv('P.IVA/CF', vat),
          if (website.isNotEmpty) _kv('Sito', website),
          if (notes.isNotEmpty) _kv('Note', notes, maxLines: 4),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Rifiuta'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                ),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approva'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(
              fontSize: 12, color: AppColors.textPrimary),
          children: [
            TextSpan(
              text: '$k: ',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.textMuted),
            ),
            TextSpan(text: v),
          ],
        ),
      ),
    );
  }
}

/// Riga di un flag qualità pendente. Mostra businessName + category +
/// message + reporter + bottoni Risolto / Ignora.
class _QualityFlagTile extends StatelessWidget {
  final String flagId;
  final Map<String, dynamic> data;
  final VoidCallback onResolve;
  final VoidCallback onIgnore;

  const _QualityFlagTile({
    required this.flagId,
    required this.data,
    required this.onResolve,
    required this.onIgnore,
  });

  static const _categoryLabels = <String, String>{
    'closed': 'Chiusa / inattiva',
    'wrong_location': 'Posizione sbagliata',
    'wrong_name': 'Nome o dati sbagliati',
    'duplicate': 'Duplicato',
    'owner_opt_out': 'Richiesta rimozione gestore',
    'other': 'Altro',
  };

  @override
  Widget build(BuildContext context) {
    final businessName = data['businessName']?.toString() ?? '—';
    final businessId = data['businessId']?.toString() ?? '';
    final categoryKey = data['category']?.toString() ?? 'other';
    final categoryLabel = _categoryLabels[categoryKey] ?? categoryKey;
    final message = data['message']?.toString() ?? '';
    final reporter = data['reporterUid']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  businessName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  categoryLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.textPrimary,
              ),
              maxLines: 3,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'businessId: $businessId  ·  reporter: $reporter  ·  flagId: $flagId',
            style: const TextStyle(
                fontSize: 10, color: AppColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onIgnore,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Ignora'),
                ),
                FilledButton.icon(
                  onPressed: onResolve,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Risolto'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
