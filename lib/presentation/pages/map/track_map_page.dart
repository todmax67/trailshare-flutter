import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/community_tracks_repository.dart';

/// Pagina mappa a schermo intero per visualizzare una traccia
/// Supporta sia Track (tracce private) che CommunityTrack (tracce community)
class TrackMapPage extends StatefulWidget {
  /// Track privata (opzionale)
  final Track? track;
  
  /// Track community (opzionale)
  final CommunityTrack? communityTrack;
  
  /// Mostra colori pendenza sulla traccia
  final bool showGradientColors;

  const TrackMapPage({
    super.key,
    this.track,
    this.communityTrack,
    this.showGradientColors = true,
  }) : assert(track != null || communityTrack != null, 'Deve essere fornita una track o communityTrack');

  @override
  State<TrackMapPage> createState() => _TrackMapPageState();
}

class _TrackMapPageState extends State<TrackMapPage> {
  final MapController _mapController = MapController();
  bool _showElevation = true;
  bool _showGradientColors = true;
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

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS per dati unificati (Track o CommunityTrack)
  // ═══════════════════════════════════════════════════════════════════════════

  String get _trackName {
    return widget.track?.name ?? widget.communityTrack?.name ?? 'Traccia';
  }

  List<TrackPoint> get _points {
    return widget.track?.points ?? widget.communityTrack?.points ?? [];
  }

  List<LatLng> get _trackPoints {
    return _points.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  bool get _isPlanned {
    return widget.track?.isPlanned ?? false;
  }

  double get _distance {
    return widget.track?.stats.distance ?? widget.communityTrack?.distance ?? 0;
  }

  double get _elevationGain {
    return widget.track?.stats.elevationGain ?? widget.communityTrack?.elevationGain ?? 0;
  }

  double get _elevationLoss {
    return widget.track?.stats.elevationLoss ?? 0;
  }

  Duration get _duration {
    if (widget.track != null) {
      return widget.track!.stats.duration;
    }
    // Per community track, normalizza la durata
    return _normalizeDuration(
      widget.communityTrack?.duration ?? 0,
      widget.communityTrack?.distance ?? 0,
    );
  }
  
  /// Normalizza la durata gestendo vari formati di salvataggio
  Duration _normalizeDuration(int rawDuration, double distanceMeters) {
    if (rawDuration <= 0 || distanceMeters <= 0) {
      return _estimateDurationFromDistance(distanceMeters);
    }
    
    // Calcola velocità implicita per verificare se il valore ha senso
    int durationSeconds = rawDuration;
    double impliedSpeedKmh = (distanceMeters / 1000) / (durationSeconds / 3600);
    
    // Se la velocità è ragionevole (1-25 km/h), usa il valore
    if (impliedSpeedKmh >= 1 && impliedSpeedKmh <= 25) {
      return Duration(seconds: durationSeconds);
    }
    
    // Prova come millisecondi
    int durationFromMs = (rawDuration / 1000).round();
    double impliedSpeedFromMs = (distanceMeters / 1000) / (durationFromMs / 3600);
    
    if (impliedSpeedFromMs >= 1 && impliedSpeedFromMs <= 25) {
      return Duration(seconds: durationFromMs);
    }
    
    // Fallback: stima dalla distanza
    return _estimateDurationFromDistance(distanceMeters);
  }
  
  Duration _estimateDurationFromDistance(double distanceMeters) {
    const avgSpeedKmh = 4.0;
    final hours = (distanceMeters / 1000) / avgSpeedKmh;
    return Duration(seconds: (hours * 3600).round());
  }

  List<double> get _elevations {
    return _points
        .where((p) => p.elevation != null)
        .map((p) => p.elevation!)
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
    _showGradientColors = widget.showGradientColors;
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

  void _toggleGradientColors() {
    setState(() {
      _showGradientColors = !_showGradientColors;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CALCOLO PENDENZA E COLORI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calcola la pendenza tra due punti (in percentuale)
  double _calculateGradient(TrackPoint p1, TrackPoint p2) {
    if (p1.elevation == null || p2.elevation == null) return 0;
    
    final distance = const Distance().as(
      LengthUnit.Meter,
      LatLng(p1.latitude, p1.longitude),
      LatLng(p2.latitude, p2.longitude),
    );
    
    if (distance < 1) return 0; // Evita divisione per zero
    
    final elevDiff = p2.elevation! - p1.elevation!;
    return (elevDiff / distance) * 100; // Pendenza in percentuale
  }

  /// Restituisce il colore in base alla pendenza
  Color _getGradientColor(double gradient) {
    // Salita (positivo) -> Rosso/Arancione/Giallo
    // Piano -> Verde
    // Discesa (negativo) -> Azzurro/Blu
    
    if (gradient > 15) {
      return const Color(0xFFB71C1C); // Rosso scuro - salita ripida
    } else if (gradient > 10) {
      return const Color(0xFFD32F2F); // Rosso - salita forte
    } else if (gradient > 6) {
      return const Color(0xFFFF5722); // Arancione - salita moderata
    } else if (gradient > 3) {
      return const Color(0xFFFF9800); // Arancione chiaro - salita leggera
    } else if (gradient > -3) {
      return const Color(0xFF4CAF50); // Verde - piano
    } else if (gradient > -6) {
      return const Color(0xFF00BCD4); // Ciano - discesa leggera
    } else if (gradient > -10) {
      return const Color(0xFF2196F3); // Blu - discesa moderata
    } else if (gradient > -15) {
      return const Color(0xFF1976D2); // Blu scuro - discesa forte
    } else {
      return const Color(0xFF0D47A1); // Blu molto scuro - discesa ripida
    }
  }

  /// Genera i segmenti colorati per la polyline
  List<Polyline> _buildGradientPolylines() {
    if (_points.length < 2 || !_showGradientColors) {
      // Polyline singola senza gradiente
      return [
        Polyline(
          points: _trackPoints,
          strokeWidth: 5,
          color: _isPlanned ? AppColors.info : AppColors.primary,
        ),
      ];
    }

    final polylines = <Polyline>[];
    
    // Raggruppa punti con pendenza simile per ridurre il numero di segmenti
    int startIndex = 0;
    Color? currentColor;
    
    for (int i = 0; i < _points.length - 1; i++) {
      final gradient = _calculateGradient(_points[i], _points[i + 1]);
      final color = _getGradientColor(gradient);
      
      if (currentColor == null) {
        currentColor = color;
        startIndex = i;
      } else if (color != currentColor || i == _points.length - 2) {
        // Colore cambiato o ultimo segmento: crea polyline
        final endIndex = (i == _points.length - 2) ? i + 2 : i + 1;
        polylines.add(
          Polyline(
            points: _trackPoints.sublist(startIndex, endIndex),
            strokeWidth: 5,
            color: currentColor,
          ),
        );
        currentColor = color;
        startIndex = i;
      }
    }
    
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    final layer = _layers[_currentLayer];
    final elevations = _elevations;

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
          // Toggle colori pendenza
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _showGradientColors ? AppColors.primary : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
            ),
            child: IconButton(
              icon: Icon(
                Icons.gradient,
                color: _showGradientColors ? Colors.white : AppColors.textPrimary,
              ),
              onPressed: _toggleGradientColors,
              tooltip: 'Colori pendenza',
            ),
          ),
          // Cambio layer
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
          // Centra traccia
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
          // Mappa
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
                tileProvider: NetworkTileProvider(
                  headers: {'User-Agent': 'TrailShare/1.0 (https://trailshare.app)'},
                ),
              ),

              // Polyline con colori pendenza
              PolylineLayer(
                polylines: _buildGradientPolylines(),
              ),

              // Markers
              if (_trackPoints.isNotEmpty)
                MarkerLayer(
                  markers: [
                    // Start marker
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
                    // End marker
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
                    // Selected point marker
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

          // Info panel in basso
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildInfoPanel(elevations),
          ),

          // Layer indicator
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
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ),

          // Legenda colori (se attiva)
          if (_showGradientColors)
            Positioned(
              top: MediaQuery.of(context).padding.top + 100,
              right: 12,
              child: _buildGradientLegend(),
            ),
        ],
      ),
    );
  }

  Widget _buildGradientLegend() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Pendenza',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _legendItem(const Color(0xFFB71C1C), '>15%', 'Salita ripida'),
          _legendItem(const Color(0xFFFF5722), '6-15%', 'Salita'),
          _legendItem(const Color(0xFFFF9800), '3-6%', 'Salita leggera'),
          _legendItem(const Color(0xFF4CAF50), '±3%', 'Piano'),
          _legendItem(const Color(0xFF00BCD4), '-3/-6%', 'Discesa leggera'),
          _legendItem(const Color(0xFF2196F3), '-6/-15%', 'Discesa'),
          _legendItem(const Color(0xFF0D47A1), '<-15%', 'Discesa ripida'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(List<double> elevations) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title e toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _trackName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showElevation ? Icons.expand_more : Icons.expand_less,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () => setState(() => _showElevation = !_showElevation),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  icon: Icons.straighten,
                  value: '${(_distance / 1000).toStringAsFixed(1)} km',
                  label: 'Distanza',
                ),
                _StatItem(
                  icon: Icons.trending_up,
                  value: '+${_elevationGain.toStringAsFixed(0)} m',
                  label: 'Salita',
                  color: AppColors.success,
                ),
                if (_elevationLoss > 0)
                  _StatItem(
                    icon: Icons.trending_down,
                    value: '-${_elevationLoss.toStringAsFixed(0)} m',
                    label: 'Discesa',
                    color: AppColors.danger,
                  ),
                if (_duration.inMinutes > 0)
                  _StatItem(
                    icon: Icons.schedule,
                    value: _formatDuration(_duration),
                    label: 'Tempo',
                  ),
              ],
            ),
          ),

          // Elevation chart
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
                    points: _points,
                    showGradientColors: _showGradientColors,
                    baseColor: _isPlanned ? AppColors.info : AppColors.primary,
                    selectedIndex: _selectedPointIndex >= 0 
                        ? (_selectedPointIndex * elevations.length / _trackPoints.length).round().clamp(0, elevations.length - 1)
                        : -1,
                    getGradientColor: _getGradientColor,
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

// ═══════════════════════════════════════════════════════════════════════════
// HELPER CLASSES
// ═══════════════════════════════════════════════════════════════════════════

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
  final List<TrackPoint> points;
  final bool showGradientColors;
  final Color baseColor;
  final int selectedIndex;
  final Color Function(double) getGradientColor;

  _ElevationPainter({
    required this.elevations,
    required this.points,
    required this.showGradientColors,
    required this.baseColor,
    this.selectedIndex = -1,
    required this.getGradientColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (elevations.isEmpty) return;

    final minEle = elevations.reduce((a, b) => a < b ? a : b);
    final maxEle = elevations.reduce((a, b) => a > b ? a : b);
    final range = maxEle - minEle;
    final safeRange = range > 0 ? range : 1;

    final stepX = size.width / (elevations.length - 1).clamp(1, double.infinity);
    final paddingY = 8.0;

    // Calcola i punti Y
    List<double> yPoints = [];
    for (int i = 0; i < elevations.length; i++) {
      final normalized = (elevations[i] - minEle) / safeRange;
      final y = size.height - paddingY - (normalized * (size.height - paddingY * 2));
      yPoints.add(y);
    }

    // Disegna area di riempimento
    final fillPath = ui.Path();
    fillPath.moveTo(0, size.height);
    for (int i = 0; i < elevations.length; i++) {
      final x = i * stepX;
      fillPath.lineTo(x, yPoints[i]);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..color = baseColor.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Disegna linea (con o senza gradiente colori)
    if (showGradientColors && points.length >= 2) {
      // Linea con segmenti colorati per pendenza
      for (int i = 0; i < elevations.length - 1; i++) {
        final x1 = i * stepX;
        final x2 = (i + 1) * stepX;
        
        // Calcola pendenza
        double gradient = 0;
        final pointIndex = (i * points.length / elevations.length).round().clamp(0, points.length - 2);
        if (pointIndex < points.length - 1) {
          final p1 = points[pointIndex];
          final p2 = points[pointIndex + 1];
          if (p1.elevation != null && p2.elevation != null) {
            final dist = const Distance().as(
              LengthUnit.Meter,
              LatLng(p1.latitude, p1.longitude),
              LatLng(p2.latitude, p2.longitude),
            );
            if (dist > 1) {
              gradient = ((p2.elevation! - p1.elevation!) / dist) * 100;
            }
          }
        }
        
        final segmentPaint = Paint()
          ..color = getGradientColor(gradient)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        
        canvas.drawLine(
          Offset(x1, yPoints[i]),
          Offset(x2, yPoints[i + 1]),
          segmentPaint,
        );
      }
    } else {
      // Linea singola colore
      final linePaint = Paint()
        ..color = baseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      final path = ui.Path();
      for (int i = 0; i < elevations.length; i++) {
        final x = i * stepX;
        if (i == 0) {
          path.moveTo(x, yPoints[i]);
        } else {
          path.lineTo(x, yPoints[i]);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Marker punto selezionato
    if (selectedIndex >= 0 && selectedIndex < elevations.length) {
      final x = selectedIndex * stepX;
      final y = yPoints[selectedIndex];

      // Linea verticale
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = baseColor.withOpacity(0.5)
          ..strokeWidth = 1,
      );

      // Pallino
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = baseColor);

      // Label quota
      final text = '${elevations[selectedIndex].toStringAsFixed(0)}m';
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(color: baseColor, fontSize: 10, fontWeight: FontWeight.bold),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      
      final labelX = (x - textPainter.width / 2).clamp(0.0, size.width - textPainter.width);
      textPainter.paint(canvas, Offset(labelX, y - 18));
    }

    // Labels min/max
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
           showGradientColors != oldDelegate.showGradientColors ||
           baseColor != oldDelegate.baseColor || 
           selectedIndex != oldDelegate.selectedIndex;
  }
}
