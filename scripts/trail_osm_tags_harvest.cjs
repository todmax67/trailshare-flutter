// Raccolta dei tag OSM a livello di WAY per tutto il catalogo — SOLA LETTURA.
//
// `sac_scale` e i tag di via ferrata stanno sulle singole way, non sulla
// relazione del percorso: all'import leggiamo solo quella della relazione, e
// per questo la difficolta' tecnica vera copre l'1% del catalogo mentre il
// resto e' la stima di _estimateDifficulty. La sonda su 1000 sentieri ha
// misurato il 60% di copertura possibile e 13 vie ferrate che il nome non
// dichiara (stima: ~200 sull'intero catalogo).
//
// Questo script NON scrive su Firestore. Scarica, incrocia e SALVA SU FILE,
// perche' una passata da tre quarti d'ora non si ripete per sfizio: il
// raccolto va riletto quante volte serve senza reinterrogare Overpass, che
// e' un servizio pubblico gratuito.
//
// Riprendibile: se il file esiste, riparte da dove era arrivato.
//
// Uso:
//   node scripts/trail_osm_tags_harvest.cjs
//   node scripts/trail_osm_tags_harvest.cjs --solo-rapporto   (nessuna rete)
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const fs = require('fs');
const path = require('path');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const UA = { 'User-Agent': 'TrailShare-enrichment/1.0 (info@trailshare.app)' };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 ? argv[i + 1] : d; };
const LOTTO = Number(opt('lotto', 50));
const PAUSA = Number(opt('pausa', 5000));
const SOLO_RAPPORTO = argv.includes('--solo-rapporto');
const RACCOLTO = path.join(__dirname, '..', '.photo_review', 'osm_way_tags.json');

const NOMI_FERRATA = /\b(ferrata|ferrate|klettersteig|sentiero attrezzato|via attrezzata|sentiero alpinistico attrezzato)/i;

const SAC = [
  ['hiking', 't'], ['mountain_hiking', 'e'], ['demanding_mountain_hiking', 'ee'],
  ['alpine_hiking', 'eea'], ['demanding_alpine_hiking', 'eea'], ['difficult_alpine_hiking', 'eea'],
];
const rangoSac = (v) => SAC.findIndex(([k]) => k === v);

/// I tre vocabolari che convivono nel campo difficulty, su una scala sola.
const RANGO_NOSTRO = {
  t: 0, turistico: 0, facile: 0,
  e: 1, escursionistico: 1, media: 1, medio: 1,
  ee: 2, difficile: 2,
  eea: 3, alpinistico: 3,
};
const RANGO_CAI = { t: 0, e: 1, ee: 2, eea: 3 };

/// 429 = ci hanno chiesto di smetterla. Ritentare a raffica alternando gli
/// endpoint — come faceva la prima versione — insiste proprio quando
/// bisognerebbe desistere, e per giunta in silenzio: il processo sembrava
/// bloccato mentre stava rimbalzando contro il limite. Ora l'attesa
/// raddoppia a ogni rifiuto e dopo tre si ferma tutto, dicendolo.
class TroppeRichieste extends Error {}

async function overpass(q) {
  const eps = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];
  let last, rifiuti = 0;
  for (let a = 0; a < 6; a++) {
    try {
      const r = await fetch(eps[a % 2], {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...UA },
        body: 'data=' + encodeURIComponent(q),
      });
      if (r.ok) return r.json();
      if (r.status === 429 || r.status === 504) {
        rifiuti++;
        if (rifiuti >= 3) throw new TroppeRichieste(`Overpass ci sta limitando (HTTP ${r.status})`);
        const attesa = 60000 * Math.pow(2, rifiuti - 1); // 60s, 120s
        console.log(`\n  HTTP ${r.status}: aspetto ${attesa / 1000}s prima di riprovare`);
        await sleep(attesa);
        continue;
      }
      last = new Error('HTTP ' + r.status);
    } catch (e) {
      if (e instanceof TroppeRichieste) throw e;
      last = e;
    }
    await sleep(12000);
  }
  throw last;
}

function caricaRaccolto() {
  if (!fs.existsSync(RACCOLTO)) return {};
  try { return JSON.parse(fs.readFileSync(RACCOLTO, 'utf8')); }
  catch (e) { console.log('raccolto illeggibile, riparto da zero: ' + e.message); return {}; }
}

(async () => {
  const snap = await db.collection('public_trails').get();
  const trails = [];
  snap.forEach((d) => {
    const x = d.data();
    if (!x.osmId) return;
    trails.push({ id: d.id, osmId: String(x.osmId), name: String(x.name || ''),
      difficulty: x.difficulty, km: (x.distance || 0) / 1000 });
  });

  const raccolto = caricaRaccolto();
  // Dal piu' corto al piu' lungo. Il costo della query lo fa il SERVER
  // caricando le way membro: un lotto di percorsi brevi si chiude in un
  // secondo, uno che contiene una traversata da migliaia di segmenti ne
  // prende ottanta. E le vie ferrate — il motivo per cui stiamo facendo
  // tutto questo — sono corte. Cosi' il valore arriva subito e la coda
  // costosa resta in fondo, dove ci si puo' anche fermare.
  const daFare = (SOLO_RAPPORTO ? [] : trails.filter((t) => !raccolto[t.osmId]))
    .sort((a, b) => a.km - b.km);
  console.log(`sentieri con osmId: ${trails.length}`);
  console.log(`gia' raccolti:      ${Object.keys(raccolto).length}`);
  console.log(`da scaricare:       ${daFare.length}` +
    (daFare.length ? `  (~${Math.ceil(daFare.length / LOTTO)} query, ~${Math.ceil(daFare.length / LOTTO * 10 / 60)} minuti)` : ''));

  for (let i = 0; i < daFare.length; i += LOTTO) {
    const chunk = daFare.slice(i, i + LOTTO);
    const ids = chunk.map((t) => t.osmId).join(',');
    let j;
    try {
      // Le way si filtrano SUL SERVER. La prima versione faceva
      // `way(r);out tags;` — tutte le way membro con tutti i loro tag — e su
      // un lotto contenente una traversata da migliaia di segmenti erano
      // decine di megabyte per poi scartarne il 99%: 250 relazioni in 16
      // minuti, cioe' 17 ore per il catalogo. Chiedendo solo le way che
      // portano davvero i tag che ci servono, il traffico crolla.
      j = await overpass(`[out:json][timeout:180];rel(id:${ids});out body;`
        + `(way(r)[sac_scale];way(r)[highway=via_ferrata];`
        + `way(r)[via_ferrata_scale];way(r)["climbing"="via_ferrata"];);out tags;`);
    } catch (e) {
      if (e instanceof TroppeRichieste) {
        console.log(`\n\nMI FERMO: ${e.message}.`);
        console.log(`Raccolte finora ${Object.keys(raccolto).length} relazioni, salvate su file.`);
        console.log('Riprendere piu\' tardi: lo script riparte da dove si e\' fermato.');
        break;
      }
      console.log(`\nlotto fallito dopo i tentativi (${e.message}); lo salto, il raccolto e' salvo`);
      continue;
    }

    const tagWay = {}, membri = {};
    for (const el of j.elements || []) {
      if (el.type === 'way') tagWay[el.id] = el.tags || {};
      else if (el.type === 'relation') {
        membri[String(el.id)] = (el.members || []).filter((m) => m.type === 'way').map((m) => m.ref);
      }
    }
    for (const t of chunk) {
      const ways = membri[t.osmId] || [];
      let peggiorSac = -1, ferrata = 0, conSac = 0;
      for (const w of ways) {
        const tg = tagWay[w];
        if (!tg) continue;
        if (tg.highway === 'via_ferrata' || tg.via_ferrata_scale || tg.climbing === 'via_ferrata') ferrata++;
        const s = tg.sac_scale && String(tg.sac_scale).toLowerCase();
        if (s) { conSac++; const r = rangoSac(s); if (r > peggiorSac) peggiorSac = r; }
      }
      raccolto[t.osmId] = {
        ways: ways.length,          // 0 = la relazione non esiste piu' o non ha way
        conSac,                     // quante way portano sac_scale
        wayFerrata: ferrata,        // quante way sono attrezzate
        sac: peggiorSac >= 0 ? SAC[peggiorSac][0] : null,
      };
    }
    fs.writeFileSync(RACCOLTO, JSON.stringify(raccolto));
    process.stdout.write(`${Math.min(i + LOTTO, daFare.length)}/${daFare.length} `);
    // Con la query filtrata siamo a ~100 KB e meno di un secondo a lotto:
    // la pausa non serve piu' a smaltire carico nostro, solo a non stare
    // addosso a un servizio pubblico gratuito.
    await sleep(PAUSA);
  }
  if (daFare.length) console.log(`\n\nraccolto salvato in ${path.relative(process.cwd(), RACCOLTO)}`);

  // ── rapporto ─────────────────────────────────────────────────────────
  let senzaWay = 0, conSac = 0, ferrate = 0, nascoste = 0, nonRaccolti = 0;
  const distr = {};
  let sotto = 0, sopra = 0, uguali = 0, senzaNostra = 0;
  const gravi = [], elencoNascoste = [];

  for (const t of trails) {
    const r = raccolto[t.osmId];
    if (!r) { nonRaccolti++; continue; }
    if (!r.ways) { senzaWay++; continue; }

    if (r.wayFerrata > 0) {
      ferrate++;
      const soloUnTratto = r.wayFerrata < r.ways;
      if (!NOMI_FERRATA.test(t.name)) {
        nascoste++;
        elencoNascoste.push({ ...t, tratti: r.wayFerrata, ways: r.ways, soloUnTratto });
      }
    }
    if (!r.sac) continue;
    conSac++;
    distr[r.sac] = (distr[r.sac] || 0) + 1;

    const cai = SAC[rangoSac(r.sac)][1];
    const nostro = RANGO_NOSTRO[String(t.difficulty || '').toLowerCase()];
    if (nostro === undefined) { senzaNostra++; continue; }
    const vero = RANGO_CAI[cai];
    if (nostro === vero) uguali++;
    else if (nostro < vero) {
      sotto++;
      if (vero - nostro >= 2) gravi.push({ ...t, cai, sac: r.sac });
    } else sopra++;
  }

  const validi = trails.length - senzaWay - nonRaccolti;
  console.log(`\n=== RACCOLTO ===`);
  console.log(`sentieri validi:              ${validi}`);
  console.log(`relazioni senza way:          ${senzaWay}`);
  if (nonRaccolti) console.log(`non ancora scaricati:         ${nonRaccolti}`);
  console.log(`con sac_scale vera:           ${conSac}  (${(100 * conSac / (validi || 1)).toFixed(1)}%)`);
  console.log(`vie attrezzate rilevate:      ${ferrate}`);
  console.log(`  che il nome NON dichiara:   ${nascoste}`);

  console.log('\nsac_scale (il tratto peggiore di ogni percorso):');
  for (const [k, cai] of SAC) if (distr[k]) console.log(`  ${k.padEnd(28)} ${String(distr[k]).padStart(6)}  -> CAI ${cai.toUpperCase()}`);

  console.log('\n=== la nostra stima contro il dato rilevato ===');
  console.log(`coincidono:                   ${uguali}`);
  console.log(`SOTTOSTIMIAMO (piu' pericoloso del dichiarato): ${sotto}`);
  console.log(`  di cui di 2+ gradi:         ${gravi.length}`);
  console.log(`sovrastimiamo:                ${sopra}`);
  if (senzaNostra) console.log(`nostra difficolta' non confrontabile: ${senzaNostra}`);

  if (gravi.length) {
    console.log('\n=== SOTTOSTIME GRAVI (2+ gradi) ===');
    gravi.slice(0, 15).forEach((g) => console.log(
      `  ${g.name.slice(0, 46).padEnd(48)} ${g.km.toFixed(1).padStart(6)} km  nostra "${g.difficulty}" -> ${g.cai.toUpperCase()} (${g.sac})`));
  }
  if (elencoNascoste.length) {
    console.log('\n=== VIE ATTREZZATE INVISIBILI DAL NOME ===');
    elencoNascoste.slice(0, 20).forEach((f) => console.log(
      `  ${f.name.slice(0, 44).padEnd(46)} ${f.km.toFixed(1).padStart(6)} km  "${f.difficulty || '—'}"  ` +
      `${f.tratti}/${f.ways} way attrezzate${f.soloUnTratto ? '  (comprende un tratto)' : '  (tutta attrezzata)'}`));
    console.log(`  ... totale ${elencoNascoste.length}`);
  }
  console.log('\nNessuna scrittura: questo script raccoglie e basta.');
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
