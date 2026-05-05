import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../data/models/tour.dart';
import '../../../data/repositories/tours_repository.dart';
import 'tour_edit_page.dart';
import 'tour_detail_page.dart';

/// Tab "Tour" nella pagina "Le mie tracce": lista dei tour creati dall'utente
/// con entry point per crearne uno nuovo.
class ToursTab extends StatefulWidget {
  const ToursTab({super.key});

  @override
  State<ToursTab> createState() => _ToursTabState();
}

class _ToursTabState extends State<ToursTab> {
  final ToursRepository _repo = ToursRepository();
  List<Tour>? _tours;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tours = await _repo.getMyTours();
      if (!mounted) return;
      setState(() {
        _tours = tours;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const TourEditPage()),
    );
    if (created == true) _load();
  }

  Future<void> _openDetail(Tour tour) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TourDetailPage(tourId: tour.id)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: Text(context.l10n.newTour),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.danger.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: Text(context.l10n.retry)),
          ],
        ),
      );
    }

    if (_tours == null || _tours!.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 100),
            Center(
              child: Column(
                children: [
                  Icon(Icons.map_outlined, size: 80, color: AppColors.primary.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.noTours,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      context.l10n.createFirstTourHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tours!.length,
        itemBuilder: (ctx, i) => _TourCard(
          tour: _tours![i],
          onTap: () => _openDetail(_tours![i]),
        ),
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
    final hours = tour.totalDuration.inHours;
    final mins = tour.totalDuration.inMinutes % 60;
    final durStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.map, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tour.title,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${context.l10n.tourDays(tour.daysCount)} · ${context.l10n.tourStages(tour.trackIds.length)}',
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (tour.isPublic)
                    Icon(Icons.public, size: 18, color: AppColors.info),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _chip(context, Icons.straighten, '${tour.totalDistanceKm.toStringAsFixed(1)} km'),
                  _chip(context, Icons.trending_up, '+${tour.totalElevationGain.toStringAsFixed(0)} m', AppColors.success),
                  if (tour.totalDuration.inMinutes > 0)
                    _chip(context, Icons.schedule, durStr),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String value, [Color? color]) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? context.textSecondary),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 13, color: color ?? context.textPrimary, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
