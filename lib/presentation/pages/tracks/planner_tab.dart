import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/services/routing_service.dart';
import '../../../data/repositories/tracks_repository.dart';
import '../../../data/models/track.dart';
import '../../../core/services/offline_tile_provider.dart';


/// Tab per pianificare nuovi percorsi con routing ORS
class PlannerTab extends StatefulWidget {
  final String orsApiKey;
  final VoidCallback? onTrackSaved;

  const PlannerTab({
    super.key,
    required this.orsApiKey,
    this.onTrackSaved,
  });

  @override
  State<PlannerTab> createState() => _PlannerTabState();
}

class _PlannerTabState extends State<PlannerTab> {
  final MapController _mapController = MapController();
  late final RoutingService _routingService;
  final TracksRepository _tracksRepository = TracksRepository();

  final List<LatLng> _waypoints = [];
  RouteResult? _routeResult;
  bool _isCalculating = false;
  String? _errorMessage;
  RoutingProfile _profile = RoutingProfile.hiking;
  bool _showElevationProfile = true;
  LatLng? _userPosition;

  @override
  void initState() {
    super.initState();
    _routingService = RoutingService(apiKey: widget.orsApiKey);
    _initUserPosition();
  }

  /// Ottieni posizione utente e centra la mappa
  Future<void> _initUserPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return; // Non abbiamo i permessi, resta sulla posizione default
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );

      if (!mounted) return;

      setState(() {
        _userPosition = LatLng(position.latitude, position.longitude);
      });

      // Centra la mappa sulla posizione utente
      _mapController.move(_userPosition!, 14);
    } catch (e) {
      debugPrint('[Planner] Errore posizione: $e');
      // Resta sulla posizione default (45.95, 9.75)
    }
  }

  /// Centra la mappa sulla posizione utente
  void _centerOnUser() {
    if (_userPosition != null) {
      _mapController.move(_userPosition!, 14);
    } else {
      _initUserPosition();
    }
  }

  /// Centra la mappa per mostrare tutto il percorso
  void _centerOnRoute() {
    if (_routeResult != null && _routeResult!.points.isNotEmpty) {
      double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
      for (final p in _routeResult!.points) {
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
      _mapController.move(center, zoom - 0.5); // un po' di margine
    } else if (_waypoints.isNotEmpty) {
      double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
      for (final p in _waypoints) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      _mapController.move(center, 14);
    }
  }

  void _addWaypoint(LatLng point) {
    setState(() {
      _waypoints.add(point);
      _errorMessage = null;
    });
    _calculateRoute();
  }

  void _removeWaypointAt(int index) {
    setState(() {
      _waypoints.removeAt(index);
      if (_waypoints.length < 2) {
        _routeResult = null;
      }
    });
    if (_waypoints.length >= 2) {
      _calculateRoute();
    }
  }

  void _removeLastWaypoint() {
    if (_waypoints.isEmpty) return;
    _removeWaypointAt(_waypoints.length - 1);
  }

  void _clearAll() {
    setState(() {
      _waypoints.clear();
      _routeResult = null;
      _errorMessage = null;
    });
  }

  void _toggleProfile() {
    setState(() {
      _profile = _profile == RoutingProfile.hiking 
          ? RoutingProfile.cycling 
          : RoutingProfile.hiking;
    });
    if (_waypoints.length >= 2) {
      _calculateRoute();
    }
  }

  Future<void> _calculateRoute() async {
    if (_waypoints.length < 2) return;

    setState(() {
      _isCalculating = true;
      _errorMessage = null;
    });

    try {
      final result = await _routingService.calculateRoute(
        _waypoints,
        profile: _profile,
      );

      setState(() {
        _routeResult = result;
        _isCalculating = false;
        if (result == null) {
          _errorMessage = context.l10n.cannotCalculateRoute;
        }
      });
    } catch (e) {
      setState(() {
        _isCalculating = false;
        _errorMessage = context.l10n.errorWithDetails(e.toString());
      });
    }
  }

  Future<void> _saveRoute() async {
    if (_routeResult == null || _waypoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.addAtLeast2Points)),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.loginToSave)),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _SaveRouteDialog(
        distance: _routeResult!.distanceKm,
        elevationGain: _routeResult!.elevationGain,
        profile: _profile,
      ),
    );

    if (result == null) return;

    try {
      final trackPoints = _routeResult!.points.map((p) => TrackPoint(
        latitude: p.latitude,
        longitude: p.longitude,
        elevation: p.elevation,
        timestamp: DateTime.now(),
      )).toList();

      double minEle = 0, maxEle = 0;
      if (_routeResult!.elevationProfile.isNotEmpty) {
        minEle = _routeResult!.elevationProfile.reduce((a, b) => a < b ? a : b);
        maxEle = _routeResult!.elevationProfile.reduce((a, b) => a > b ? a : b);
      }

      final track = Track(
        name: result['name'] as String,
        description: result['description'] as String?,
        points: trackPoints,
        activityType: _profile == RoutingProfile.hiking 
            ? ActivityType.trekking 
            : ActivityType.cycling,
        createdAt: DateTime.now(),
        stats: TrackStats(
          distance: _routeResult!.distance,
          elevationGain: _routeResult!.elevationGain,
          elevationLoss: _routeResult!.elevationLoss,
          duration: Duration(seconds: _routeResult!.estimatedDuration.toInt()),
          minElevation: minEle,
          maxElevation: maxEle,
        ),
        isPlanned: true,
      );

      await _tracksRepository.saveTrack(track);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.routeSaved),
            backgroundColor: AppColors.success,
          ),
        );
        _clearAll();
        widget.onTrackSaved?.call();
      }
    } catch (e) {
      print('[Planner] Errore salvataggio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorWithDetails(e.toString())), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(45.95, 9.75),
            initialZoom: 12,
            minZoom: 8,
            maxZoom: 18,
            onTap: (tapPosition, point) => _addWaypoint(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.trailshare.app',
              tileProvider: OfflineFallbackTileProvider(),
            ),

            if (_routeResult != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routeResult!.points.map((p) => p.latLng).toList(),
                    strokeWidth: 5,
                    color: _profile == RoutingProfile.hiking 
                        ? AppColors.success 
                        : AppColors.info,
                  ),
                ],
              ),

            if (_waypoints.length >= 2 && _routeResult == null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _waypoints,
                    strokeWidth: 3,
                    color: Colors.grey.withOpacity(0.5),
                  ),
                ],
              ),

            MarkerLayer(
              markers: _waypoints.asMap().entries.map((entry) {
                final index = entry.key;
                final point = entry.value;
                final isFirst = index == 0;
                final isLast = index == _waypoints.length - 1 && _waypoints.length > 1;

                return Marker(
                  point: point,
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onLongPress: () => _removeWaypointAt(index),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isFirst 
                            ? AppColors.success 
                            : isLast 
                                ? AppColors.danger 
                                : AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          isFirst ? 'S' : isLast ? 'F' : '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            // Marker posizione utente
            if (_userPosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _userPosition!,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),

        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: _buildHeader(),
        ),

        if (_errorMessage != null)
          Positioned(
            top: 70,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => setState(() => _errorMessage = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),

        Positioned(
          right: 12,
          bottom: _routeResult != null && _showElevationProfile ? 220 : 120,
          child: _buildControlsFab(),
        ),

        if (_routeResult != null || _waypoints.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildStatsPanel(),
          ),

        if (_isCalculating)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _profile == RoutingProfile.hiking 
                              ? context.l10n.calculatingRouteHiking 
                              : context.l10n.calculatingRouteCycling,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (_profile == RoutingProfile.hiking ? AppColors.success : AppColors.info).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _profile == RoutingProfile.hiking ? Icons.hiking : Icons.directions_bike,
              color: _profile == RoutingProfile.hiking ? AppColors.success : AppColors.info,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _waypoints.isEmpty
                      ? context.l10n.tapMapToStart
                      : _waypoints.length == 1 
                          ? context.l10n.waypointSingle 
                          : context.l10n.waypointCount(_waypoints.length),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  _waypoints.isEmpty
                      ? context.l10n.addPointsToCreate
                      : context.l10n.longPressToRemove,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleProfile,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.textMuted.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _profile == RoutingProfile.hiking ? Icons.directions_bike : Icons.hiking,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _profile == RoutingProfile.hiking ? 'Bike' : 'Hiking',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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

  Widget _buildControlsFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Centra su percorso (se c'è una route o waypoints)
        if (_routeResult != null || _waypoints.length >= 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FloatingActionButton.small(
              heroTag: 'centerRoute',
              onPressed: _centerOnRoute,
              backgroundColor: Colors.white,
              elevation: 4,
              child: const Icon(Icons.fit_screen, color: AppColors.textPrimary),
            ),
          ),
        // Centra su posizione utente
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FloatingActionButton.small(
            heroTag: 'centerUser',
            onPressed: _centerOnUser,
            backgroundColor: Colors.white,
            elevation: 4,
            child: Icon(
              Icons.my_location,
              color: _userPosition != null ? AppColors.primary : AppColors.textMuted,
            ),
          ),
        ),
        if (_waypoints.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FloatingActionButton.small(
              heroTag: 'undo',
              onPressed: _removeLastWaypoint,
              backgroundColor: Colors.white,
              elevation: 4,
              child: const Icon(Icons.undo, color: AppColors.textPrimary),
            ),
          ),
        if (_waypoints.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FloatingActionButton.small(
              heroTag: 'clear',
              onPressed: _showClearConfirmDialog,
              backgroundColor: Colors.white,
              elevation: 4,
              child: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
          ),
        if (_routeResult != null)
          FloatingActionButton.extended(
            heroTag: 'save',
            onPressed: _saveRoute,
            backgroundColor: AppColors.primary,
            elevation: 4,
            icon: const Icon(Icons.save),
            label: Text(context.l10n.save),
          ),
      ],
    );
  }

  Widget _buildStatsPanel() {
    final hasRoute = _routeResult != null;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, -3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showElevationProfile = !_showElevationProfile),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  icon: Icons.straighten,
                  value: hasRoute ? '${_routeResult!.distanceKm.toStringAsFixed(1)} km' : '--',
                  label: context.l10n.distanceLabel,
                ),
                _StatItem(
                  icon: Icons.trending_up,
                  value: hasRoute ? '+${_routeResult!.elevationGain.toStringAsFixed(0)} m' : '--',
                  label: context.l10n.ascentLabel,
                  valueColor: AppColors.success,
                ),
                _StatItem(
                  icon: Icons.trending_down,
                  value: hasRoute ? '-${_routeResult!.elevationLoss.toStringAsFixed(0)} m' : '--',
                  label: context.l10n.descentLabel,
                  valueColor: AppColors.danger,
                ),
                _StatItem(
                  icon: Icons.schedule,
                  value: hasRoute ? _routeResult!.durationFormatted : '--',
                  label: context.l10n.timeEstLabel,
                ),
              ],
            ),
          ),
          if (_showElevationProfile && hasRoute && _routeResult!.elevationProfile.isNotEmpty)
            Container(
              height: 100,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: _ElevationProfileChart(
                elevations: _routeResult!.elevationProfile,
                color: _profile == RoutingProfile.hiking ? AppColors.success : AppColors.info,
              ),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }

  void _showClearConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.clearRoute),
        content: Text(context.l10n.clearRouteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearAll();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.clearAction),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppColors.textMuted),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }
}

class _ElevationProfileChart extends StatelessWidget {
  final List<double> elevations;
  final Color color;

  const _ElevationProfileChart({required this.elevations, required this.color});

  @override
  Widget build(BuildContext context) {
    if (elevations.isEmpty) return const SizedBox();
    final minEle = elevations.reduce((a, b) => a < b ? a : b);
    final maxEle = elevations.reduce((a, b) => a > b ? a : b);
    final range = maxEle - minEle;

    return CustomPaint(
      painter: _ElevationPainter(
        elevations: elevations,
        minEle: minEle,
        maxEle: maxEle,
        range: range > 0 ? range : 1,
        color: color,
      ),
      size: Size.infinite,
    );
  }
}

class _ElevationPainter extends CustomPainter {
  final List<double> elevations;
  final double minEle;
  final double maxEle;
  final double range;
  final Color color;

  _ElevationPainter({
    required this.elevations,
    required this.minEle,
    required this.maxEle,
    required this.range,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (elevations.isEmpty) return;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final path = ui.Path();
    final fillPath = ui.Path();

    final stepX = size.width / (elevations.length - 1).clamp(1, double.infinity);
    final paddingY = size.height * 0.1;

    fillPath.moveTo(0, size.height);

    for (int i = 0; i < elevations.length; i++) {
      final x = i * stepX;
      final normalized = (elevations[i] - minEle) / range;
      final y = size.height - paddingY - (normalized * (size.height - paddingY * 2));

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final textStyle = TextStyle(color: Colors.grey[600], fontSize: 10);
    final maxText = TextSpan(text: '${maxEle.toStringAsFixed(0)}m', style: textStyle);
    final minText = TextSpan(text: '${minEle.toStringAsFixed(0)}m', style: textStyle);

    final maxPainter = TextPainter(text: maxText, textDirection: TextDirection.ltr)..layout();
    final minPainter = TextPainter(text: minText, textDirection: TextDirection.ltr)..layout();

    maxPainter.paint(canvas, Offset(4, paddingY - 6));
    minPainter.paint(canvas, Offset(4, size.height - paddingY - 4));
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter oldDelegate) {
    return elevations != oldDelegate.elevations || color != oldDelegate.color;
  }
}

class _SaveRouteDialog extends StatefulWidget {
  final double distance;
  final double elevationGain;
  final RoutingProfile profile;

  const _SaveRouteDialog({
    required this.distance,
    required this.elevationGain,
    required this.profile,
  });

  @override
  State<_SaveRouteDialog> createState() => _SaveRouteDialogState();
}

class _SaveRouteDialogState extends State<_SaveRouteDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final activity = widget.profile == RoutingProfile.hiking ? context.l10n.hikeDefaultName : context.l10n.bikeDefaultName;
    final date = DateTime.now();
    _nameController.text = '$activity ${date.day}/${date.month}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.saveRoute),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('${widget.distance.toStringAsFixed(1)} km',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(context.l10n.distanceLabel, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                  Column(
                    children: [
                      Text('+${widget.elevationGain.toStringAsFixed(0)} m',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                      Text(context.l10n.elevationGainShort, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: context.l10n.routeName,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.edit),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? context.l10n.enterAName : null,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: context.l10n.descriptionOptional,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.notes),
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'name': _nameController.text.trim(),
                'description': _descController.text.trim().isEmpty ? null : _descController.text.trim(),
              });
            }
          },
          icon: const Icon(Icons.save),
          label: Text(context.l10n.save),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
