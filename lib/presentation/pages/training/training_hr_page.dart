import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/utils/heart_rate_zones.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../../widgets/paywall_sheet.dart';
import '../../../core/services/pro_gate_service.dart';

/// Epic 6.5 — "Allenamento HR personalizzato" MVP.
///
/// Aggrega le tracce dell'utente delle ultime 4 settimane e mostra
/// per ogni settimana:
/// - n° tracce
/// - tempo totale registrato
/// - zona HR prevalente (quella in cui ha passato più tempo)
/// - suggerimento di prossima sessione basato sulla zona prevalente
///   (es. se sta sempre in Z2, suggerisci una sessione in Z3-Z4 per
///   stimolare la soglia anaerobica).
///
/// Feature Pro: gating via showPaywallSheet quando l'utente non è Pro.
class TrainingHrPage extends StatefulWidget {
  const TrainingHrPage({super.key});

  @override
  State<TrainingHrPage> createState() => _TrainingHrPageState();
}

class _TrainingHrPageState extends State<TrainingHrPage> {
  final _repo = TracksRepository();
  bool _loading = true;
  int _maxHR = 0;
  List<_WeekBucket> _weeks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('user_max_hr') ?? 0;
    if (saved > 0) _maxHR = saved;

    final tracks = await _repo.getMyTracksLightweight(limit: 200);
    final now = DateTime.now();
    final weekBuckets = <_WeekBucket>[];
    for (int w = 0; w < 4; w++) {
      // Settimane "rotolanti" di 7gg, dalla più recente.
      final end = now.subtract(Duration(days: 7 * w));
      final start = end.subtract(const Duration(days: 7));
      final inWindow = tracks.where((t) {
        final date = t.recordedAt ?? t.createdAt;
        return date.isAfter(start) && date.isBefore(end);
      }).toList();
      weekBuckets.add(_buildBucket(start: start, tracks: inWindow));
    }

    if (mounted) {
      setState(() {
        _weeks = weekBuckets;
        _loading = false;
      });
    }
  }

  _WeekBucket _buildBucket({
    required DateTime start,
    required List<Track> tracks,
  }) {
    if (tracks.isEmpty || _maxHR <= 0) {
      return _WeekBucket(
        start: start,
        trackCount: tracks.length,
        totalDuration: tracks.fold<Duration>(
          Duration.zero,
          (s, t) => s + t.stats.duration,
        ),
        dominantZone: null,
        zoneTimes: const {},
      );
    }
    // Aggrega tempo per zona sommando le distribuzioni di tutte le
    // tracce della settimana che hanno dati HR.
    final zones = HeartRateZones(maxHR: _maxHR);
    final totalSeconds = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    Duration totalDuration = Duration.zero;
    for (final t in tracks) {
      totalDuration += t.stats.duration;
      final hr = t.heartRateData;
      if (hr == null || hr.isEmpty) continue;
      final dist = zones.calculateDistribution(hr);
      for (int z = 1; z <= 5; z++) {
        totalSeconds[z] =
            (totalSeconds[z] ?? 0) + (dist.secondsPerZone[z] ?? 0);
      }
    }
    int dominantZone = 1;
    int maxSec = 0;
    for (int z = 1; z <= 5; z++) {
      final sec = totalSeconds[z] ?? 0;
      if (sec > maxSec) {
        maxSec = sec;
        dominantZone = z;
      }
    }
    return _WeekBucket(
      start: start,
      trackCount: tracks.length,
      totalDuration: totalDuration,
      dominantZone: maxSec > 0 ? dominantZone : null,
      zoneTimes: totalSeconds,
    );
  }

  String _suggestionFor(int? dominantZone) {
    switch (dominantZone) {
      case 1:
      case 2:
        return 'Stai costruendo bene la base aerobica. '
            'Per la prossima sessione prova qualche minuto in Zona 3-4 '
            '(80% sforzo) per stimolare la soglia.';
      case 3:
        return 'Buon mix base-soglia. Mantieni questo ritmo e '
            'aggiungi una sessione lunga settimanale in Z2 per il '
            'volume aerobico.';
      case 4:
        return 'Stai allenando intensità. Inserisci 1-2 sessioni '
            'lunghe in Z1-Z2 per recuperare e costruire base.';
      case 5:
        return 'Tanta Z5 = tanto stress. Ricorda i giorni di recupero '
            'attivo in Z1 per evitare overtraining.';
      default:
        return 'Imposta la FC max in Impostazioni per ricevere '
            'suggerimenti personalizzati sulle zone.';
    }
  }

  String _zoneName(int z) {
    switch (z) {
      case 1:
        return 'Recupero';
      case 2:
        return 'Base aerobica';
      case 3:
        return 'Aerobica';
      case 4:
        return 'Soglia';
      case 5:
        return 'Massimo';
      default:
        return '—';
    }
  }

  Color _zoneColor(int z) {
    switch (z) {
      case 1:
        return const Color(0xFF90CAF9);
      case 2:
        return const Color(0xFF66BB6A);
      case 3:
        return const Color(0xFFFFCA28);
      case 4:
        return const Color(0xFFFF7043);
      case 5:
        return const Color(0xFFEF5350);
      default:
        return Colors.grey;
    }
  }

  String _weekLabel(DateTime start) {
    final end = start.add(const Duration(days: 7));
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return '${fmt(start)} – ${fmt(end)}';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ProGateService().isPro;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Allenamento HR'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: context.textPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !isPro
              ? _buildPaywallCta()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildHeaderCard(),
                      const SizedBox(height: 16),
                      if (_maxHR <= 0) _buildSetMaxHrCta(),
                      const SizedBox(height: 12),
                      ..._weeks.map(_buildWeekCard),
                    ],
                  ),
                ),
    );
  }

  Widget _buildPaywallCta() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.workspace_premium,
              size: 64, color: AppColors.primary),
          const SizedBox(height: 16),
          const Text(
            'Allenamento HR personalizzato',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Analisi delle zone cardio sulle ultime 4 settimane + '
            'suggerimenti personalizzati per la prossima sessione. '
            'Disponibile con TrailShare Pro.',
            style: TextStyle(color: context.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => showPaywallSheet(
              context,
              trigger: PaywallTrigger.generic,
            ),
            icon: const Icon(Icons.lock_open),
            label: const Text('Sblocca con Pro'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final lastWeek = _weeks.isNotEmpty ? _weeks.first : null;
    final dominant = lastWeek?.dominantZone;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Ultimi 28 giorni',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _suggestionFor(dominant),
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetMaxHrCta() {
    return Card(
      color: AppColors.warning.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Imposta la FC max in Impostazioni per analisi zona corrette.',
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekCard(_WeekBucket w) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _weekLabel(w.start),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (w.dominantZone != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _zoneColor(w.dominantZone!)
                          .withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Z${w.dominantZone} • ${_zoneName(w.dominantZone!)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _zoneColor(w.dominantZone!),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.route, size: 14, color: context.textMuted),
                const SizedBox(width: 4),
                Text('${w.trackCount} tracce',
                    style: TextStyle(
                        fontSize: 12, color: context.textSecondary)),
                const SizedBox(width: 14),
                Icon(Icons.timer_outlined,
                    size: 14, color: context.textMuted),
                const SizedBox(width: 4),
                Text(_formatDuration(w.totalDuration),
                    style: TextStyle(
                        fontSize: 12, color: context.textSecondary)),
              ],
            ),
            if (w.dominantZone != null) ...[
              const SizedBox(height: 10),
              _buildZoneStrip(w),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildZoneStrip(_WeekBucket w) {
    final totalSec = w.zoneTimes.values.fold<int>(0, (s, v) => s + v);
    if (totalSec == 0) return const SizedBox.shrink();
    return Row(
      children: [
        for (int z = 1; z <= 5; z++)
          Expanded(
            flex: (w.zoneTimes[z] ?? 0).clamp(1, 10000),
            child: Container(
              height: 8,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: _zoneColor(z),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}

class _WeekBucket {
  final DateTime start;
  final int trackCount;
  final Duration totalDuration;
  final int? dominantZone;
  final Map<int, int> zoneTimes;

  const _WeekBucket({
    required this.start,
    required this.trackCount,
    required this.totalDuration,
    required this.dominantZone,
    required this.zoneTimes,
  });
}
