import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/heart_rate_zones.dart';

/// Widget che mostra la distribuzione del tempo nelle zone cardio
class HeartRateZonesWidget extends StatefulWidget {
  final Map<DateTime, int> heartRateData;

  const HeartRateZonesWidget({
    super.key,
    required this.heartRateData,
  });

  @override
  State<HeartRateZonesWidget> createState() => _HeartRateZonesWidgetState();
}

class _HeartRateZonesWidgetState extends State<HeartRateZonesWidget> {
  int _maxHR = 0;

  @override
  void initState() {
    super.initState();
    _loadMaxHR();
  }

  Future<void> _loadMaxHR() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('user_max_hr') ?? 0;
    if (mounted) setState(() => _maxHR = saved);
  }

  @override
  Widget build(BuildContext context) {
    if (_maxHR == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.monitor_heart, color: AppColors.danger.withOpacity(0.5)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Zone Cardio',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Imposta la tua FC massima nelle Impostazioni per vedere le zone cardio.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final zones = HeartRateZones(maxHR: _maxHR);
    final distribution = zones.calculateDistribution(widget.heartRateData);

    if (distribution.totalSeconds == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.monitor_heart, color: AppColors.danger, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Zone Cardio',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  'FC Max: $_maxHR',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Barre zone (dal 5 all'1, ordine classico)
            for (int z = 5; z >= 1; z--)
              _ZoneBar(
                zoneRange: zones.zones[z]!,
                percentage: distribution.percentageForZone(z),
                duration: distribution.formatDuration(z),
                color: _zoneColor(z),
              ),
          ],
        ),
      ),
    );
  }

  Color _zoneColor(int zone) {
    switch (zone) {
      case 1: return const Color(0xFF90CAF9); // Azzurro chiaro
      case 2: return const Color(0xFF66BB6A); // Verde
      case 3: return const Color(0xFFFFCA28); // Giallo
      case 4: return const Color(0xFFFF7043); // Arancione
      case 5: return const Color(0xFFEF5350); // Rosso
      default: return Colors.grey;
    }
  }
}

/// Singola barra di zona
class _ZoneBar extends StatelessWidget {
  final ZoneRange zoneRange;
  final double percentage;
  final String duration;
  final Color color;

  const _ZoneBar({
    required this.zoneRange,
    required this.percentage,
    required this.duration,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Label zona
          SizedBox(
            width: 28,
            child: Text(
              'Z${zoneRange.zone}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: color,
              ),
            ),
          ),

          // Barra
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Barra colorata
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      // Sfondo
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      // Riempimento
                      FractionallySizedBox(
                        widthFactor: (percentage / 100).clamp(0.0, 1.0),
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 6),
                          child: percentage >= 8
                              ? Text(
                                  '${percentage.toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Info zona
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  duration,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${zoneRange.minBpm}-${zoneRange.maxBpm}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}