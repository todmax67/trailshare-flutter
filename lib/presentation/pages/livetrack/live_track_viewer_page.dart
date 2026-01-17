import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/live_track_repository.dart';

/// Pagina per visualizzare una sessione LiveTrack in tempo reale
/// 
/// Mostra la posizione di chi sta condividendo su mappa con:
/// - Marker posizione corrente
/// - Traccia del percorso
/// - Info: nome utente, batteria, ultimo aggiornamento
class LiveTrackViewerPage extends StatefulWidget {
  final String sessionId;

  const LiveTrackViewerPage({
    super.key,
    required this.sessionId,
  });

  @override
  State<LiveTrackViewerPage> createState() => _LiveTrackViewerPageState();
}

class _LiveTrackViewerPageState extends State<LiveTrackViewerPage> {
  final LiveTrackRepository _repository = LiveTrackRepository();
  final MapController _mapController = MapController();
  
  StreamSubscription<LiveSession?>? _subscription;
  LiveSession? _session;
  bool _isLoading = true;
  String? _error;
  bool _followUser = true;

  @override
  void initState() {
    super.initState();
    _startWatching();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _startWatching() {
    _subscription = _repository.watchSession(widget.sessionId).listen(
      (session) {
        if (session == null) {
          setState(() {
            _error = 'Sessione non trovata o scaduta';
            _isLoading = false;
          });
          return;
        }

        setState(() {
          _session = session;
          _isLoading = false;
        });

        // Centra mappa sulla posizione
        if (_followUser && session.currentLocation != null) {
          _mapController.move(
            LatLng(session.currentLocation!.latitude, session.currentLocation!.longitude),
            15,
          );
        }
      },
      onError: (e) {
        setState(() {
          _error = 'Errore: $e';
          _isLoading = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Mappa
          _buildMap(),
          
          // Card info in alto
          if (_session != null) _buildInfoCard(),
          
          // Loading
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
          
          // Errore
          if (_error != null) _buildError(),
          
          // Bottone centra
          if (_session?.currentLocation != null)
            Positioned(
              bottom: 100,
              right: 16,
              child: FloatingActionButton.small(
                onPressed: () {
                  setState(() => _followUser = true);
                  if (_session?.currentLocation != null) {
                    _mapController.move(
                      LatLng(_session!.currentLocation!.latitude, _session!.currentLocation!.longitude),
                      15,
                    );
                  }
                },
                backgroundColor: _followUser ? AppColors.primary : Colors.white,
                child: Icon(
                  Icons.my_location,
                  color: _followUser ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final defaultCenter = LatLng(45.9, 9.9);
    
    LatLng? currentPos;
    if (_session?.currentLocation != null) {
      currentPos = LatLng(
        _session!.currentLocation!.latitude,
        _session!.currentLocation!.longitude,
      );
    }

    // Converti path in lista di LatLng
    final pathPoints = _session?.path
        .map((gp) => LatLng(gp.latitude, gp.longitude))
        .toList() ?? [];

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: currentPos ?? defaultCenter,
        initialZoom: 14,
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) {
            setState(() => _followUser = false);
          }
        },
      ),
      children: [
        // Tile layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.trailshare.app',
        ),
        
        // Traccia percorso
        if (pathPoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: pathPoints,
                strokeWidth: 4,
                color: AppColors.danger.withOpacity(0.8),
                pattern: const StrokePattern.dotted(),
      ),
            ],
          ),
        
        // Marker posizione corrente
        if (currentPos != null)
          MarkerLayer(
            markers: [
              // Punto di partenza
              if (pathPoints.isNotEmpty)
                Marker(
                  point: pathPoints.first,
                  width: 24,
                  height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.flag, color: Colors.white, size: 12),
                  ),
                ),
              
              // Posizione corrente (pulsante)
              Marker(
                point: currentPos,
                width: 40,
                height: 40,
                child: _PulsingMarker(),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildInfoCard() {
    final session = _session!;
    
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          bottom: 16,
          left: 16,
          right: 16,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
            ),
          ],
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header con back button
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    session.userName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48), // Balance
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Status badge + battery
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: session.isActive ? AppColors.success : Colors.grey,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (session.isActive)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(
                        session.isActive ? 'IN DIRETTA' : 'TERMINATA',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Batteria
                Row(
                  children: [
                    Icon(
                      _getBatteryIcon(session.batteryLevel),
                      size: 18,
                      color: _getBatteryColor(session.batteryLevel),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${session.batteryLevel}%',
                      style: TextStyle(
                        color: _getBatteryColor(session.batteryLevel),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Ultimo aggiornamento
            Text(
              'Ultimo segnale: ${session.lastUpdateFormatted}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            
            // Durata
            if (session.startTime != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Durata: ${session.durationFormatted}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Torna indietro'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getBatteryIcon(int level) {
    if (level > 80) return Icons.battery_full;
    if (level > 60) return Icons.battery_5_bar;
    if (level > 40) return Icons.battery_4_bar;
    if (level > 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color _getBatteryColor(int level) {
    if (level > 50) return AppColors.success;
    if (level > 20) return AppColors.warning;
    return AppColors.danger;
  }
}

/// Marker pulsante per posizione corrente
class _PulsingMarker extends StatefulWidget {
  @override
  State<_PulsingMarker> createState() => _PulsingMarkerState();
}

class _PulsingMarkerState extends State<_PulsingMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.danger.withOpacity(0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 20,
            ),
          ),
        );
      },
    );
  }
}
