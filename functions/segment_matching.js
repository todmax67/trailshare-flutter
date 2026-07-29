// Porting JavaScript di lib/core/services/segment_matching_service.dart.
//
// ATTENZIONE — QUESTO FILE E' UN GEMELLO, NON UN ORIGINALE.
// Raggi, tolleranze e criteri vanno cambiati su ENTRAMBI i file, o la stessa
// traccia produce due risultati diversi a seconda di chi la confronta —
// l'app al salvataggio o il recupero storico. La prova di fedelta' e' in
// scripts/segment_backfill.cjs --verifica, che rifa' i conti sugli sforzi
// gia' scritti dall'app e controlla che i tempi coincidano.
//
// Allineato al Dart al 2026-07-29.

'use strict';

const RAGGIO_PARTENZA = 30;      // m dal punto di partenza del segmento
const RAGGIO_ARRIVO = 30;        // m dal punto di arrivo
const TOLLERANZA_MEDIA = 40;     // m di scostamento medio dal tracciato
const TOLLERANZA_MASSIMA = 80;   // m di scostamento nel punto peggiore
const PADDING_BBOX = 0.01;       // ~1 km, per lo scarto rapido

function distanzaMetri(la1, ln1, la2, ln2) {
  const R = 6371000, rad = (x) => (x * Math.PI) / 180;
  const dLat = rad(la2 - la1), dLon = rad(ln2 - ln1);
  const sLat = Math.sin(dLat / 2), sLon = Math.sin(dLon / 2);
  const h = sLat * sLat
    + Math.cos(rad(la1)) * Math.cos(rad(la2)) * sLon * sLon;
  return 2 * R * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/// Distanza dal VERTICE piu' vicino del tracciato, non dal segmento fra due
/// vertici. E' una semplificazione dell'originale Dart (distanceToPolyline
/// scorre i punti, non le corde) e va replicata cosi': se qui misurassimo
/// meglio, i due calcoli non coinciderebbero piu'.
function distanzaDalTracciato(polilinea, la, ln) {
  if (!polilinea.length) return Infinity;
  let best = Infinity;
  for (const p of polilinea) {
    const d = distanzaMetri(p.lat, p.lng, la, ln);
    if (d < best) best = d;
  }
  return best;
}

function segueIlTracciato(sottoPunti, polilinea) {
  if (!sottoPunti.length || !polilinea.length) return false;
  let somma = 0, massimo = 0;
  for (const p of sottoPunti) {
    const d = distanzaDalTracciato(polilinea, p.lat, p.lng);
    somma += d;
    if (d > massimo) massimo = d;
  }
  const media = somma / sottoPunti.length;
  if (media > TOLLERANZA_MEDIA) return false;
  if (massimo > TOLLERANZA_MASSIMA) return false;
  return true;
}

/// Un solo segmento contro una traccia. Ritorna null se non e' stato
/// percorso: partenza mai avvicinata, arrivo mai raggiunto dopo la
/// partenza, percorso troppo lontano, o durata non positiva.
function confrontaSingolo(punti, seg) {
  let iPartenza = null;
  for (let i = 0; i < punti.length; i++) {
    if (distanzaMetri(punti[i].lat, punti[i].lng, seg.startLat, seg.startLng) < RAGGIO_PARTENZA) {
      iPartenza = i;
      break;
    }
  }
  if (iPartenza === null) return null;

  let iArrivo = null;
  for (let i = iPartenza + 1; i < punti.length; i++) {
    if (distanzaMetri(punti[i].lat, punti[i].lng, seg.endLat, seg.endLng) < RAGGIO_ARRIVO) {
      iArrivo = i;
      break;
    }
  }
  if (iArrivo === null) return null;

  const sotto = punti.slice(iPartenza, iArrivo + 1);
  if (!segueIlTracciato(sotto, seg.polyline)) return null;

  const durata = Math.round((punti[iArrivo].t - punti[iPartenza].t) / 1000);
  if (durata <= 0) return null;

  return {
    segmento: seg,
    iPartenza,
    iArrivo,
    durataSecondi: durata,
    velocitaMediaKmh: seg.distance > 0 ? (seg.distance / durata) * 3.6 : 0,
    quando: new Date(punti[iArrivo].t),
  };
}

/// Attivita' confrontabili fra loro. Un segmento di corsa non ha senso in
/// bici: si va molto piu' forte e ogni passaggio diventa un primato. Ma
/// corsa e trail running sulla stessa salita sono la stessa gara, e
/// camminare e' la versione lenta di correre — separarli darebbe classifiche
/// vuote. Sci ed e-bike invece stanno per conto loro.
const FAMIGLIE = [
  ['trekking', 'walking', 'running', 'trailRunning'],
  ['cycling', 'gravelBiking', 'mountainBiking'],
  ['eBike', 'eMountainBike'],
  ['skiTouring', 'alpineSkiing', 'nordicSkiing', 'snowboarding', 'snowshoeing'],
];
function attivitaCompatibili(a, b) {
  if (!a || !b) return true;          // dato mancante: non si esclude nulla
  if (a === b) return true;
  return FAMIGLIE.some((f) => f.includes(a) && f.includes(b));
}

/// Tutti i segmenti percorsi da una traccia.
/// [attivita] e' quella della traccia: i segmenti di un'altra famiglia si
/// saltano, altrimenti una pedalata entra nella classifica dei podisti.
function confronta(punti, segmenti, attivita) {
  const out = [];
  if (punti.length < 2 || !segmenti.length) return out;

  let minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
  for (const p of punti) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lng < minLng) minLng = p.lng;
    if (p.lng > maxLng) maxLng = p.lng;
  }

  for (const seg of segmenti) {
    if (!attivitaCompatibili(attivita, seg.activityType)) continue;
    if (seg.startLat < minLat - PADDING_BBOX || seg.startLat > maxLat + PADDING_BBOX) continue;
    if (seg.startLng < minLng - PADDING_BBOX || seg.startLng > maxLng + PADDING_BBOX) continue;
    const r = confrontaSingolo(punti, seg);
    if (r) out.push(r);
  }
  return out;
}

module.exports = { confronta, confrontaSingolo, distanzaMetri, attivitaCompatibili,
  RAGGIO_PARTENZA, RAGGIO_ARRIVO, TOLLERANZA_MEDIA, TOLLERANZA_MASSIMA };
