import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/business.dart';
import '../../data/repositories/business_repository.dart';
import '../../presentation/pages/business/business_edit_page.dart';
import '../../presentation/pages/business/business_post_composer_page.dart';
import '../../presentation/pages/business/business_profile_page.dart';
import '../../presentation/pages/business/business_services_manager_page.dart';

/// Dashboard web del singolo Spazio Pro: panoramica + azioni rapide.
/// Le azioni di edit/post/listino aprono le pagine mobile in dialog
/// (riuso codice). Su desktop appaiono in dialog centrati con larghezza
/// massima limitata.
class WebBusinessDashboardPage extends StatefulWidget {
  final String businessId;
  const WebBusinessDashboardPage({super.key, required this.businessId});

  @override
  State<WebBusinessDashboardPage> createState() =>
      _WebBusinessDashboardPageState();
}

class _WebBusinessDashboardPageState extends State<WebBusinessDashboardPage> {
  final _repo = BusinessRepository();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Business?>(
      stream: _repo.watchBusiness(widget.businessId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final business = snap.data;
        if (business == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Spazio Pro non trovato')),
          );
        }
        return _build(business);
      },
    );
  }

  Widget _build(Business b) {
    return Scaffold(
      appBar: AppBar(
        title: Text(b.name),
        actions: [
          OutlinedButton.icon(
            onPressed: () => _openInDialog(
              BusinessProfilePage(businessId: b.id!),
            ),
            icon: const Icon(Icons.preview),
            label: const Text('Anteprima profilo'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildHero(b),
              const SizedBox(height: 24),
              _buildStatsRow(b),
              const SizedBox(height: 24),
              _buildQuickActions(b),
              const SizedBox(height: 24),
              _buildIdentitySection(b),
            ],
          ),
        ),
      ),
    );
  }

  // ─── HERO ────────────────────────────────────────────────────────────
  Widget _buildHero(Business b) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.primary.withValues(alpha: 0.1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (b.branding.heroPhotoUrl != null)
            CachedNetworkImage(
              imageUrl: b.branding.heroPhotoUrl!,
              fit: BoxFit.cover,
            )
          else
            Center(
              child: Text(b.type.icon,
                  style: const TextStyle(fontSize: 100)),
            ),
          // Gradient overlay per leggibilità testo
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            bottom: 20,
            right: 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (b.branding.logoUrl != null)
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CachedNetworkImage(
                      imageUrl: b.branding.logoUrl!,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (b.branding.logoUrl != null) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(blurRadius: 8, color: Colors.black54),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _Pill(b.type.displayName, color: Colors.white24),
                          const SizedBox(width: 8),
                          _Pill('★ ${b.tier.displayName}',
                              color: Colors.white24),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── STATS ───────────────────────────────────────────────────────────
  Widget _buildStatsRow(Business b) {
    return Row(
      children: [
        _StatCard(
          icon: Icons.people,
          label: 'Follower',
          value: '${b.followerCount}',
        ),
        const SizedBox(width: 12),
        _StatCard(
          icon: Icons.post_add,
          label: 'Aggiornamenti',
          value: '${b.postsCount}',
        ),
        const SizedBox(width: 12),
        _StatCard(
          icon: Icons.star_outline,
          label: 'Rating',
          value: b.rating != null
              ? '${b.rating!.toStringAsFixed(1)} (${b.reviewCount})'
              : '—',
        ),
        const SizedBox(width: 12),
        _StatCard(
          icon: Icons.photo_library,
          label: 'Galleria',
          value: '${b.branding.galleryUrls.length}',
        ),
      ],
    );
  }

  // ─── QUICK ACTIONS ──────────────────────────────────────────────────
  Widget _buildQuickActions(Business b) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gestione',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ActionButton(
                  icon: Icons.post_add,
                  label: 'Nuovo aggiornamento',
                  primary: true,
                  onTap: () => _openInDialog(
                    BusinessPostComposerPage(businessId: b.id!),
                  ),
                ),
                _ActionButton(
                  icon: Icons.list_alt,
                  label: 'Listino servizi',
                  onTap: () => _openInDialog(
                    BusinessServicesManagerPage(businessId: b.id!),
                  ),
                ),
                _ActionButton(
                  icon: Icons.edit,
                  label: 'Modifica profilo',
                  onTap: () => _openInDialog(
                    BusinessEditPage(businessId: b.id!),
                  ),
                ),
                _ActionButton(
                  icon: Icons.preview,
                  label: 'Anteprima pubblica',
                  onTap: () => _openInDialog(
                    BusinessProfilePage(businessId: b.id!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── IDENTITÀ (riepilogo dati base) ──────────────────────────────────
  Widget _buildIdentitySection(Business b) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Riepilogo profilo',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _row('Slug pubblico',
                'trailshare.app/b/${b.slug}', copyable: true),
            _row(
              'Posizione',
              '${b.location.lat.toStringAsFixed(4)}, ${b.location.lng.toStringAsFixed(4)}',
            ),
            if (b.location.city != null) _row('Città', b.location.city!),
            if (b.location.address != null)
              _row('Indirizzo', b.location.address!),
            if (b.contacts.phone != null) _row('Telefono', b.contacts.phone!),
            if (b.contacts.whatsapp != null)
              _row('WhatsApp', b.contacts.whatsapp!),
            if (b.contacts.email != null) _row('Email', b.contacts.email!),
            if (b.contacts.website != null) _row('Sito', b.contacts.website!),
            _row('Stato', b.status.name.toUpperCase()),
            _row('Tier', b.tier.displayName),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────
  void _openInDialog(Widget child) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 720,
          height: 720,
          child: child,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill(this.label, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500)),
    );
  }
}
