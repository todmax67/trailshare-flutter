// Sezione del terreno attorno a ogni rifugio senza foto, dal DEM europeo a
// 25 m. E' il dato su cui si disegna la copertina generata: una linea di
// cresta vera, diversa per ogni posto, invece del gradiente con l'emoji.
//
// Sezione EST-OVEST di 6 km centrata sul rifugio, 60 campioni (uno ogni
// 100 m). Est-ovest per tutti, non la direzione di massimo rilievo: la
// costanza rende le copertine confrontabili fra loro, e una scelta
// "furba" per rifugio renderebbe il disegno non riproducibile.
//
// opentopodata pubblico da 100 posizioni per chiamata, 1 al secondo, 1000
// al giorno: sono ~1.550 chiamate in tutto, quindi due giorni. Lo script
// si ferma da solo prima del tetto e riparte da dove era con --resume.
//
// Uso:
//   node scripts/business_terrain_profile.cjs --dry --limit 5
//   node scripts/business_terrain_profile.cjs [--resume] [--max-chiamate 900]
//   node scripts/business_terrain_profile.cjs --undo
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
const RESUME = argv.includes('--resume');
const LIMIT = parseInt(arg('--limit', '0'), 10) || 0;
const MAX_CHIAMATE = parseInt(arg('--max-chiamate', '900'), 10);
const TYPE = arg('--type', 'rifugio');

const CAMPIONI = 60;
const LARGHEZZA_KM = 6;
const PER_CHIAMATA = 100;

const DIR = path.join(__dirname, '..', '.photo_review');
const REGISTRO = path.join(DIR, 'terrain_profile.json');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let chiamate = 0;
async function dem(punti, tentativo = 0) {
  const url = 'https://api.opentopodata.org/v1/eudem25m?locations=' +
    punti.map((p) => `${p.lat},${p.lng}`).join('|');
  try {
    const r = await fetch(url);
    const j = await r.json();
    if (j.status !== 'OK') throw new Error(j.error || j.status);
    chiamate++;
    return j.results.map((x) => (x.elevation == null ? null : Math.round(x.elevation)));
  } catch (e) {
    if (tentativo >= 3) throw e;
    await sleep(5000 * (tentativo + 1));
    return dem(punti, tentativo + 1);
  }
}

/// Il profilo va dentro il documento business, e getNearby ne carica fino a
/// mille per volta: sessanta interi a scheda sono lo stesso errore dei punti
/// GPS annegati nei doc delle tracce, quello che ha fatto saturare la cache.
/// Quantizzo su 0-255 rispetto a min/max e impacchetto in base64: 60 byte
/// diventano 80 caratteri, e al disegno serve solo la forma normalizzata
/// piu' i due estremi in metri, che stanno gia' a parte.
function comprimi(valori, min, max) {
  const span = Math.max(1, max - min);
  const buf = Buffer.alloc(valori.length);
  valori.forEach((v, i) => {
    buf[i] = Math.max(0, Math.min(255, Math.round((v - min) / span * 255)));
  });
  return buf.toString('base64');
}

/// I 60 punti della sezione: latitudine fissa, longitudine che scorre.
/// Il fattore coseno serve perche' un grado di longitudine si accorcia
/// salendo di latitudine — senza, la sezione di un rifugio austriaco
/// sarebbe piu' stretta di quella di uno appenninico.
function sezione(lat, lng) {
  const dLng = (LARGHEZZA_KM / 2) / (111.32 * Math.cos(lat * Math.PI / 180));
  const pts = [];
  for (let i = 0; i < CAMPIONI; i++) {
    const f = (i / (CAMPIONI - 1)) * 2 - 1;
    pts.push({ lat, lng: lng + f * dLng });
  }
  return pts;
}

async function undo() {
  if (!fs.existsSync(REGISTRO)) {
    console.error('Niente da annullare: manca ' + REGISTRO);
    process.exit(1);
  }
  const ids = JSON.parse(fs.readFileSync(REGISTRO, 'utf8')).fatti || [];
  console.log(`Rimuovo il profilo da ${ids.length} schede…`);
  let ok = 0;
  for (const id of ids) {
    try {
      await db.collection('businesses').doc(id)
        .update({ terrainProfile: admin.firestore.FieldValue.delete() });
      ok++;
    } catch (e) { console.log('err', id, String(e.message).slice(0, 50)); }
  }
  console.log(`Rimossi: ${ok}/${ids.length}`);
  process.exit(0);
}

(async () => {
  if (UNDO) return undo();
  fs.mkdirSync(DIR, { recursive: true });

  const snap = await db.collection('businesses')
    .where('status', '==', 'active').where('type', '==', TYPE).get();
  const tutti = [];
  snap.forEach((d) => {
    const x = d.data(); const L = x.location || {};
    if (L.lat == null || L.lng == null) return;
    if ((x.branding || {}).heroPhotoUrl) return; // la foto vera vince sempre
    if (x.terrainProfile) return;                 // gia' fatto
    tutti.push({ id: d.id, nome: x.name, lat: L.lat, lng: L.lng, quota: L.elevation });
  });

  let fatti = [];
  if (RESUME && fs.existsSync(REGISTRO)) {
    fatti = JSON.parse(fs.readFileSync(REGISTRO, 'utf8')).fatti || [];
    console.log(`Riprendo: ${fatti.length} profili gia' scritti`);
  }
  const lista = LIMIT ? tutti.slice(0, LIMIT) : tutti;
  const chiamateStimate = Math.ceil(lista.length * CAMPIONI / PER_CHIAMATA);
  console.log(`Rifugi da profilare: ${lista.length}  →  ~${chiamateStimate} chiamate ` +
    `(tetto di questo giro: ${MAX_CHIAMATE})${DRY ? '  (SIMULAZIONE)' : ''}`);
  if (!lista.length) process.exit(0);

  // Si accodano i punti di piu' rifugi nella stessa chiamata: 100 posizioni
  // sono 1,67 rifugi, sprecarne una parte costerebbe giornate in piu'.
  let coda = [], codaOwner = [];
  const parziali = new Map();
  let scritti = 0, scartati = 0, fermato = false;

  const svuota = async () => {
    if (!coda.length) return;
    const quote = await dem(coda);
    for (let i = 0; i < coda.length; i++) {
      const o = codaOwner[i];
      if (!parziali.has(o.id)) parziali.set(o.id, { rif: o, valori: [] });
      parziali.get(o.id).valori.push(quote[i]);
    }
    coda = []; codaOwner = [];
  };

  const chiudiPronti = async () => {
    for (const [id, p] of [...parziali.entries()]) {
      if (p.valori.length < CAMPIONI) continue;
      parziali.delete(id);
      const v = p.valori;
      if (v.some((x) => x == null)) { scartati++; continue; }
      const min = Math.min(...v), max = Math.max(...v);
      if (max - min < 1) { scartati++; continue; } // pianura piatta: niente da disegnare
      if (!DRY) {
        await db.collection('businesses').doc(id).update({
          terrainProfile: {
            p: comprimi(v, min, max),
            n: v.length,
            widthKm: LARGHEZZA_KM,
            minM: min,
            maxM: max,
            source: 'eudem25m',
          },
        });
      }
      fatti.push(id);
      scritti++;
      if (scritti % 25 === 0) {
        if (!DRY) fs.writeFileSync(REGISTRO, JSON.stringify({ fatti }, null, 1));
        process.stdout.write(`${scritti} profili · ${chiamate} chiamate\n`);
      }
    }
  };

  for (const r of lista) {
    if (chiamate >= MAX_CHIAMATE) { fermato = true; break; }
    for (const p of sezione(r.lat, r.lng)) {
      coda.push(p); codaOwner.push(r);
      if (coda.length === PER_CHIAMATA) {
        await svuota();
        await chiudiPronti();
        await sleep(1200);
        if (chiamate >= MAX_CHIAMATE) { fermato = true; break; }
      }
    }
    if (fermato) break;
  }
  if (!fermato && coda.length) { await svuota(); await chiudiPronti(); }

  if (!DRY && fatti.length) fs.writeFileSync(REGISTRO, JSON.stringify({ fatti }, null, 1));

  console.log(`\n=== PROFILI ${DRY ? '(SIMULAZIONE)' : ''} ===`);
  console.log(`scritti in questo giro: ${scritti} | scartati: ${scartati} | chiamate: ${chiamate}`);
  // `tutti` sono i rifugi che a inizio giro il profilo NON ce l'avevano, quindi
  // e' gia' il totale da fare: sommarci `fatti` conterebbe due volte i propri.
  console.log(`profilati in tutto: ${fatti.length} | ne restano ${tutti.length - scritti}`);
  if (fermato) {
    console.log(`\nFermato al tetto di ${MAX_CHIAMATE} chiamate per non sbattere contro il ` +
      `limite giornaliero. Domani:\n  node scripts/business_terrain_profile.cjs --resume`);
  }
  process.exit(0);
})().catch((e) => { console.error('ERR', e); process.exit(1); });
