// Backfill delle quote nelle geometrie del catalogo.
//
// PROBLEMA: 421 doc in `public_trail_geometries` hanno `coordinatesJson` con
// tutte le quote a 0. Causa: trail_import_service.fetchElevations() riempie di
// `0.0` in silenzio quando OpenTopoData risponde male (righe 210/213), e un
// batch di import di dic-2025/gen-2026 e' finito cosi'. Gli aggregati sul doc
// index sono corretti perche' una passata successiva li ha ricalcolati, ma la
// geometria non e' mai stata riscritta: il grafico altimetrico e' impossibile.
//
// SOGGETTI: solo i doc con TUTTE le quote a zero. Chi ha almeno una quota vera
// non viene toccato.
//
// SORGENTE: tile SRTM .hgt 1-arcsec (~30 m) in locale (nessun limite di rate,
// a differenza dell'API OpenTopoData: 1000 richieste/giorno).
//
// Tre fasi separate, ognuna ispezionabile e ripartibile: il campionamento e'
// la parte lenta e non va rifatta se la scrittura fallisce.
//
//   node scripts/backfill_trail_elevations.cjs export   -> estrae le coordinate
//   python3 scripts/dem_sample_batch.py <in> <out>      -> campiona le quote
//   node scripts/backfill_trail_elevations.cjs apply    -> scrive (o --dry-run)
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const sa = require(path.join(__dirname, '../functions/serviceAccountKey.json'));

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const CMD = process.argv[2] || 'export';
const DRY = process.argv.includes('--dry-run');
const WORK = process.env.BACKFILL_DIR || '/tmp/trailshare_backfill';
const F_COORDS = path.join(WORK, 'coords.json');
const F_META = path.join(WORK, 'meta.json');
const F_ELES = path.join(WORK, 'elevations.json');

/// Stessa isteresi di trail_import_service.calculateElevationStats: ignora le
/// variazioni sotto i 3 m, altrimenti il rumore del DEM gonfia il dislivello.
function statistiche(eles) {
  let gain = 0, loss = 0, min = eles[0], max = eles[0];
  for (let i = 1; i < eles.length; i++) {
    const d = eles[i] - eles[i - 1];
    if (d > 3) gain += d; else if (d < -3) loss += Math.abs(d);
    if (eles[i] < min) min = eles[i];
    if (eles[i] > max) max = eles[i];
  }
  return { gain: Math.round(gain), loss: Math.round(loss), min: Math.round(min), max: Math.round(max) };
}

async function esporta() {
  fs.mkdirSync(WORK, { recursive: true });
  console.log('Scansione di public_trail_geometries...');
  const snap = await db.collection('public_trail_geometries').get();
  const coords = {}, meta = {};
  snap.forEach(d => {
    const cj = d.data().coordinatesJson;
    if (typeof cj !== 'string' || !cj) return;
    let arr;
    try { arr = JSON.parse(cj); } catch { return; }
    if (!Array.isArray(arr) || arr.length < 2) return;
    if (arr.some(c => Array.isArray(c) && c.length > 2 && c[2] !== 0)) return; // ha già quote
    coords[d.id] = arr.map(c => [c[0], c[1]]);
    meta[d.id] = { n: arr.length };
  });
  fs.writeFileSync(F_COORDS, JSON.stringify(coords));
  fs.writeFileSync(F_META, JSON.stringify(meta));
  const tot = Object.values(coords).reduce((a, v) => a + v.length, 0);
  console.log(`Geometrie con tutte le quote a zero: ${Object.keys(coords).length}`);
  console.log(`Punti da campionare: ${tot.toLocaleString()}`);
  console.log(`\nScritto ${F_COORDS}`);
  console.log(`Ora esegui:\n  python3 ${path.join(__dirname, 'dem_sample_batch.py')} ${F_COORDS} ${F_ELES}`);
}

async function applica() {
  if (!fs.existsSync(F_ELES)) {
    console.error(`Manca ${F_ELES}: esegui prima export e poi dem_sample_batch.py`);
    process.exit(1);
  }
  const coords = JSON.parse(fs.readFileSync(F_COORDS, 'utf8'));
  const eles = JSON.parse(fs.readFileSync(F_ELES, 'utf8'));
  console.log(DRY ? 'dry-run: nessuna scrittura' : '*** APPLY: scrive su Firestore ***');

  let scritti = 0, saltatiCopertura = 0, saltatiSize = 0, errori = 0, ridottaPrecisione = 0;
  const esempi = [];
  for (const [id, ll] of Object.entries(coords)) {
    const q = eles[id];
    if (!Array.isArray(q) || q.length !== ll.length) { saltatiCopertura++; continue; }

    const validi = q.filter(e => e !== null).length;
    const copertura = validi / q.length;
    // Sotto l'80% il profilo avrebbe buchi grossi: meglio lasciare il doc
    // invariato e riprenderlo quando ci sono i tile mancanti.
    if (copertura < 0.8) { saltatiCopertura++; continue; }

    // i pochi null residui: interpola dai vicini validi
    const e2 = q.slice();
    for (let i = 0; i < e2.length; i++) {
      if (e2[i] !== null) continue;
      let a = i - 1; while (a >= 0 && e2[a] === null) a--;
      let b = i + 1; while (b < e2.length && e2[b] === null) b++;
      e2[i] = a >= 0 && b < e2.length ? (e2[a] + e2[b]) / 2
            : a >= 0 ? e2[a] : b < e2.length ? e2[b] : 0;
    }

    let nuove = ll.map((c, i) => [c[0], c[1], Math.round(e2[i] * 10) / 10]);
    let json = JSON.stringify(nuove);
    // Aggiungere le quote allunga il JSON e i tracciati lunghi sfondano il
    // limite di 1 MB per documento. Prima di decimare — che butterebbe via
    // geometria — si riduce la precisione delle coordinate: quelle salvate
    // hanno 15 decimali (~1 femtometro), 6 bastano per ~11 cm, molto piu'
    // fine della griglia DEM da 30 m. Dimezza il JSON senza perdere un punto.
    if (json.length > 900 * 1024) {
      nuove = nuove.map(c => [+c[0].toFixed(6), +c[1].toFixed(6), c[2]]);
      json = JSON.stringify(nuove);
      if (json.length <= 900 * 1024) {
        ridottaPrecisione++;
      } else {
        saltatiSize++;
        continue;
      }
    }

    const st = statistiche(e2);
    try {
      if (!DRY) {
        await db.collection('public_trail_geometries').doc(id).update({
          coordinatesJson: json,
          elevationBackfilledAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        // NB: si aggiornano solo min/maxAltitude, NON elevationGain/Loss.
        //
        // min/max sono verificati: coincidono con quelli già sul doc entro
        // ~10 m (es. 88 vs 99, 1790 vs 1782), quindi il DEM è affidabile.
        //
        // Il D+ no. calculateElevationStats() confronta solo punti ADIACENTI e
        // scarta i passi sotto i 3 m invece di accumularli: con campionamento
        // denso (qui 13 m fra punti) una salita costante di 2 m per passo
        // conta zero. Il risultato dipende dalla densità, non dal terreno —
        // ricalcolandolo qui verrebbe 0,67x quello esistente, e questi 183
        // sarebbero incoerenti col resto del catalogo. Serve prima decidere
        // una formula a riferimento mobile per TUTTI i 16.321.
        await db.collection('public_trails').doc(id).update({
          minAltitude: st.min,
          maxAltitude: st.max,
          elevationBackfilledAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      scritti++;
      if (esempi.length < 12) esempi.push({ id, n: nuove.length, ...st, cop: copertura });
      if (scritti % 50 === 0) console.log(`  ...${scritti} sistemati`);
    } catch (e) {
      errori++;
      console.log(`  ${id}: ERRORE ${e.message}`);
    }
  }

  console.log('\nEsempi:');
  console.log('id                            punti    D+    D-   min   max  copertura');
  esempi.forEach(e => console.log(
    `${e.id.padEnd(28)} ${String(e.n).padStart(6)} ${String(e.gain).padStart(5)} ${String(e.loss).padStart(5)} ${String(e.min).padStart(5)} ${String(e.max).padStart(5)}  ${(e.cop*100).toFixed(0)}%`));

  console.log(`\n=== RIEPILOGO ===`);
  console.log(`${DRY ? 'da scrivere' : 'scritti'}:              ${scritti}`);
  console.log(`saltati (copertura DEM):  ${saltatiCopertura}`);
  console.log(`con precisione ridotta:   ${ridottaPrecisione}`);
  console.log(`saltati (doc >900KB):     ${saltatiSize}`);
  console.log(`errori:                   ${errori}`);
  if (DRY) console.log(`\nNiente scritto. Rilancia senza --dry-run.`);
}

(async () => {
  if (CMD === 'export') await esporta();
  else if (CMD === 'apply') await applica();
  else { console.error(`Comando sconosciuto: ${CMD} (usa export | apply)`); process.exit(1); }
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
