import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/services/voice_guidance_service.dart';
import '../../../data/models/navigation_step.dart';

/// Pagina di navigazione turn-by-turn con guida vocale.
///
/// Riceve un [RouteResult] (tipicamente dal Planner) e segue l'utente step
/// per step, emettendo annunci TTS alle soglie 500/200/50 m prima di ogni
/// svolta e alla svolta stessa.
class NavigationPage extends StatefulWidget {
  final RouteResult route;

  const NavigationPage({super.key, required this.route});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  final MapController _mapController = MapController();
  final VoiceGuidanceService _voice = VoiceGuidanceService();

  StreamSubscription<Position>? _positionSub;
  LatLng? _userPos;
  double? _userSpeedKmh;
  int _userIndex = 0;
  NavigationStep? _currentStep;
  NavigationStep? _nextStep;
  double _distanceToNextTurn = 0;
  double _remainingTotal = 0;
  bool _offRoute = false;
  DateTime? _lastOffRouteAnnouncement;
  bool _arrived = false;

  /// Soglie raggiunte per ogni step (chiave: "stepIndex_threshold")
  final Set<String> _spokenThresholds = {};

  late final List<LatLng> _polyline;

  @override
  void initState() {
    super.initState();
    _polyline = widget.route.points.map((p) => p.latLng).toList();
    _remainingTotal = widget.route.distance;
    _initVoice();
    _initLocation();
  }

  Future<void> _initVoice() async {
    await _voice.init();
    // Annuncio di benvenuto
    final firstStep = widget.route.steps.isNotEmpty ? widget.route.steps.first : null;
    if (firstStep != null) {
      final next = widget.route.steps.length > 1 ? widget.route.steps[1] : null;
      final welcome = next != null
          ? 'Navigazione avviata. Prima manovra: ${next.maneuver.italianAction.toLowerCase()}'
          : 'Navigazione avviata';
      await _voice.speak(welcome);
    }
  }

  Future<void> _initLocation() async {
    try {
      // Permessi
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permessi di localizzazione negati')),
          );
        }
        return;
      }

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen(_onPosition);
    } catch (e) {
      debugPrint('[Nav] Errore init location: $e');
    }
  }

  void _onPosition(Position pos) {
    if (!mounted || _arrived) return;
    final user = LatLng(pos.latitude, pos.longitude);

    // Aggiorna indice utente sul polyline (mai indietro)
    final newIndex = NavigationService.findNearestPointIndex(
      _polyline,
      user,
      minIndex: _userIndex,
    );

    // Current step
    final curStep = NavigationService.currentStep(widget.route.steps, newIndex);
    final next = NavigationService.nextStep(widget.route.steps, curStep);

    // Distanza alla prossima svolta
    double distToTurn = 0;
    if (curStep != null) {
      distToTurn = NavigationService.remainingDistanceInStep(
        _polyline,
        newIndex,
        user,
        curStep,
      );
    }

    // Distanza residua totale
    final remainingTotal = NavigationService.remainingDistanceTotal(
      _polyline,
      newIndex,
      user,
    );

    // Off-route check
    final distFromRoute = NavigationService.distanceToPolyline(_polyline, user);
    final offRoute = distFromRoute > 50;

    setState(() {
      _userPos = user;
      _userSpeedKmh = pos.speed * 3.6;
      _userIndex = newIndex;
      _currentStep = curStep;
      _nextStep = next;
      _distanceToNextTurn = distToTurn;
      _remainingTotal = remainingTotal;
      _offRoute = offRoute;
    });

    // Segue l'utente con la mappa
    _mapController.move(user, _mapController.camera.zoom);

    // TTS logic
    _maybeAnnounce(curStep, distToTurn, offRoute, remainingTotal);
  }

  void _maybeAnnounce(
    NavigationStep? step,
    double distToTurn,
    bool offRoute,
    double remainingTotal,
  ) {
    // Arrivo
    if (remainingTotal < 30 && !_arrived) {
      _arrived = true;
      _voice.speak('Sei arrivato a destinazione');
      return;
    }

    // Off-route (con debounce 10s)
    if (offRoute) {
      final now = DateTime.now();
      if (_lastOffRouteAnnouncement == null ||
          now.difference(_lastOffRouteAnnouncement!).inSeconds > 10) {
        _voice.speak('Attenzione, sei fuori percorso');
        _lastOffRouteAnnouncement = now;
      }
      return;
    }

    if (step == null) return;

    // Soglie: 500 / 200 / 50 metri
    // Annunciamo solo se la distanza scende SOTTO la soglia per la prima volta.
    void trySpeak(double threshold, String key) {
      final lookupKey = '${step.index}_$key';
      if (distToTurn <= threshold && !_spokenThresholds.contains(lookupKey)) {
        _spokenThresholds.add(lookupKey);
        // Pulisce le soglie più grandi già superate
        _voice.speak(step.maneuver.instructionWithDistance(distToTurn));
      }
    }

    if (distToTurn > 500) {
      // reset per questo step (caso rarissimo di retrocessione)
      _spokenThresholds.removeWhere((k) => k.startsWith('${step.index}_'));
      return;
    }
    trySpeak(500, '500');
    if (distToTurn <= 200) trySpeak(200, '200');
    if (distToTurn <= 50) trySpeak(50, '50');
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _voice.dispose();
    super.dispose();
  }

  String _formatDistance(double m) {
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double seconds) {
    final hours = (seconds / 3600).floor();
    final mins = ((seconds % 3600) / 60).floor();
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _polyline.isNotEmpty
        ? LatLngBounds.fromPoints(_polyline)
        : null;

    return Scaffold(
      body: Stack(
        children: [
          // Mappa
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _polyline.isNotEmpty ? _polyline.first : const LatLng(45, 10),
              initialZoom: 15,
              minZoom: 10,
              maxZoom: 18,
              initialCameraFit: bounds != null
                  ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80))
                  : null,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.trailshare.app',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _polyline,
                    strokeWidth: 6,
                    color: AppColors.primary,
                  ),
                ],
              ),
              if (_userPos != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userPos!,
                      width: 26,
                      height: 26,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.3),
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

          // Top panel: istruzione corrente
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _buildInstructionPanel(),
            ),
          ),

          // Bottom panel: stats + controlli
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _buildStatsPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionPanel() {
    final step = _currentStep;
    if (step == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Avvio navigazione...'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: _offRoute ? AppColors.danger : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _offRoute
                      ? Colors.white
                      : AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _offRoute ? Icons.warning_amber : step.maneuver.icon,
                  size: 36,
                  color: _offRoute ? AppColors.danger : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _offRoute
                          ? 'Sei fuori percorso'
                          : step.maneuver.italianAction,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _offRoute ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    if (!_offRoute) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Tra ${_formatDistance(_distanceToNextTurn)}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _voice.enabled ? Icons.volume_up : Icons.volume_off,
                  color: _offRoute ? Colors.white : AppColors.primary,
                ),
                onPressed: () => setState(() => _voice.enabled = !_voice.enabled),
                tooltip: _voice.enabled ? 'Silenzia' : 'Attiva voce',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsPanel() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_nextStep != null && !_offRoute) ...[
                Row(
                  children: [
                    Icon(_nextStep!.maneuver.icon, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Poi ${_nextStep!.maneuver.italianAction.toLowerCase()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
              ],
              Row(
                children: [
                  _statItem(
                    Icons.straighten,
                    _formatDistance(_remainingTotal),
                    'Residuo',
                  ),
                  const SizedBox(width: 8),
                  _statItem(
                    Icons.schedule,
                    _formatDuration(_estimatedRemainingDuration()),
                    'Arrivo',
                  ),
                  const SizedBox(width: 8),
                  _statItem(
                    Icons.speed,
                    '${(_userSpeedKmh ?? 0).round()} km/h',
                    'Velocità',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Termina navigazione'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  double _estimatedRemainingDuration() {
    if (widget.route.distance <= 0) return 0;
    final ratio = _remainingTotal / widget.route.distance;
    return widget.route.estimatedDuration * ratio;
  }
}
