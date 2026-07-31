/// Riquadri di inquadratura sicuri per `CameraFit.bounds`.
///
/// Nasce dal crash comparso il 2026-07-31 sulla 2.9.4:
/// `_TileLayerState._clampToNativeZoom` → *Unsupported operation: Infinity or
/// NaN*. flutter_map calcola lo zoom che serve a far entrare il riquadro nello
/// schermo; se il riquadro ha **dimensione zero** — tutti i punti alla stessa
/// coordinata, o un punto solo — quel calcolo tende a infinito, e il primo
/// `.round()` a valle solleva.
///
/// I controlli che c'erano nell'app (`isNotEmpty`, `length >= 2`) non bastavano:
/// dieci punti identici li superano entrambi. Non è un caso di laboratorio —
/// una registrazione avviata e chiusa senza muoversi, un import con un punto
/// ripetuto, o una geometria di catalogo vuota lo producono.
///
/// La scelta qui è **allargare** invece di rifiutare: per una traccia di un
/// punto solo la cosa utile è vedere la mappa centrata lì, non ritrovarsi
/// sull'inquadratura di default a mille chilometri di distanza.
library;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Semiampiezza minima del riquadro, in gradi (~110 m di latitudine).
///
/// Sotto questa soglia il riquadro viene allargato attorno al suo centro. Il
/// valore corrisponde a uno zoom di circa 16: abbastanza stretto da vedere il
/// dettaglio, abbastanza largo da non chiedere alle tile uno zoom che non
/// esiste.
const double _kMinHalfSpanDeg = 0.001;

/// Costruisce un riquadro utilizzabile da `CameraFit.bounds`, oppure null se
/// non c'è nessuna coordinata valida su cui inquadrare.
///
/// Scarta i punti con coordinate non finite o fuori dai limiti terrestri: un
/// singolo NaN in mezzo a mille punti buoni avvelena l'intero riquadro, e a
/// valle diventa lo stesso crash.
LatLngBounds? safeBounds(Iterable<LatLng> points) {
  double? minLat, maxLat, minLng, maxLng;

  for (final p in points) {
    final lat = p.latitude;
    final lng = p.longitude;
    // `isFinite` e' falso sia per NaN sia per gli infiniti. Il confronto con
    // NaN restituisce sempre false, quindi senza questo controllo esplicito i
    // punti guasti passerebbero silenziosamente.
    if (!lat.isFinite || !lng.isFinite) continue;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;

    minLat = (minLat == null || lat < minLat) ? lat : minLat;
    maxLat = (maxLat == null || lat > maxLat) ? lat : maxLat;
    minLng = (minLng == null || lng < minLng) ? lng : minLng;
    maxLng = (maxLng == null || lng > maxLng) ? lng : maxLng;
  }

  if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
    return null;
  }

  // Allarga solo quanto serve: una traccia normale esce da qui intatta.
  final latPad = ((_kMinHalfSpanDeg * 2) - (maxLat - minLat)) / 2;
  final lngPad = ((_kMinHalfSpanDeg * 2) - (maxLng - minLng)) / 2;
  if (latPad > 0) {
    minLat -= latPad;
    maxLat += latPad;
  }
  if (lngPad > 0) {
    minLng -= lngPad;
    maxLng += lngPad;
  }

  // L'allargamento puo' sconfinare ai poli o ai meridiani estremi.
  return LatLngBounds(
    LatLng(minLat.clamp(-90.0, 90.0), minLng.clamp(-180.0, 180.0)),
    LatLng(maxLat.clamp(-90.0, 90.0), maxLng.clamp(-180.0, 180.0)),
  );
}

/// Come [safeBounds], ma partendo da oggetti con latitudine e longitudine
/// sciolte — i punti traccia dell'app, che non sono `LatLng`.
LatLngBounds? safeBoundsFromCoords(
  Iterable<({double lat, double lng})> coords,
) =>
    safeBounds(coords.map((c) => LatLng(c.lat, c.lng)));
