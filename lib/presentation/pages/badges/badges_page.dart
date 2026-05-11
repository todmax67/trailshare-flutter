import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/badge_evaluator_service.dart';
import '../../../data/models/badge_family.dart';

/// Pagina Badge "Garmin-style" (Epic refactor).
///
/// 11 famiglie × 4 tier (Bronze / Argento / Oro / Platino) = 44 badge.
/// Ogni famiglia è una "card" con:
/// - icona grande dentro un ring colorato del tier corrente
/// - titolo + descrizione del tier
/// - progress bar verso il prossimo tier
/// - "X / Y unità" come label
///
/// Tab "I miei badge" mostra solo le famiglie con almeno il bronze;
/// "Tutti" mostra ogni famiglia anche se non ancora iniziata.
class BadgesPage extends StatefulWidget {
  const BadgesPage({super.key});

  @override
  State<BadgesPage> createState() => _BadgesPageState();
}

class _BadgesPageState extends State<BadgesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<BadgeProgress> _progress = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final progress = await BadgeEvaluatorService().getAllProgress();
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final earned = _progress.where((p) => p.currentTier != null).toList();
    final totalUnlocks = earned.fold<int>(
        0, (s, p) => s + (p.currentTier!.index + 1));
    final maxUnlocks = GameBadgeFamily.values.length * 4;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Badge'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Conquistati (${earned.length})'),
            Tab(text: 'Tutti (${GameBadgeFamily.values.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(totalUnlocks, maxUnlocks),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildEarnedTab(earned),
                      _buildAllTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(int unlocked, int max) {
    final ratio = max > 0 ? unlocked / max : 0.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.75),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events,
                  color: Colors.white, size: 28),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'I tuoi traguardi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$unlocked / $max',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarnedTab(List<BadgeProgress> earned) {
    if (earned.isEmpty) return _buildEmpty();
    final grouped = _groupByCategory(earned);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in grouped.entries) ...[
            _buildSectionTitle(entry.key),
            ...entry.value.map((p) => _BadgeFamilyCard(progress: p)),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildAllTab() {
    final grouped = _groupByCategory(_progress);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in grouped.entries) ...[
            _buildSectionTitle(entry.key),
            ...entry.value.map((p) => _BadgeFamilyCard(progress: p)),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Map<String, List<BadgeProgress>> _groupByCategory(
      List<BadgeProgress> list) {
    final out = <String, List<BadgeProgress>>{};
    for (final p in list) {
      out.putIfAbsent(p.family.categoryGroup, () => []).add(p);
    }
    // Ordine custom delle categorie
    final ordered = <String>[
      'Volume',
      'Sport',
      'Costanza',
      'Esplorazione',
      'Social',
    ];
    return {
      for (final k in ordered)
        if (out.containsKey(k)) k: out[k]!,
    };
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: context.textMuted,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏅', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text(
              'Nessun badge ancora',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Registra la tua prima traccia per iniziare a sbloccare i badge!',
              style: TextStyle(color: context.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _tabController.animateTo(1),
              icon: const Icon(Icons.visibility),
              label: const Text('Mostra tutti i badge'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card di una famiglia di badge. Rappresenta tutti e 4 i tier in modo
/// compatto: tier ring colorato + progress + 4 mini-pallini in fondo
/// che indicano quali tier sono unlocked.
class _BadgeFamilyCard extends StatelessWidget {
  final BadgeProgress progress;
  const _BadgeFamilyCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final family = progress.family;
    final tier = progress.currentTier;
    final tierColor = tier?.color ?? Colors.grey.shade400;
    final isLocked = tier == null;

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLocked
                ? context.themedBorder
                : tierColor.withValues(alpha: 0.4),
            width: isLocked ? 1 : 1.5,
          ),
        ),
        child: Row(
          children: [
            _TierRing(family: family, tier: tier),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          family.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (tier != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tier.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: tierColor,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    progress.progressLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.progressToNext,
                      minHeight: 5,
                      backgroundColor: Colors.grey.withValues(alpha: 0.18),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progress.nextTier?.color ??
                            (tier?.color ?? AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _TierDotsRow(progress: progress),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BadgeFamilyDetail(progress: progress),
    );
  }
}

class _TierRing extends StatelessWidget {
  final GameBadgeFamily family;
  final GameBadgeTier? tier;
  const _TierRing({required this.family, required this.tier});

  @override
  Widget build(BuildContext context) {
    final isLocked = tier == null;
    final color = tier?.color ?? Colors.grey.shade400;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isLocked
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tier!.gradient,
              ),
        color: isLocked ? Colors.grey.shade200 : null,
        border: Border.all(
          color: color,
          width: 2,
        ),
        boxShadow: isLocked
            ? null
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Center(
        child: Opacity(
          opacity: isLocked ? 0.35 : 1.0,
          child: Text(
            family.icon,
            style: const TextStyle(fontSize: 28),
          ),
        ),
      ),
    );
  }
}

/// 4 pallini affiancati che indicano lo stato di ciascun tier
/// (pieni se unlocked, vuoti se non ancora). Visibili sotto la
/// progress bar nella card.
class _TierDotsRow extends StatelessWidget {
  final BadgeProgress progress;
  const _TierDotsRow({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final tier in GameBadgeTier.values) ...[
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: progress.tierUnlocked(tier)
                  ? tier.color
                  : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
          if (tier != GameBadgeTier.platinum)
            Container(
              width: 12,
              height: 1,
              margin: const EdgeInsets.only(right: 4),
              color: progress.tierUnlocked(tier.next ?? tier)
                  ? (tier.next?.color ?? Colors.transparent)
                      .withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.2),
            ),
        ],
      ],
    );
  }
}

class _BadgeFamilyDetail extends StatelessWidget {
  final BadgeProgress progress;
  const _BadgeFamilyDetail({required this.progress});

  @override
  Widget build(BuildContext context) {
    final family = progress.family;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TierRing(family: family, tier: progress.currentTier),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        family.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        progress.progressLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Tier list
            for (final tier in GameBadgeTier.values) ...[
              _TierRow(family: family, tier: tier, progress: progress),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            if (progress.nextTier != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flag, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ti mancano ${BadgeProgress.formatValue(progress.remainingToNext)} ${family.unit} '
                        'per il tier ${progress.nextTier!.label}.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GameBadgeTier.platinum.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.workspace_premium,
                        color: GameBadgeTier.platinum.color),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Platino raggiunto. Tier massimo sbloccato!',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
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
}

class _TierRow extends StatelessWidget {
  final GameBadgeFamily family;
  final GameBadgeTier tier;
  final BadgeProgress progress;
  const _TierRow({
    required this.family,
    required this.tier,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final unlocked = progress.tierUnlocked(tier);
    final unlockedAt = progress.unlockedAtFor(tier);
    final threshold = family.thresholdFor(tier);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked
            ? tier.color.withValues(alpha: 0.06)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: unlocked
              ? tier.color.withValues(alpha: 0.4)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: unlocked
                  ? LinearGradient(
                      colors: tier.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: unlocked ? null : Colors.grey.withValues(alpha: 0.2),
            ),
            child: Center(
              child: Icon(
                unlocked ? Icons.check : Icons.lock_outline,
                color: unlocked ? Colors.white : Colors.grey,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tier.label} · ${BadgeProgress.formatValue(threshold)} ${family.unit}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: unlocked ? tier.color : context.textSecondary,
                  ),
                ),
                if (unlockedAt != null)
                  Text(
                    'Sbloccato il ${_formatDate(unlockedAt)}',
                    style: TextStyle(
                      fontSize: 11,
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

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
