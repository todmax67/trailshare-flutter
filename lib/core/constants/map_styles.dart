import 'package:flutter/material.dart';

import 'api_keys.dart';

/// Stile mappa disponibile nell'app
class MapStyle {
  final String name;
  final String urlTemplate;
  final List<String> subdomains;
  final IconData icon;

  /// Opzionale: ColorFilter applicato ai tile. Usato per schiarire lo stile
  /// dark di CartoDB, che altrimenti risulterebbe illeggibile su mobile.
  final ColorFilter? tileColorFilter;

  /// Se `true`, lo stile è disponibile solo per gli utenti TrailShare Pro.
  /// La UI del picker mostra un badge "PRO" e al tap apre il PaywallSheet
  /// invece di applicare lo stile.
  final bool isPro;

  /// Breve descrizione (1 riga) mostrata sotto il nome nel picker.
  /// Aiuta l'utente a capire quando usare uno stile vs l'altro.
  final String? subtitle;

  const MapStyle({
    required this.name,
    required this.urlTemplate,
    this.subdomains = const [],
    this.icon = Icons.map,
    this.tileColorFilter,
    this.isPro = false,
    this.subtitle,
  });
}

/// ColorFilter per schiarire i tile CartoDB dark_all.
/// Combina un bump di luminosità (+0.18) con un leggero boost di contrasto
/// (1.15) così strade, sentieri ed etichette diventano leggibili.
const ColorFilter _darkBrightenFilter = ColorFilter.matrix(<double>[
  1.15, 0,    0,    0, 46,
  0,    1.15, 0,    0, 46,
  0,    0,    1.15, 0,  46,
  0,    0,    0,    1,  0,
]);

/// Stili mappa disponibili nell'app.
///
/// I primi 4 sono **free per tutti**. Gli ultimi sono **Pro**: la UI del
/// picker li mostra con badge e al tap di un utente non-Pro apre il
/// PaywallSheet.
List<MapStyle> get mapStyles => [
      const MapStyle(
        name: 'Standard',
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        icon: Icons.map_outlined,
      ),
      const MapStyle(
        name: 'Topografica',
        urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
        subdomains: ['a', 'b', 'c'],
        icon: Icons.terrain,
        subtitle: 'Curve di livello + sentieri OSM',
      ),
      const MapStyle(
        name: 'Satellite',
        urlTemplate:
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        icon: Icons.satellite_alt,
      ),
      const MapStyle(
        // CartoDB dark_all + ColorFilter di schiaritura lato client: senza
        // filtro il tile originale è troppo scuro su mobile (feedback
        // utente). Il filtro aumenta luminosità e contrasto mantenendo
        // l'estetica notturna.
        name: 'Notte',
        urlTemplate:
            'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
        subdomains: ['a', 'b', 'c', 'd'],
        icon: Icons.dark_mode,
        tileColorFilter: _darkBrightenFilter,
      ),
      // ─── Pro styles (TrailShare Pro) ───
      // Servite da MapTiler Cloud (free tier: 100k tile/mese). La key è
      // restretta per bundle ID lato dashboard, vedi ApiKeys.mapTiler.
      MapStyle(
        name: 'Topo Pro',
        urlTemplate:
            'https://api.maptiler.com/maps/topo-v4/{z}/{x}/{y}.png?key=${ApiKeys.mapTiler}',
        icon: Icons.terrain,
        isPro: true,
        subtitle: 'Cartografia topografica premium (stile IGM-like)',
      ),
      MapStyle(
        name: 'Satellite Pro',
        urlTemplate:
            'https://api.maptiler.com/maps/hybrid-v4/{z}/{x}/{y}.png?key=${ApiKeys.mapTiler}',
        icon: Icons.satellite,
        isPro: true,
        subtitle: 'Satellite + nomi vette, sentieri e comuni',
      ),
      MapStyle(
        name: 'Inverno Pro',
        urlTemplate:
            'https://api.maptiler.com/maps/winter-v4/{z}/{x}/{y}.png?key=${ApiKeys.mapTiler}',
        icon: Icons.ac_unit,
        isPro: true,
        subtitle: 'Piste sci, ciaspole, scialpinismo',
      ),
    ];
