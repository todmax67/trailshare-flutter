import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
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
import '../../pages/record/record_page.dart';
import '../../pages/tours/community_tour_detail_page.dart';
import '../../widgets/weekly_challenge_card.dart';

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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _bloc.addListener(_onChanged);
    _bloc.load();
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

  Widget _buildSections(HomeFeedData data, bool geoPending) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _HeroCard(data: data),
        if (data.resume != null)
          _ResumeCard(item: data.resume!, onTap: _openRecord),
        if (data.challenge != null) ...[
          _SectionHeader(title: context.l10n.homeSectionChallenge),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: WeeklyChallengeCard(),
          ),
        ],
        if (data.followingPosts.isNotEmpty) ...[
          _SectionHeader(
            title: context.l10n.homeSectionFollowing,
            actionLabel: context.l10n.homeViewAll,
            onAction: _openCommunity,
          ),
          _FollowingStrip(
            posts: data.followingPosts,
            onTap: _openCommunityTrack,
          ),
        ],
        if (data.editorialTour != null) ...[
          _SectionHeader(title: context.l10n.homeSectionTour),
          _EditorialTourCard(
            tour: data.editorialTour!,
            onTap: () => _openTour(data.editorialTour!),
          ),
        ],
        // ── Sezioni geo (Fase 2) ──
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
            onExplore: _openDiscover,
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
}

// ═══════════════════════════════════════════════════════════════════════
// Hero
// ═══════════════════════════════════════════════════════════════════════

class _HeroCard extends StatelessWidget {
  final HomeFeedData data;
  const _HeroCard({required this.data});

  String _greeting(BuildContext context) {
    final h = DateTime.now().hour;
    if (h < 12) return context.l10n.homeGreetingMorning;
    if (h < 18) return context.l10n.homeGreetingAfternoon;
    return context.l10n.homeGreetingEvening;
  }

  @override
  Widget build(BuildContext context) {
    final weather = data.weather;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(context),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.homeReadyForTrail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          if (weather != null)
            Row(
              children: [
                Icon(weather.current.icon,
                    size: 28, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  '${weather.current.temperature.round()}°',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
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
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: posts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final t = posts[i];
          final cover = t.photoUrls.isNotEmpty ? t.photoUrls.first : null;
          return GestureDetector(
            onTap: () => onTap(t),
            child: SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: cover != null
                        ? CachedNetworkImage(
                            imageUrl: cover,
                            height: 110,
                            width: 220,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                _coverFallback(context),
                          )
                        : _coverFallback(context),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${t.activityIcon} ${t.ownerUsername} · ${t.distanceKm.toStringAsFixed(1)} km',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: context.textSecondary),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _coverFallback(BuildContext context) =>
      _TrailCoverPlaceholder(height: 110, width: 220);
}

/// Placeholder gradevole per tracce/sentieri senza foto: gradiente
/// "topografico" verde→primario con icona montagna leggera. Sostituisce
/// il vecchio box grigio piatto che risultava respingente.
class _TrailCoverPlaceholder extends StatelessWidget {
  final double height;
  final double width;
  const _TrailCoverPlaceholder({required this.height, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF4C8C5A).withValues(alpha: 0.85),
            AppColors.primary.withValues(alpha: 0.75),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.landscape_outlined,
          color: Colors.white.withValues(alpha: 0.85),
          size: 34,
        ),
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

  @override
  Widget build(BuildContext context) {
    final cover = tour.coverPhotoUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              cover != null
                  ? CachedNetworkImage(
                      imageUrl: cover,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _fallback(context),
                    )
                  : _fallback(context),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.65),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tour.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${tour.daysCount} ${tour.daysCount == 1 ? "giorno" : "giorni"} · '
                      '${tour.totalDistanceKm.toStringAsFixed(0)} km · ${tour.ownerName}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
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

  Widget _fallback(BuildContext context) => Container(
        height: 180,
        width: double.infinity,
        color: context.themedSurfaceVariant,
        child: Icon(Icons.map, color: context.textMuted, size: 40),
      );
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
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final b = items[i];
          final cover = b.branding.heroPhotoUrl ?? b.branding.logoUrl;
          final city = b.location.city;
          return GestureDetector(
            onTap: () => onTap(b),
            child: SizedBox(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: cover != null
                        ? CachedNetworkImage(
                            imageUrl: cover,
                            height: 100,
                            width: 180,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => _ProPlaceholder(business: b),
                          )
                        : _ProPlaceholder(business: b),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (city != null)
                    Text(
                      city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.textSecondary),
                    ),
                ],
              ),
            ),
          );
        },
      ),
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
    final initial =
        business.name.isNotEmpty ? business.name[0].toUpperCase() : '?';
    return Container(
      height: 100,
      width: 180,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, base.withValues(alpha: 0.7)],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Discover preview
// ═══════════════════════════════════════════════════════════════════════

class _DiscoverPreview extends StatelessWidget {
  final List<PublicTrail> trails;
  final LatLng? userLocation;
  final VoidCallback onExplore;
  const _DiscoverPreview({
    required this.trails,
    required this.userLocation,
    required this.onExplore,
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
              leading: const Icon(Icons.route, color: AppColors.primary),
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
              onTap: onExplore,
            ),
        ],
      ),
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
