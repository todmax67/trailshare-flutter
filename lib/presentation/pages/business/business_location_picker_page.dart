import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geohash_util.dart';

/// Picker della posizione di uno Spazio Pro.
///
/// Pattern "center-pin": l'utente sposta la mappa, il pin resta fisso al
/// centro dello schermo. Tap "Conferma posizione" → ritorna `LatLng` al
/// chiamante (che salverà tramite BusinessRepository).
///
/// Comodità:
/// - Bottone "📍 La mia posizione" per centrare su GPS corrente
/// - Coordinate live in basso (lat,lng arrotondate)
/// - Bottoni zoom in/out
class BusinessLocationPickerPage extends StatefulWidget {
  /// Posizione iniziale (es. quella attuale del business). Se null, usa
  /// la GPS corrente come default; se anche quella fallisce, fallback a
  /// Bergamo.
  final LatLng? initial;
  final String title;

  const BusinessLocationPickerPage({
    super.key,
    this.initial,
    this.title = 'Posizione del business',
  });

  @override
  State<BusinessLocationPickerPage> createState() =>
      _BusinessLocationPickerPageState();
}

class _BusinessLocationPickerPageState
    extends State<BusinessLocationPickerPage> {
  final MapController _map = MapController();
  LatLng _center = const LatLng(45.6982, 9.6773); // fallback Bergamo
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (widget.initial != null) {
      _center = widget.initial!;
      setState(() => _ready = true);
      return;
    }
    // Prova GPS corrente
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos != null) _center = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      // ignora — restiamo sul fallback
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _useMyLocation() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      final r = await Geolocator.requestPermission();
      if (r == LocationPermission.denied ||
          r == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permesso posizione negato')),
        );
        return;
      }
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final p = LatLng(pos.latitude, pos.longitude);
      _map.move(p, 15);
      setState(() => _center = p);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossibile leggere la posizione: $e')),
      );
    }
  }

  void _confirm() {
    Navigator.pop(context, _center);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'La mia posizione',
            onPressed: _useMyLocation,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: widget.initial != null ? 15 : 11,
              minZoom: 4,
              maxZoom: 19,
              onPositionChanged: (pos, _) {
                setState(() => _center = pos.center);
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.trailshare.app',
              ),
            ],
          ),
          // Pin centrale fisso
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on,
                        size: 48, color: AppColors.primary),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Banner bottom: coordinate + conferma
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.gps_fixed,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          '${_center.latitude.toStringAsFixed(5)}, '
                          '${_center.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _confirm,
                        icon: const Icon(Icons.check),
                        label: const Text('Conferma posizione'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper: dato un [LatLng] nuovo, ritorna la mappa Firestore aggiornata
/// per il campo `location` di un business (lat/lng/geohash + altri
/// campi preservati).
Map<String, dynamic> buildLocationUpdate({
  required LatLng newPos,
  required Map<String, dynamic> oldLocationMap,
}) {
  return {
    ...oldLocationMap,
    'lat': newPos.latitude,
    'lng': newPos.longitude,
    'geohash': GeoHashUtil.encode(newPos.latitude, newPos.longitude),
  };
}
