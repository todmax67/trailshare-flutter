import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/trail_poi.dart';

/// Layer riusabile per renderizzare i POI come marker su una FlutterMap.
///
/// Ogni marker mostra l'emoji del tipo dentro un pin colorato con il
/// colore del tipo. Tap sul marker → callback [onTap] con il POI.
///
/// Uso tipico:
/// ```dart
/// PoiMarkerLayer(
///   pois: _myPois,
///   onTap: (poi) => showPoiDetailSheet(context, poi: poi),
/// )
/// ```
class PoiMarkerLayer extends StatelessWidget {
  final List<TrailPoi> pois;
  final ValueChanged<TrailPoi>? onTap;
  final double markerSize;

  const PoiMarkerLayer({
    super.key,
    required this.pois,
    this.onTap,
    this.markerSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    if (pois.isEmpty) return const SizedBox.shrink();
    return MarkerLayer(
      markers: pois.map((poi) => _buildMarker(poi)).toList(),
    );
  }

  Marker _buildMarker(TrailPoi poi) {
    return Marker(
      point: LatLng(poi.latitude, poi.longitude),
      width: markerSize,
      height: markerSize,
      child: GestureDetector(
        onTap: () => onTap?.call(poi),
        child: _PoiPin(poi: poi, size: markerSize),
      ),
    );
  }
}

/// Pin circolare con emoji + bordino bianco, color pin = type.pinColor.
/// Su tap mostra un feedback visuale tramite ripple (inkwell).
class _PoiPin extends StatelessWidget {
  final TrailPoi poi;
  final double size;

  const _PoiPin({required this.poi, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: poi.type.pinColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: poi.type.pinColor.withOpacity(0.35),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        poi.type.emoji,
        style: TextStyle(fontSize: size * 0.5),
      ),
    );
  }
}
