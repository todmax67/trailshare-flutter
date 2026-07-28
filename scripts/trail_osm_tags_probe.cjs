// Rilettura dei tag OSM a livello di WAY per i sentieri del catalogo.
//
// Perche': `sac_scale` sta quasi sempre sulle singole way, non sulla
// relazione del percorso, e noi all'import leggiamo solo quella della
// relazione. Risultato: 158 sentieri su 16.350 (l'1%) hanno una difficolta'
// tecnica vera, tutti gli altri hanno la stima di _estimateDifficulty.
// Stessa storia per le vie ferrate, che oggi riconosciamo dal nome — quindi
// quelle che non si chiamano "ferrata" ci sfuggono.
//
// Questo script SONDA e basta: non scrive niente su Firestore. Serve a
// misurare quanta copertura otterremmo davvero prima di impegnare una
// passata completa su 16.350 relazioni.
//
// Una query per lotto restituisce entrambe le cose:
//   rel(id:...); out body;   -> l'elenco dei membri di ogni relazione
//   way(r);      out tags;   -> i tag di tutte le way membro
// che poi si incrociano in locale.
//
// Uso:
//   node scripts/trail_osm_tags_probe.cjs --limit 300
//   node scripts/trail_osm_tags_probe.cjs --limit 300 --solo-senza-nome
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const UA = { 'User-Agent': 'TrailShare-enrichment/1.0 (info@trailshare.app)' };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 ? argv[i + 1] : d; };
const LIMIT = Number(opt('limit', 300));
const LOTTO = Number(opt('lotto', 50));
const SOLO_SENZA_NOME = argv.includes('--solo-senza-nome');

const NOMI_FERRATA = /\b(ferrata|ferrate|klettersteig|sentiero attrezzato|via attrezzata|sentiero alpinistico attrezzato)/i;

/// Scala SAC ordinata dal facile al difficile, con il grado CAI corrispondente.
/// Stessa mappatura di _difficultyFromTags in trail_import_service.dart.
const SAC = [
  ['hiking', 't'],
  ['mountain_hiking', 'e'],
  ['demanding_mountain_hiking', 'ee'],
  ['alpine_hiking', 'eea'],
  ['demanding_alpine_hiking', 'eea'],
  ['difficult_alpine_hiking', 'eea'],
];
const rangoSac = (v) => SAC.findIndex(([k]) => k === v);

async function overpass(q) {
  const eps = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];
  let last;
  for (let a = 0; a < 6; a++) {
    try {
      const r = await fetch(eps[a % 2], {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...UA },
        body: 'data=' + encodeURIComponent(q),
      });
      if (r.ok) return r.json();
      last = new Error('HTTP ' + r.status);
    } catch (e) { last = e; }
    await sleep(12000);
  }
  throw last;
}

(async () => {
  const snap = await db.collection('public_trails').get();
  let trails = [];
  snap.forEach((d) => {
    const x = d.data();
    if (!x.osmId) return;
    if (SOLO_SENZA_NOME && NOMI_FERRATA.test(String(x.name || ''))) return;
    trails.push({ id: d.id, osmId: String(x.osmId), name: String(x.name || ''),
      difficulty: x.difficulty, km: (x.distance || 0) / 1000 });
  });
  trails = trails.slice(0, LIMIT);
  console.log(`sondo ${trails.length} sentieri, ${LOTTO} per volta\n`);

  const perTrail = {};
  for (let i = 0; i < trails.length; i += LOTTO) {
    const chunk = trails.slice(i, i + LOTTO);
    const ids = chunk.map((t) => t.osmId).join(',');
    const j = await overpass(
      `[out:json][timeout:180];rel(id:${ids});out body;way(r);out tags;`);

    const tagWay = {}, membri = {};
    for (const el of j.elements || []) {
      if (el.type === 'way') tagWay[el.id] = el.tags || {};
      else if (el.type === 'relation') {
        membri[String(el.id)] = (el.members || [])
          .filter((m) => m.type === 'way').map((m) => m.ref);
      }
    }
    for (const t of chunk) {
      const ways = membri[t.osmId] || [];
      let peggiorSac = -1, ferrata = false, conSac = 0;
      for (const w of ways) {
        const tg = tagWay[w];
        if (!tg) continue;
        if (tg.highway === 'via_ferrata' || tg.via_ferrata_scale
            || tg.climbing === 'via_ferrata') ferrata = true;
        const s = tg.sac_scale && String(tg.sac_scale).toLowerCase();
        if (s) { conSac++; const r = rangoSac(s); if (r > peggiorSac) peggiorSac = r; }
      }
      perTrail[t.id] = { ways: ways.length, conSac, ferrata,
        sac: peggiorSac >= 0 ? SAC[peggiorSac] : null };
    }
    process.stdout.write(`${Math.min(i + LOTTO, trails.length)}/${trails.length} `);
    await sleep(8000);
  }

  // ── risultati ────────────────────────────────────────────────────────
  let senzaWay = 0, conSac = 0, ferrate = 0, ferrateNascoste = 0;
  const distr = {}, disaccordi = [], nascoste = [];
  for (const t of trails) {
    const r = perTrail[t.id];
    if (!r || !r.ways) { senzaWay++; continue; }
    if (r.ferrata) {
      ferrate++;
      if (!NOMI_FERRATA.test(t.name)) { ferrateNascoste++; nascoste.push({ t, r }); }
    }
    if (r.sac) {
      conSac++;
      distr[r.sac[0]] = (distr[r.sac[0]] || 0) + 1;
      const attuale = String(t.difficulty || '').toLowerCase();
      if (attuale && attuale !== r.sac[1]) disaccordi.push({ t, r });
    }
  }
  const validi = trails.length - senzaWay;
  console.log(`\n\n=== ESITO SU ${trails.length} SENTIERI ===`);
  console.log(`relazioni senza way restituite:  ${senzaWay}`);
  console.log(`con sac_scale sulle way:         ${conSac}  (${(100 * conSac / (validi || 1)).toFixed(1)}% dei validi)`);
  console.log(`  --- oggi, da tag relazione:    ~1%`);
  console.log(`vie ferrate riconosciute:        ${ferrate}`);
  console.log(`  di cui INVISIBILI dal nome:    ${ferrateNascoste}`);

  if (Object.keys(distr).length) {
    console.log('\nsac_scale trovate (il peggior tratto di ogni percorso):');
    for (const [k, cai] of SAC) if (distr[k]) console.log(`  ${k.padEnd(28)} ${String(distr[k]).padStart(5)}  -> CAI ${cai.toUpperCase()}`);
  }
  if (nascoste.length) {
    console.log('\n=== FERRATE CHE IL NOME NON DICHIARA ===');
    nascoste.slice(0, 12).forEach(({ t }) => console.log(
      `  ${t.name.slice(0, 50).padEnd(52)} ${t.km.toFixed(1).padStart(6)} km  oggi "${t.difficulty || '—'}"`));
  }
  if (disaccordi.length) {
    console.log(`\n=== dove OSM contraddice la nostra difficolta' (${disaccordi.length}) ===`);
    disaccordi.slice(0, 12).forEach(({ t, r }) => console.log(
      `  ${t.name.slice(0, 44).padEnd(46)} nostra "${String(t.difficulty).padEnd(9)}" OSM ${r.sac[1].toUpperCase().padEnd(4)} (${r.sac[0]})`));
  }
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
