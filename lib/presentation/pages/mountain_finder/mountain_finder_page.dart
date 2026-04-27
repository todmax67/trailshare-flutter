import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../data/models/mountain_peak.dart';

/// **Mountain Finder AR** — schermata "punta il telefono e riconosci le cime".
///
/// **Step 1 (v2.0.0)**: scaffolding tecnico.
/// Mostra:
/// - preview live della fotocamera posteriore
/// - GPS dell'utente
/// - heading dalla bussola
/// - lista debug delle 5 cime più vicine fra [famousItalianPeaks]
///
/// La math di proiezione (bearing → x viewport, altitude+distance → y) e
/// l'overlay AR sui peak verranno implementati nello Step 2. Qui ci
/// limitiamo a verificare che camera + sensori + GPS funzionino sui
/// dispositivi reali.
class MountainFinderPage extends StatefulWidget {
  const MountainFinderPage({super.key});

  @override
  State<MountainFinderPage> createState() => _MountainFinderPageState();
}

class _MountainFinderPageState extends State<MountainFinderPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _initializing = true;
  String? _error;

  // Sensor state
  Position? _userPosition;
  double? _heading; // gradi 0-360, 0 = Nord
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;

  // Debug: le 5 cime più vicine all'utente.
  List<_NearbyPeak> _nearbyPeaks = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBindingObserver;
    _bootstrap();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // Camera permission e inizializzazione (la permission Camera è
      // gestita dal plugin in modo cross-platform al primo accesso).
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = context.l10n.mfCameraNotAvailable;
        });
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _camera = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _camera!.initialize();

      // GPS: prima posizione + stream.
      try {
        _userPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        // proseguiamo anche senza posizione iniziale
      }
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen(
        (pos) {
          if (!mounted) return;
          setState(() {
            _userPosition = pos;
            _nearbyPeaks = _computeNearby(pos);
          });
        },
      );

      // Compass.
      _compassSub = FlutterCompass.events?.listen((event) {
        if (!mounted) return;
        final h = event.heading;
        if (h == null) return;
        // FlutterCompass restituisce -180..180; normalizzo a 0..360
        final normalized = h < 0 ? h + 360 : h;
        setState(() => _heading = normalized);
      });

      if (_userPosition != null) {
        _nearbyPeaks = _computeNearby(_userPosition!);
      }

      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = context.l10n.errorWithDetails(e.toString());
      });
    }
  }

  /// Calcola le 5 cime più vicine alla posizione utente. In Step 1 usa il
  /// dataset hardcoded; in Step 3 sarà sostituito dal dataset OSM full.
  List<_NearbyPeak> _computeNearby(Position pos) {
    final list = famousItalianPeaks
        .map((p) => _NearbyPeak(
              peak: p,
              distanceMeters: _haversine(
                pos.latitude,
                pos.longitude,
                p.latitude,
                p.longitude,
              ),
              bearingDeg: _initialBearing(
                pos.latitude,
                pos.longitude,
                p.latitude,
                p.longitude,
              ),
            ))
        .toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return list.take(5).toList();
  }

  // Haversine: distanza tra due lat/lng in metri.
  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Bearing iniziale da p1 a p2 in gradi (0 = Nord).
  double _initialBearing(
      double lat1, double lng1, double lat2, double lng2) {
    final y = math.sin(_toRad(lng2 - lng1)) * math.cos(_toRad(lat2));
    final x = math.cos(_toRad(lat1)) * math.sin(_toRad(lat2)) -
        math.sin(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.cos(_toRad(lng2 - lng1));
    final brng = _toDeg(math.atan2(y, x));
    return (brng + 360) % 360;
  }

  double _toRad(double deg) => deg * math.pi / 180;
  double _toDeg(double rad) => rad * 180 / math.pi;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_initializing)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (_error != null)
              _buildError(_error!)
            else if (_camera != null && _camera!.value.isInitialized)
              _buildCameraPreview()
            else
              const SizedBox.shrink(),

            // HUD: titolo + stato sensori (sempre visibile).
            _buildTopHUD(),

            // Debug card: lista 5 cime più vicine.
            if (!_initializing && _error == null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _buildDebugCard(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Positioned.fill(
      child: AspectRatio(
        aspectRatio: _camera!.value.aspectRatio,
        child: CameraPreview(_camera!),
      ),
    );
  }

  Widget _buildTopHUD() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Row(
        children: [
          // Back
          Material(
            color: Colors.black.withValues(alpha: 0.5),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: context.l10n.cancel,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.terrain,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.mfTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _heading != null
                        ? '${_heading!.toStringAsFixed(0)}°'
                        : '—°',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 56, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _initializing = true;
                  _error = null;
                });
                _bootstrap();
              },
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugCard() {
    final pos = _userPosition;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.themedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                context.l10n.mfDebugTitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              if (pos != null)
                Text(
                  '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_nearbyPeaks.isEmpty)
            Text(
              context.l10n.mfDebugWaitingGps,
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ..._nearbyPeaks.map((np) => _buildPeakRow(np)),
        ],
      ),
    );
  }

  Widget _buildPeakRow(_NearbyPeak np) {
    final relativeBearing = _heading == null
        ? null
        : ((np.bearingDeg - _heading!) + 540) % 360 - 180; // -180..180

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            np.peak.type == 'volcano' ? Icons.local_fire_department : Icons.terrain,
            size: 16,
            color: np.peak.type == 'volcano'
                ? AppColors.danger
                : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  np.peak.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  '${(np.distanceMeters / 1000).toStringAsFixed(1)} km · '
                  '${np.bearingDeg.toStringAsFixed(0)}°'
                  '${np.peak.elevation != null ? ' · ${np.peak.elevation!.round()} m' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (relativeBearing != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: relativeBearing.abs() < 30
                    ? AppColors.success.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: relativeBearing.abs() < 30
                      ? AppColors.success
                      : context.themedBorder,
                ),
              ),
              child: Text(
                '${relativeBearing > 0 ? '→' : '←'} ${relativeBearing.abs().toStringAsFixed(0)}°',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: relativeBearing.abs() < 30
                      ? AppColors.success
                      : context.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Peak con distanza e bearing pre-calcolati rispetto alla posizione utente.
class _NearbyPeak {
  final MountainPeak peak;
  final double distanceMeters;
  final double bearingDeg;

  const _NearbyPeak({
    required this.peak,
    required this.distanceMeters,
    required this.bearingDeg,
  });
}
