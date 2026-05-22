import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/map_styles.dart';
import '../../../core/services/offline_tile_provider.dart';
import '../../../core/extensions/l10n_extension.dart';

/// Pagina full-screen per scegliere la posizione di un nuovo POI tappando
/// sulla mappa. Mostra la polyline di riferimento (trail/track) per aiutare
/// l'utente a posizionare il POI lungo il percorso.
///
/// Ritorna `LatLng` della posizione scelta, o null se annullato.
class PoiLocationPickerPage extends StatefulWidget {
  /// Polyline del trail o track su cui posizionare il POI. Se vuoto
  /// mostra solo la mappa senza linea guida.
  final List<LatLng> polyline;

  /// Centro iniziale della mappa. Se null usa il primo punto della
  /// polyline o un fallback (centro Italia).
  final LatLng? initialCenter;

  /// Titolo dell'app bar (es. "Dove si trova il POI?").
  final String title;

  const PoiLocationPickerPage({
    super.key,
    this.polyline = const [],
    this.initialCenter,
    this.title = 'Scegli la posizione del POI',
  });

  @override
  State<PoiLocationPickerPage> createState() => _PoiLocationPickerPageState();
}

class _PoiLocationPickerPageState extends State<PoiLocationPickerPage> {
  final MapController _mapController = MapController();
  LatLng? _picked;
  int _currentMapStyle = 0;

  LatLng get _startCenter =>
      widget.initialCenter ??
      (widget.polyline.isNotEmpty
          ? widget.polyline.first
          : const LatLng(42.5, 12.5));

  double get _startZoom => widget.polyline.length > 1 ? 14 : 11;

  void _onMapTap(TapPosition tapPosition, LatLng latLng) {
    setState(() => _picked = latLng);
  }

  void _snapToNearestOnPolyline() {
    if (widget.polyline.isEmpty || _picked == null) return;
    final dist = const Distance();
    LatLng nearest = widget.polyline.first;
    double min = double.infinity;
    for (final p in widget.polyline) {
      final d = dist.as(LengthUnit.Meter, _picked!, p);
      if (d < min) {
        min = d;
        nearest = p;
      }
    }
    setState(() => _picked = nearest);
  }

  @override
  Widget build(BuildContext context) {
    final bounds = widget.polyline.length >= 2
        ? LatLngBounds.fromPoints(widget.polyline)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.polyline.isNotEmpty && _picked != null)
            IconButton(
              icon: const Icon(Icons.route),
              tooltip: 'Aggancia al percorso',
              onPressed: _snapToNearestOnPolyline,
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _startCenter,
              initialZoom: _startZoom,
              minZoom: 4,
              maxZoom: 18,
              initialCameraFit: bounds != null
                  ? CameraFit.bounds(
                      bounds: bounds, padding: const EdgeInsets.all(50))
                  : null,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: mapStyles[_currentMapStyle].urlTemplate,
                subdomains: mapStyles[_currentMapStyle].subdomains,
                userAgentPackageName: 'com.trailshare.app',
                tileProvider: OfflineFallbackTileProvider(),
                tileBuilder:
                    mapStyles[_currentMapStyle].tileColorFilter != null
                        ? (context, tileWidget, tile) => ColorFiltered(
                              colorFilter:
                                  mapStyles[_currentMapStyle].tileColorFilter!,
                              child: tileWidget,
                            )
                        : null,
              ),
              if (widget.polyline.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: widget.polyline,
                    strokeWidth: 5,
                    color: AppColors.info.withValues(alpha: 0.7),
                    pattern:
                        StrokePattern.dashed(segments: const [10, 6]),
                  ),
                ]),
              if (_picked != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _picked!,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.success.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.place,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ]),
            ],
          ),

          // Helper in alto
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withValues(alpha: 0.95),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _picked == null
                          ? Icons.touch_app
                          : Icons.check_circle,
                      color: _picked == null
                          ? AppColors.info
                          : AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _picked == null
                            ? 'Tocca sulla mappa per posizionare il POI'
                            : 'Posizione scelta · ${_picked!.latitude.toStringAsFixed(5)}, ${_picked!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Cambio stile mappa in basso-destra
          Positioned(
            right: 12,
            bottom: 90,
            child: FloatingActionButton.small(
              heroTag: 'poi_picker_layer',
              backgroundColor: Colors.white,
              onPressed: () => setState(() =>
                  _currentMapStyle = (_currentMapStyle + 1) % mapStyles.length),
              child: Icon(mapStyles[_currentMapStyle].icon,
                  color: AppColors.primary),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop<LatLng?>(context, null),
                  child: Text(context.l10n.cancel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _picked == null
                      ? null
                      : () => Navigator.pop<LatLng>(context, _picked),
                  icon: const Icon(Icons.check),
                  label: const Text('Conferma posizione'),
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
      ),
    );
  }
}
