import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/web_layout.dart';
import '../../data/models/track.dart';
import '../../data/repositories/tracks_repository.dart';
import 'web_track_detail_page.dart';

/// Sezione "Le mie tracce" della dashboard web — versione potenziata
/// con search, filtri per macro-categoria e ordinamento.
///
/// Volutamente leggera (no edit, no upload, no foreground service):
/// la registrazione GPS resta solo su mobile, il web è
/// "consultativo" — vedi tracce, scarica GPX, condividi link.
///
/// Strategia carico: full-load via [TracksRepository.getMyTracks].
/// Per gli utenti tipici (qualche centinaia di tracce max) è
/// sufficiente; oltre quella soglia tornare al paginato + query
/// Firestore lato server.
class WebTracksListPage extends StatefulWidget {
  const WebTracksListPage({super.key});

  @override
  State<WebTracksListPage> createState() => _WebTracksListPageState();
}

/// Macro-categoria attività per i filter chips. Raggruppiamo le 14
/// [ActivityType] in 5 categorie + "All" per non saturare la UI.
enum _ActivityGroup { all, hike, run, bike, snow }

extension _ActivityGroupX on _ActivityGroup {
  String get label {
    switch (this) {
      case _ActivityGroup.all:
        return 'Tutte';
      case _ActivityGroup.hike:
        return 'Trek/Cammino';
      case _ActivityGroup.run:
        return 'Corsa';
      case _ActivityGroup.bike:
        return 'Bici';
      case _ActivityGroup.snow:
        return 'Neve';
    }
  }

  IconData get icon {
    switch (this) {
      case _ActivityGroup.all:
        return Icons.all_inclusive;
      case _ActivityGroup.hike:
        return Icons.terrain;
      case _ActivityGroup.run:
        return Icons.directions_run;
      case _ActivityGroup.bike:
        return Icons.directions_bike;
      case _ActivityGroup.snow:
        return Icons.ac_unit;
    }
  }

  bool matches(ActivityType type) {
    switch (this) {
      case _ActivityGroup.all:
        return true;
      case _ActivityGroup.hike:
        return type == ActivityType.trekking ||
            type == ActivityType.walking ||
            type == ActivityType.snowshoeing;
      case _ActivityGroup.run:
        return type == ActivityType.trailRunning ||
            type == ActivityType.running;
      case _ActivityGroup.bike:
        return type == ActivityType.cycling ||
            type == ActivityType.mountainBiking ||
            type == ActivityType.gravelBiking ||
            type == ActivityType.eBike ||
            type == ActivityType.eMountainBike;
      case _ActivityGroup.snow:
        return type == ActivityType.alpineSkiing ||
            type == ActivityType.skiTouring ||
            type == ActivityType.nordicSkiing ||
            type == ActivityType.snowboarding;
    }
  }
}

enum _SortMode {
  dateDesc,
  dateAsc,
  distanceDesc,
  elevationDesc,
  durationDesc,
}

extension _SortModeX on _SortMode {
  String get label {
    switch (this) {
      case _SortMode.dateDesc:
        return 'Più recenti';
      case _SortMode.dateAsc:
        return 'Più vecchie';
      case _SortMode.distanceDesc:
        return 'Distanza ↓';
      case _SortMode.elevationDesc:
        return 'Dislivello ↓';
      case _SortMode.durationDesc:
        return 'Durata ↓';
    }
  }
}

class _WebTracksListPageState extends State<WebTracksListPage> {
  final _repo = TracksRepository();
  final _searchController = TextEditingController();

  List<Track> _all = [];
  bool _loading = true;

  String _query = '';
  _ActivityGroup _group = _ActivityGroup.all;
  _SortMode _sort = _SortMode.dateDesc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tracks = await _repo.getMyTracks();
    if (!mounted) return;
    setState(() {
      _all = tracks;
      _loading = false;
    });
  }

  List<Track> get _filtered {
    final q = _query.trim().toLowerCase();
    Iterable<Track> out = _all;
    if (_group != _ActivityGroup.all) {
      out = out.where((t) => _group.matches(t.activityType));
    }
    if (q.isNotEmpty) {
      out = out.where((t) => t.name.toLowerCase().contains(q));
    }
    final list = out.toList();
    switch (_sort) {
      case _SortMode.dateDesc:
        list.sort((a, b) => (b.recordedAt ?? b.createdAt)
            .compareTo(a.recordedAt ?? a.createdAt));
        break;
      case _SortMode.dateAsc:
        list.sort((a, b) => (a.recordedAt ?? a.createdAt)
            .compareTo(b.recordedAt ?? b.createdAt));
        break;
      case _SortMode.distanceDesc:
        list.sort((a, b) => b.stats.distance.compareTo(a.stats.distance));
        break;
      case _SortMode.elevationDesc:
        list.sort(
            (a, b) => b.stats.elevationGain.compareTo(a.stats.elevationGain));
        break;
      case _SortMode.durationDesc:
        list.sort((a, b) => b.stats.duration.compareTo(a.stats.duration));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: WebContentWrapper(
        maxWidth: 880,
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildToolbar()),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_all.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else if (_filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoResultsState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  sliver: SliverList.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) =>
                        _TrackTile(track: _filtered[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final user = FirebaseAuth.instance.currentUser;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Le mie tracce',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.displayName != null
                ? 'Tracce di ${user!.displayName}'
                : 'Tutte le tracce registrate dal tuo account TrailShare',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          if (!_loading)
            Text(
              _filtered.length == _all.length
                  ? '${_all.length} ${_all.length == 1 ? "traccia" : "tracce"}'
                  : '${_filtered.length} di ${_all.length} tracce',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Riga 1: search + sort
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Cerca per nome…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.border,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.border,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _SortDropdown(
                value: _sort,
                onChanged: (v) => setState(() => _sort = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Riga 2: filter chips macro-categoria
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _ActivityGroup.values.map((g) {
                final selected = _group == g;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          g.icon,
                          size: 16,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(g.label),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _group = g),
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    backgroundColor: AppColors.surface,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.border,
                    ),
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final _SortMode value;
  final ValueChanged<_SortMode> onChanged;
  const _SortDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_SortMode>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          isDense: true,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          items: _SortMode.values
              .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined,
                size: 56, color: AppColors.textMuted.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            const Text(
              'Nessuna traccia ancora',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Apri TrailShare sul telefono e registra la tua prima traccia. '
              'Una volta registrata la troverai qui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 48, color: AppColors.textMuted.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            const Text(
              'Nessun risultato',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Prova a modificare i filtri o la ricerca.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final Track track;
  const _TrackTile({required this.track});

  String _formatDate(DateTime d) {
    const months = [
      'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
      'lug', 'ago', 'set', 'ott', 'nov', 'dic',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final stats = track.stats;
    final km = (stats.distance / 1000).toStringAsFixed(1);
    final ele = stats.elevationGain.toStringAsFixed(0);
    final duration = _formatDuration(stats.duration);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WebTrackDetailPage(track: track),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    track.activityType.icon,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.activityType.displayName} · '
                      '${_formatDate(track.recordedAt ?? track.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _Metric(label: 'km', value: km),
              const SizedBox(width: 16),
              _Metric(label: 'D+', value: '${ele}m'),
              const SizedBox(width: 16),
              _Metric(label: 'tempo', value: duration),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
