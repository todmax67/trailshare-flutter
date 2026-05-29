import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/map_styles.dart';
import '../../core/services/routing_service.dart';
import '../../data/models/track.dart';
import '../../data/repositories/tracks_repository.dart';
import '../widgets/web_map_layer_control.dart';

/// Pianificatore tracce per dashboard web.
///
/// MVP scope:
/// - Mappa con click per aggiungere waypoint (max 25)
/// - Sidebar destra con lista waypoint, activity type, calcola, save
/// - Routing via Cloud Function proxy ORS (stessa di mobile)
/// - Salva su Firestore come Track con isPlanned=true
///
/// Out of scope (round successivi):
/// - "Usa la mia posizione" GPS
/// - Ricerca indirizzo (geocoding)
/// - Drag-reorder waypoint (oggi: delete + re-click)
/// - Grafico elevazione lungo il percorso
class WebPlannerPage extends StatefulWidget {
  const WebPlannerPage({super.key});

  @override
  State<WebPlannerPage> createState() => _WebPlannerPageState();
}

class _WebPlannerPageState extends State<WebPlannerPage> {
  final _routingService = RoutingService(
    proxyBaseUrl: AppConfig.orsProxyBaseUrl,
  );
  final _tracksRepo = TracksRepository();
  final _mapController = MapController();
  MapStyle _mapStyle = mapStyles.first;

  // Limite waypoint: alzato 10→25 (richiesta utente). Su sentieri con
  // molti incroci servono più punti per guidare il router sul percorso
  // giusto. 25 resta ben sotto il limite ORS (~50 coordinate/richiesta)
  // e mantiene la lista laterale gestibile.
  static const int _maxWaypoints = 25;
  static const _initialCenter = LatLng(45.9, 10.5); // Lombardia / Lago di Garda
  static const double _initialZoom = 10;

  final List<LatLng> _waypoints = [];
  RoutingProfile _profile = RoutingProfile.hiking;

  RouteResult? _route;
  bool _calculating = false;
  bool _saving = false;
  String? _error;
  /// Indice (0-based) del waypoint che l'ultimo calcolo ha segnalato come
  /// problematico. Lo mostriamo in rosso sulla mappa per aiutare l'utente
  /// a spostarlo. null = nessun waypoint problematico.
  int? _errorWaypointIndex;

  void _onMapTap(TapPosition _, LatLng latlng) {
    if (_waypoints.length >= _maxWaypoints) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Massimo $_maxWaypoints waypoint per percorso'),
        ),
      );
      return;
    }
    setState(() {
      _waypoints.add(latlng);
      // Cambiare i waypoint invalida la route già calcolata.
      _route = null;
      _error = null;
      _errorWaypointIndex = null;
    });
  }

  void _removeWaypoint(int index) {
    setState(() {
      _waypoints.removeAt(index);
      _route = null;
      _error = null;
      _errorWaypointIndex = null;
    });
  }

  void _clearAll() {
    setState(() {
      _waypoints.clear();
      _route = null;
      _error = null;
      _errorWaypointIndex = null;
    });
  }

  Future<void> _calculate() async {
    if (_waypoints.length < 2) return;
    setState(() {
      _calculating = true;
      _error = null;
      _errorWaypointIndex = null;
    });
    final outcome = await _routingService.calculateRouteWithDetails(
      _waypoints,
      profile: _profile,
    );
    if (!mounted) return;
    setState(() {
      _calculating = false;
      if (outcome.isSuccess) {
        _route = outcome.result;
      } else {
        _error = outcome.failure!.userMessage;
        _errorWaypointIndex = outcome.failure!.waypointIndex;
      }
    });
  }

  Future<void> _save() async {
    if (_route == null) return;
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (_) => const _SaveDialog(),
    );
    if (result == null) return;

    setState(() => _saving = true);
    try {
      final trackPoints = _route!.points
          .map((p) => TrackPoint(
                latitude: p.latitude,
                longitude: p.longitude,
                elevation: p.elevation,
                timestamp: DateTime.now(),
              ))
          .toList();

      double minEle = 0, maxEle = 0;
      if (_route!.elevationProfile.isNotEmpty) {
        minEle = _route!.elevationProfile.reduce((a, b) => a < b ? a : b);
        maxEle = _route!.elevationProfile.reduce((a, b) => a > b ? a : b);
      }

      final track = Track(
        name: result['name']!,
        description: result['description'],
        points: trackPoints,
        activityType: _profile == RoutingProfile.hiking
            ? ActivityType.trekking
            : ActivityType.cycling,
        createdAt: DateTime.now(),
        stats: TrackStats(
          distance: _route!.distance,
          elevationGain: _route!.elevationGain,
          elevationLoss: _route!.elevationLoss,
          duration: Duration(seconds: _route!.estimatedDuration.toInt()),
          minElevation: minEle,
          maxElevation: maxEle,
        ),
        isPlanned: true,
      );
      await _tracksRepo.saveTrack(track);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Percorso salvato — la trovi in "Le mie tracce"'),
          backgroundColor: AppColors.success,
        ),
      );
      _clearAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          Expanded(child: _buildMap()),
          const VerticalDivider(width: 1),
          SizedBox(width: 320, child: _buildPanel()),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _initialCenter,
            initialZoom: _initialZoom,
            minZoom: 4,
            maxZoom: 18,
            onTap: _onMapTap,
          ),
          children: [
            tileLayerForStyle(_mapStyle),
        if (_route != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _route!.points
                    .map((p) => LatLng(p.latitude, p.longitude))
                    .toList(),
                strokeWidth: 4,
                color: AppColors.primary,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (int i = 0; i < _waypoints.length; i++)
              Marker(
                point: _waypoints[i],
                width: 32,
                height: 32,
                child: _WaypointMarker(
                  index: i + 1,
                  hasError: i == _errorWaypointIndex,
                ),
              ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 10,
          right: 10,
          child: WebMapLayerControl(
            current: _mapStyle,
            onChanged: (s) => setState(() => _mapStyle = s),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel() {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pianificatore',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Clicca sulla mappa per aggiungere waypoint, poi calcola '
                  'il percorso.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Activity type
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<RoutingProfile>(
              segments: const [
                ButtonSegment(
                  value: RoutingProfile.hiking,
                  icon: Icon(Icons.hiking),
                  label: Text('Trekking'),
                ),
                ButtonSegment(
                  value: RoutingProfile.cycling,
                  icon: Icon(Icons.directions_bike),
                  label: Text('Bike'),
                ),
              ],
              selected: {_profile},
              onSelectionChanged: (s) {
                setState(() {
                  _profile = s.first;
                  _route = null;
                });
              },
            ),
          ),
          // Waypoints list
          Expanded(
            child: _waypoints.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Nessun waypoint.\nClicca sulla mappa per iniziare.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _waypoints.length,
                    itemBuilder: (ctx, i) => _WaypointTile(
                      index: i,
                      latlng: _waypoints[i],
                      onRemove: () => _removeWaypoint(i),
                    ),
                  ),
          ),
          if (_route != null) _buildStats(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                ),
              ),
            ),
          // Action bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed:
                      (_calculating || _waypoints.length < 2) ? null : _calculate,
                  icon: _calculating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.route),
                  label: Text(_calculating
                      ? 'Calcolo…'
                      : _waypoints.length < 2
                          ? 'Aggiungi almeno 2 waypoint'
                          : 'Calcola percorso'),
                ),
                if (_route != null) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Salvo…' : 'Salva percorso'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                  ),
                ],
                if (_waypoints.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Pulisci'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final r = _route!;
    final km = (r.distance / 1000).toStringAsFixed(1);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statBlock('$km km', 'Distanza'),
          _statBlock('${r.elevationGain.toStringAsFixed(0)}m', 'D+'),
          _statBlock('${r.elevationLoss.toStringAsFixed(0)}m', 'D-'),
          _statBlock(r.durationFormatted, 'Tempo'),
        ],
      ),
    );
  }

  Widget _statBlock(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
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

class _WaypointMarker extends StatelessWidget {
  final int index;
  /// Fix 8.B1.3: quando l'ultimo calcolo routing è fallito a causa di
  /// questo waypoint, lo coloriamo di rosso per segnalare visivamente
  /// che è quello da spostare.
  final bool hasError;
  const _WaypointMarker({required this.index, this.hasError = false});

  @override
  Widget build(BuildContext context) {
    final color = hasError ? AppColors.danger : AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Text(
          hasError ? '!' : '$index',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _WaypointTile extends StatelessWidget {
  final int index;
  final LatLng latlng;
  final VoidCallback onRemove;

  const _WaypointTile({
    required this.index,
    required this.latlng,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final lat = latlng.latitude.toStringAsFixed(5);
    final lon = latlng.longitude.toStringAsFixed(5);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$lat, $lon',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: AppColors.textMuted,
            tooltip: 'Rimuovi',
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

/// Dialog di salvataggio percorso pianificato.
class _SaveDialog extends StatefulWidget {
  const _SaveDialog();

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Salva percorso pianificato'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Es. Anello del Lago',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descrizione (opzionale)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, {
              'name': name,
              'description': _descController.text.trim().isEmpty
                  ? null
                  : _descController.text.trim(),
            });
          },
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
