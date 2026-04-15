import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/navigation_service.dart';
import '../../../data/models/segment.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/public_trails_repository.dart';
import '../../../data/repositories/segments_repository.dart';

/// Pagina per admin: creazione di un nuovo segmento da un sentiero pubblico.
///
/// L'utente tocca due punti sulla mappa; l'editor trova i punti del polyline
/// del sentiero più vicini ai tap e estrae il sub-tratto tra i due indici
/// come polyline del segmento.
class SegmentEditorPage extends StatefulWidget {
  final PublicTrail trail;
  final List<TrackPoint> trailPoints;

  const SegmentEditorPage({
    super.key,
    required this.trail,
    required this.trailPoints,
  });

  @override
  State<SegmentEditorPage> createState() => _SegmentEditorPageState();
}

class _SegmentEditorPageState extends State<SegmentEditorPage> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _segmentsRepo = SegmentsRepository();
  final MapController _mapController = MapController();

  int? _startIdx;
  int? _endIdx;
  bool _saving = false;

  late List<LatLng> _trailLatLng;

  @override
  void initState() {
    super.initState();
    _trailLatLng = widget.trailPoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_trailLatLng.isEmpty) return;
    // Trova il punto più vicino del polyline del trail
    final idx = NavigationService.findNearestPointIndex(_trailLatLng, point);
    setState(() {
      if (_startIdx == null) {
        _startIdx = idx;
      } else if (_endIdx == null) {
        // Ordina: start < end
        if (idx < _startIdx!) {
          _endIdx = _startIdx;
          _startIdx = idx;
        } else {
          _endIdx = idx;
        }
      } else {
        // Reset e ricomincia
        _startIdx = idx;
        _endIdx = null;
      }
    });
  }

  void _resetSelection() {
    setState(() {
      _startIdx = null;
      _endIdx = null;
    });
  }

  /// Sub-polyline tra i due indici (incluso).
  List<LatLng> get _subPolyline {
    if (_startIdx == null || _endIdx == null) return [];
    return _trailLatLng.sublist(_startIdx!, _endIdx! + 1);
  }

  /// Sub-points con elevazione (per calcolare dislivello).
  List<TrackPoint> get _subPoints {
    if (_startIdx == null || _endIdx == null) return [];
    return widget.trailPoints.sublist(_startIdx!, _endIdx! + 1);
  }

  double get _subDistance {
    final pts = _subPolyline;
    if (pts.length < 2) return 0;
    double total = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      total += NavigationService.distanceMeters(pts[i], pts[i + 1]);
    }
    return total;
  }

  double get _subElevationGain {
    final pts = _subPoints;
    if (pts.length < 2) return 0;
    double gain = 0;
    for (var i = 1; i < pts.length; i++) {
      final prev = pts[i - 1].elevation;
      final curr = pts[i].elevation;
      if (prev != null && curr != null && curr > prev) {
        gain += curr - prev;
      }
    }
    return gain;
  }

  bool get _canSave =>
      _startIdx != null &&
      _endIdx != null &&
      _nameController.text.trim().isNotEmpty &&
      _subDistance >= 100 && // minimo 100m per evitare segmenti troppo corti
      !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    final start = _subPolyline.first;
    final end = _subPolyline.last;

    final segment = Segment(
      id: '',
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      trailId: widget.trail.id,
      createdBy: user.uid,
      startLat: start.latitude,
      startLng: start.longitude,
      endLat: end.latitude,
      endLng: end.longitude,
      polyline: _subPolyline,
      distance: _subDistance,
      elevationGain: _subElevationGain,
      activityType: widget.trail.activityType,
      createdAt: DateTime.now(),
    );

    final id = await _segmentsRepo.createSegment(segment);
    if (!mounted) return;
    setState(() => _saving = false);

    if (id != null) {
      Navigator.pop(context, id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante la creazione del segmento'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _trailLatLng.isNotEmpty
        ? LatLngBounds.fromPoints(_trailLatLng)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuovo segmento'),
        actions: [
          if (_startIdx != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetSelection,
              tooltip: 'Reset selezione',
            ),
        ],
      ),
      body: Column(
        children: [
          // Mappa
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _trailLatLng.isNotEmpty ? _trailLatLng.first : const LatLng(45, 10),
                    initialZoom: 14,
                    minZoom: 10,
                    maxZoom: 18,
                    onTap: _onMapTap,
                    initialCameraFit: bounds != null
                        ? CameraFit.bounds(
                            bounds: bounds,
                            padding: const EdgeInsets.all(60),
                          )
                        : null,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.trailshare.app',
                    ),
                    // Polyline intero del sentiero in grigio
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _trailLatLng,
                          strokeWidth: 3,
                          color: Colors.grey.withValues(alpha: 0.6),
                        ),
                      ],
                    ),
                    // Sub-polyline del segmento selezionato
                    if (_subPolyline.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _subPolyline,
                            strokeWidth: 6,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    // Markers start/end
                    MarkerLayer(
                      markers: [
                        if (_startIdx != null)
                          Marker(
                            point: _trailLatLng[_startIdx!],
                            width: 26,
                            height: 26,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                              child: const Center(
                                child: Text(
                                  'S',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_endIdx != null)
                          Marker(
                            point: _trailLatLng[_endIdx!],
                            width: 26,
                            height: 26,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                              child: const Center(
                                child: Text(
                                  'F',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                // Banner istruzioni
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        _startIdx == null
                            ? '1/2 - Tocca il punto di inizio sul tracciato'
                            : _endIdx == null
                                ? '2/2 - Tocca il punto di fine sul tracciato'
                                : 'Selezione completata. Tocca ancora per ricominciare.',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Form in basso
          _buildForm(),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats
          if (_subDistance > 0) ...[
            Row(
              children: [
                _stat(Icons.straighten, '${(_subDistance / 1000).toStringAsFixed(2)} km', 'Distanza'),
                const SizedBox(width: 12),
                _stat(Icons.trending_up, '+${_subElevationGain.round()} m', 'Dislivello'),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nome segmento *',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLength: 50,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Descrizione (opzionale)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLength: 200,
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canSave ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Salvataggio...' : 'Crea segmento'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}
