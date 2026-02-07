import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/track.dart';
import '../../data/repositories/community_tracks_repository.dart';
import '../pages/map/track_map_page.dart';

/// Widget mappa interattiva per visualizzare tracce GPS
/// 
/// Funzionalità:
/// - Zoom e pan abilitati
/// - Espandibile a fullscreen
/// - Marker posizione utente
/// - Marker foto (se forniti)
/// - Info al tap sul percorso
/// - Marker punto evidenziato (sincronizzazione con grafico)
class InteractiveTrackMap extends StatefulWidget {
  /// Punti del percorso
  final List<TrackPoint> points;
  
  /// Altezza della mappa in modalità compatta
  final double height;
  
  /// URL delle foto con posizione (opzionale)
  /// Mappa: url -> LatLng
  final Map<String, LatLng>? photoMarkers;
  
  /// Callback quando si tocca un marker foto
  final void Function(String url)? onPhotoMarkerTap;
  
  /// Mostra posizione utente
  final bool showUserLocation;
  
  /// Titolo per la pagina fullscreen
  final String? title;
  
  /// Indice del punto da evidenziare (sincronizzazione con grafico)
  final int? highlightedPointIndex;
  
  /// Callback quando si tocca un punto sul percorso
  final void Function(int index)? onPointTap;
  
  /// Track privata per fullscreen (opzionale)
  final Track? track;
  
  /// Track community per fullscreen (opzionale)
  final CommunityTrack? communityTrack;

  const InteractiveTrackMap({
    super.key,
    required this.points,
    this.height = 250,
    this.photoMarkers,
    this.onPhotoMarkerTap,
    this.showUserLocation = true,
    this.title,
    this.highlightedPointIndex,
    this.onPointTap,
    this.track,
    this.communityTrack,
  });

  @override
  State<InteractiveTrackMap> createState() => _InteractiveTrackMapState();
}

class _InteractiveTrackMapState extends State<InteractiveTrackMap> {
  final MapController _mapController = MapController();
  LatLng? _userPosition;
  LatLng? _tappedPoint;
  double? _tappedDistance;
  double? _tappedElevation;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    if (widget.showUserLocation) {
      _loadUserPosition();
    }
  }

  Future<void> _loadUserPosition() async {
    setState(() => _isLoadingLocation = true);
    
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      
      if (mounted) {
        setState(() {
          _userPosition = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      debugPrint('[InteractiveMap] Errore posizione: $e');
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  /// Calcola il centro e lo zoom ottimali per i punti
  (LatLng center, double zoom) _calculateBounds() {
    if (widget.points.isEmpty) {
      return (const LatLng(45.0, 9.0), 10.0);
    }

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    
    for (final p in widget.points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    
    double zoom = 14.0;
    if (maxDiff > 0.5) zoom = 10;
    else if (maxDiff > 0.2) zoom = 11;
    else if (maxDiff > 0.1) zoom = 12;
    else if (maxDiff > 0.05) zoom = 13;

    return (center, zoom);
  }

  /// Trova il punto più vicino al tap
  void _onMapTap(TapPosition tapPosition, LatLng tappedLatLng) {
    if (widget.points.isEmpty) return;

    // Trova il punto più vicino
    double minDistance = double.infinity;
    TrackPoint? nearestPoint;
    int nearestIndex = 0;
    
    for (int i = 0; i < widget.points.length; i++) {
      final p = widget.points[i];
      final distance = const Distance().as(
        LengthUnit.Meter,
        tappedLatLng,
        LatLng(p.latitude, p.longitude),
      );
      
      if (distance < minDistance) {
        minDistance = distance;
        nearestPoint = p;
        nearestIndex = i;
      }
    }

    // Solo se il tap è abbastanza vicino al percorso (< 100m)
    if (nearestPoint != null && minDistance < 100) {
      // Calcola distanza dall'inizio
      double totalDistance = 0;
      for (int i = 1; i <= nearestIndex; i++) {
        final prev = widget.points[i - 1];
        final curr = widget.points[i];
        totalDistance += const Distance().as(
          LengthUnit.Meter,
          LatLng(prev.latitude, prev.longitude),
          LatLng(curr.latitude, curr.longitude),
        );
      }

      setState(() {
        _tappedPoint = LatLng(nearestPoint!.latitude, nearestPoint.longitude);
        _tappedDistance = totalDistance;
        _tappedElevation = nearestPoint.elevation;
      });
      
      // ⭐ Notifica il parent dell'indice del punto toccato
      widget.onPointTap?.call(nearestIndex);
    } else {
      setState(() {
        _tappedPoint = null;
        _tappedDistance = null;
        _tappedElevation = null;
      });
    }
  }

  void _openFullscreen() {
    // Se abbiamo Track o CommunityTrack, usa TrackMapPage con colori pendenza
    if (widget.track != null || widget.communityTrack != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrackMapPage(
            track: widget.track,
            communityTrack: widget.communityTrack,
            showGradientColors: true,
          ),
        ),
      );
    } else {
      // Fallback alla pagina interna semplice
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _FullscreenMapPage(
            points: widget.points,
            photoMarkers: widget.photoMarkers,
            onPhotoMarkerTap: widget.onPhotoMarkerTap,
            userPosition: _userPosition,
            title: widget.title ?? 'Mappa',
          ),
        ),
      );
    }
  }

  void _centerOnTrack() {
    final (center, zoom) = _calculateBounds();
    _mapController.move(center, zoom);
  }

  void _centerOnUser() {
    if (_userPosition != null) {
      _mapController.move(_userPosition!, 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text('Nessun dato GPS disponibile'),
        ),
      );
    }

    final (center, zoom) = _calculateBounds();
    final polylinePoints = widget.points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            // Mappa
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                onTap: _onMapTap,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                // Tile layer
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.trailshare.app',
                  tileProvider: NetworkTileProvider(
                    headers: {'User-Agent': 'TrailShare/1.0 (https://trailshare.app)'},
                  ),
                ),
                
                // Percorso
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: polylinePoints,
                      strokeWidth: 4,
                      color: AppColors.primary,
                    ),
                  ],
                ),
                
                // Markers
                MarkerLayer(
                  markers: [
                    // Start marker
                    Marker(
                      point: polylinePoints.first,
                      width: 32,
                      height: 32,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                      ),
                    ),
                    
                    // End marker
                    Marker(
                      point: polylinePoints.last,
                      width: 32,
                      height: 32,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.flag, color: Colors.white, size: 16),
                      ),
                    ),
                    
                    // User position marker
                    if (_userPosition != null)
                      Marker(
                        point: _userPosition!,
                        width: 24,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Tapped point marker
                    if (_tappedPoint != null)
                      Marker(
                        point: _tappedPoint!,
                        width: 20,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.warning,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    
                    // Photo markers
                    if (widget.photoMarkers != null)
                      ...widget.photoMarkers!.entries.map((entry) => Marker(
                        point: entry.value,
                        width: 32,
                        height: 32,
                        child: GestureDetector(
                          onTap: () => widget.onPhotoMarkerTap?.call(entry.key),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.info,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                          ),
                        ),
                      )),
                    
                    // ⭐ Highlighted point marker (sincronizzazione con grafico)
                    if (widget.highlightedPointIndex != null && 
                        widget.highlightedPointIndex! >= 0 && 
                        widget.highlightedPointIndex! < polylinePoints.length)
                      Marker(
                        point: polylinePoints[widget.highlightedPointIndex!],
                        width: 28,
                        height: 28,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.5),
                                blurRadius: 10,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.location_on, color: Colors.white, size: 16),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            
            // Info box quando si tocca il percorso
            if (_tappedPoint != null)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.straighten, size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        '${(_tappedDistance! / 1000).toStringAsFixed(2)} km',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_tappedElevation != null) ...[
                        const SizedBox(width: 16),
                        const Icon(Icons.terrain, size: 16, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(
                          '${_tappedElevation!.toStringAsFixed(0)} m',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _tappedPoint = null),
                        child: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Controlli mappa
            Positioned(
              bottom: 8,
              right: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fullscreen
                  _MapButton(
                    icon: Icons.fullscreen,
                    onTap: _openFullscreen,
                    tooltip: 'Schermo intero',
                  ),
                  const SizedBox(height: 8),
                  // Centra su traccia
                  _MapButton(
                    icon: Icons.crop_free,
                    onTap: _centerOnTrack,
                    tooltip: 'Centra su traccia',
                  ),
                  if (widget.showUserLocation) ...[
                    const SizedBox(height: 8),
                    // Centra su utente
                    _MapButton(
                      icon: _isLoadingLocation 
                          ? Icons.hourglass_empty 
                          : Icons.my_location,
                      onTap: _userPosition != null ? _centerOnUser : _loadUserPosition,
                      tooltip: 'La mia posizione',
                      isLoading: _isLoadingLocation,
                    ),
                  ],
                ],
              ),
            ),
            
            // Indicatore foto se presenti
            if (widget.photoMarkers != null && widget.photoMarkers!.isNotEmpty)
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.photoMarkers!.length} foto',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET: Map Button
// ═══════════════════════════════════════════════════════════════════════════

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool isLoading;

  const _MapButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        elevation: 4,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE: Fullscreen Map
// ═══════════════════════════════════════════════════════════════════════════

class _FullscreenMapPage extends StatefulWidget {
  final List<TrackPoint> points;
  final Map<String, LatLng>? photoMarkers;
  final void Function(String url)? onPhotoMarkerTap;
  final LatLng? userPosition;
  final String title;

  const _FullscreenMapPage({
    required this.points,
    this.photoMarkers,
    this.onPhotoMarkerTap,
    this.userPosition,
    required this.title,
  });

  @override
  State<_FullscreenMapPage> createState() => _FullscreenMapPageState();
}

class _FullscreenMapPageState extends State<_FullscreenMapPage> {
  final MapController _mapController = MapController();
  LatLng? _tappedPoint;
  double? _tappedDistance;
  double? _tappedElevation;
  int _currentMapStyle = 0;
  
  final List<(String name, String url)> _mapStyles = [
    ('Standard', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
    ('Topo', 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png'),
    ('Satellite', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'),
  ];

  (LatLng center, double zoom) _calculateBounds() {
    if (widget.points.isEmpty) {
      return (const LatLng(45.0, 9.0), 10.0);
    }

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    
    for (final p in widget.points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    
    double zoom = 14.0;
    if (maxDiff > 0.5) zoom = 10;
    else if (maxDiff > 0.2) zoom = 11;
    else if (maxDiff > 0.1) zoom = 12;
    else if (maxDiff > 0.05) zoom = 13;

    return (center, zoom);
  }

  void _onMapTap(TapPosition tapPosition, LatLng tappedLatLng) {
    if (widget.points.isEmpty) return;

    double minDistance = double.infinity;
    TrackPoint? nearestPoint;
    int nearestIndex = 0;
    
    for (int i = 0; i < widget.points.length; i++) {
      final p = widget.points[i];
      final distance = const Distance().as(
        LengthUnit.Meter,
        tappedLatLng,
        LatLng(p.latitude, p.longitude),
      );
      
      if (distance < minDistance) {
        minDistance = distance;
        nearestPoint = p;
        nearestIndex = i;
      }
    }

    if (nearestPoint != null && minDistance < 100) {
      double totalDistance = 0;
      for (int i = 1; i <= nearestIndex; i++) {
        final prev = widget.points[i - 1];
        final curr = widget.points[i];
        totalDistance += const Distance().as(
          LengthUnit.Meter,
          LatLng(prev.latitude, prev.longitude),
          LatLng(curr.latitude, curr.longitude),
        );
      }

      setState(() {
        _tappedPoint = LatLng(nearestPoint!.latitude, nearestPoint.longitude);
        _tappedDistance = totalDistance;
        _tappedElevation = nearestPoint.elevation;
      });
    } else {
      setState(() {
        _tappedPoint = null;
        _tappedDistance = null;
        _tappedElevation = null;
      });
    }
  }

  void _cycleMapStyle() {
    setState(() {
      _currentMapStyle = (_currentMapStyle + 1) % _mapStyles.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final (center, zoom) = _calculateBounds();
    final polylinePoints = widget.points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // Cambio stile mappa
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: _cycleMapStyle,
            tooltip: _mapStyles[_currentMapStyle].$1,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              onTap: _onMapTap,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: _mapStyles[_currentMapStyle].$2,
                userAgentPackageName: 'com.trailshare.app',
                subdomains: const ['a', 'b', 'c'],
                tileProvider: NetworkTileProvider(
                  headers: {'User-Agent': 'TrailShare/1.0 (https://trailshare.app)'},
                ),
              ),
              
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: polylinePoints,
                    strokeWidth: 5,
                    color: AppColors.primary,
                  ),
                ],
              ),
              
              MarkerLayer(
                markers: [
                  // Start
                  Marker(
                    point: polylinePoints.first,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                    ),
                  ),
                  
                  // End
                  Marker(
                    point: polylinePoints.last,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.flag, color: Colors.white, size: 20),
                    ),
                  ),
                  
                  // User
                  if (widget.userPosition != null)
                    Marker(
                      point: widget.userPosition!,
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // Tapped
                  if (_tappedPoint != null)
                    Marker(
                      point: _tappedPoint!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  
                  // Photos
                  if (widget.photoMarkers != null)
                    ...widget.photoMarkers!.entries.map((entry) => Marker(
                      point: entry.value,
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () {
                          widget.onPhotoMarkerTap?.call(entry.key);
                          Navigator.pop(context);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.info,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                        ),
                      ),
                    )),
                ],
              ),
            ],
          ),
          
          // Info box
          if (_tappedPoint != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.straighten, size: 20, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Distanza: ${(_tappedDistance! / 1000).toStringAsFixed(2)} km',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          if (_tappedElevation != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.terrain, size: 20, color: AppColors.success),
                                const SizedBox(width: 8),
                                Text(
                                  'Quota: ${_tappedElevation!.toStringAsFixed(0)} m',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _tappedPoint = null),
                    ),
                  ],
                ),
              ),
            ),
          
          // Style indicator
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                _mapStyles[_currentMapStyle].$1,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ),
          
          // Controls
          Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapButton(
                  icon: Icons.crop_free,
                  onTap: () {
                    final (c, z) = _calculateBounds();
                    _mapController.move(c, z);
                  },
                  tooltip: 'Centra su traccia',
                ),
                if (widget.userPosition != null) ...[
                  const SizedBox(height: 8),
                  _MapButton(
                    icon: Icons.my_location,
                    onTap: () => _mapController.move(widget.userPosition!, 15),
                    tooltip: 'La mia posizione',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
