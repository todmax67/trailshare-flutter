import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/business.dart';
import '../../data/repositories/admin_repository.dart';
import '../../data/repositories/business_repository.dart';
import '../../presentation/pages/business/business_analytics_page.dart';
import '../../presentation/pages/business/business_edit_page.dart';
import '../../presentation/pages/business/business_post_composer_page.dart';
import '../../presentation/pages/business/business_profile_page.dart';
import '../../presentation/pages/business/business_qr_card_page.dart';
import '../../presentation/pages/business/business_services_manager_page.dart';
import 'web_home_page.dart';

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
  bool _isPlatformAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadAdminFlag();
  }

  Future<void> _loadAdminFlag() async {
    final isAdmin = await AdminRepository.isCurrentUserAdmin();
    if (mounted) setState(() => _isPlatformAdmin = isAdmin);
  }

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Torna a Spazi Pro',
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              // Deep link diretto /business/{id}: rimanda al picker
              // ricostruendo lo shell con sidebar.
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const WebHomePage(initialTab: 4),
                ),
              );
            }
          },
        ),
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
              if (_isPlatformAdmin) ...[
                const SizedBox(height: 24),
                _buildAdminToolsSection(b),
              ],
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
                  icon: Icons.analytics_outlined,
                  label: 'Statistiche',
                  onTap: () => _openInDialog(
                    BusinessAnalyticsPage(business: b),
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
                _ActionButton(
                  icon: Icons.qr_code_2,
                  label: 'Vetrina QR',
                  onTap: () => _openInDialog(
                    BusinessQrCardPage(business: b),
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

  // ─── ADMIN TOOLS (solo platform admin) ──────────────────────────────
  Widget _buildAdminToolsSection(Business b) {
    return Card(
      color: AppColors.warning.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    color: Colors.amber.shade800, size: 22),
                const SizedBox(width: 8),
                const Text('Admin tools',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Operazioni privilegiate sul doc business. Disponibili '
              'solo per platform admin TrailShare.',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            // Owner attuale (utile per sapere chi sostituisci)
            _row('Business ID', b.id ?? '—', copyable: true),
            _row('Owner UID (attuale)', b.ownerId, copyable: true),
            if (b.adminUserIds.isNotEmpty)
              _row('Co-admin', b.adminUserIds.join(', ')),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _showTransferOwnershipDialog(b),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Trasferisci ownership'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.warning,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showAddCoAdminDialog(b),
                  icon: const Icon(Icons.group_add, size: 18),
                  label: const Text('Aggiungi co-admin'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _confirmAndDelete(b),
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('Elimina Spazio Pro'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(
                        color: AppColors.danger.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Eliminazione definitiva di uno Spazio Pro (solo platform admin).
  /// Conferma type-to-confirm: l'admin deve riscrivere il nome esatto.
  /// Nota: cancella il doc business; eventuali sotto-collezioni (post,
  /// recensioni, follower) restano orfane ma non più accessibili.
  Future<void> _confirmAndDelete(Business b) async {
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final matches = confirmCtrl.text.trim() == b.name.trim();
            return AlertDialog(
              title: const Text('Elimina Spazio Pro'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stai per eliminare definitivamente "${b.name}". '
                    'L\'operazione NON è reversibile: la scheda sparirà da '
                    'app e web. Foto e recensioni collegate restano orfane '
                    '(non più accessibili).',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Per confermare, riscrivi il nome esatto della scheda:',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: b.name,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed:
                      matches ? () => Navigator.pop(ctx, true) : null,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger),
                  child: const Text('Elimina definitivamente'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    try {
      await _repo.deleteBusiness(b.id!);
      if (!mounted) return;
      _snack('Spazio Pro "${b.name}" eliminato', error: false);
      // La dashboard non ha più nulla da mostrare: torna al picker.
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const WebHomePage(initialTab: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) _snack('Errore eliminazione: $e', error: true);
    }
  }

  Future<void> _showTransferOwnershipDialog(Business b) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trasferisci ownership'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Il vecchio owner (${b.ownerId}) verrà spostato in '
              'co-admin per non perdere accesso. Il nuovo owner '
              'diventa autonomo nella gestione.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'UID nuovo owner',
                hintText: 'Es. abc123xyz... (Firebase Auth UID)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Lo trovi su Firebase Console → Authentication → '
              'cerca per email → copia UID.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trasferisci'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newOwner = ctrl.text.trim();
    if (newOwner.isEmpty) return;
    if (newOwner == b.ownerId) {
      _snack('Il nuovo owner è uguale a quello attuale. Niente da fare.',
          error: true);
      return;
    }
    try {
      final newAdmins = {
        ...b.adminUserIds.where((id) => id != newOwner),
        b.ownerId,
      }.toList();
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(b.id)
          .update({
        'ownerId': newOwner,
        'adminUserIds': newAdmins,
        'claimedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'pendingSelfManagement': false,
      });
      _snack('Ownership trasferita a $newOwner', error: false);
    } catch (e) {
      _snack('Errore: $e', error: true);
    }
  }

  Future<void> _showAddCoAdminDialog(Business b) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aggiungi co-admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Un co-admin può editare la scheda come l\'owner ma non '
              'può rimuoverlo o trasferire ownership.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'UID co-admin',
                border: OutlineInputBorder(),
                isDense: true,
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newAdmin = ctrl.text.trim();
    if (newAdmin.isEmpty) return;
    if (newAdmin == b.ownerId || b.adminUserIds.contains(newAdmin)) {
      _snack('Già owner o co-admin.', error: true);
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(b.id)
          .update({
        'adminUserIds': FieldValue.arrayUnion([newAdmin]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _snack('Co-admin aggiunto.', error: false);
    } catch (e) {
      _snack('Errore: $e', error: true);
    }
  }

  void _snack(String msg, {required bool error}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : AppColors.success,
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
