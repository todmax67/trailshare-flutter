import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/business.dart';
import '../../data/repositories/business_repository.dart';
import '../../presentation/widgets/business_claim_banner.dart';
import 'web_claim_request_page.dart';
import '../../presentation/widgets/photo_credit_chip.dart';

/// Epic 7.D1 — Landing pubblica `/b/{slug}` di uno Spazio Pro.
///
/// Mostra hero brandizzato + descrizione + tracce consigliate + listino +
/// recensioni + mappa + CTA "Apri in TrailShare". NESSUN login richiesto:
/// è la pagina pubblica per condivisione web + SEO. Richiama
/// `BusinessRepository.getBusinessBySlug` per risolvere lo slug.
///
/// CTA usa deep link `trailshare://b/{id}` (apre l'app se installata) e
/// fallback alle pagine store (App Store / Play Store).
class WebBusinessPublicPage extends StatefulWidget {
  final String slug;
  const WebBusinessPublicPage({super.key, required this.slug});

  @override
  State<WebBusinessPublicPage> createState() => _WebBusinessPublicPageState();
}

class _WebBusinessPublicPageState extends State<WebBusinessPublicPage> {
  final _repo = BusinessRepository();
  Business? _business;
  bool _loading = true;
  String? _error;
  // 7.D3 — Percorsi consigliati (preview lista + marker mappa)
  List<RecommendedTrack> _recommended = const [];

  // Store URLs — placeholder fino a pubblicazione (vedi _kAppStoreId TODO).
  static const _appStoreUrl =
      'https://apps.apple.com/it/app/trailshare/id0000000000';
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.trailshare.app';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final business = await _repo.getBusinessBySlug(widget.slug);
      if (!mounted) return;
      if (business == null) {
        setState(() {
          _loading = false;
          _error = 'Spazio Pro non trovato';
        });
        return;
      }
      // Fetch recommended tracks in parallel
      List<RecommendedTrack> recs = const [];
      try {
        recs = await _repo
            .watchRecommendedTracks(business.id!)
            .first
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // best-effort: la landing funziona anche senza recommended
      }
      if (!mounted) return;
      setState(() {
        _business = business;
        _recommended = recs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Errore di caricamento: $e';
      });
    }
  }

  /// CTA "Apri in TrailShare": prova prima il deep link custom scheme
  /// (apre l'app se installata), poi fallback alle pagine store.
  Future<void> _openInApp() async {
    final business = _business;
    if (business == null) return;
    final deepLink = Uri.parse('trailshare://b/${business.id}');
    try {
      final ok = await launchUrl(
        deepLink,
        mode: LaunchMode.externalApplication,
      );
      if (ok) return;
    } catch (_) {}
    // Fallback: store. Sceglie iOS/Android in base alla piattaforma del
    // browser (su web Platform.is* è false → mostriamo un picker).
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Scarica TrailShare',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.apple),
              title: const Text('App Store (iOS)'),
              onTap: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(_appStoreUrl),
                    mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.android),
              title: const Text('Google Play (Android)'),
              onTap: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(_playStoreUrl),
                    mode: LaunchMode.externalApplication);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Color _parsePrimaryColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.primary;
    final clean = hex.replaceFirst('#', '');
    if (clean.length == 6) {
      final v = int.tryParse(clean, radix: 16);
      if (v == null) return AppColors.primary;
      return Color(0xFF000000 | v);
    }
    if (clean.length == 8) {
      final v = int.tryParse(clean, radix: 16);
      if (v == null) return AppColors.primary;
      return Color(v);
    }
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final business = _business;
    if (business == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 64, color: AppColors.danger.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text(_error ?? 'Spazio Pro non trovato',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/'),
                  child: const Text('Vai a trailshare.app'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final accent = _parsePrimaryColor(business.branding.primaryColor);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ─── Hero brandizzato ─────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: accent,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                business.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              centerTitle: false,
              background: _buildHero(business, accent),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.launch),
                tooltip: 'Apri in TrailShare',
                onPressed: _openInApp,
              ),
            ],
          ),
          // ─── Body con max-width per leggibilità ───────────────────
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 7.H4 — Banner claim per schede unclaimed,
                      // sopra a tutto il body così è la prima cosa
                      // che vede chi visita una scheda pre-popolata.
                      if (BusinessClaimBanner.shouldShow(business)) ...[
                        BusinessClaimBanner(
                          business: business,
                          onClaimPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => WebClaimRequestPage(
                                  business: business,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildTypeBadge(business, accent),
                      const SizedBox(height: 16),
                      if (business.description?.isNotEmpty == true) ...[
                        Text(
                          business.description!,
                          style: const TextStyle(fontSize: 15, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                      ],
                      _buildCtaCard(accent),
                      const SizedBox(height: 24),
                      _buildContactsSection(business, accent),
                      const SizedBox(height: 24),
                      _buildMap(business, accent),
                      const SizedBox(height: 24),
                      if (_recommended.isNotEmpty) ...[
                        _buildRecommendedSection(accent),
                        const SizedBox(height: 24),
                      ],
                      _buildRatingRow(business, accent),
                      const SizedBox(height: 40),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(Business b, Color accent) {
    final hero = b.branding.heroPhotoUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hero != null && hero.isNotEmpty)
          CachedNetworkImage(
            imageUrl: hero,
            fit: BoxFit.cover,
            placeholder: (_, url) => Container(color: accent),
            errorWidget: (_, url, err) => Container(color: accent),
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accent.withValues(alpha: 0.75)],
              ),
            ),
          ),
        // Scura overlay per leggibilità titolo
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55),
              ],
            ),
          ),
        ),
        // Credito CC per foto da Wikimedia Commons (arricchimento)
        if (hero != null && b.photoAttribution != null)
          Positioned(
            right: 8,
            bottom: 8,
            child: PhotoCreditChip(attribution: b.photoAttribution!),
          ),
        // Logo (se presente)
        if (b.branding.logoUrl != null && b.branding.logoUrl!.isNotEmpty)
          Positioned(
            left: 24,
            bottom: 56,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              clipBehavior: Clip.antiAlias,
              child: CachedNetworkImage(
                imageUrl: b.branding.logoUrl!,
                fit: BoxFit.cover,
                placeholder: (_, url) => Container(color: Colors.white),
                errorWidget: (_, url, err) => Icon(Icons.business,
                    color: accent, size: 32),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTypeBadge(Business b, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.business, color: accent, size: 14),
          const SizedBox(width: 6),
          Text(
            _typeLabel(b.type),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCtaCard(Color accent) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accent.withValues(alpha: 0.75)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apri in TrailShare',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Segui questo Spazio Pro, scopri percorsi consigliati, leggi le '
            'recensioni e ricevi gli aggiornamenti.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.95),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: _openInApp,
                icon: const Icon(Icons.launch),
                label: const Text('Apri TrailShare'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: accent,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(
                      kIsWeb || !Platform.isAndroid ? _appStoreUrl : _playStoreUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.download),
                label: const Text('Scarica l\'app'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactsSection(Business b, Color accent) {
    final contacts = b.contacts;
    final rows = <Widget>[];
    void addRow(IconData icon, String label, String value, VoidCallback? onTap) {
      rows.add(
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: accent, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3)),
                      Text(value,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.open_in_new,
                      color: AppColors.textMuted, size: 16),
              ],
            ),
          ),
        ),
      );
    }

    if (contacts.phone?.isNotEmpty == true) {
      addRow(Icons.phone, 'Telefono', contacts.phone!,
          () => launchUrl(Uri.parse('tel:${contacts.phone}')));
    }
    if (contacts.email?.isNotEmpty == true) {
      addRow(Icons.email_outlined, 'Email', contacts.email!,
          () => launchUrl(Uri.parse('mailto:${contacts.email}')));
    }
    if (contacts.website?.isNotEmpty == true) {
      addRow(Icons.language, 'Sito web', contacts.website!, () {
        var url = contacts.website!;
        if (!url.startsWith('http')) url = 'https://$url';
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      });
    }
    if (b.location.address?.isNotEmpty == true) {
      addRow(Icons.location_on_outlined, 'Indirizzo',
          b.location.address!, null);
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: rows,
      ),
    );
  }

  Widget _buildMap(Business b, Color accent) {
    final lat = b.location.lat;
    final lng = b.location.lng;
    // 7.D3 — aggrega marker dei punti partenza delle tracce consigliate
    // (solo quelle che hanno trackStartLat/Lng denormalizzati). Per le
    // vecchie senza coordinate, restano solo nella lista qui sotto.
    final recsWithCoords = _recommended
        .where((r) => r.trackStartLat != null && r.trackStartLng != null)
        .toList();
    // BBox auto-fit per includere business + tutte le tracce.
    LatLng center = LatLng(lat, lng);
    double zoom = 14;
    if (recsWithCoords.isNotEmpty) {
      double minLat = lat, maxLat = lat, minLng = lng, maxLng = lng;
      for (final r in recsWithCoords) {
        final rLat = r.trackStartLat!;
        final rLng = r.trackStartLng!;
        if (rLat < minLat) minLat = rLat;
        if (rLat > maxLat) maxLat = rLat;
        if (rLng < minLng) minLng = rLng;
        if (rLng > maxLng) maxLng = rLng;
      }
      center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      final spread =
          [(maxLat - minLat), (maxLng - minLng)].reduce((a, b) => a > b ? a : b);
      // Heuristic: spread°→zoom (più spread, meno zoom).
      if (spread > 0.5) {
        zoom = 9;
      } else if (spread > 0.2) {
        zoom = 10;
      } else if (spread > 0.1) {
        zoom = 11;
      } else if (spread > 0.05) {
        zoom = 12;
      } else if (spread > 0.02) {
        zoom = 13;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          recsWithCoords.isEmpty
              ? 'Posizione'
              : 'Posizione e percorsi consigliati',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 280,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'app.trailshare',
                ),
                MarkerLayer(
                  markers: [
                    // Business
                    Marker(
                      point: LatLng(lat, lng),
                      width: 40,
                      height: 40,
                      child: Icon(Icons.place, color: accent, size: 36),
                    ),
                    // Recommended tracks
                    for (final r in recsWithCoords)
                      Marker(
                        point: LatLng(r.trackStartLat!, r.trackStartLng!),
                        width: 28,
                        height: 28,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: accent, width: 2),
                          ),
                          child: const Center(
                            child: Icon(Icons.hiking,
                                size: 14, color: Colors.black87),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendedSection(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.route, color: accent, size: 20),
            const SizedBox(width: 8),
            Text(
              'Percorsi consigliati (${_recommended.length})',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._recommended.take(8).map((r) => _buildRecCard(r, accent)),
        if (_recommended.length > 8) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _openInApp,
              icon: const Icon(Icons.launch),
              label: Text('Vedi tutti i ${_recommended.length} percorsi in app'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRecCard(RecommendedTrack r, Color accent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          // Thumbnail / icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: r.trackPhotoUrl != null && r.trackPhotoUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: r.trackPhotoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, url) => const SizedBox(),
                    errorWidget: (_, url, err) =>
                        Icon(Icons.hiking, color: accent),
                  )
                : Icon(Icons.hiking, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.trackName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.straighten,
                        size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 3),
                    Text(r.distanceKmFormatted,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                    const SizedBox(width: 10),
                    Icon(Icons.trending_up,
                        size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 3),
                    Text(r.elevationFormatted,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
                if (r.note != null && r.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    r.note!,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingRow(Business b, Color accent) {
    if (b.reviewCount == 0 || b.rating == null) return const SizedBox.shrink();
    final rating = b.rating!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.star, color: accent, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rating.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w900),
              ),
              Text(
                '${b.reviewCount} recension${b.reviewCount == 1 ? "e" : "i"}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _openInApp,
            icon: const Icon(Icons.launch, size: 16),
            label: const Text('Leggi e scrivi'),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hiking, color: AppColors.textMuted, size: 16),
          const SizedBox(width: 6),
          Text(
            'Powered by TrailShare',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(BusinessType t) {
    switch (t) {
      case BusinessType.rifugio:
        return 'Rifugio';
      case BusinessType.noleggio:
        return 'Noleggio';
      case BusinessType.guidaAlpina:
        return 'Guida alpina';
      case BusinessType.scuolaAlpinismo:
        return 'Scuola alpinismo';
      case BusinessType.shop:
        return 'Negozio outdoor';
      case BusinessType.tourOperator:
        return 'Tour operator';
      case BusinessType.consorzioTurismo:
        return 'Consorzio turismo';
      case BusinessType.altro:
        return 'Spazio Pro';
    }
  }
}
