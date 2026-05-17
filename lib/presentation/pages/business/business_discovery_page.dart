import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/italian_regions.dart';
import '../../../data/models/business.dart';
import '../../../data/repositories/business_repository.dart';
import 'business_profile_page.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Pagina Discovery degli Spazi Pro: lista + mappa dei business nelle
/// vicinanze. Filtri per tipo. Niente login richiesto per la lettura
/// (rules pubbliche).
class BusinessDiscoveryPage extends StatefulWidget {
  const BusinessDiscoveryPage({super.key});

  @override
  State<BusinessDiscoveryPage> createState() => _BusinessDiscoveryPageState();
}

/// Modo di discovery: "vicino a me" (default, UX consumer in zona) o
/// "tutta Italia" (planning viaggio).
enum _DiscoveryMode { nearby, nationwide }

class _BusinessDiscoveryPageState extends State<BusinessDiscoveryPage> {
  final _repo = BusinessRepository();
  final _searchCtrl = TextEditingController();

  _DiscoveryMode _mode = _DiscoveryMode.nearby;
  bool _showMap = false;
  bool _loading = true;
  String? _error;
  List<Business> _businesses = [];
  LatLng? _userPos;
  BusinessType? _filterType;
  String? _filterRegionCode; // solo in modo nationwide
  String _searchQuery = '';
  double _radiusKm = 50;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Posizione utente (anche in modo nationwide la calcoliamo,
      // così possiamo mostrare la distanza nelle card lista).
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        // Fallback Bergamo come default (zona test)
        _userPos = const LatLng(45.6982, 9.6773);
      } else {
        _userPos = LatLng(pos.latitude, pos.longitude);
      }

      List<Business> list;
      if (_mode == _DiscoveryMode.nationwide) {
        // Fetch nazionale (max 500). Filtri regione/search applicati
        // in-memory dal getter _filteredBusinesses.
        list = await _repo.getAllNationwide(
          type: _filterType,
          limit: 2000,
        );
      } else {
        list = await _repo.getNearby(
          lat: _userPos!.latitude,
          lng: _userPos!.longitude,
          radiusKm: _radiusKm,
          type: _filterType,
        );
      }
      debugPrint('[BusinessDiscovery] mode=${_mode.name} '
          'userPos=${_userPos!.latitude},${_userPos!.longitude} '
          'radius=$_radiusKm type=${_filterType?.name} '
          'found=${list.length}');
      if (!mounted) return;
      setState(() {
        _businesses = list;
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

  /// Lista filtrata in base a: search query, filtro regione (solo
  /// nationwide). Filtri applicati in memoria sul set fetched.
  List<Business> get _filteredBusinesses {
    Iterable<Business> result = _businesses;
    if (_mode == _DiscoveryMode.nationwide && _filterRegionCode != null) {
      final region = ItalianRegions.all.firstWhere(
        (r) => r.code == _filterRegionCode,
        orElse: () => const ItalianRegion(
            code: '', nameIt: '', nameEn: '', flag: ''),
      );
      if (region.code.isNotEmpty) {
        result = result.where((b) =>
            region.contains(b.location.lat, b.location.lng));
      }
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((b) =>
          b.name.toLowerCase().contains(q) ||
          (b.location.city?.toLowerCase().contains(q) ?? false));
    }
    final list = result.toList();
    // Ordering: nearby per distanza (già fatto dal repo), nationwide
    // per nome alfabetico (planning friendly).
    if (_mode == _DiscoveryMode.nationwide) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == _DiscoveryMode.nearby
          ? _DiscoveryMode.nationwide
          : _DiscoveryMode.nearby;
      // Reset filtri specifici al mode.
      if (_mode == _DiscoveryMode.nearby) {
        _filterRegionCode = null;
      }
    });
    _load();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim());
    });
  }

  double _distance(Business b) {
    if (_userPos == null) return 0;
    return _haversineKm(
      _userPos!.latitude,
      _userPos!.longitude,
      b.location.lat,
      b.location.lng,
    );
  }

  void _showMarkerSheet(Business b) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero / fallback
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 140,
                width: double.infinity,
                child: b.branding.heroPhotoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: b.branding.heroPhotoUrl!,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        alignment: Alignment.center,
                        child: Text(b.type.icon,
                            style: const TextStyle(fontSize: 56)),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(b.name,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(b.type.displayName,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                const Text('  •  ',
                    style: TextStyle(color: AppColors.textMuted)),
                const Icon(Icons.location_on,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 2),
                Text('${_distance(b).toStringAsFixed(1)} km',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            if (b.shortDescription != null) ...[
              const SizedBox(height: 8),
              Text(b.shortDescription!,
                  style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          BusinessProfilePage(businessId: b.id!),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Apri profilo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  @override
  Widget build(BuildContext context) {
    final isNationwide = _mode == _DiscoveryMode.nationwide;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spazi Pro'),
        actions: [
          // Toggle modo: vicino/nazionale. Icona contestuale.
          IconButton(
            icon: Icon(isNationwide
                ? Icons.my_location
                : Icons.public_outlined),
            tooltip: isNationwide ? 'Vicino a me' : 'Tutta Italia',
            onPressed: _toggleMode,
          ),
          IconButton(
            icon: Icon(_showMap ? Icons.list : Icons.map),
            tooltip: _showMap ? 'Lista' : 'Mappa',
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildModeIndicator(),
          _buildSearchBar(),
          _buildFilters(),
          if (isNationwide) _buildRegionFilter(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// Banner sottile che chiarisce in che modo siamo. Importante perché
  /// "Vicino a me" vs "Tutta Italia" cambia radicalmente il risultato
  /// e l'utente deve capirlo subito.
  Widget _buildModeIndicator() {
    final isNationwide = _mode == _DiscoveryMode.nationwide;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isNationwide
          ? AppColors.info.withValues(alpha: 0.1)
          : AppColors.primary.withValues(alpha: 0.06),
      child: Row(
        children: [
          Icon(
            isNationwide ? Icons.public : Icons.near_me,
            size: 14,
            color: isNationwide ? AppColors.info : AppColors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isNationwide
                  ? 'Tutta Italia · sfoglia per pianificare un viaggio'
                  : 'Vicino a te (${_radiusKm.round()} km)',
              style: TextStyle(
                fontSize: 12,
                color: isNationwide ? AppColors.info : AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Cerca per nome o città…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildRegionFilter() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _regionChip(null, 'Tutte le regioni'),
          ...ItalianRegions.all
              .where((r) => r.code != 'international')
              .map((r) => _regionChip(r.code, '${r.flag} ${r.nameIt}')),
        ],
      ),
    );
  }

  Widget _regionChip(String? code, String label) {
    final selected = _filterRegionCode == code;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) {
          setState(() => _filterRegionCode = code);
        },
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _filterChip(null, 'Tutti'),
          ...BusinessType.values.map(
            (t) => _filterChip(t, '${t.icon} ${t.displayName}'),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(BusinessType? type, String label) {
    final selected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _filterType = type);
          _load();
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.danger),
            SizedBox(height: 12),
            Text(context.l10n.genericErrorWith(_error.toString())),
            SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: Text(context.l10n.retry)),
          ],
        ),
      );
    }
    final filtered = _filteredBusinesses;
    if (filtered.isEmpty) {
      final isNationwide = _mode == _DiscoveryMode.nationwide;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_searching,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              isNationwide
                  ? _searchQuery.isNotEmpty || _filterRegionCode != null
                      ? 'Nessun risultato per i filtri attivi'
                      : 'Nessuno Spazio Pro in Italia'
                  : _filterType == null
                      ? 'Nessuno Spazio Pro entro ${_radiusKm.round()} km'
                      : 'Nessun ${_filterType!.displayName.toLowerCase()} nelle vicinanze',
            ),
            const SizedBox(height: 4),
            Text(
              isNationwide
                  ? 'Prova a cambiare regione o cercare per nome'
                  : 'Espandi il raggio o cambia filtro',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return _showMap ? _buildMap(filtered) : _buildList(filtered);
  }

  Widget _buildList(List<Business> items) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _BusinessCard(
          business: items[i],
          distanceKm: _distance(items[i]),
          showDistance: _mode == _DiscoveryMode.nearby,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  BusinessProfilePage(businessId: items[i].id!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMap(List<Business> items) {
    if (_userPos == null) return const SizedBox.shrink();
    final isNationwide = _mode == _DiscoveryMode.nationwide;

    // In modo nationwide, fit bounds su tutti i marker (zoom out su
    // Italia o regione filtrata). In modo nearby, center sull'utente
    // a zoom 11.
    MapOptions options;
    if (isNationwide && items.isNotEmpty) {
      final points = items
          .map((b) => LatLng(b.location.lat, b.location.lng))
          .toList();
      options = MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(40),
        ),
      );
    } else {
      options = MapOptions(
        initialCenter: _userPos!,
        initialZoom: 11,
      );
    }

    // Costruiamo prima i marker dei business (riutilizzati sia da
    // MarkerLayer nearby che da MarkerClusterLayerWidget nationwide).
    final businessMarkers = items
        .map((b) => Marker(
              point: LatLng(b.location.lat, b.location.lng),
              width: isNationwide ? 36 : 44,
              height: isNationwide ? 36 : 44,
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () => _showMarkerSheet(b),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      b.type.icon,
                      style: TextStyle(
                          fontSize: isNationwide ? 18 : 22),
                    ),
                  ),
                ),
              ),
            ))
        .toList();

    return FlutterMap(
      options: options,
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.trailshare.app',
        ),
        // User position — solo in modo nearby (in nazionale è
        // visivamente confondente, sarebbe sempre in un angolo).
        if (!isNationwide)
          MarkerLayer(
            markers: [
              Marker(
                point: _userPos!,
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.info,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ],
          ),
        // Business markers. In nationwide usiamo il cluster widget:
        // raggruppa marker vicini in una bolla numerata. Click sulla
        // bolla → zoom-in. In nearby (≤50km, max ~50 marker) niente
        // cluster — già leggibili a quel livello di zoom.
        if (isNationwide)
          MarkerClusterLayerWidget(
            options: MarkerClusterLayerOptions(
              maxClusterRadius: 60,
              size: const Size(48, 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(50),
              maxZoom: 14,
              markers: businessMarkers,
              builder: (context, markers) {
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${markers.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        else
          MarkerLayer(markers: businessMarkers),
      ],
    );
  }
}

class _BusinessCard extends StatelessWidget {
  final Business business;
  final double distanceKm;
  final bool showDistance;
  final VoidCallback onTap;

  const _BusinessCard({
    required this.business,
    required this.distanceKm,
    required this.onTap,
    this.showDistance = true,
  });

  @override
  Widget build(BuildContext context) {
    final b = business;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Thumbnail
            SizedBox(
              width: 100,
              child: b.branding.heroPhotoUrl != null
                  ? CachedNetworkImage(
                      imageUrl: b.branding.heroPhotoUrl!,
                      fit: BoxFit.cover,
                    )
                  : b.branding.logoUrl != null
                      ? CachedNetworkImage(
                          imageUrl: b.branding.logoUrl!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          alignment: Alignment.center,
                          child: Text(b.type.icon,
                              style: const TextStyle(fontSize: 36)),
                        ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      b.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            b.type.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        ),
                        const Text(' • ',
                            style: TextStyle(
                                color: AppColors.textMuted)),
                        const Icon(Icons.location_on,
                            size: 12, color: AppColors.textSecondary),
                        Flexible(
                          child: Text(
                            showDistance
                                ? '${distanceKm.toStringAsFixed(1)} km'
                                : (b.location.city ??
                                    'lat ${b.location.lat.toStringAsFixed(2)}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    if (b.shortDescription != null ||
                        b.description != null) ...[
                      const SizedBox(height: 4),
                      Flexible(
                        child: Text(
                          b.shortDescription ?? b.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
