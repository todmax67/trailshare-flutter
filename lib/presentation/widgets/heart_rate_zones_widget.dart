import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../core/extensions/l10n_extension.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../core/utils/heart_rate_zones.dart';
import '../pages/settings/settings_page.dart';

/// Widget che mostra la distribuzione del tempo nelle zone cardio (Z1-Z5).
///
/// 4.6 — Migliorato in v1.10.0:
/// - Localizzazione completa (IT/EN) di etichette e messaggi
/// - Fallback automatico: se l'utente non ha impostato la FC max, usiamo
///   il 105% del picco osservato in questa traccia come stima di lavoro
///   (con badge "stimata" e CTA per impostare il valore reale)
/// - Header con FC media + FC max della sessione
/// - Tap sull'header CTA porta alle impostazioni
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
  /// Valore impostato manualmente dall'utente; 0 se non settato.
  int _userMaxHR = 0;

  @override
  void initState() {
    super.initState();
    _loadMaxHR();
  }

  Future<void> _loadMaxHR() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('user_max_hr') ?? 0;
    if (mounted) setState(() => _userMaxHR = saved);
  }

  /// Calcola la FC media e di picco di questa sessione.
  ({int avg, int peak, bool hasData}) _sessionStats() {
    if (widget.heartRateData.isEmpty) {
      return (avg: 0, peak: 0, hasData: false);
    }
    final values = widget.heartRateData.values.toList();
    final sum = values.fold<int>(0, (s, v) => s + v);
    final avg = (sum / values.length).round();
    final peak = values.fold<int>(0, (m, v) => v > m ? v : m);
    return (avg: avg, peak: peak, hasData: true);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _sessionStats();
    if (!stats.hasData) {
      return const SizedBox.shrink();
    }

    // Fallback automatico: se l'utente non ha settato la FC max usiamo il
    // 105% del picco osservato (è una stima conservativa che tipicamente
    // non sottostima i valori reali).
    final isEstimated = _userMaxHR == 0;
    final effectiveMaxHR = isEstimated
        ? (stats.peak * 1.05).round().clamp(120, 220)
        : _userMaxHR;

    final zones = HeartRateZones(maxHR: effectiveMaxHR);
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
            // Header con titolo + stats sessione
            Row(
              children: [
                Icon(Icons.monitor_heart,
                    color: AppColors.danger, size: 20),
                const SizedBox(width: 8),
                Text(
                  context.l10n.hrZonesTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  context.l10n.hrZonesAvgPeak(stats.avg, stats.peak),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Riga FC max + chip "stimata" + CTA
            Row(
              children: [
                Text(
                  context.l10n.hrZonesMaxHR(effectiveMaxHR),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isEstimated) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      context.l10n.hrZonesEstimated,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (isEstimated)
                  TextButton(
                    onPressed: _openSettings,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      context.l10n.hrZonesSetCta,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

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

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    if (mounted) _loadMaxHR();
  }

  Color _zoneColor(int zone) {
    switch (zone) {
      case 1:
        return const Color(0xFF90CAF9); // Azzurro chiaro - Recupero
      case 2:
        return const Color(0xFF66BB6A); // Verde - Base aerobica
      case 3:
        return const Color(0xFFFFCA28); // Giallo - Aerobica
      case 4:
        return const Color(0xFFFF7043); // Arancione - Soglia
      case 5:
        return const Color(0xFFEF5350); // Rosso - Massimo
      default:
        return Colors.grey;
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      // Sfondo
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      // Riempimento
                      FractionallySizedBox(
                        widthFactor: (percentage / 100).clamp(0.0, 1.0),
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.7),
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
                  style: TextStyle(
                    fontSize: 10,
                    color: context.textMuted,
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
