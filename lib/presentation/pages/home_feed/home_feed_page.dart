import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../widgets/trail_route_thumb.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../data/models/business.dart';
import '../../../data/models/home_feed_data.dart';
import '../../../data/models/home_resume_item.dart';
import '../../../data/models/tour.dart';
import '../../../data/repositories/community_tracks_repository.dart'
    show CommunityTrack;
import '../../../data/repositories/public_trails_repository.dart'
    show PublicTrail;
import '../../blocs/home_feed_bloc.dart';
import '../../pages/business/business_profile_page.dart';
import '../../pages/community/community_page.dart';
import '../../pages/discover/community_track_detail_page.dart';
import '../../pages/discover/discover_page.dart';
import '../../pages/discover/trail_detail_page.dart';
import '../../pages/profile/profile_page.dart';
import '../../pages/record/record_page.dart';
import '../../pages/tours/community_tour_detail_page.dart';
import '../../widgets/onboarding_checklist_card.dart';
import '../../widgets/route_thumbnail.dart';
import '../../../core/services/onboarding_checklist_service.dart';

/// Home Feed prototype — aggrega in sezioni separate i building block
/// esistenti (recovery, sfida, seguiti, tour, Spazi Pro, scopri).
///
/// Prototipo: i widget di sezione sono privati in questo file. Saranno
/// estratti in file separati dopo l'approvazione del design.
class HomeFeedPage extends StatefulWidget {
  const HomeFeedPage({super.key});

  @override
  State<HomeFeedPage> createState() => _HomeFeedPageState();
}

class _HomeFeedPageState extends State<HomeFeedPage>
    with AutomaticKeepAliveClientMixin {
  final HomeFeedBloc _bloc = HomeFeedBloc();

  // Onboarding attivo: checklist "primi passi" per i nuovi utenti.
  final OnboardingChecklistService _onboarding = OnboardingChecklistService();
  OnboardingChecklistState? _checklist;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _bloc.addListener(_onChanged);
    _bloc.load();
    _loadChecklist();
  }

  Future<void> _loadChecklist() async {
    final s = await _onboarding.load();
    if (mounted) setState(() => _checklist = s);
  }

  /// Naviga e ricarica la checklist al ritorno (un task può essersi spuntato).
  Future<void> _goAndRefresh(Widget page) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _loadChecklist();
  }

  void _dismissChecklist() {
    _onboarding.dismiss();
    setState(() => _checklist = null);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bloc.removeListener(_onChanged);
    _bloc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = _bloc.data;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _bloc.refresh,
          child: _bloc.isInitialLoading
              ? const _HomeFeedSkeleton()
              : data == null
                  ? _ErrorView(error: _bloc.error, onRetry: _bloc.load)
                  // Empty state solo quando ANCHE la fase geo è finita:
                  // evita il flash di "vuoto" mentre i sentieri/Pro
                  // stanno ancora arrivando.
                  : (data.isCompletelyEmpty && !_bloc.geoPending)
                      ? _HomeEmptyState(onRecord: _openRecord)
                      : _buildSections(data, _bloc.geoPending),
        ),
      ),
    );
  }

  // ── Sections ────────────────────────────────────────────────────────

  /// Striscia "conoscitiva" tra le sezioni: consiglio rotante (per giorno).
  Widget _tip(int offset) => _TipBanner(
        text: _homeTips[(DateTime.now().day + offset) % _homeTips.length],
      );

  Widget _buildSections(HomeFeedData data, bool geoPending) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // Hero fotografico: saluto + i due ingressi principali (Registra/
        // Scopri) allo stesso peso visivo. Sostituisce mini-mappa + saluto
        // testuale (redesign "Editoriale con hero", 2026-07-23).
        _PhotoHeroCard(
          data: data,
          onRecord: _openRecord,
          onDiscover: _openDiscover,
        ),
        // Onboarding attivo: i primi passi del nuovo utente (sparisce a fine).
        if (_checklist != null)
          OnboardingChecklistCard(
            state: _checklist!,
            onRecord: () => _goAndRefresh(const RecordPage()),
            onExplore: () => _goAndRefresh(const DiscoverPage()),
            onFavorite: () => _goAndRefresh(const DiscoverPage()),
            onProfile: () => _goAndRefresh(const ProfilePage()),
            onDismiss: _dismissChecklist,
          ),
        if (data.resume != null)
          _ResumeCard(item: data.resume!, onTap: _openRecord),
        // 1) Tour del mese — subito sotto l'hero, in evidenza editoriale.
        if (data.editorialTour != null) ...[
          _SectionHeader(title: context.l10n.homeSectionTour),
          _EditorialTourCard(
            tour: data.editorialTour!,
            onTap: () => _openTour(data.editorialTour!),
          ),
        ],
        // 2) Community generale — sempre ricca: la prima cosa che vede
        // anche il nuovo utente senza seguiti (risolve il cold-start).
        if (data.community.isNotEmpty) ...[
          _SectionHeader(
            title: 'Dalla community',
            actionLabel: context.l10n.homeViewAll,
            onAction: _openCommunity,
          ),
          _FollowingStrip(
            posts: data.community,
            onTap: _openCommunityTrack,
          ),
        ],
        _tip(0),
        // 3) I tuoi seguiti — sempre visibile; CTA se non segui nessuno.
        _SectionHeader(
          title: context.l10n.homeSectionFollowing,
          actionLabel: context.l10n.homeViewAll,
          onAction: _openCommunity,
        ),
        if (data.followingPosts.isNotEmpty)
          _FollowingStrip(
            posts: data.followingPosts,
            onTap: _openCommunityTrack,
          )
        else
          _FollowingEmptyCta(onTap: _openCommunity),
        _tip(1),
        // 4) Rifugi da visitare — aspirazionale, dal bundle POI, non geo.
        if (data.rifugi.isNotEmpty) ...[
          const _SectionHeader(title: 'Rifugi da visitare'),
          _RifugiStrip(
            items: data.rifugi,
            userLocation: data.userLocation,
            onTap: _openBusiness,
          ),
        ],
        // 5) I sentieri più amati — criterio popolarità, non distanza.
        if (data.popularTracks.isNotEmpty) ...[
          _SectionHeader(
            title: 'I sentieri più amati',
            actionLabel: context.l10n.homeViewAll,
            onAction: _openCommunity,
          ),
          _FollowingStrip(
            posts: data.popularTracks,
            onTap: _openCommunityTrack,
          ),
        ],
        // ── Sezioni geo (Fase 2) — complemento: vicino a te ──
        // Mentre geoPending, mostriamo header + loader per dare
        // feedback "sto cercando vicino a te". Quando arrivano i dati,
        // si riempiono; se restano vuote a fine fase, si nascondono.
        if (data.nearbyPro.isNotEmpty) ...[
          _SectionHeader(title: context.l10n.homeSectionPro),
          _ProStrip(items: data.nearbyPro, onTap: _openBusiness),
        ] else if (geoPending) ...[
          _SectionHeader(title: context.l10n.homeSectionPro),
          const _GeoStripLoader(),
        ],
        if (data.nearbyTrails.isNotEmpty) ...[
          _SectionHeader(
            title: context.l10n.homeSectionDiscover,
            actionLabel: context.l10n.homeExploreArea,
            onAction: _openDiscover,
          ),
          _DiscoverPreview(
            trails: data.nearbyTrails,
            userLocation: data.userLocation,
            onOpenTrail: _openTrail,
          ),
        ] else if (geoPending) ...[
          _SectionHeader(title: context.l10n.homeSectionDiscover),
          const _GeoListLoader(),
        ],
      ],
    );
  }

  // ── Navigation ──────────────────────────────────────────────────────

  void _openRecord() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RecordPage()),
      );

  void _openCommunity() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CommunityPage()),
      );

  void _openDiscover() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DiscoverPage()),
      );

  void _openCommunityTrack(CommunityTrack t) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CommunityTrackDetailPage(track: t)),
      );

  void _openTour(Tour tour) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommunityTourDetailPage(tourId: tour.id),
        ),
      );

  void _openBusiness(Business b) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessProfilePage(businessId: b.id ?? ''),
        ),
      );

  void _openTrail(PublicTrail t) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TrailDetailPage(trail: t)),
      );
}

// ═══════════════════════════════════════════════════════════════════════
// Hero
// ═══════════════════════════════════════════════════════════════════════

/// Sorgente foto+attribuzione per l'hero: la prima traccia con una foto
/// reale, cercata tra i pool community in ordine di rilevanza editoriale.
class _HeroTrackPick {
  final String photoUrl;
  final String ownerUsername;
  final String trackName;
  const _HeroTrackPick({
    required this.photoUrl,
    required this.ownerUsername,
    required this.trackName,
  });

  /// Sceglie una foto a caso tra tutte le tracce candidate — non sempre
  /// la stessa: varietà ad ogni caricamento/refresh della Home.
  static _HeroTrackPick? pickRandom(HomeFeedData data) {
    final candidates = <_HeroTrackPick>[
      for (final pool in [data.community, data.popularTracks, data.followingPosts])
        for (final t in pool)
          for (final photo in t.photoUrls)
            _HeroTrackPick(
              photoUrl: photo,
              ownerUsername: t.ownerUsername,
              trackName: t.name,
            ),
    ];
    if (candidates.isEmpty) return null;
    return candidates[Random().nextInt(candidates.length)];
  }
}

/// Hero fotografico in apertura Home: foto da una traccia della community,
/// saluto, e i due ingressi principali (Registra/Scopri) allo stesso peso
/// visivo — sostituisce la mini-mappa e il vecchio saluto testuale.
///
/// Stateful: la foto è scelta a caso una volta sola (initState) e resta
/// fissa tra i rebuild incidentali (es. checklist onboarding); si
/// ri-sceglie solo quando la Home ricarica davvero i dati (refresh).
class _PhotoHeroCard extends StatefulWidget {
  final HomeFeedData data;
  final VoidCallback onRecord;
  final VoidCallback onDiscover;
  const _PhotoHeroCard({
    required this.data,
    required this.onRecord,
    required this.onDiscover,
  });

  @override
  State<_PhotoHeroCard> createState() => _PhotoHeroCardState();
}

class _PhotoHeroCardState extends State<_PhotoHeroCard> {
  _HeroTrackPick? _pick;

  @override
  void initState() {
    super.initState();
    _pick = _HeroTrackPick.pickRandom(widget.data);
  }

  @override
  void didUpdateWidget(covariant _PhotoHeroCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _pick = _HeroTrackPick.pickRandom(widget.data);
    }
  }

  String _kicker(BuildContext context) {
    final h = DateTime.now().hour;
    return h < 12
        ? context.l10n.homeGreetingMorning
        : h < 18
            ? context.l10n.homeGreetingAfternoon
            : context.l10n.homeGreetingEvening;
  }

  String _headline(BuildContext context) {
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
    if (name == null || name.isEmpty) return context.l10n.homeReadyForTrail;
    return context.l10n.homeReadyForTrailNamed(name.split(' ').first);
  }

  @override
  Widget build(BuildContext context) {
    final pick = _pick;
    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          pick != null
              ? CachedNetworkImage(
                  imageUrl: pick.photoUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const _HeroFallbackCover(),
                )
              : const _HeroFallbackCover(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33141814),
                  Color(0x1F141814),
                  Color(0xD9141814),
                ],
                stops: [0.0, 0.4, 1.0],
              ),
            ),
          ),
          if (pick != null)
            Positioned(
              left: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 11, 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.primary, AppColors.primaryDark],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        pick.ownerUsername.isNotEmpty
                            ? pick.ownerUsername[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '@${pick.ownerUsername} · ${pick.trackName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kicker(context).toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _headline(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    shadows: [
                      Shadow(blurRadius: 10, color: Color(0x59000000)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _HeroButton(
                        icon: Icons.radio_button_checked,
                        label: context.l10n.recordLabel,
                        background: AppColors.primary,
                        foreground: Colors.white,
                        onTap: widget.onRecord,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroButton(
                        icon: Icons.map_outlined,
                        label: context.l10n.discover,
                        background: Colors.white.withValues(alpha: 0.92),
                        foreground: AppColors.textPrimary,
                        onTap: widget.onDiscover,
                      ),
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
}

/// Copertina generica quando nessuna traccia community ha ancora una foto:
/// gradiente "alpino" — mai un placeholder morto sull'elemento più in vista.
class _HeroFallbackCover extends StatelessWidget {
  const _HeroFallbackCover();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E5E4E), Color(0xFF3E7A5E), Color(0xFF6BA368)],
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Tip banner
// ═══════════════════════════════════════════════════════════════════════

/// Consigli/curiosità mostrati tra una sezione e l'altra.
const List<String> _homeTips = [
  'Tocca una traccia per vederla colorata per pendenza: verde in piano, rosso in salita.',
  'Segui altri escursionisti per riempire "Dai tuoi seguiti".',
  'Rifugi, sorgenti e punti panoramici lungo il percorso compaiono sulla mappa.',
  'Apri una traccia a schermo intero per il grafico di elevazione interattivo.',
  'Salva una traccia tra i preferiti per ritrovarla anche offline.',
];

class _TipBanner extends StatelessWidget {
  final String text;
  const _TipBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, size: 17, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Section header
// ═══════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (onAction != null && actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Resume
// ═══════════════════════════════════════════════════════════════════════

class _ResumeCard extends StatelessWidget {
  final HomeResumeItem item;
  final VoidCallback onTap;
  const _ResumeCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill,
                    color: AppColors.primary, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(item.subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: context.textSecondary)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: context.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Following strip
// ═══════════════════════════════════════════════════════════════════════

class _FollowingStrip extends StatelessWidget {
  final List<CommunityTrack> posts;
  final void Function(CommunityTrack) onTap;
  const _FollowingStrip({required this.posts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _FeatureCarousel(
      height: 200,
      itemCount: posts.length,
      itemBuilder: (context, i) {
        final t = posts[i];
        final cover = t.photoUrls.isNotEmpty ? t.photoUrls.first : null;
        return _FeaturedCard(
          onTap: () => onTap(t),
          title: t.name,
          subtitle:
              '${t.activityIcon} ${t.ownerUsername} · ${t.distanceKm.toStringAsFixed(1)} km',
          cover: cover != null
              ? CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => RouteThumbnail(
                    points: t.points,
                    borderRadius: BorderRadius.zero,
                  ),
                )
              : RouteThumbnail(
                  points: t.points,
                  borderRadius: BorderRadius.zero,
                ),
        );
      },
    );
  }
}

/// Carosello a card **full-width** con swipe (PageView). Il `viewportFraction`
/// < 1 lascia sbirciare la card successiva → segnala che si scorre.
class _FeatureCarousel extends StatefulWidget {
  final int itemCount;
  final double height;
  final Widget Function(BuildContext, int) itemBuilder;
  const _FeatureCarousel({
    required this.itemCount,
    required this.height,
    required this.itemBuilder,
  });

  @override
  State<_FeatureCarousel> createState() => _FeatureCarouselState();
}

class _FeatureCarouselState extends State<_FeatureCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.92);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
}

/// Card "featured" full-width: copertina che riempie + scrim in basso +
/// titolo/sottotitolo sovrapposti (lo stile "completo" dei tour).
class _FeaturedCard extends StatelessWidget {
  final Widget cover;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _FeaturedCard({
    required this.cover,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              cover,
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Following empty CTA
// ═══════════════════════════════════════════════════════════════════════

/// Mostrata nella sezione "I tuoi seguiti" quando l'utente non segue ancora
/// nessuno: invito all'azione verso la community invece di una sezione vuota.
class _FollowingEmptyCta extends StatelessWidget {
  final VoidCallback onTap;
  const _FollowingEmptyCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              const Icon(Icons.group_add_outlined,
                  color: AppColors.primary, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Non segui ancora nessuno',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Esplora la community e trova escursionisti da seguire',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Rifugi strip
// ═══════════════════════════════════════════════════════════════════════

enum _RifugioFilter { altitude, nearby }

class _RifugiStrip extends StatefulWidget {
  final List<Business> items;
  final LatLng? userLocation;
  final void Function(Business) onTap;
  const _RifugiStrip({
    required this.items,
    required this.onTap,
    this.userLocation,
  });

  @override
  State<_RifugiStrip> createState() => _RifugiStripState();
}

class _RifugiStripState extends State<_RifugiStrip> {
  _RifugioFilter _filter = _RifugioFilter.altitude;
  static const Distance _distance = Distance();

  double _distM(Business b) => _distance.as(LengthUnit.Meter,
      widget.userLocation!, LatLng(b.location.lat, b.location.lng));

  List<Business> get _shown {
    final list = [...widget.items];
    if (_filter == _RifugioFilter.nearby && widget.userLocation != null) {
      list.sort((a, b) => _distM(a).compareTo(_distM(b)));
    } else {
      list.sort((a, b) =>
          (b.location.elevation ?? 0).compareTo(a.location.elevation ?? 0));
    }
    return list.take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    final canNearby = widget.userLocation != null;
    final shown = _shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Wrap(
            spacing: 8,
            children: [
              _chip('I più alti', _RifugioFilter.altitude),
              if (canNearby) _chip('I più vicini', _RifugioFilter.nearby),
            ],
          ),
        ),
        _FeatureCarousel(
          height: 160,
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final r = shown[i];
            final photo = r.branding.heroPhotoUrl ?? r.branding.logoUrl;
            final showDist =
                _filter == _RifugioFilter.nearby && widget.userLocation != null;
            return _FeaturedCard(
              onTap: () => widget.onTap(r),
              title: r.name,
              subtitle: showDist ? _distLabel(r) : _eleLabel(r),
              cover: photo != null
                  ? CachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const _RifugioCover(),
                    )
                  : const _RifugioCover(),
            );
          },
        ),
      ],
    );
  }

  String? _eleLabel(Business b) => b.location.elevation != null
      ? '${b.location.elevation!.round()} m s.l.m.'
      : null;

  String _distLabel(Business b) {
    final m = _distM(b);
    final km = m / 1000;
    final d = km < 1 ? '${m.round()} m' : '${km.toStringAsFixed(1)} km';
    final ele = b.location.elevation != null
        ? ' · ${b.location.elevation!.round()} m'
        : '';
    return '$d da te$ele';
  }

  Widget _chip(String label, _RifugioFilter f) {
    final selected = _filter == f;
    return GestureDetector(
      onTap: () => setState(() => _filter = f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : context.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Copertina generata per un rifugio (Spazio Pro) senza foto: gradiente
/// "alpino" + icona. Sostituita dalla foto quando il gestore la carica.
class _RifugioCover extends StatelessWidget {
  const _RifugioCover();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E5E4E), Color(0xFF6BA368)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.cabin,
          color: Colors.white.withValues(alpha: 0.85),
          size: 36,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Pro strip
// ═══════════════════════════════════════════════════════════════════════

class _ProStrip extends StatelessWidget {
  final List<Business> items;
  final void Function(Business) onTap;
  const _ProStrip({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _FeatureCarousel(
      height: 170,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final b = items[i];
        final cover = b.branding.heroPhotoUrl ?? b.branding.logoUrl;
        return _FeaturedCard(
          onTap: () => onTap(b),
          title: b.name,
          subtitle: b.location.city,
          cover: cover != null
              ? CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _ProPlaceholder(business: b),
                )
              : _ProPlaceholder(business: b),
        );
      },
    );
  }
}

/// Placeholder per Spazi Pro senza logo/foto: usa il colore brand del
/// business (se presente) come sfondo + iniziale del nome. Molto più
/// gradevole e riconoscibile del generico box grigio con storefront.
class _ProPlaceholder extends StatelessWidget {
  final Business business;
  const _ProPlaceholder({required this.business});

  /// Parse "#RRGGBB" → Color, fallback al primario TrailShare.
  Color _brandColor() {
    final hex = business.branding.primaryColor;
    if (hex == null) return AppColors.primary;
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length != 6) return AppColors.primary;
    final v = int.tryParse('FF$clean', radix: 16);
    return v == null ? AppColors.primary : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final base = _brandColor();
    final rating = business.rating;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, base.withValues(alpha: 0.7)],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              Icons.storefront_outlined,
              color: Colors.white.withValues(alpha: 0.9),
              size: 32,
            ),
          ),
          // Badge "Spazio Pro" in alto a sinistra (identità, non iniziale)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Spazio Pro',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          // Rating in basso a sinistra, se disponibile (info-density)
          if (rating != null)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 12, color: Color(0xFFFFC107)),
                    const SizedBox(width: 3),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Editorial tour
// ═══════════════════════════════════════════════════════════════════════

class _EditorialTourCard extends StatelessWidget {
  final Tour tour;
  final VoidCallback onTap;
  const _EditorialTourCard({required this.tour, required this.onTap});

  static const double _height = 210;

  @override
  Widget build(BuildContext context) {
    final cover = tour.coverPhotoUrl;
    final difficulty = tour.difficultyGrade;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              cover != null
                  ? CachedNetworkImage(
                      imageUrl: cover,
                      height: _height,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _fallback(context),
                    )
                  : _fallback(context),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.68),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 15,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tour.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(blurRadius: 6, color: Color(0x66000000)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statPill('${tour.totalDistanceKm.toStringAsFixed(1)} km'),
                        _statPill('+${tour.totalElevationGain.round()} m'),
                        if (difficulty != null && difficulty.isNotEmpty)
                          _statPill(difficulty, color: AppColors.primaryDark),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statPill(String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.textPrimary,
          ),
        ),
      );

  Widget _fallback(BuildContext context) => Container(
        height: _height,
        width: double.infinity,
        color: context.themedSurfaceVariant,
        child: Icon(Icons.map, color: context.textMuted, size: 40),
      );
}

// ═══════════════════════════════════════════════════════════════════════
// Discover preview
// ═══════════════════════════════════════════════════════════════════════

class _DiscoverPreview extends StatelessWidget {
  final List<PublicTrail> trails;
  final LatLng? userLocation;
  final void Function(PublicTrail) onOpenTrail;
  const _DiscoverPreview({
    required this.trails,
    required this.userLocation,
    required this.onOpenTrail,
  });

  static const Distance _distance = Distance();

  String? _distanceFromUser(PublicTrail t) {
    final loc = userLocation;
    if (loc == null) return null;
    final km = _distance.as(
      LengthUnit.Kilometer,
      loc,
      LatLng(t.startLat, t.startLng),
    );
    if (km < 1) return '${(km * 1000).round()} m da te';
    return '${km.toStringAsFixed(1)} km da te';
  }

  @override
  Widget build(BuildContext context) {
    final preview = trails.take(5).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        children: [
          for (final t in preview)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _TrailThumb(trail: t),
              title: Text(
                t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  _distanceFromUser(t),
                  if (t.length != null)
                    'lung. ${(t.length! / 1000).toStringAsFixed(1)} km',
                  if (t.difficulty != null) t.difficulty!,
                ].whereType<String>().join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onOpenTrail(t),
            ),
        ],
      ),
    );
  }
}

/// Miniatura quadrata del tracciato nelle righe sentiero della Home.
/// Immagine statica leggera; fallback icona se non disponibile.
class _TrailThumb extends StatelessWidget {
  final PublicTrail trail;
  const _TrailThumb({required this.trail});

  @override
  Widget build(BuildContext context) {
    if (!TrailRouteThumb.canRender(trail.points)) {
      return const Icon(Icons.route, color: AppColors.primary);
    }
    return TrailRouteThumb(
      points: trail.points,
      width: 52,
      height: 52,
      borderRadius: BorderRadius.circular(8),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Skeleton / Error / Empty
// ═══════════════════════════════════════════════════════════════════════

/// Loader orizzontale per la sezione Spazi Pro mentre la Fase 2
/// (posizione + fetch) è in corso.
class _GeoStripLoader extends StatelessWidget {
  const _GeoStripLoader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, _) => Container(
          width: 180,
          height: 100,
          decoration: BoxDecoration(
            color: context.themedSurfaceVariant,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Loader a lista per la sezione Scopri mentre la Fase 2 è in corso.
class _GeoListLoader extends StatelessWidget {
  const _GeoListLoader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              height: 44,
              decoration: BoxDecoration(
                color: context.themedSurfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeFeedSkeleton extends StatelessWidget {
  const _HomeFeedSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h) => Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          height: h,
          decoration: BoxDecoration(
            color: context.themedSurfaceVariant,
            borderRadius: BorderRadius.circular(14),
          ),
        );
    return ListView(
      children: [box(60), box(90), box(140), box(120), box(120)],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String? error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.cloud_off, size: 48, color: context.textMuted),
        const SizedBox(height: 12),
        Center(
          child: Text('Errore nel caricamento',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 12),
        Center(
          child: ElevatedButton(
            onPressed: onRetry,
            child: const Text('Riprova'),
          ),
        ),
      ],
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  final VoidCallback onRecord;
  const _HomeEmptyState({required this.onRecord});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.terrain, size: 64, color: AppColors.primary),
        const SizedBox(height: 16),
        Center(
          child: Text(
            context.l10n.homeEmptyTitle,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            context.l10n.homeEmptySubtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: context.textSecondary),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onRecord,
          icon: const Icon(Icons.fiber_manual_record),
          label: Text(context.l10n.homeEmptyRecord),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}
