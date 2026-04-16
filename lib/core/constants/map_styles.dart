import 'package:flutter/material.dart';

/// Stile mappa disponibile nell'app
class MapStyle {
  final String name;
  final String urlTemplate;
  final List<String> subdomains;
  final IconData icon;

  /// Opzionale: ColorFilter applicato ai tile. Usato per schiarire lo stile
  /// dark di CartoDB, che altrimenti risulterebbe illeggibile su mobile.
  final ColorFilter? tileColorFilter;

  const MapStyle({
    required this.name,
    required this.urlTemplate,
    this.subdomains = const [],
    this.icon = Icons.map,
    this.tileColorFilter,
  });
}

/// ColorFilter per schiarire i tile CartoDB dark_all.
/// Combina un bump di luminosità (+0.18) con un leggero boost di contrasto
/// (1.15) così strade, sentieri ed etichette diventano leggibili.
const ColorFilter _darkBrightenFilter = ColorFilter.matrix(<double>[
  1.15, 0,    0,    0, 46,
  0,    1.15, 0,    0, 46,
  0,    0,    1.15, 0, 46,
  0,    0,    0,    1,  0,
]);

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
  MapStyle(
    // CartoDB dark_all + ColorFilter di schiaritura lato client: senza filtro
    // il tile originale è troppo scuro su mobile (feedback utente). Il filtro
    // aumenta luminosità e contrasto mantenendo l'estetica notturna.
    name: 'Notte',
    urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c', 'd'],
    icon: Icons.dark_mode,
    tileColorFilter: _darkBrightenFilter,
  ),
];
