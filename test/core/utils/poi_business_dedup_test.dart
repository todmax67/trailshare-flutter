import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/poi_business_dedup.dart';
import 'package:trailshare_flutter/data/models/osm_poi.dart';

OsmPoi _poi(String name, double lat, double lng) => OsmPoi(
      id: '$name-$lat',
      type: OsmPoiType.alpineHut,
      name: name,
      latitude: lat,
      longitude: lng,
    );

/// Le coordinate reali del Rifugio Jean-Antoine Carrel, che ha originato la
/// segnalazione: scheda business e POI OSM a 5 metri con lo stesso nome.
const _carrelLat = 45.9730, _carrelLng = 7.6478;

void main() {
  group('dedupOsmPois', () {
    test('senza schede non tocca niente', () {
      final pois = [_poi('Rifugio X', 45.0, 9.0)];
      expect(dedupOsmPois(pois, const []), same(pois));
    });

    test('il caso Carrel: stesso nome a pochi metri sparisce', () {
      final out = dedupOsmPois(
        [_poi('Rifugio Jean-Antoine Carrel', _carrelLat, _carrelLng)],
        [(name: 'Rifugio Jean-Antoine Carrel', lat: 45.97305, lng: 7.64775)],
      );
      expect(out, isEmpty);
    });

    test('stesso nome ma lontano resta: sono due posti diversi', () {
      // Due "Rifugio Alpino" a 2 km l'uno dall'altro esistono davvero.
      final out = dedupOsmPois(
        [_poi('Rifugio Alpino', 45.9730, 7.6478)],
        [(name: 'Rifugio Alpino', lat: 45.9910, lng: 7.6478)],
      );
      expect(out, hasLength(1));
    });

    test('vicino ma con nome diverso resta: fontana accanto al rifugio', () {
      final out = dedupOsmPois(
        [_poi('Fontana del Carrel', _carrelLat, _carrelLng)],
        [(name: 'Rifugio Jean-Antoine Carrel', lat: _carrelLat, lng: _carrelLng)],
      );
      expect(out, hasLength(1),
          reason: 'nascondere un POI legittimo e\' l\'errore costoso');
    });

    test('maiuscole e spazi doppi non fanno differenza', () {
      final out = dedupOsmPois(
        [_poi('  RIFUGIO   Jean-Antoine  Carrel ', _carrelLat, _carrelLng)],
        [(name: 'Rifugio Jean-Antoine Carrel', lat: _carrelLat, lng: _carrelLng)],
      );
      expect(out, isEmpty);
    });

    test('toglie solo i duplicati, il resto della lista sopravvive', () {
      final out = dedupOsmPois(
        [
          _poi('Rifugio Carrel', _carrelLat, _carrelLng),
          _poi('Sorgente', 45.9740, 7.6480),
          _poi('Bivacco Perelli', 45.9800, 7.6500),
        ],
        [(name: 'Rifugio Carrel', lat: _carrelLat, lng: _carrelLng)],
      );
      expect(out.map((p) => p.name), ['Sorgente', 'Bivacco Perelli']);
    });

    test('una scheda senza nome non nasconde nulla', () {
      final out = dedupOsmPois(
        [_poi('Rifugio Carrel', _carrelLat, _carrelLng)],
        [(name: '   ', lat: _carrelLat, lng: _carrelLng)],
      );
      expect(out, hasLength(1));
    });

    test('più schede omonime: basta che una sia vicina', () {
      final out = dedupOsmPois(
        [_poi('Rifugio Alpino', _carrelLat, _carrelLng)],
        [
          (name: 'Rifugio Alpino', lat: 46.5, lng: 8.0),
          (name: 'Rifugio Alpino', lat: _carrelLat, lng: _carrelLng),
        ],
      );
      expect(out, isEmpty);
    });
  });
}
