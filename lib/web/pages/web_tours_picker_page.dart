import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/tour.dart';
import '../../data/repositories/tours_repository.dart';
import 'web_tour_edit_page.dart';

/// Gestione Tour sul web (MVP): lista dei propri tour + crea/modifica/elimina/
/// pubblica. Riusa ToursRepository (stesso data layer del mobile).
class WebToursPickerPage extends StatelessWidget {
  const WebToursPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = ToursRepository();
    return StreamBuilder<List<Tour>>(
      stream: repo.watchMyTours(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final tours = snap.data ?? const <Tour>[];
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'I miei Tour',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WebTourEditPage(),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Crea Tour'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Un Tour raggruppa più tracce in un itinerario a tappe '
                '(es. trekking di più giorni). Da qui li crei, modifichi e '
                'pubblichi nella community.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: tours.isEmpty
                    ? _empty(context)
                    : GridView.count(
                        crossAxisCount: 3,
                        childAspectRatio: 1.45,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        children: tours
                            .map((t) => _TourCard(
                                  tour: t,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          WebTourEditPage(tourId: t.id),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.route, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 12),
          const Text('Nessun Tour',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Crea il tuo primo itinerario a tappe partendo dalle tue tracce.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebTourEditPage()),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Crea Tour'),
          ),
        ],
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  final Tour tour;
  final VoidCallback onTap;
  const _TourCard({required this.tour, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final km = (tour.totalDistance / 1000).toStringAsFixed(1);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (tour.coverPhotoUrl != null)
                    CachedNetworkImage(
                      imageUrl: tour.coverPhotoUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => _placeholder(),
                    )
                  else
                    _placeholder(),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (tour.isPublic
                                ? AppColors.success
                                : AppColors.textMuted)
                            .withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        tour.isPublic ? 'Pubblico' : 'Bozza',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tour.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${tour.daysCount} giorni · ${tour.trackIds.length} tappe · $km km',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.primary.withValues(alpha: 0.08),
        child: const Center(
          child: Icon(Icons.route, size: 48, color: AppColors.primary),
        ),
      );
}
