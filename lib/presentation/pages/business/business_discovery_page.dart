import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
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

class _BusinessDiscoveryPageState extends State<BusinessDiscoveryPage> {
  final _repo = BusinessRepository();

  bool _showMap = false;
  bool _loading = true;
  String? _error;
  List<Business> _businesses = [];
  LatLng? _userPos;
  BusinessType? _filterType;
  double _radiusKm = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Posizione utente
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

      final list = await _repo.getNearby(
        lat: _userPos!.latitude,
        lng: _userPos!.longitude,
        radiusKm: _radiusKm,
        type: _filterType,
      );
      debugPrint('[BusinessDiscovery] userPos=${_userPos!.latitude},'
          '${_userPos!.longitude} radius=$_radiusKm type=${_filterType?.name} '
          'found=${list.length}');
      for (final b in list) {
        debugPrint('  → ${b.name} @ ${b.location.lat},${b.location.lng} '
            '(${_haversineKm(_userPos!.latitude, _userPos!.longitude, b.location.lat, b.location.lng).toStringAsFixed(1)}km)');
      }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spazi Pro'),
        actions: [
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
          _buildFilters(),
          Expanded(child: _buildBody()),
        ],
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
    if (_businesses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_searching,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(_filterType == null
                ? 'Nessuno Spazio Pro entro ${_radiusKm.round()} km'
                : 'Nessun ${_filterType!.displayName.toLowerCase()} nelle vicinanze'),
            const SizedBox(height: 4),
            const Text(
              'Espandi il raggio o cambia filtro',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return _showMap ? _buildMap() : _buildList();
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _businesses.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _BusinessCard(
          business: _businesses[i],
          distanceKm: _distance(_businesses[i]),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  BusinessProfilePage(businessId: _businesses[i].id!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (_userPos == null) return const SizedBox.shrink();
    return FlutterMap(
      options: MapOptions(
        initialCenter: _userPos!,
        initialZoom: 11,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.trailshare.app',
        ),
        MarkerLayer(
          markers: [
            // User position
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
            // Businesses
            ..._businesses.map(
              (b) => Marker(
                point: LatLng(b.location.lat, b.location.lng),
                width: 44,
                height: 44,
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
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BusinessCard extends StatelessWidget {
  final Business business;
  final double distanceKm;
  final VoidCallback onTap;

  const _BusinessCard({
    required this.business,
    required this.distanceKm,
    required this.onTap,
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
                        Text(
                          '${distanceKm.toStringAsFixed(1)} km',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
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
