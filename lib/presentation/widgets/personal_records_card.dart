import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../data/models/track.dart';
import '../../data/repositories/tracks_repository.dart';

/// Card "Personal Records" che confronta la traccia [current] con il
/// best storico dell'utente per lo stesso tipo di attività (Epic 4.7).
///
/// - Se la traccia è il nuovo PR per una metrica → badge "🏆 Nuovo PR!"
/// - Altrimenti mostra la percentuale rispetto al best (es. "82% del PR")
/// - Disclaimer "su N attività dello stesso tipo" per dare contesto
///
/// Engagement booster: dare all'utente un feedback chiaro sul progresso
/// di volume/distanza/dislivello senza dover navigare manualmente nello
/// storico.
class PersonalRecordsCard extends StatefulWidget {
  final Track current;
  const PersonalRecordsCard({super.key, required this.current});

  @override
  State<PersonalRecordsCard> createState() => _PersonalRecordsCardState();
}

class _PersonalRecordsCardState extends State<PersonalRecordsCard> {
  final _repo = TracksRepository();
  PersonalRecords? _records;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await _repo.getPersonalRecordsForActivity(
      activityType: widget.current.activityType.name,
      excludeTrackId: widget.current.id,
    );
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final records = _records;
    // Prima attività di questo tipo o nessuno storico → niente confronto.
    if (records == null || records.sampleSize == 0) {
      return const SizedBox.shrink();
    }
    final current = widget.current;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events_outlined,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Personal Records',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  'su ${records.sampleSize} attività',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MetricRow(
              icon: Icons.straighten,
              label: 'Distanza',
              currentValue: '${(current.stats.distance / 1000).toStringAsFixed(2)} km',
              bestValue: records.bestDistance != null
                  ? '${(records.bestDistance!.stats.distance / 1000).toStringAsFixed(2)} km'
                  : null,
              ratio: records.bestDistance != null
                  ? current.stats.distance / records.bestDistance!.stats.distance
                  : null,
              isNewRecord: records.isNewDistanceRecord(current),
            ),
            const SizedBox(height: 10),
            _MetricRow(
              icon: Icons.timer_outlined,
              label: 'Durata',
              currentValue: _formatDuration(current.stats.duration),
              bestValue: records.bestDuration != null
                  ? _formatDuration(records.bestDuration!.stats.duration)
                  : null,
              ratio: records.bestDuration != null
                  ? current.stats.duration.inSeconds /
                      records.bestDuration!.stats.duration.inSeconds
                  : null,
              isNewRecord: records.isNewDurationRecord(current),
            ),
            const SizedBox(height: 10),
            _MetricRow(
              icon: Icons.trending_up,
              label: 'Dislivello',
              currentValue: '${current.stats.elevationGain.toStringAsFixed(0)} m',
              bestValue: records.bestElevation != null
                  ? '${records.bestElevation!.stats.elevationGain.toStringAsFixed(0)} m'
                  : null,
              ratio: records.bestElevation != null && records.bestElevation!.stats.elevationGain > 0
                  ? current.stats.elevationGain /
                      records.bestElevation!.stats.elevationGain
                  : null,
              isNewRecord: records.isNewElevationRecord(current),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _MetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String currentValue;
  final String? bestValue;
  final double? ratio;
  final bool isNewRecord;

  const _MetricRow({
    required this.icon,
    required this.label,
    required this.currentValue,
    required this.bestValue,
    required this.ratio,
    required this.isNewRecord,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.textMuted),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            currentValue,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (isNewRecord)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏆', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 4),
                Text(
                  'Nuovo PR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          )
        else if (ratio != null && bestValue != null) ...[
          Text(
            '${(ratio! * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              color: context.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'di $bestValue',
            style: TextStyle(
              fontSize: 11,
              color: context.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}
