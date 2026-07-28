// Raccolta dei tag OSM a livello di WAY — versione LOCALE, da estratti .pbf.
//
// Sostituisce trail_osm_tags_harvest.cjs (che interroga Overpass) per il
// lavoro di massa. Motivo: 16.287 relazioni sull'API pubblica significano
// ore di richieste e un HTTP 429 quando il servizio si stufa — giustamente,
// perche' e' un bene comune gratuito e non un fornitore. Su un estratto
// scaricato una volta sola non c'e' limite, non c'e' attesa, e il lavoro si
// puo' rifare quante volte serve.
//
// Produce ESATTAMENTE lo stesso formato di file della versione Overpass,
// cosi' trail_ferrata_from_osm.cjs e il rapporto funzionano immutati:
//   { "<osmId>": { ways, conSac, wayFerrata, sac } }
//
// Prerequisiti:
//   brew install osmium-tool
//   estratti .pbf in /Volumes/Lexar/osm_data (vedi scarica.sh)
//
// Uso:
//   node scripts/trail_osm_local_harvest.cjs --prepara     (scrive gli id)
//   ...poi si lancia osmium (il comando lo stampa lo script)...
//   node scripts/trail_osm_local_harvest.cjs --unisci      (incrocia e salva)
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const LAVORO = '/Volumes/Lexar/osm_data/lavoro';
const RACCOLTO = path.join(__dirname, '..', '.photo_review', 'osm_way_tags.json');

const SAC = ['hiking', 'mountain_hiking', 'demanding_mountain_hiking',
  'alpine_hiking', 'demanding_alpine_hiking', 'difficult_alpine_hiking'];

async function prepara() {
  fs.mkdirSync(LAVORO, { recursive: true });
  const snap = await db.collection('public_trails').get();
  const ids = [];
  snap.forEach((d) => { const x = d.data(); if (x.osmId) ids.push('r' + x.osmId); });
  const f = path.join(LAVORO, 'rel_ids.txt');
  fs.writeFileSync(f, ids.join('\n') + '\n');
  console.log(`${ids.length} identificativi di relazione scritti in ${f}\n`);
  console.log('Ora, per ogni estratto, due passate di osmium:\n');
  console.log('  # 1) le NOSTRE relazioni, con l\'elenco dei membri');
  console.log(`  osmium getid ESTRATTO.osm.pbf -i ${f} -f opl -o ${LAVORO}/rels_NOME.opl --overwrite\n`);
  console.log('  # 2) le sole way che portano i tag che ci interessano');
  console.log(`  osmium tags-filter ESTRATTO.osm.pbf w/sac_scale w/highway=via_ferrata \\`);
  console.log(`      w/via_ferrata_scale w/climbing=via_ferrata -f opl -o ${LAVORO}/ways_NOME.opl --overwrite\n`);
  console.log('Poi:  node scripts/trail_osm_local_harvest.cjs --unisci');
}

/// Legge un OPL riga per riga senza caricarlo in memoria: gli estratti
/// pesano giga e la macchina non deve accorgersene.
async function perRiga(file, fn) {
  if (!fs.existsSync(file)) return 0;
  let n = 0;
  const rl = readline.createInterface({
    input: fs.createReadStream(file), crlfDelay: Infinity });
  for await (const riga of rl) { if (riga) { fn(riga); n++; } }
  return n;
}

/// I campi OPL sono separati da spazi: `w123 v2 ... Ttag=val,tag=val Nn1,n2`
/// Il valore di un tag puo' contenere spazi codificati (%20), non spazi veri.
function campo(riga, lettera) {
  for (const p of riga.split(' ')) if (p[0] === lettera) return p.slice(1);
  return null;
}

async function unisci() {
  // ── 1. le way con i tag utili ──────────────────────────────────────
  const sacDiWay = new Map();     // wayId -> indice SAC
  const ferrataWay = new Set();   // wayId attrezzate
  const filesWay = fs.readdirSync(LAVORO).filter((f) => f.startsWith('ways_') && f.endsWith('.opl'));
  if (!filesWay.length) { console.error(`Nessun ways_*.opl in ${LAVORO}: prima gira osmium.`); process.exit(1); }
  for (const f of filesWay) {
    const n = await perRiga(path.join(LAVORO, f), (riga) => {
      if (riga[0] !== 'w') return;
      const id = riga.split(' ')[0].slice(1);
      const tags = campo(riga, 'T') || '';
      let sac = null, ferrata = false;
      for (const kv of tags.split(',')) {
        const i = kv.indexOf('=');
        if (i < 0) continue;
        const k = kv.slice(0, i), v = kv.slice(i + 1).toLowerCase();
        if (k === 'sac_scale') sac = v;
        else if (k === 'via_ferrata_scale') ferrata = true;
        else if (k === 'highway' && v === 'via_ferrata') ferrata = true;
        else if (k === 'climbing' && v === 'via_ferrata') ferrata = true;
      }
      if (ferrata) ferrataWay.add(id);
      if (sac) { const r = SAC.indexOf(sac); if (r >= 0) sacDiWay.set(id, r); }
    });
    console.log(`  ${f}: ${n} righe`);
  }
  console.log(`way con sac_scale: ${sacDiWay.size} | way attrezzate: ${ferrataWay.size}\n`);

  // ── 2. le nostre relazioni e i loro membri ─────────────────────────
  const raccolto = fs.existsSync(RACCOLTO)
    ? JSON.parse(fs.readFileSync(RACCOLTO, 'utf8')) : {};
  const primaAvevamo = Object.keys(raccolto).length;
  const filesRel = fs.readdirSync(LAVORO).filter((f) => f.startsWith('rels_') && f.endsWith('.opl'));
  let trovate = 0;
  for (const f of filesRel) {
    await perRiga(path.join(LAVORO, f), (riga) => {
      if (riga[0] !== 'r') return;
      const relId = riga.split(' ')[0].slice(1);
      const membri = campo(riga, 'M') || '';
      let ways = 0, conSac = 0, wayFerrata = 0, peggiore = -1;
      for (const m of membri.split(',')) {
        if (!m || m[0] !== 'w') continue;
        const wid = m.slice(1).split('@')[0];
        ways++;
        if (ferrataWay.has(wid)) wayFerrata++;
        const r = sacDiWay.get(wid);
        if (r !== undefined) { conSac++; if (r > peggiore) peggiore = r; }
      }
      if (!ways) return;
      trovate++;
      raccolto[relId] = { ways, conSac, wayFerrata,
        sac: peggiore >= 0 ? SAC[peggiore] : null };
    });
    console.log(`  ${f}: relazioni lette`);
  }

  fs.writeFileSync(RACCOLTO, JSON.stringify(raccolto));
  console.log(`\nrelazioni trovate negli estratti: ${trovate}`);
  console.log(`raccolto: da ${primaAvevamo} a ${Object.keys(raccolto).length} relazioni`);
  console.log(`salvato in ${path.relative(process.cwd(), RACCOLTO)}`);
  console.log('\nRapporto:  node scripts/trail_osm_tags_harvest.cjs --solo-rapporto');
}

(async () => {
  if (argv.includes('--prepara')) await prepara();
  else if (argv.includes('--unisci')) await unisci();
  else console.log('Serve --prepara oppure --unisci (vedi intestazione del file).');
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
