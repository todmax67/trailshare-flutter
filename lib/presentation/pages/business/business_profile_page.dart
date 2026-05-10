import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/business_repository.dart';
import 'business_edit_page.dart';
import 'business_post_composer_page.dart';
import 'business_services_manager_page.dart';

/// Profilo pubblico di uno Spazio Pro (rifugio, noleggio, guida, ecc).
/// Visualizza:
/// - Hero photo + logo + nome + badge tier + tipo
/// - Bottoni follow / contatti / direzioni
/// - Description
/// - Mini mappa + indirizzo
/// - Listino (se presente)
/// - Posts (aggiornamenti)
/// - Orari (se presenti)
class BusinessProfilePage extends StatefulWidget {
  final String businessId;
  const BusinessProfilePage({super.key, required this.businessId});

  @override
  State<BusinessProfilePage> createState() => _BusinessProfilePageState();
}

class _BusinessProfilePageState extends State<BusinessProfilePage> {
  final BusinessRepository _repo = BusinessRepository();

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
            appBar: AppBar(),
            body: const Center(child: Text('Spazio Pro non trovato')),
          );
        }
        return _buildContent(business);
      },
    );
  }

  Widget _buildContent(Business b) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isOwner = b.isOwnerOrAdmin(uid);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(b, isOwner),
          SliverList(
            delegate: SliverChildListDelegate([
              _buildHeader(b),
              const Divider(height: 1),
              _buildActions(b),
              const Divider(height: 1),
              if (b.description != null && b.description!.isNotEmpty)
                _buildDescription(b),
              _buildLocation(b),
              if (isOwner) _buildOwnerActions(b),
              _buildServicesPreview(b),
              _buildPostsPreview(b),
              _buildOpeningHours(b),
              const SizedBox(height: 32),
            ]),
          ),
        ],
      ),
    );
  }

  // ─── HEADER (hero + logo + nome) ─────────────────────────────────────────
  Widget _buildAppBar(Business b, bool isOwner) {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: b.branding.heroPhotoUrl != null
            ? CachedNetworkImage(
                imageUrl: b.branding.heroPhotoUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.border),
                errorWidget: (_, __, ___) =>
                    Container(color: AppColors.border),
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.85),
                      AppColors.primaryDark.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: Center(
                  child: Text(b.type.icon,
                      style: const TextStyle(fontSize: 80)),
                ),
              ),
      ),
      actions: [
        if (isOwner)
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Modifica',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BusinessEditPage(businessId: b.id!),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.share),
          tooltip: 'Condividi',
          onPressed: () => _shareProfile(b),
        ),
      ],
    );
  }

  Widget _buildHeader(Business b) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: b.branding.logoUrl != null
                ? CachedNetworkImage(
                    imageUrl: b.branding.logoUrl!,
                    fit: BoxFit.cover,
                  )
                : Center(
                    child: Text(b.type.icon,
                        style: const TextStyle(fontSize: 32)),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Chip(b.type.displayName, color: AppColors.primary),
                    if (b.tier != BusinessTier.verified)
                      _Chip('★ ${b.tier.displayName}',
                          color: AppColors.warning),
                    if (b.followerCount > 0)
                      _Chip(
                        '${b.followerCount} ${b.followerCount == 1 ? "follower" : "followers"}',
                        color: AppColors.info,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── AZIONI: follow / contatti / direzioni ───────────────────────────────
  Widget _buildActions(Business b) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: StreamBuilder<bool>(
              stream: _repo.watchIsFollowing(b.id!),
              builder: (context, snap) {
                final following = snap.data == true;
                return ElevatedButton.icon(
                  onPressed: () async {
                    if (following) {
                      await _repo.unfollow(b.id!);
                    } else {
                      await _repo.follow(b.id!);
                    }
                  },
                  icon: Icon(following ? Icons.check : Icons.add),
                  label: Text(following ? 'Seguito' : 'Segui'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        following ? AppColors.surface : AppColors.primary,
                    foregroundColor:
                        following ? AppColors.primary : Colors.white,
                    side: following
                        ? const BorderSide(color: AppColors.primary)
                        : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          if (b.contacts.whatsapp != null || b.contacts.phone != null)
            IconButton.filledTonal(
              tooltip: 'Contatta',
              icon: Icon(b.contacts.whatsapp != null
                  ? Icons.chat_bubble_outline
                  : Icons.phone),
              onPressed: () => _openContact(b.contacts),
            ),
          IconButton.filledTonal(
            tooltip: 'Indicazioni',
            icon: const Icon(Icons.directions),
            onPressed: () => _openDirections(b),
          ),
        ],
      ),
    );
  }

  void _openContact(BusinessContacts c) {
    final messenger = ScaffoldMessenger.of(context);
    if (c.whatsapp != null) {
      final clean = c.whatsapp!.replaceAll(RegExp(r'[^0-9+]'), '');
      launchUrl(Uri.parse('https://wa.me/$clean'),
          mode: LaunchMode.externalApplication);
    } else if (c.phone != null) {
      launchUrl(Uri.parse('tel:${c.phone}'),
          mode: LaunchMode.externalApplication);
    } else {
      messenger.showSnackBar(
          const SnackBar(content: Text('Nessun contatto disponibile')));
    }
  }

  void _openDirections(Business b) {
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${b.location.lat},${b.location.lng}';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _shareProfile(Business b) {
    // TODO: integrate share_plus quando avremo URL pubblici (es. trailshare.app/b/<slug>)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Condivisione: trailshare.app/b/${b.slug}')),
    );
  }

  // ─── DESCRIPTION ─────────────────────────────────────────────────────────
  Widget _buildDescription(Business b) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Text(
        b.description!,
        style: const TextStyle(fontSize: 14, height: 1.4),
      ),
    );
  }

  // ─── LOCATION + mini mappa ───────────────────────────────────────────────
  Widget _buildLocation(Business b) {
    final pos = LatLng(b.location.lat, b.location.lng);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Dove siamo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (b.location.address != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.location_on,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [b.location.address, b.location.city]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(', '),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 160,
              child: AbsorbPointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: pos,
                    initialZoom: 13,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.trailshare.app',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: pos,
                        width: 40,
                        height: 40,
                        child: Icon(Icons.location_on,
                            color: AppColors.primary, size: 40),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── OWNER ACTIONS (modifica, aggiungi post, gestisci listino) ───────────
  Widget _buildOwnerActions(Business b) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Strumenti owner',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BusinessPostComposerPage(businessId: b.id!),
                  ),
                ),
                icon: const Icon(Icons.post_add),
                label: const Text('Nuovo aggiornamento'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BusinessServicesManagerPage(businessId: b.id!),
                  ),
                ),
                icon: const Icon(Icons.list_alt),
                label: const Text('Listino'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BusinessEditPage(businessId: b.id!),
                  ),
                ),
                icon: const Icon(Icons.settings),
                label: const Text('Profilo'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── SERVIZI / LISTINO (preview top 3) ───────────────────────────────────
  Widget _buildServicesPreview(Business b) {
    return StreamBuilder<List<BusinessService>>(
      stream: _repo.watchServices(b.id!),
      builder: (context, snap) {
        final services =
            snap.data?.where((s) => s.isActive).toList() ?? const [];
        if (services.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Listino',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (services.length > 3)
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BusinessServicesManagerPage(
                              businessId: b.id!, readOnly: true),
                        ),
                      ),
                      child: Text('Tutti (${services.length})'),
                    ),
                ],
              ),
              ...services.take(3).map((s) => _ServiceTile(service: s)),
            ],
          ),
        );
      },
    );
  }

  // ─── POSTS PREVIEW ───────────────────────────────────────────────────────
  Widget _buildPostsPreview(Business b) {
    return StreamBuilder<List<BusinessPost>>(
      stream: _repo.watchPosts(b.id!, limit: 5),
      builder: (context, snap) {
        final posts = snap.data ?? const [];
        if (posts.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aggiornamenti',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...posts.map((p) => _PostCard(post: p)),
            ],
          ),
        );
      },
    );
  }

  // ─── ORARI ────────────────────────────────────────────────────────────────
  Widget _buildOpeningHours(Business b) {
    if (b.openingHours.isEmpty) return const SizedBox.shrink();
    const dayLabels = {
      'monday': 'Lun',
      'tuesday': 'Mar',
      'wednesday': 'Mer',
      'thursday': 'Gio',
      'friday': 'Ven',
      'saturday': 'Sab',
      'sunday': 'Dom',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Orari',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...dayLabels.entries.map((e) {
            final h = b.openingHours[e.key];
            String text;
            if (h == null) {
              text = '—';
            } else if (h.closed) {
              text = 'Chiuso';
            } else if (h.open24h) {
              text = 'Aperto 24h';
            } else {
              text = '${h.open} – ${h.close}';
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                      width: 50,
                      child: Text(e.value,
                          style: const TextStyle(
                              color: AppColors.textSecondary))),
                  Text(text),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── HELPER WIDGETS ──────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final BusinessService service;
  const _ServiceTile({required this.service});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (service.photoUrl != null)
            Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: CachedNetworkImage(
                imageUrl: service.photoUrl!,
                fit: BoxFit.cover,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (service.description != null)
                  Text(service.description!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (service.price != null)
            Text(
              '€${service.price!.toStringAsFixed(0)} ${service.priceUnit.displayName}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final BusinessPost post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final ago = _formatAgo(post.createdAt);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.update, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(ago,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 6),
            Text(post.text, style: const TextStyle(fontSize: 14)),
            if (post.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: post.photoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: post.photoUrls[i],
                      width: 160,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m fa';
    if (diff.inHours < 24) return '${diff.inHours}h fa';
    if (diff.inDays < 7) return '${diff.inDays}g fa';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
