// Inverte il verso di una traccia del catalogo quando la geometria va nella
// direzione opposta al suo `from -> to` dichiarato.
//
// PROBLEMA: alcune relazioni OSM hanno i way membri in ordine invertito
// rispetto ai tag from/to. L'importer li concatena nell'ordine dato, quindi la
// geometria "scende" dove la scheda dice che sale. Effetti: profilo altimetrico
// a rovescio, D+ e D- scambiati, navigazione "segui la traccia" che parte dal
// capo sbagliato.
//
// IDEMPOTENTE: prima di toccare qualcosa confronta i due capi della geometria
// con le coordinate di from/to; se il verso è già giusto non fa nulla. Si può
// rilanciare senza rischio di doppia inversione.
//
// Uso:
//   node scripts/fix_trail_direction.cjs <trailId> [<trailId>...] [--apply]
const admin = require('firebase-admin');
const path = require('path');
const sa = require(path.join(__dirname, '../functions/serviceAccountKey.json'));

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');
const IDS = process.argv.slice(2).filter(a => !a.startsWith('--'));

/// Ancore geografiche dei capolinea. Servono per decidere il verso senza
/// fidarsi delle quote (che su un anello non bastano). Chiave = valore esatto
/// dei campi `from`/`to` sul doc.
const ANCORE = {
  'Riva del Garda':        [10.841, 45.886],
  'Rifugio Nino Pernici':  [10.769, 45.927],
  'Malga Stabio':          [10.778, 46.018],
  'Stenico':               [10.855, 46.053],
  'Rifugio Al Cacciatore': [10.881, 46.130],
  'Comano Terme':          [10.869, 46.028],
  'Rifugio San Pietro':    [10.839, 45.933],
  'Varone':                [10.833, 45.897],
};

function hav(a, b) {
  const R = 6371000, r = x => x * Math.PI / 180;
  const dLat = r(b[1] - a[1]), dLon = r(b[0] - a[0]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(r(a[1])) * Math.cos(r(b[1])) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

(async () => {
  if (!IDS.length) { console.error('Serve almeno un trailId'); process.exit(1); }
  console.log(APPLY ? '*** APPLY: scrive su Firestore ***' : 'dry-run (nessuna scrittura)');

  for (const id of IDS) {
    console.log(`\n─── ${id} ───`);
    const tSnap = await db.collection('public_trails').doc(id).get();
    const gSnap = await db.collection('public_trail_geometries').doc(id).get();
    if (!tSnap.exists || !gSnap.exists) { console.log('  doc mancante, salto'); continue; }
    const t = tSnap.data(), g = gSnap.data();

    const arr = JSON.parse(g.coordinatesJson);
    const n = arr.length;
    const p0 = arr[0], pN = arr[n - 1];
    const aFrom = ANCORE[t.from], aTo = ANCORE[t.to];
    if (!aFrom || !aTo) {
      console.log(`  ancora mancante per "${t.from}" / "${t.to}" — aggiungila ad ANCORE`);
      continue;
    }
    const errDritto = hav(p0, aFrom) + hav(pN, aTo);
    const errInvers = hav(p0, aTo) + hav(pN, aFrom);
    console.log(`  ${t.from} -> ${t.to}`);
    console.log(`  errore capi: dritto ${(errDritto/1000).toFixed(2)}km | invertito ${(errInvers/1000).toFixed(2)}km`);
    if (errInvers >= errDritto) { console.log('  verso già corretto, non tocco nulla'); continue; }

    // 1) coordinate: semplice reverse (ogni punto resta [lon, lat, quota])
    const nuoveCoord = arr.slice().reverse();

    // 2) terrainSegments: gli indici puntano a posizioni nell'array, quindi
    //    vanno rimappati oltre che riordinati. [a,b] -> [(n-1)-b, (n-1)-a]
    const seg = Array.isArray(g.terrainSegments) ? g.terrainSegments : [];
    const nuoviSeg = seg
      .map(s => ({ ...s, startIdx: (n - 1) - s.endIdx, endIdx: (n - 1) - s.startIdx }))
      .sort((a, b) => a.startIdx - b.startIdx);

    // 3) simplifiedPoints: reverse (sono {lng, lat}, nessun indice dentro)
    const sp = Array.isArray(t.simplifiedPoints) ? t.simplifiedPoints.slice().reverse() : null;

    console.log(`  coordinate: ${n} punti, quota ${Math.round(p0[2])}m -> ${Math.round(pN[2])}m  diventa  ${Math.round(pN[2])}m -> ${Math.round(p0[2])}m`);
    console.log(`  terrainSegments: ${seg.length} rimappati (primo ${JSON.stringify(seg[0])} -> ${JSON.stringify(nuoviSeg[0])})`);
    console.log(`  D+/D- ${Math.round(t.elevationGain)}/${Math.round(t.elevationLoss)} -> ${Math.round(t.elevationLoss)}/${Math.round(t.elevationGain)}  (si scambiano)`);
    console.log(`  startPoint/endPoint: si scambiano`);

    const json = JSON.stringify(nuoveCoord);
    if (json.length > 900 * 1024) { console.log('  JSON troppo grande, salto'); continue; }

    if (APPLY) {
      await db.collection('public_trail_geometries').doc(id).update({
        coordinatesJson: json,
        ...(nuoviSeg.length ? { terrainSegments: nuoviSeg } : {}),
        directionFixedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await db.collection('public_trails').doc(id).update({
        // from/to NON si toccano: sono corretti, è la geometria che li seguiva
        // al contrario. Qui allineiamo tutto il resto a loro.
        startPoint: t.endPoint,
        endPoint: t.startPoint,
        elevationGain: t.elevationLoss ?? 0,
        elevationLoss: t.elevationGain ?? 0,
        ...(sp ? { simplifiedPoints: sp } : {}),
        directionFixedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log('  ✔ invertita');
    } else {
      console.log('  (dry-run, non scritto)');
    }
  }
  if (!APPLY) console.log('\nNiente scritto. Rilancia con --apply.');
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
