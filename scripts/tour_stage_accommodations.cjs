// Rifugi dove dormire a fine tappa, proposti per i tour esistenti.
//
// `stageAccommodations` (trackId -> businessId) e' il campo che dice in quale
// rifugio si pernotta alla fine di ogni tappa. E' vuoto su tutti e sei i tour,
// mentre e' la cosa che uno cerca per prima quando pianifica un cammino di
// otto giorni — e i rifugi ce li abbiamo, 4.318 con le coordinate.
//
// Il criterio e' il PUNTO DI ARRIVO della tappa, non il percorso: a meta'
// strada un rifugio e' una sosta, alla fine e' il posto dove si dorme. Per
// l'ultima tappa la proposta ha meno senso (di solito si scende a valle), ma
// si mostra lo stesso e decide chi cura il tour.
//
// NON SCRIVE NIENTE di default: propone e basta. L'accostamento tappa-rifugio
// e' una scelta editoriale — il rifugio piu' vicino puo' essere chiuso,
// privato o irraggiungibile — e va confermata da chi il tour lo firma.
//
// Uso:
//   node scripts/tour_stage_accommodations.cjs
//   node scripts/tour_stage_accommodations.cjs --raggio 4
//   node scripts/tour_stage_accommodations.cjs --scrivi     (solo i primi in classifica)
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 ? argv[i + 1] : d; };
const RAGGIO_KM = Number(opt('raggio', 3));
const SCRIVI = argv.includes('--scrivi');

function km(lat1, lon1, lat2, lon2) {
  const R = 6371, r = (x) => x * Math.PI / 180;
  const dLat = r(lat2 - lat1), dLon = r(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/// Ultimo punto valido della traccia: e' li' che finisce la tappa.
///
/// I punti GPS non stanno piu' nel documento traccia: sono stati spostati in
/// una sottocollezione `geometry/data` come stringa JSON, perche' inline
/// facevano saturare la cache di Firestore. Le tracce migrate portano
/// `hasGeometryDoc: true`; le piu' vecchie hanno ancora `points` inline, e
/// vanno lette lo stesso.
async function puntiDi(ref, t) {
  if (Array.isArray(t.points) && t.points.length) return t.points;
  try {
    const g = await ref.collection('geometry').doc('data').get();
    if (!g.exists) return [];
    const raw = g.data().pointsJson;
    return typeof raw === 'string' ? JSON.parse(raw) : (raw || []);
  } catch (e) {
    return [];
  }
}

function arrivo(pts) {
  pts = Array.isArray(pts) ? pts : [];
  for (let i = pts.length - 1; i >= 0; i--) {
    const p = pts[i];
    const la = p?.latitude ?? p?.lat ?? (Array.isArray(p) ? p[0] : null);
    const ln = p?.longitude ?? p?.lng ?? p?.lon ?? (Array.isArray(p) ? p[1] : null);
    if (Number.isFinite(Number(la)) && Number.isFinite(Number(ln))) {
      return [Number(la), Number(ln)];
    }
  }
  return null;
}

(async () => {
  // Rifugi con coordinate, caricati una volta sola.
  const bSnap = await db.collection('businesses').where('type', '==', 'rifugio').get();
  const rifugi = [];
  bSnap.forEach((d) => {
    const x = d.data(), L = x.location || {};
    const la = L.latitude ?? L.lat, ln = L.longitude ?? L.lng;
    if (la == null || ln == null) return;
    rifugi.push({ id: d.id, nome: x.name, lat: Number(la), lng: Number(ln),
      quota: L.elevation, rivendicato: !!x.claimedBy });
  });
  console.log(`rifugi in banca dati con coordinate: ${rifugi.length}\n`);

  const tSnap = await db.collection('community_tours').get();
  const daScrivere = [];
  let tappeTot = 0, conProposta = 0, senzaNulla = 0;

  for (const doc of tSnap.docs) {
    const tour = doc.data();
    const ids = tour.trackIds || [];
    if (!ids.length) continue;
    const gia = tour.stageAccommodations || {};

    console.log('═'.repeat(74));
    console.log(`${tour.title}   (${ids.length} tappe, autore ${tour.ownerName || '—'})`);
    console.log('═'.repeat(74));

    const mappa = { ...gia };
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i];
      tappeTot++;
      let track = null;
      try {
        const s = await db.collection('users').doc(tour.ownerId)
          .collection('tracks').doc(id).get();
        if (s.exists) track = s.data();
      } catch (e) { /* traccia non leggibile: si segnala sotto */ }

      const etichetta = `  tappa ${String(i + 1).padStart(2)}/${ids.length}`;
      if (!track) { console.log(`${etichetta}  (traccia non trovata: ${id})`); continue; }
      const fine = arrivo(await puntiDi(
        db.collection('users').doc(tour.ownerId).collection('tracks').doc(id), track));
      if (!fine) { console.log(`${etichetta}  ${String(track.name || '').slice(0, 34)} — senza coordinate`); continue; }

      const vicini = rifugi
        .map((r) => ({ ...r, d: km(fine[0], fine[1], r.lat, r.lng) }))
        .filter((r) => r.d <= RAGGIO_KM)
        .sort((a, b) => a.d - b.d)
        .slice(0, 3);

      const nome = String(track.name || '(senza nome)').slice(0, 34).padEnd(36);
      if (!vicini.length) {
        senzaNulla++;
        console.log(`${etichetta}  ${nome} nessun rifugio entro ${RAGGIO_KM} km`);
        continue;
      }
      conProposta++;
      const gia1 = gia[id];
      console.log(`${etichetta}  ${nome}${gia1 ? '[gia\' assegnato]' : ''}`);
      vicini.forEach((r, k) => console.log(
        `        ${k === 0 ? '→' : ' '} ${r.nome.slice(0, 38).padEnd(40)} ${r.d.toFixed(1).padStart(5)} km` +
        `${r.quota ? '  ' + Math.round(r.quota) + ' m' : ''}${r.rivendicato ? '  [rivendicato]' : ''}`));
      if (!gia1) mappa[id] = vicini[0].id;
    }
    console.log();
    if (Object.keys(mappa).length > Object.keys(gia).length) {
      daScrivere.push({ ref: doc.ref, titolo: tour.title, mappa });
    }
  }

  console.log('═'.repeat(74));
  console.log(`tappe esaminate:            ${tappeTot}`);
  console.log(`con almeno una proposta:    ${conProposta}`);
  console.log(`senza rifugi entro ${RAGGIO_KM} km:   ${senzaNulla}`);
  console.log(`tour con proposte da salvare: ${daScrivere.length}`);

  if (!SCRIVI) {
    console.log('\nNessuna scrittura: sono proposte. Per salvare i primi in classifica,');
    console.log('rilanciare con --scrivi (le assegnazioni gia\' esistenti non si toccano).');
    process.exit(0);
  }
  for (const w of daScrivere) {
    await w.ref.update({ stageAccommodations: w.mappa });
    console.log(`  salvato: ${w.titolo}`);
  }
  console.log(`\nFatto: ${daScrivere.length} tour con gli alloggi di tappa.`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
