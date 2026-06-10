import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/business.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/business_repository.dart';
import '../../presentation/pages/business/business_create_page.dart';
import 'web_business_dashboard_page.dart';
import 'web_ai_drafts_review_page.dart';

/// Lista degli Spazi Pro di cui l'utente è owner. Se ne ha 1, redirige
/// direttamente alla dashboard. Se più, picker. Se zero, CTA "Contatta
/// l'admin per attivare il tuo Spazio Pro" + pulsante admin (se admin
/// loggato).
class WebBusinessPickerPage extends StatefulWidget {
  const WebBusinessPickerPage({super.key});

  @override
  State<WebBusinessPickerPage> createState() => _WebBusinessPickerPageState();
}

class _WebBusinessPickerPageState extends State<WebBusinessPickerPage> {
  final _repo = BusinessRepository();
  final _searchCtrl = TextEditingController();

  // L'utente loggato è admin? Caricato async al mount. Default false
  // mantiene il bottone "Crea Spazio Pro" NASCOSTO finché non sappiamo
  // (fail-closed): meglio che il bottone appaia tardi piuttosto che
  // mostrarlo a chiunque per uno stutter di Firestore.
  bool _isAdmin = false;
  String _searchQuery = '';
  BusinessTier? _filterTier;
  BusinessType? _filterType;
  String? _filterRegion;

  // Stream Firestore memoizzato: senza questa cache, build() veniva
  // chiamato ad ogni keystroke della search bar (setState) e ricreava
  // un NUOVO oggetto Stream → StreamBuilder ri-subscribeva → re-fetch
  // Firestore + perdita focus textfield. Memoizziamo dopo il check
  // admin.
  Stream<List<Business>>? _businessesStream;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAdmin();
  }

  Future<void> _loadAdmin() async {
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
      // Memoizza lo stream UNA VOLTA in base al ruolo. I successivi
      // rebuild (search bar, filtri) riusano lo stesso oggetto Stream.
      _businessesStream = isAdmin
          ? _repo.watchAllBusinesses()
          : _repo.watchMyBusinesses();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Aspetta che _loadAdmin abbia inizializzato _businessesStream
    // (Admin platform → watchAllBusinesses, owner → watchMyBusinesses).
    final stream = _businessesStream;
    if (stream == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<Business>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final businesses = snap.data ?? [];
        if (businesses.isEmpty) return _buildEmpty();
        return _buildList(businesses);
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront,
                  size: 64, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text(
                'Nessuno Spazio Pro',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isAdmin
                    ? 'Non sei ancora owner di uno Spazio Pro. Puoi '
                        'crearne uno tu stesso, oppure assegnarne uno '
                        'esistente a un cliente.'
                    : 'Non sei ancora owner di uno Spazio Pro. '
                        'Contatta info@trailshare.app per attivare '
                        'la tua vetrina.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              // Bottone "Crea Spazio Pro" visibile SOLO agli admin.
              // Le Firestore rules bloccano comunque la create da non-
              // admin, ma mostrare il bottone a tutti era UX falsa
              // promessa (l'utente compilava il form e poi scopriva
              // permission-denied al submit).
              if (_isAdmin)
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BusinessCreatePage(),
                    ),
                  ),
                  icon: const Icon(Icons.add_business),
                  label: const Text('Crea Spazio Pro'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<Business> businesses) {
    // Regioni distinte presenti (per il filtro a tendina), ordinate.
    final regions = businesses
        .map((b) => b.location.region)
        .whereType<String>()
        .where((r) => r.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Filtri in-memory: search (nome + città) + tier + tipo + regione.
    Iterable<Business> filtered = businesses;
    if (_filterTier != null) {
      filtered = filtered.where((b) => b.tier == _filterTier);
    }
    if (_filterType != null) {
      filtered = filtered.where((b) => b.type == _filterType);
    }
    if (_filterRegion != null) {
      filtered = filtered.where((b) => b.location.region == _filterRegion);
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((b) =>
          b.name.toLowerCase().contains(q) ||
          (b.location.city?.toLowerCase().contains(q) ?? false));
    }
    final list = filtered.toList();

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _isAdmin ? 'Tutti gli Spazi Pro' : 'I tuoi Spazi Pro',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${list.length} / ${businesses.length}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          // Controlli ricerca + filtro visibili solo a admin (per owner
          // singolo non servono — di solito ha 1-3 schede).
          if (_isAdmin) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cerca per nome o città…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<BusinessTier?>(
                  value: _filterTier,
                  hint: const Text('Tutti i tier'),
                  items: [
                    const DropdownMenuItem<BusinessTier?>(
                      value: null,
                      child: Text('Tutti i tier'),
                    ),
                    ...BusinessTier.values.map(
                      (t) => DropdownMenuItem<BusinessTier?>(
                        value: t,
                        child: Text(t.displayName),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filterTier = v),
                ),
                DropdownButton<BusinessType?>(
                  value: _filterType,
                  hint: const Text('Tutti i tipi'),
                  items: [
                    const DropdownMenuItem<BusinessType?>(
                      value: null,
                      child: Text('Tutti i tipi'),
                    ),
                    ...BusinessType.values.map(
                      (t) => DropdownMenuItem<BusinessType?>(
                        value: t,
                        child: Text(t.displayName),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filterType = v),
                ),
                DropdownButton<String?>(
                  value: (_filterRegion != null &&
                          regions.contains(_filterRegion))
                      ? _filterRegion
                      : null,
                  hint: const Text('Tutte le regioni'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tutte le regioni'),
                    ),
                    ...regions.map(
                      (r) => DropdownMenuItem<String?>(
                        value: r,
                        child: Text(r),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filterRegion = v),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WebAiDraftsReviewPage(),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Bozze AI'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      'Nessun risultato per i filtri attivi',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : GridView.count(
                    crossAxisCount: 3,
                    childAspectRatio: 1.4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: list
                        .map((b) => _BusinessTile(
                              business: b,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WebBusinessDashboardPage(
                                      businessId: b.id!),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BusinessTile extends StatelessWidget {
  final Business business;
  final VoidCallback onTap;
  const _BusinessTile({required this.business, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = business;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: b.branding.heroPhotoUrl != null
                  ? CachedNetworkImage(
                      imageUrl: b.branding.heroPhotoUrl!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      alignment: Alignment.center,
                      child: Text(b.type.icon,
                          style: const TextStyle(fontSize: 56)),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(b.type.displayName,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                      const Spacer(),
                      Text('${b.followerCount} follower',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
