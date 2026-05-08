import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/gamification_service.dart';
import '../../core/utils/web_layout.dart';
import '../../data/models/track.dart';
import '../../data/repositories/tracks_repository.dart';

/// Profilo personale dell'utente — versione web.
///
/// Mostra:
/// - Hero: avatar, nome, livello, barra XP verso prossimo livello
/// - Lifetime stats (totali tracce/km/D+/tempo)
/// - Breakdown per macro-categoria attività
/// - Volume annuale (12 mesi anno corrente)
/// - Badge: sbloccati + locked roadmap
class WebProfilePage extends StatefulWidget {
  const WebProfilePage({super.key});

  @override
  State<WebProfilePage> createState() => _WebProfilePageState();
}

class _WebProfilePageState extends State<WebProfilePage> {
  final _tracksRepo = TracksRepository();
  final _gamification = GamificationService();
  final _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  List<Track> _tracks = [];
  int _totalXp = 0;
  List<UnlockedBadge> _unlocked = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);

    final results = await Future.wait([
      _tracksRepo.getMyTracksLightweight(),
      _firestore.collection('user_profiles').doc(user.uid).get(),
      _gamification.getUnlockedBadges(user.uid),
    ]);

    if (!mounted) return;

    final tracks = results[0] as List<Track>;
    final profileDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    final unlocked = results[2] as List<UnlockedBadge>;

    setState(() {
      _tracks = tracks;
      _totalXp = (profileDoc.data()?['totalXp'] as num?)?.toInt() ?? 0;
      _unlocked = unlocked;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final levelInfo = _gamification.calculateLevelInfo(_totalXp);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: WebContentWrapper(
        maxWidth: 960,
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  children: [
                    _HeroHeader(user: user, levelInfo: levelInfo),
                    const SizedBox(height: 20),
                    _LifetimeStats(tracks: _tracks),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _MonthlyVolumeCard(tracks: _tracks),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _ActivityBreakdownCard(tracks: _tracks),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _BadgesSection(unlocked: _unlocked),
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ),
    );
  }
}

// ============================================================
// HERO HEADER
// ============================================================

class _HeroHeader extends StatelessWidget {
  final User? user;
  final LevelInfo levelInfo;
  const _HeroHeader({required this.user, required this.levelInfo});

  @override
  Widget build(BuildContext context) {
    final name = user?.displayName ?? user?.email?.split('@').first ?? 'Utente';
    final email = user?.email ?? '';
    final photo = user?.photoURL;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.10),
            AppColors.primary.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _Avatar(name: name, photoUrl: photo),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Liv. ${levelInfo.level}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      levelInfo.levelName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: levelInfo.progress / 100,
                    minHeight: 8,
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${levelInfo.progressText}  ·  '
                  '${levelInfo.nextLevelXp} XP al prossimo livello',
                  style: const TextStyle(
                    fontSize: 11,
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

class _Avatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  const _Avatar({required this.name, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: photoUrl != null && photoUrl!.isNotEmpty
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: photoUrl!,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _initialAvatar(initial),
              ),
            )
          : _initialAvatar(initial),
    );
  }

  Widget _initialAvatar(String c) => Center(
        child: Text(
          c,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
}

// ============================================================
// LIFETIME STATS
// ============================================================

class _LifetimeStats extends StatelessWidget {
  final List<Track> tracks;
  const _LifetimeStats({required this.tracks});

  @override
  Widget build(BuildContext context) {
    final totalKm = tracks.fold<double>(
            0, (s, t) => s + t.stats.distance) /
        1000;
    final totalEle = tracks.fold<double>(
        0, (s, t) => s + t.stats.elevationGain);
    final totalSec = tracks.fold<int>(
        0, (s, t) => s + t.stats.duration.inSeconds);
    final totalH = totalSec / 3600;

    return GridView.count(
      crossAxisCount: 4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.7,
      children: [
        _StatTile(
          icon: Icons.route,
          color: const Color(0xFF2E7D5B),
          label: 'Tracce',
          value: tracks.length.toString(),
        ),
        _StatTile(
          icon: Icons.straighten,
          color: const Color(0xFF1976D2),
          label: 'km totali',
          value: totalKm.toStringAsFixed(1),
        ),
        _StatTile(
          icon: Icons.terrain,
          color: const Color(0xFFE65100),
          label: 'D+ totali',
          value: '${totalEle.toStringAsFixed(0)}m',
        ),
        _StatTile(
          icon: Icons.timer,
          color: const Color(0xFF6A1B9A),
          label: 'Ore',
          value: totalH.toStringAsFixed(1),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
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

// ============================================================
// MONTHLY VOLUME (12 mesi anno corrente)
// ============================================================

class _MonthlyVolumeCard extends StatelessWidget {
  final List<Track> tracks;
  const _MonthlyVolumeCard({required this.tracks});

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final perMonthKm = List<double>.filled(12, 0);
    for (final t in tracks) {
      final d = t.recordedAt ?? t.createdAt;
      if (d.year != year) continue;
      perMonthKm[d.month - 1] += t.stats.distance / 1000;
    }
    final maxKm = perMonthKm.reduce((a, b) => a > b ? a : b);
    final maxY = (maxKm <= 0 ? 10.0 : (maxKm * 1.2)).ceilToDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Volume mensile',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$year',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'totale ${perMonthKm.reduce((a, b) => a + b).toStringAsFixed(0)} km',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.border,
                    strokeWidth: 1,
                    dashArray: const [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: maxY / 4,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        const labels = [
                          'G', 'F', 'M', 'A', 'M', 'G',
                          'L', 'A', 'S', 'O', 'N', 'D',
                        ];
                        final i = v.toInt();
                        if (i < 0 || i >= 12) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            labels[i],
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (int i = 0; i < 12; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: perMonthKm[i],
                          color: AppColors.primary,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                ],
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) =>
                        AppColors.textPrimary.withValues(alpha: 0.9),
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      '${rod.toY.toStringAsFixed(1)} km',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ACTIVITY BREAKDOWN
// ============================================================

class _ActivityBreakdownCard extends StatelessWidget {
  final List<Track> tracks;
  const _ActivityBreakdownCard({required this.tracks});

  @override
  Widget build(BuildContext context) {
    // Conteggio per macro-categoria
    final counts = <String, int>{};
    for (final t in tracks) {
      final g = _macroLabel(t.activityType);
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (s, e) => s + e.value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tipo attività',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Nessuna attività registrata',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BreakdownRow(
                  label: e.key,
                  count: e.value,
                  pct: e.value / total,
                  color: _colorFor(e.key),
                ),
              ),
        ],
      ),
    );
  }

  String _macroLabel(ActivityType t) {
    switch (t) {
      case ActivityType.trekking:
      case ActivityType.walking:
      case ActivityType.snowshoeing:
        return 'Trek/Cammino';
      case ActivityType.trailRunning:
      case ActivityType.running:
        return 'Corsa';
      case ActivityType.cycling:
      case ActivityType.mountainBiking:
      case ActivityType.gravelBiking:
      case ActivityType.eBike:
      case ActivityType.eMountainBike:
        return 'Bici';
      case ActivityType.alpineSkiing:
      case ActivityType.skiTouring:
      case ActivityType.nordicSkiing:
      case ActivityType.snowboarding:
        return 'Neve';
    }
  }

  Color _colorFor(String label) {
    switch (label) {
      case 'Trek/Cammino':
        return const Color(0xFF2E7D5B);
      case 'Corsa':
        return const Color(0xFFE65100);
      case 'Bici':
        return const Color(0xFF1976D2);
      case 'Neve':
        return const Color(0xFF6A1B9A);
      default:
        return AppColors.primary;
    }
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final int count;
  final double pct;
  final Color color;
  const _BreakdownRow({
    required this.label,
    required this.count,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$count · ${(pct * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BADGES
// ============================================================

class _BadgesSection extends StatelessWidget {
  final List<UnlockedBadge> unlocked;
  const _BadgesSection({required this.unlocked});

  @override
  Widget build(BuildContext context) {
    final unlockedIds = unlocked.map((u) => u.badge.id).toSet();
    final all = GamificationService.availableBadges;
    final lockedCount = all.length - unlockedIds.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Badge',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${unlockedIds.length} / ${all.length} sbloccati'
                '${lockedCount > 0 ? "  ·  $lockedCount da conquistare" : ""}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final badge in all)
                _BadgeTile(
                  badge: badge,
                  isUnlocked: unlockedIds.contains(badge.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final GameBadge badge;
  final bool isUnlocked;
  const _BadgeTile({required this.badge, required this.isUnlocked});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${badge.name}\n${badge.description}'
          '${badge.requirement != null ? "\n\n${badge.requirement}" : ""}',
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isUnlocked
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isUnlocked
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: isUnlocked ? 1.0 : 0.30,
              child: Text(
                badge.icon,
                style: const TextStyle(fontSize: 28),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              badge.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isUnlocked
                    ? AppColors.textPrimary
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
