import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/business_photos_service.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/business_repository.dart';
import '../../widgets/business_claim_banner.dart';
import '../../widgets/expandable_description.dart';
import '../../widgets/star_rating.dart';
import 'business_claim_request_page.dart';
import 'business_analytics_page.dart';
import 'business_community_sheet.dart';
import 'business_qr_card_page.dart';
import 'business_edit_page.dart';
import 'business_post_composer_page.dart';
import 'business_recommended_tracks_manager_page.dart';
import 'business_reviews_page.dart';
import 'business_services_manager_page.dart';
import 'recommended_track_navigator.dart';
import '../../../core/extensions/l10n_extension.dart';

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
  bool _viewTracked = false;
  // Platform admin TrailShare (team interno che gestisce per conto
  // di rifugi/noleggi non tech-savvy). Caricato async; default
  // fail-closed: niente bottoni admin finché non confermato.
  bool _isPlatformAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadPlatformAdminFlag();
    // Tracking visita profilo (one-shot per apertura).
    // Skip se l'utente è owner o non autenticato.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_viewTracked) return;
      _viewTracked = true;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      // L'owner che si auto-visita non conta (evita inflate metriche).
      // Il check viene fatto qui in modo pessimista: tracciamo solo se
      // possiamo confermare che NON sei l'owner.
      _repo.getBusiness(widget.businessId).then((b) {
        if (b == null) return;
        if (uid != null && b.isOwnerOrAdmin(uid)) return;
        _repo.recordProfileView(widget.businessId);
      }).catchError((_) {});
    });
  }

  Future<void> _loadPlatformAdminFlag() async {
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
    // isOwner qui include anche il platform admin TrailShare:
    // l'admin del team puo' editare schede di clienti non
    // tech-savvy (Epic 7.H pre-seeding & support).
    final isOwner = b.isOwnerOrAdmin(uid, isPlatformAdmin: _isPlatformAdmin);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(b, isOwner),
          SliverList(
            delegate: SliverChildListDelegate([
              _buildHeader(b),
              // 7.H4 — Banner claim per schede unclaimed.
              if (BusinessClaimBanner.shouldShow(b))
                BusinessClaimBanner(
                  business: b,
                  onClaimPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            BusinessClaimRequestPage(business: b),
                      ),
                    );
                  },
                ),
              const Divider(height: 1),
              _buildActions(b),
              const Divider(height: 1),
              if (b.description != null && b.description!.isNotEmpty)
                _buildDescription(b)
              else if (isOwner)
                _ownerCta(
                  'Aggiungi una descrizione',
                  Icons.notes,
                  () => _openEdit(b),
                ),
              _buildLocation(b),
              if (isOwner) _buildOwnerActions(b),
              // 7.H7 — Analytics pre-claim (solo owner): mostra il
              // funnel di visualizzazioni/rivendicazioni accumulato
              // quando la scheda era unclaimed. Subito dopo il claim
              // dà al rifugista la "prova" che la scheda aveva già
              // un audience → driver per pagare il Pro.
              if (isOwner) _buildClaimFunnelStats(b),
              _buildGallery(b, isOwner),
              _buildRecommendedTracks(b, isOwner),
              _buildServicesPreview(b, isOwner),
              _buildPostsPreview(b, isOwner),
              _buildOpeningHours(b, isOwner),
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
                    // Chip "premium" solo per pro/enterprise: verified è
                    // l'entry-level (silenzioso), unclaimed mostra il
                    // banner big sotto e non duplica info qui.
                    if (b.tier == BusinessTier.pro ||
                        b.tier == BusinessTier.enterprise)
                      _Chip('★ ${b.tier.displayName}',
                          color: AppColors.warning),
                    if (b.followerCount > 0)
                      _Chip(
                        '${b.followerCount} ${b.followerCount == 1 ? "follower" : "followers"}',
                        color: AppColors.info,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _RatingBadge(business: b),
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
      _repo.recordContactClick(
          widget.businessId, BusinessContactType.whatsapp);
      launchUrl(Uri.parse('https://wa.me/$clean'),
          mode: LaunchMode.externalApplication);
    } else if (c.phone != null) {
      _repo.recordContactClick(
          widget.businessId, BusinessContactType.phone);
      launchUrl(Uri.parse('tel:${c.phone}'),
          mode: LaunchMode.externalApplication);
    } else {
      messenger.showSnackBar(
          const SnackBar(content: Text('Nessun contatto disponibile')));
    }
  }

  void _openDirections(Business b) {
    _repo.recordContactClick(
        widget.businessId, BusinessContactType.directions);
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
      child: ExpandableDescription(
        text: b.description!,
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
  // 7.H7 — Analytics pre-claim. Mostra all'owner i contatori funnel
  // accumulati quando la scheda era unclaimed. Se zero → niente card
  // (evita di rumoreggiare il profilo con "0 visite").
  Widget _buildClaimFunnelStats(Business b) {
    final counters = b.funnelCounters;
    final views = counters['unclaimed_view'] ?? 0;
    final started = counters['claim_started'] ?? 0;
    final completed = counters['claim_completed'] ?? 0;
    final approved = counters['claim_approved'] ?? 0;
    final rejected = counters['claim_rejected'] ?? 0;
    final total = views + started + completed + approved + rejected;
    if (total == 0) return const SizedBox.shrink();

    final conversion = views > 0
        ? '${((completed / views) * 100).toStringAsFixed(1)}%'
        : '—';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined,
                  color: AppColors.info, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Funnel claim',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Da quando la scheda è online (tutti i tempi).',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _miniStat('Visualizzazioni', views),
              _miniStat('Click "Rivendica"', started),
              _miniStat('Form completati', completed),
              if (approved > 0) _miniStat('Approvate', approved),
              if (rejected > 0) _miniStat('Rifiutate', rejected),
              _miniStat('Conversion view→completed', conversion),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, Object value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textMuted)),
          Text('$value',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

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
                        BusinessRecommendedTracksManagerPage(business: b),
                  ),
                ),
                icon: const Icon(Icons.route),
                label: const Text('Percorsi consigliati'),
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
                    builder: (_) =>
                        BusinessAnalyticsPage(business: b),
                  ),
                ),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Statistiche'),
              ),
              OutlinedButton.icon(
                onPressed: () => showBusinessCommunitySheet(context, b),
                icon: Icon(
                  b.linkedGroupId != null ? Icons.groups : Icons.groups_2,
                ),
                label: Text(
                  b.linkedGroupId != null
                      ? 'Apri community'
                      : 'Crea community',
                ),
              ),
              // 7.C9 — Card QR brandizzata da stampare/condividere
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BusinessQrCardPage(business: b),
                  ),
                ),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Vetrina QR'),
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

  void _openEdit(Business b) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessEditPage(businessId: b.id!),
      ),
    );
  }

  Widget _ownerCta(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                style: BorderStyle.solid),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary),
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  // ─── GALLERIA ─────────────────────────────────────────────────────────
  Widget _buildGallery(Business b, bool isOwner) {
    final photos = b.branding.galleryUrls;
    if (photos.isEmpty && !isOwner) return const SizedBox.shrink();
    if (photos.isEmpty && isOwner) {
      return _ownerCta(
        'Aggiungi foto della galleria',
        Icons.photo_library,
        () => _addGalleryPhoto(b),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Galleria',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (isOwner)
                TextButton.icon(
                  onPressed: () => _addGalleryPhoto(b),
                  icon: const Icon(Icons.add_a_photo, size: 16),
                  label: const Text('Aggiungi'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _openGalleryLightbox(photos, i),
                onLongPress: isOwner
                    ? () => _confirmRemoveGalleryPhoto(b, photos[i])
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: photos[i],
                    width: 160,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          if (isOwner)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Tieni premuta una foto per rimuoverla',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  void _openGalleryLightbox(List<String> photos, int initialIndex) {
    showDialog<void>(
      context: context,
      builder: (_) => _GalleryLightbox(
        photos: photos,
        initialIndex: initialIndex,
      ),
    );
  }

  Future<void> _addGalleryPhoto(Business b) async {
    final photos = BusinessPhotosService();
    final url = await photos.pickAndUpload(
      businessId: b.id!,
      kind: BusinessPhotoKind.gallery,
    );
    if (url == null) return;
    final newGallery = [...b.branding.galleryUrls, url];
    await _repo.updateBusiness(b.id!, {
      'branding': {
        ...b.branding.toMap(),
        'galleryUrls': newGallery,
      },
    });
  }

  Future<void> _confirmRemoveGalleryPhoto(Business b, String url) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovere foto?'),
        content: Text('La foto verrà eliminata dalla galleria.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.danger),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newGallery =
        b.branding.galleryUrls.where((u) => u != url).toList();
    await _repo.updateBusiness(b.id!, {
      'branding': {
        ...b.branding.toMap(),
        'galleryUrls': newGallery,
      },
    });
    BusinessPhotosService().deletePhotoByUrl(url);
  }

  // ─── PERCORSI CONSIGLIATI (preview top 3) ────────────────────────────────
  Widget _buildRecommendedTracks(Business b, bool isOwner) {
    return StreamBuilder<List<RecommendedTrack>>(
      stream: _repo.watchRecommendedTracks(b.id!),
      builder: (context, snap) {
        final tracks = snap.data ?? const [];
        if (tracks.isEmpty) {
          if (!isOwner) return const SizedBox.shrink();
          return _ownerCta(
            'Aggiungi percorsi consigliati',
            Icons.route,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    BusinessRecommendedTracksManagerPage(business: b),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.route,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 6),
                  const Text('Percorsi consigliati',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (tracks.length > 3 || isOwner)
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              BusinessRecommendedTracksManagerPage(
                                  business: b),
                        ),
                      ),
                      child: Text(isOwner
                          ? 'Gestisci (${tracks.length})'
                          : 'Tutti (${tracks.length})'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ...tracks.take(3).map((t) => _RecommendedTrackPreview(track: t)),
            ],
          ),
        );
      },
    );
  }

  // ─── SERVIZI / LISTINO (preview top 3) ───────────────────────────────────
  Widget _buildServicesPreview(Business b, bool isOwner) {
    return StreamBuilder<List<BusinessService>>(
      stream: _repo.watchServices(b.id!),
      builder: (context, snap) {
        final services =
            snap.data?.where((s) => s.isActive).toList() ?? const [];
        if (services.isEmpty) {
          if (!isOwner) return const SizedBox.shrink();
          return _ownerCta(
            'Aggiungi voci al listino',
            Icons.list_alt,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    BusinessServicesManagerPage(businessId: b.id!),
              ),
            ),
          );
        }
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
  Widget _buildPostsPreview(Business b, bool isOwner) {
    return StreamBuilder<List<BusinessPost>>(
      stream: _repo.watchPosts(b.id!, limit: 5),
      builder: (context, snap) {
        final posts = snap.data ?? const [];
        if (posts.isEmpty) {
          if (!isOwner) return const SizedBox.shrink();
          return _ownerCta(
            'Pubblica il primo aggiornamento',
            Icons.post_add,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    BusinessPostComposerPage(businessId: b.id!),
              ),
            ),
          );
        }
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
  Widget _buildOpeningHours(Business b, bool isOwner) {
    if (b.openingHours.isEmpty) {
      if (!isOwner) return const SizedBox.shrink();
      return _ownerCta(
        'Imposta gli orari di apertura',
        Icons.schedule,
        () => _openEdit(b),
      );
    }
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

/// Badge rating + count cliccabile sotto il nome del business.
/// Apre la pagina dettaglio recensioni.
class _RatingBadge extends StatelessWidget {
  final Business business;
  const _RatingBadge({required this.business});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessReviewsPage(business: business),
        ),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StarRating(
              value: business.rating ?? 0,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              business.reviewCount == 0
                  ? 'Nessuna recensione'
                  : '${(business.rating ?? 0).toStringAsFixed(1)} '
                      '(${business.reviewCount})',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _RecommendedTrackPreview extends StatelessWidget {
  final RecommendedTrack track;
  const _RecommendedTrackPreview({required this.track});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openRecommendedTrackDetail(context, track),
        child: SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 96,
                child: track.trackPhotoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: track.trackPhotoUrl!,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        alignment: Alignment.center,
                        child: const Icon(Icons.route,
                            size: 32, color: AppColors.primary),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        track.trackName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${track.distanceKmFormatted} · ${track.elevationFormatted}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      if (track.note != null && track.note!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '"${track.note!}"',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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

/// Lightbox fullscreen per la galleria dello Spazio Pro.
///
/// Dialog con sfondo nero, immagine corrente al centro fit:contain,
/// frecce ← → per navigare tra le foto, X in alto a destra per
/// chiudere, contatore '1/N' in alto.
class _GalleryLightbox extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;
  const _GalleryLightbox({
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_GalleryLightbox> createState() => _GalleryLightboxState();
}

class _GalleryLightboxState extends State<_GalleryLightbox> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final url = widget.photos[_index];
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, _) => const SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(),
                ),
                errorWidget: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
          // Close
          Positioned(
            top: 12,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          // Counter
          Positioned(
            left: 0,
            right: 0,
            top: 16,
            child: Center(
              child: Text(
                '${_index + 1} / ${widget.photos.length}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          // Prev
          if (_index > 0)
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_left,
                      color: Colors.white, size: 36),
                  onPressed: () => setState(() => _index--),
                ),
              ),
            ),
          // Next
          if (_index < widget.photos.length - 1)
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_right,
                      color: Colors.white, size: 36),
                  onPressed: () => setState(() => _index++),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
