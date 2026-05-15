import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/business.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/business_repository.dart';
import '../../presentation/pages/business/business_create_page.dart';
import 'web_business_dashboard_page.dart';

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
  // L'utente loggato è admin? Caricato async al mount. Default false
  // mantiene il bottone "Crea Spazio Pro" NASCOSTO finché non sappiamo
  // (fail-closed): meglio che il bottone appaia tardi piuttosto che
  // mostrarlo a chiunque per uno stutter di Firestore.
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadAdmin();
  }

  Future<void> _loadAdmin() async {
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    if (mounted) setState(() => _isAdmin = isAdmin);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Business>>(
      stream: _repo.watchMyBusinesses(),
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
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('I tuoi Spazi Pro',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 1.4,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: businesses
                  .map((b) => _BusinessTile(
                        business: b,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                WebBusinessDashboardPage(businessId: b.id!),
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
