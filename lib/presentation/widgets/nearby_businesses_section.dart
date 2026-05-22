import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';
import '../../data/repositories/business_repository.dart';
import '../pages/business/business_profile_page.dart';

/// Sezione **"Spazi Pro lungo questo percorso"**.
///
/// Si carica async via [BusinessRepository.getNearPolyline] e mostra
/// gli Spazi Pro (rifugi, noleggi, guide, ecc.) che si trovano vicini
/// alla polyline della traccia, ordinati per km progressivi.
///
/// Pensata per i detail page (CommunityTrackDetailPage e
/// TrackDetailPage in modalità illustrative / non-owner) come pattern
/// di discovery contestuale alto-intent: l'utente sta valutando o
/// percorrendo un trail e qui scopre chi può aiutarlo (vitto/sonno/
/// noleggio gear).
///
/// Si auto-nasconde se non ci sono risultati — niente sezione vuota
/// che spamma la pagina.
class NearbyBusinessesSection extends StatefulWidget {
  /// Polyline del percorso (lat/lng dei vertici GPS).
  final List<LatLng> polyline;

  /// Raggio di ricerca dal percorso in km. Default 2 km — abbastanza
  /// per includere rifugi a margine del sentiero ma non spazi
  /// "geograficamente vicini" che non c'entrano col trail.
  final double radiusKm;

  const NearbyBusinessesSection({
    super.key,
    required this.polyline,
    this.radiusKm = 2,
  });

  @override
  State<NearbyBusinessesSection> createState() =>
      _NearbyBusinessesSectionState();
}

class _NearbyBusinessesSectionState extends State<NearbyBusinessesSection> {
  final _repo = BusinessRepository();
  bool _loading = true;
  List<NearPolylineBusiness> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NearbyBusinessesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Riload solo se la polyline è cambiata davvero (length diversa o
    // primo/ultimo punto diversi — euristica veloce, niente deep
    // equals).
    final oldPoly = oldWidget.polyline;
    final newPoly = widget.polyline;
    if (oldPoly.length != newPoly.length ||
        (newPoly.isNotEmpty &&
            (oldPoly.first != newPoly.first ||
                oldPoly.last != newPoly.last))) {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.polyline.length < 2) {
      setState(() {
        _loading = false;
        _items = const [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await _repo.getNearPolyline(
        widget.polyline
            .map((p) => (lat: p.latitude, lng: p.longitude))
            .toList(),
        radiusKm: widget.radiusKm,
      );
      if (!mounted) return;
      setState(() {
        _items = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // Niente skeleton: questa sezione è secondaria, evitiamo
      // sfarfallio. Mostra placeholder minuscolo solo per non
      // saltare improvvisamente quando arrivano i dati.
      return const SizedBox(height: 0);
    }
    // Auto-hide se vuoto — niente sezione "Nessuno Spazio Pro vicino"
    // che spammerebbe ogni traccia in zone non coperte.
    if (_items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_city,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Spazi Pro lungo il percorso',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_items.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Rifugi, noleggi e altri spazi vicini al tragitto.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _BusinessCard(item: _items[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  final NearPolylineBusiness item;
  const _BusinessCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final b = item.business;
    return SizedBox(
      width: 220,
      child: Material(
        color: AppColors.surface,
        elevation: 0,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final id = b.id;
            if (id == null) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BusinessProfilePage(businessId: id),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero / logo / placeholder
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (b.branding.heroPhotoUrl != null &&
                          b.branding.heroPhotoUrl!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: b.branding.heroPhotoUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: AppColors.background,
                          ),
                          errorWidget: (_, _, _) =>
                              _placeholder(b.type.icon),
                        )
                      else if (b.branding.logoUrl != null &&
                          b.branding.logoUrl!.isNotEmpty)
                        ClipRRect(
                          child: CachedNetworkImage(
                            imageUrl: b.branding.logoUrl!,
                            fit: BoxFit.contain,
                            placeholder: (_, _) =>
                                _placeholder(b.type.icon),
                            errorWidget: (_, _, _) =>
                                _placeholder(b.type.icon),
                          ),
                        )
                      else
                        _placeholder(b.type.icon),
                      // Badge km da inizio percorso
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${item.kmFromStart.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${b.type.icon} ${b.type.displayName}',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(String emoji) => Container(
        color: AppColors.primary.withValues(alpha: 0.08),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 36)),
      );
}
