// Quota mancante ai rifugi, ricavata dal DEM europeo a 25 m (opentopodata,
// dataset eudem25m). Primo passo della copertina generata: senza altitudine
// la card resta muta per quasi meta' delle schede.
//
// Attendibilita' misurata su 297 rifugi che la quota ce l'avevano gia' da OSM:
// scarto mediano 9 m, 92% entro 30 m, nessun punto scoperto (Croazia inclusa).
// Gli scarti oltre i 100 m sono rifugi su parete, che un raster a 25 m smussa.
//
// Scrive location.elevation SOLO dove manca — non ritocca mai un valore OSM —
// e marca la provenienza in location.elevationSource.
//
// Uso:
//   node scripts/business_elevation_backfill.cjs --dry
//   node scripts/business_elevation_backfill.cjs [--type rifugio] [--limit 200]
//   node scripts/business_elevation_backfill.cjs --undo
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const fs = require('fs');
const path = require('path');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const arg = (n, d = null) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
};
const DRY = argv.includes('--dry');
const UNDO = argv.includes('--undo');
const TYPE = arg('--type', 'rifugio');
const LIMIT = parseInt(arg('--limit', '0'), 10) || 0;

const DIR = path.join(__dirname, '..', '.photo_review');
const REGISTRO = path.join(DIR, 'elevation_backfill.json');

// opentopodata pubblico: 100 posizioni per chiamata, 1 chiamata al secondo,
// 1000 al giorno. 1.400 rifugi stanno in 14 chiamate.
const PER_CHIAMATA = 100;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function dem(punti, tentativo = 0) {
  const url = 'https://api.opentopodata.org/v1/eudem25m?locations=' +
    punti.map((p) => `${p.lat},${p.lng}`).join('|');
  try {
    const r = await fetch(url);
    const j = await r.json();
    if (j.status !== 'OK') throw new Error(j.error || j.status);
    return j.results.map((x) => (x.elevation == null ? null : Math.round(x.elevation)));
  } catch (e) {
    if (tentativo >= 3) throw e;
    await sleep(4000 * (tentativo + 1));
    return dem(punti, tentativo + 1);
  }
}

async function undo() {
  if (!fs.existsSync(REGISTRO)) {
    console.error('Niente da annullare: manca ' + REGISTRO);
    process.exit(1);
  }
  const r = JSON.parse(fs.readFileSync(REGISTRO, 'utf8')).scritte || [];
  console.log(`Rimuovo la quota da ${r.length} schede…`);
  let ok = 0;
  for (const x of r) {
    try {
      await db.collection('businesses').doc(x.id).update({
        'location.elevation': admin.firestore.FieldValue.delete(),
        'location.elevationSource': admin.firestore.FieldValue.delete(),
      });
      ok++;
    } catch (e) { console.log('err', x.nome, String(e.message).slice(0, 50)); }
  }
  console.log(`Rimosse: ${ok}/${r.length}`);
  process.exit(0);
}

(async () => {
  if (UNDO) return undo();
  fs.mkdirSync(DIR, { recursive: true });

  const snap = await db.collection('businesses')
    .where('status', '==', 'active').where('type', '==', TYPE).get();
  const mancanti = [];
  snap.forEach((d) => {
    const x = d.data(); const L = x.location || {};
    if (L.lat == null || L.lng == null) return;
    if (L.elevation != null) return;
    mancanti.push({ id: d.id, nome: x.name, lat: L.lat, lng: L.lng, paese: L.country || 'IT' });
  });
  const lista = LIMIT ? mancanti.slice(0, LIMIT) : mancanti;
  console.log(`Rifugi senza quota: ${mancanti.length}` +
    (LIMIT ? ` — ne faccio ${lista.length}` : '') +
    `  →  ${Math.ceil(lista.length / PER_CHIAMATA)} chiamate${DRY ? '  (SIMULAZIONE)' : ''}`);
  if (!lista.length) process.exit(0);

  const scritte = [];
  let vuoti = 0, errori = 0;
  const perPaese = {};

  for (let i = 0; i < lista.length; i += PER_CHIAMATA) {
    const chunk = lista.slice(i, i + PER_CHIAMATA);
    let quote;
    try {
      quote = await dem(chunk);
    } catch (e) {
      errori += chunk.length;
      console.log(`  errore sul blocco ${i / PER_CHIAMATA + 1}: ${String(e.message).slice(0, 60)}`);
      await sleep(1200);
      continue;
    }
    for (let k = 0; k < chunk.length; k++) {
      const q = quote[k];
      if (q == null) { vuoti++; continue; }
      // Quote assurde: il DEM restituisce anche fondali e valori sotto zero
      // dove il raster non ha dati veri.
      if (q < -50 || q > 5000) { vuoti++; continue; }
      if (!DRY) {
        await db.collection('businesses').doc(chunk[k].id).update({
          'location.elevation': q,
          'location.elevationSource': 'eudem25m',
        });
      }
      scritte.push({ id: chunk[k].id, nome: chunk[k].nome, quota: q });
      perPaese[chunk[k].paese] = (perPaese[chunk[k].paese] || 0) + 1;
    }
    process.stdout.write(`${Math.min(i + PER_CHIAMATA, lista.length)}/${lista.length} `);
    await sleep(1200);
  }

  if (!DRY && scritte.length) {
    fs.writeFileSync(REGISTRO, JSON.stringify({
      scrittoIl: new Date().toISOString(), scritte,
    }, null, 1));
  }

  const q = scritte.map((x) => x.quota).sort((a, b) => a - b);
  console.log(`\n\n=== QUOTE ${DRY ? '(SIMULAZIONE)' : ''} ===`);
  console.log(`ricavate: ${scritte.length} | senza dato: ${vuoti} | errori: ${errori}`);
  if (q.length) {
    console.log(`quote — min ${q[0]} | mediana ${q[Math.floor(q.length / 2)]} | max ${q[q.length - 1]}`);
    console.log('per paese: ' + JSON.stringify(perPaese));
  }
  if (!DRY && scritte.length) {
    console.log(`\nPer tornare indietro:  node scripts/business_elevation_backfill.cjs --undo`);
  }
  process.exit(0);
})().catch((e) => { console.error('ERR', e); process.exit(1); });
