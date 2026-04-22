import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/italian_regions.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/user_region_service.dart';
import '../../../data/repositories/regional_leaderboard_repository.dart';
import '../../widgets/region_picker_sheet.dart';
import '../../widgets/topo_empty_state.dart';
import '../profile/public_profile_page.dart';

/// Pagina "Classifica regionale" — top utenti della stessa regione
/// dell'utente corrente, con due tab: "Totale" (per XP) e "Mese in corso"
/// (per distanza del mese).
///
/// Se l'utente non ha ancora impostato una regione, mostra un empty state
/// con CTA per aprire il [showRegionPickerSheet].
class RegionalLeaderboardPage extends StatefulWidget {
  const RegionalLeaderboardPage({super.key});

  @override
  State<RegionalLeaderboardPage> createState() =>
      _RegionalLeaderboardPageState();
}

class _RegionalLeaderboardPageState extends State<RegionalLeaderboardPage>
    with SingleTickerProviderStateMixin {
  final _repo = RegionalLeaderboardRepository();
  final _regionService = UserRegionService();

  late final TabController _tabController;
  List<RegionalLeaderboardEntry>? _allTime;
  List<RegionalLeaderboardEntry>? _monthly;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    if (!_regionService.isLoaded) {
      await _regionService.load();
    }
    final code = _regionService.cachedRegionCode;
    if (code == null || code.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _allTime = null;
        _monthly = null;
      });
      return;
    }

    final allTimeFuture = _repo.getTop(
      regionCode: code,
      period: RegionalLeaderboardPeriod.allTime,
    );
    final monthlyFuture = _repo.getTop(
      regionCode: code,
      period: RegionalLeaderboardPeriod.monthly,
    );

    final results = await Future.wait([allTimeFuture, monthlyFuture]);
    if (!mounted) return;
    setState(() {
      _allTime = results[0];
      _monthly = results[1];
      _loading = false;
    });
  }

  Future<void> _openRegionPicker() async {
    final selected = await showRegionPickerSheet(
      context,
      currentCode: _regionService.cachedRegionCode,
    );
    if (selected != null) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final region = _regionService.cachedRegion;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.regionalLeaderboardTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: context.textPrimary,
        actions: [
          if (region != null)
            IconButton(
              icon: const Icon(Icons.edit_location_alt_outlined),
              tooltip: context.l10n.regionalLeaderboardChangeRegion,
              onPressed: _openRegionPicker,
            ),
        ],
        bottom: region != null
            ? TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: context.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: [
                  Tab(text: context.l10n.regionalLeaderboardTabAllTime),
                  Tab(text: context.l10n.regionalLeaderboardTabMonthly),
                ],
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : region == null
              ? _buildNoRegion()
              : Column(
                  children: [
                    _buildRegionHeader(region, locale),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildList(
                            _allTime ?? const [],
                            period: RegionalLeaderboardPeriod.allTime,
                          ),
                          _buildList(
                            _monthly ?? const [],
                            period: RegionalLeaderboardPeriod.monthly,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildRegionHeader(ItalianRegion region, String locale) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: context.themedBorder),
        ),
      ),
      child: Row(
        children: [
          Text(
            region.flag,
            style: const TextStyle(fontSize: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  region.displayName(locale),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  context.l10n.regionalLeaderboardYourRegion,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoRegion() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TopoEmptyState(
              title: context.l10n.regionalLeaderboardNoRegionTitle,
              message: context.l10n.regionalLeaderboardNoRegionBody,
              variant: 1,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openRegionPicker,
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: Text(context.l10n.regionalLeaderboardSetRegionCta),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    List<RegionalLeaderboardEntry> entries, {
    required RegionalLeaderboardPeriod period,
  }) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: TopoEmptyState(
          title: context.l10n.regionalLeaderboardEmptyTitle,
          message: period == RegionalLeaderboardPeriod.allTime
              ? context.l10n.regionalLeaderboardEmptyAllTime
              : context.l10n.regionalLeaderboardEmptyMonthly,
          variant: 0,
        ),
      );
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: entries.length,
        separatorBuilder: (_, i) => const SizedBox(height: 2),
        itemBuilder: (_, i) {
          final e = entries[i];
          return _LeaderboardTile(
            entry: e,
            period: period,
            isCurrentUser: e.userId == currentUid,
          );
        },
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final RegionalLeaderboardEntry entry;
  final RegionalLeaderboardPeriod period;
  final bool isCurrentUser;

  const _LeaderboardTile({
    required this.entry,
    required this.period,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final rankColor = _rankColor(entry.rank);
    final bg = isCurrentUser
        ? AppColors.primary.withValues(alpha: 0.10)
        : Colors.transparent;

    final primaryText = period == RegionalLeaderboardPeriod.allTime
        ? '${entry.totalXp} XP'
        : '${(entry.distance / 1000).toStringAsFixed(1)} km';
    final secondaryText = period == RegionalLeaderboardPeriod.allTime
        ? context.l10n.levelNumber(entry.level)
        : context.l10n.regionalLeaderboardTracksCount(entry.tracks);

    return Material(
      color: bg,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PublicProfilePage(userId: entry.userId),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: _RankBadge(rank: entry.rank, color: rankColor),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                backgroundImage:
                    entry.avatarUrl != null && entry.avatarUrl!.isNotEmpty
                        ? NetworkImage(entry.avatarUrl!)
                        : null,
                child: entry.avatarUrl == null || entry.avatarUrl!.isEmpty
                    ? Text(
                        entry.initial,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.username,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              context.l10n.regionalLeaderboardYouBadge,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      secondaryText,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    primaryText,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _rankColor(int rank) {
    if (rank == 1) return const Color(0xFFFFD700); // oro
    if (rank == 2) return const Color(0xFFC0C0C0); // argento
    if (rank == 3) return const Color(0xFFCD7F32); // bronzo
    return Colors.grey;
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  final Color color;

  const _RankBadge({required this.rank, required this.color});

  @override
  Widget build(BuildContext context) {
    if (rank <= 3) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      );
    }
    return Center(
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: context.textSecondary,
        ),
      ),
    );
  }
}
