import 'package:flutter/material.dart';

/// Stile mappa disponibile nell'app
class MapStyle {
  final String name;
  final String urlTemplate;
  final List<String> subdomains;
  final IconData icon;

  const MapStyle({
    required this.name,
    required this.urlTemplate,
    this.subdomains = const [],
    this.icon = Icons.map,
  });
}

/// Stili mappa disponibili nell'app
const List<MapStyle> mapStyles = [
  MapStyle(
    name: 'Standard',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    icon: Icons.map_outlined,
  ),
  MapStyle(
    name: 'Topografica',
    urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    icon: Icons.terrain,
  ),
  MapStyle(
    name: 'Satellite',
    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    icon: Icons.satellite_alt,
  ),
];
