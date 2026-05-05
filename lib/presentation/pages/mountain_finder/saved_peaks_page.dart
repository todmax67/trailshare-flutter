import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../data/models/mountain_peak.dart';
import '../../../data/repositories/saved_peaks_repository.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/topo_empty_state.dart';
import 'mountain_finder_page.dart';
import 'peak_map_page.dart';

/// Pagina "Le mie cime" — collezione personale di vette identificate
/// con il Mountain Finder e salvate dall'utente.
///
/// Mostra:
/// - Lista live (StreamBuilder su SavedPeaksRepository.watchAll)
/// - Per ogni cima: nome, altitudine, regione, distanza dalla posizione
///   corrente (se disponibile), pulsante remove
/// - Tap su una cima → PeakMapPage
/// - Empty state con CTA per aprire il Mountain Finder
class SavedPeaksPage extends StatefulWidget {
  const SavedPeaksPage({super.key});

  @override
  State<SavedPeaksPage> createState() => _SavedPeaksPageState();
}

class _SavedPeaksPageState extends State<SavedPeaksPage> {
  final SavedPeaksRepository _repo = SavedPeaksRepository();
  Position? _userPosition;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (mounted && pos != null) {
        setState(() => _userPosition = pos);
      }
    } catch (_) {}
  }

  Future<void> _removePeak(MountainPeak peak) async {
    try {
      await _repo.toggle(peak); // Rimuove se già salvata
      if (!mounted) return;
      AppSnackBar.success(
          context, context.l10n.mfDetailSaveRemoved);
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, context.l10n.mfDetailSaveError);
    }
  }

  double? _distanceKm(MountainPeak peak) {
    final pos = _userPosition;
    if (pos == null) return null;
    return _haversineKm(
      pos.latitude,
      pos.longitude,
      peak.latitude,
      peak.longitude,
    );
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.savedPeaksTitle),
      ),
      body: StreamBuilder<List<MountainPeak>>(
        stream: _repo.watchAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final peaks = snap.data ?? const [];
          if (peaks.isEmpty) {
            return _buildEmpty(context);
          }
          return Column(
            children: [
              _buildHeader(peaks.length),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: peaks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final peak = peaks[i];
                    return _PeakTile(
                      peak: peak,
                      distanceKm: _distanceKm(peak),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PeakMapPage(peak: peak),
                          ),
                        );
                      },
                      onRemove: () => _removePeak(peak),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(color: context.themedBorder),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.terrain, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.savedPeaksCount(count),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TopoEmptyState(
              title: context.l10n.savedPeaksEmptyTitle,
              message: context.l10n.savedPeaksEmptyBody,
              variant: 1,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MountainFinderPage(),
                  ),
                );
              },
              icon: const Icon(Icons.terrain),
              label: Text(context.l10n.savedPeaksOpenFinder),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeakTile extends StatelessWidget {
  final MountainPeak peak;
  final double? distanceKm;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PeakTile({
    required this.peak,
    required this.distanceKm,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isVolcano = peak.type == 'volcano';
    final accent = isVolcano ? AppColors.danger : AppColors.primary;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: context.themedBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isVolcano
                      ? Icons.local_fire_department
                      : Icons.terrain,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peak.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (peak.elevation != null) ...[
                          Text(
                            '${peak.elevation!.round()} m',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: accent,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (distanceKm != null) ...[
                          Icon(Icons.straighten,
                              size: 12, color: context.textMuted),
                          const SizedBox(width: 2),
                          Text(
                            '${distanceKm! < 10 ? distanceKm!.toStringAsFixed(1) : distanceKm!.toStringAsFixed(0)} km',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textMuted,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (peak.region != null && peak.region!.isNotEmpty)
                          Flexible(
                            child: Text(
                              peak.region!,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: Icon(
                  Icons.bookmark_remove_outlined,
                  color: context.textSecondary,
                ),
                tooltip: context.l10n.mfDetailSaveRemoved,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
