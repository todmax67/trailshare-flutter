import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/track.dart';

/// Pagina mappa a schermo intero per visualizzare una traccia
class TrackMapPage extends StatefulWidget {
  final Track track;

  const TrackMapPage({super.key, required this.track});

  @override
  State<TrackMapPage> createState() => _TrackMapPageState();
}

class _TrackMapPageState extends State<TrackMapPage> {
  final MapController _mapController = MapController();
  bool _showElevation = true;
  int _selectedPointIndex = -1;

  int _currentLayer = 0;
  final List<_MapLayer> _layers = [
    _MapLayer(
      name: 'OpenStreetMap',
      url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    ),
    _MapLayer(
      name: 'Topografica',
      url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
    ),
    _MapLayer(
      name: 'Satellite',
      url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    ),
  ];

  List<LatLng> get _trackPoints {
    return widget.track.points
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
  }

  LatLng get _center {
    if (_trackPoints.isEmpty) return const LatLng(45.95, 9.75);
    
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in _trackPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  LatLngBounds? get _bounds {
    if (_trackPoints.isEmpty) return null;
    return LatLngBounds.fromPoints(_trackPoints);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitBounds();
    });
  }

  void _fitBounds() {
    final bounds = _bounds;
    if (bounds != null) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ),
      );
    }
  }

  void _cycleLayer() {
    setState(() {
      _currentLayer = (_currentLayer + 1) % _layers.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final stats = track.stats;
    final layer = _layers[_currentLayer];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
            ),
            child: IconButton(
              icon: const Icon(Icons.layers, color: AppColors.textPrimary),
              onPressed: _cycleLayer,
              tooltip: layer.name,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
            ),
            child: IconButton(
              icon: const Icon(Icons.fit_screen, color: AppColors.textPrimary),
              onPressed: _fitBounds,
              tooltip: 'Centra traccia',
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13,
              minZoom: 5,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: layer.url,
                subdomains: layer.subdomains,
                userAgentPackageName: 'com.trailshare.app',
              ),

              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _trackPoints,
                    strokeWidth: 5,
                    color: track.isPlanned ? AppColors.info : AppColors.primary,
                  ),
                ],
              ),

              if (_trackPoints.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _trackPoints.first,
                      width: 36,
                      height: 36,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.play_arrow, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                    if (_trackPoints.length > 1)
                      Marker(
                        point: _trackPoints.last,
                        width: 36,
                        height: 36,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.flag, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    if (_selectedPointIndex >= 0 && _selectedPointIndex < _trackPoints.length)
                      Marker(
                        point: _trackPoints[_selectedPointIndex],
                        width: 20,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary, width: 3),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildInfoPanel(track, stats),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
              ),
              child: Text(
                layer.name,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(Track track, TrackStats stats) {
    final elevations = widget.track.points
        .where((p) => p.elevation != null)
        .map((p) => p.elevation!)
        .toList();

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
            onTap: () => setState(() => _showElevation = !_showElevation),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (track.isPlanned ? AppColors.info : AppColors.primary).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: track.isPlanned
                      ? const Icon(Icons.edit_location_alt, color: AppColors.info, size: 20)
                      : Text(track.activityType.icon, style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          if (track.isPlanned)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: AppColors.info.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PIANIFICATA',
                                style: TextStyle(fontSize: 9, color: AppColors.info, fontWeight: FontWeight.bold),
                              ),
                            ),
                          Text(
                            track.activityType.displayName,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  icon: Icons.straighten,
                  value: '${(stats.distance / 1000).toStringAsFixed(1)} km',
                  label: 'Distanza',
                ),
                _StatItem(
                  icon: Icons.trending_up,
                  value: '+${stats.elevationGain.toStringAsFixed(0)} m',
                  label: 'Salita',
                  color: AppColors.success,
                ),
                _StatItem(
                  icon: Icons.trending_down,
                  value: '-${stats.elevationLoss.toStringAsFixed(0)} m',
                  label: 'Discesa',
                  color: AppColors.danger,
                ),
                if (stats.duration.inMinutes > 0)
                  _StatItem(
                    icon: Icons.schedule,
                    value: _formatDuration(stats.duration),
                    label: 'Tempo',
                  ),
              ],
            ),
          ),

          if (_showElevation && elevations.isNotEmpty)
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                final width = box.size.width - 32;
                final x = details.localPosition.dx - 16;
                final ratio = (x / width).clamp(0.0, 1.0);
                final index = (ratio * (_trackPoints.length - 1)).round();
                
                if (index != _selectedPointIndex) {
                  setState(() => _selectedPointIndex = index);
                  if (index >= 0 && index < _trackPoints.length) {
                    _mapController.move(_trackPoints[index], _mapController.camera.zoom);
                  }
                }
              },
              onHorizontalDragEnd: (_) {
                setState(() => _selectedPointIndex = -1);
              },
              child: Container(
                height: 80,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CustomPaint(
                  painter: _ElevationPainter(
                    elevations: elevations,
                    color: track.isPlanned ? AppColors.info : AppColors.primary,
                    selectedIndex: _selectedPointIndex >= 0 
                        ? (_selectedPointIndex * elevations.length / _trackPoints.length).round().clamp(0, elevations.length - 1)
                        : -1,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _MapLayer {
  final String name;
  final String url;
  final List<String> subdomains;

  const _MapLayer({
    required this.name,
    required this.url,
    this.subdomains = const [],
  });
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color ?? AppColors.textPrimary,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
      ],
    );
  }
}

class _ElevationPainter extends CustomPainter {
  final List<double> elevations;
  final Color color;
  final int selectedIndex;

  _ElevationPainter({
    required this.elevations,
    required this.color,
    this.selectedIndex = -1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (elevations.isEmpty) return;

    final minEle = elevations.reduce((a, b) => a < b ? a : b);
    final maxEle = elevations.reduce((a, b) => a > b ? a : b);
    final range = maxEle - minEle;
    final safeRange = range > 0 ? range : 1;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final path = ui.Path();
    final fillPath = ui.Path();

    final stepX = size.width / (elevations.length - 1).clamp(1, double.infinity);
    final paddingY = 8.0;

    fillPath.moveTo(0, size.height);

    for (int i = 0; i < elevations.length; i++) {
      final x = i * stepX;
      final normalized = (elevations[i] - minEle) / safeRange;
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

    if (selectedIndex >= 0 && selectedIndex < elevations.length) {
      final x = selectedIndex * stepX;
      final normalized = (elevations[selectedIndex] - minEle) / safeRange;
      final y = size.height - paddingY - (normalized * (size.height - paddingY * 2));

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = color.withOpacity(0.5)
          ..strokeWidth = 1,
      );

      canvas.drawCircle(Offset(x, y), 6, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = color);

      final text = '${elevations[selectedIndex].toStringAsFixed(0)}m';
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      
      final labelX = (x - textPainter.width / 2).clamp(0.0, size.width - textPainter.width);
      textPainter.paint(canvas, Offset(labelX, y - 18));
    }

    final labelStyle = TextStyle(color: Colors.grey[500], fontSize: 9);
    
    final maxSpan = TextSpan(text: '${maxEle.toStringAsFixed(0)}m', style: labelStyle);
    final minSpan = TextSpan(text: '${minEle.toStringAsFixed(0)}m', style: labelStyle);
    
    final maxPainter = TextPainter(text: maxSpan, textDirection: TextDirection.ltr)..layout();
    final minPainter = TextPainter(text: minSpan, textDirection: TextDirection.ltr)..layout();
    
    maxPainter.paint(canvas, const Offset(2, 0));
    minPainter.paint(canvas, Offset(2, size.height - 12));
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter oldDelegate) {
    return elevations != oldDelegate.elevations || 
           color != oldDelegate.color || 
           selectedIndex != oldDelegate.selectedIndex;
  }
}
