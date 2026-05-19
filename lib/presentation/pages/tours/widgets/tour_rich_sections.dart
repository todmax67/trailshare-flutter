import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/tour.dart';
import '../../business/business_profile_page.dart';

/// Epic 11 — Sezioni "ricche" della scheda Tour: gallery carousel,
/// chip difficoltà/periodo, blocchi descrizione strutturata
/// (equipaggiamento, note storiche/naturalistiche), pernottamento
/// per tappa (badge cliccabile che apre BusinessProfilePage del
/// rifugio).
///
/// Pensato come blocco unico da inserire nelle detail page del tour
/// (owner e community) sotto la mappa + descrizione generale, prima
/// della lista tappe.
class TourRichHeaderSections extends StatelessWidget {
  final Tour tour;
  const TourRichHeaderSections({super.key, required this.tour});

  @override
  Widget build(BuildContext context) {
    final hasMeta = tour.difficultyGrade != null || tour.bestPeriod != null;
    final hasGallery = tour.galleryUrls.isNotEmpty;
    final hasEquipment =
        tour.equipment != null && tour.equipment!.trim().isNotEmpty;
    final hasNotes =
        tour.naturalNotes != null && tour.naturalNotes!.trim().isNotEmpty;

    if (!hasMeta && !hasGallery && !hasEquipment && !hasNotes) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasMeta) ...[
          _MetaChipsRow(tour: tour),
          const SizedBox(height: 16),
        ],
        if (hasGallery) ...[
          _GallerySection(urls: tour.galleryUrls),
          const SizedBox(height: 20),
        ],
        if (hasEquipment) ...[
          _SectionCard(
            icon: Icons.backpack_outlined,
            title: 'Equipaggiamento consigliato',
            text: tour.equipment!,
            accent: AppColors.warning,
          ),
          const SizedBox(height: 12),
        ],
        if (hasNotes) ...[
          _SectionCard(
            icon: Icons.menu_book_outlined,
            title: 'Cenni storici e naturalistici',
            text: tour.naturalNotes!,
            accent: AppColors.info,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _MetaChipsRow extends StatelessWidget {
  final Tour tour;
  const _MetaChipsRow({required this.tour});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (tour.difficultyGrade != null)
          _metaChip(
            icon: Icons.hiking,
            label: tour.difficultyGrade!,
            color: AppColors.danger,
          ),
        if (tour.bestPeriod != null)
          _metaChip(
            icon: Icons.event_available_outlined,
            label: tour.bestPeriod!,
            color: AppColors.success,
          ),
      ],
    );
  }

  Widget _metaChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _GallerySection extends StatelessWidget {
  final List<String> urls;
  const _GallerySection({required this.urls});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final url = urls[i];
          return GestureDetector(
            onTap: () => _openFullScreen(ctx, urls, i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: url,
                width: 180,
                height: 140,
                fit: BoxFit.cover,
                placeholder: (c, _) => Container(
                  width: 180,
                  height: 140,
                  color: AppColors.surface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openFullScreen(BuildContext ctx, List<String> urls, int startIndex) {
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => _GalleryViewerPage(urls: urls, initialIndex: startIndex),
      ),
    );
  }
}

class _GalleryViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _GalleryViewerPage({required this.urls, required this.initialIndex});

  @override
  State<_GalleryViewerPage> createState() => _GalleryViewerPageState();
}

class _GalleryViewerPageState extends State<_GalleryViewerPage> {
  late final PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Color accent;
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Mini-pill cliccabile da aggiungere sotto un _StageTile per
/// indicare il rifugio dove si dorme a fine tappa. Apre la
/// BusinessProfilePage al tap.
class StageAccommodationBadge extends StatelessWidget {
  final String businessId;
  final String? businessName;
  const StageAccommodationBadge({
    super.key,
    required this.businessId,
    required this.businessName,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BusinessProfilePage(businessId: businessId),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bed, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                businessName ?? 'Pernottamento',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, size: 12, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
