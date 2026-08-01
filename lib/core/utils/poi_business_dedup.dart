/// Toglie dai POI OSM quelli che sono già mostrati come scheda Spazio Pro.
///
/// Nasce da una segnalazione utente del 2026-07-31 sul Rifugio Jean-Antoine
/// Carrel, marcata "Duplicato". Non era un duplicato fra schede — entro 600 m
/// ce n'è una sola — ma fra **sorgenti diverse**: lo stesso rifugio esiste sia
/// in `businesses` sia in `assets/data/pois_italy_clean.json`, perché entrambi
/// i dataset derivano da OpenStreetMap.
///
/// Misurato sull'intero catalogo: **2.949 schede su 6.496 (45,4%)** hanno un
/// POI OSM con nome identico a meno di 60 metri. Sulla mappa di un percorso
/// che passa di lì compaiono due marker sovrapposti e due schede di dettaglio
/// diverse per lo stesso posto.
///
/// Vince la scheda business: ha foto, orari, listino, percorsi consigliati e
/// lo stato di rivendicazione. Il POI OSM è il ripiego per tutto ciò che una
/// scheda non ce l'ha.
///
/// ## Perché il nome deve combaciare esatto
///
/// Sui 3.042 POI entro 60 m da una scheda, 2.949 hanno il nome **identico**.
/// I 93 restanti sono quasi sempre cose diverse che stanno vicine — una
/// fontana accanto a un rifugio, un parcheggio davanti a un bar — e toglierli
/// significherebbe nascondere informazione vera.
///
/// Un confronto più permissivo (contenimento, distanza di edit) prenderebbe
/// quel 3% in più al prezzo di far sparire POI legittimi. Non conviene: qui
/// l'errore costoso è nascondere, non lasciare un duplicato.
library;

import 'dart:math' as math;

import '../../data/models/osm_poi.dart';

/// Coordinate e nome di una scheda già disegnata sulla mappa.
typedef BusinessMarker = ({String name, double lat, double lng});

/// Distanza oltre la quale due punti con lo stesso nome non sono più lo
/// stesso posto. 60 m copre lo scarto fra il nodo OSM e il centroide della
/// scheda senza arrivare a unire edifici distinti.
const double _kMaxMeters = 60;

/// Confronto tollerante alla forma ma non al contenuto: maiuscole, spazi
/// doppi e spazi ai bordi non fanno differenza, il resto sì.
String _normalize(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

double _meters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
}

/// I POI da disegnare, tolti quelli che una scheda già rappresenta.
///
/// Restituisce la lista originale quando non c'è nessuna scheda: il caso più
/// comune, e non deve costare niente.
List<OsmPoi> dedupOsmPois(
  List<OsmPoi> pois,
  Iterable<BusinessMarker> businesses,
) {
  if (pois.isEmpty || businesses.isEmpty) return pois;

  // Indice per nome: senza, sono |pois| × |schede| confronti a ogni build.
  final byName = <String, List<BusinessMarker>>{};
  for (final b in businesses) {
    final k = _normalize(b.name);
    if (k.isEmpty) continue;
    (byName[k] ??= []).add(b);
  }
  if (byName.isEmpty) return pois;

  return pois.where((p) {
    final candidates = byName[_normalize(p.name)];
    if (candidates == null) return true;
    for (final b in candidates) {
      if (_meters(p.latitude, p.longitude, b.lat, b.lng) <= _kMaxMeters) {
        return false;
      }
    }
    return true;
  }).toList();
}
