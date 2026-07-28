// Vie attrezzate rilevate dai tag OSM delle way — applicazione al catalogo.
//
// Legge il raccolto di trail_osm_tags_harvest.cjs (nessuna rete) e marca i
// sentieri le cui way portano highway=via_ferrata, via_ferrata_scale o
// climbing=via_ferrata.
//
// Perche' serve, dato che le ferrate le avevamo gia' sistemate: quelle le
// riconoscevamo DAL NOME. La sonda ha trovato vie attrezzate chiamate
// "Wanderweg 548" (0,9 km, classificata "T — turistico") o "Garfagnana
// Trekking Tappa 3b". Il nome non e' una fonte, e' un indizio.
//
// Distingue due casi, perche' dire la cosa sbagliata in senso opposto e'
// comunque dire una cosa sbagliata:
//   - TUTTA attrezzata      -> e' una via ferrata
//   - COMPRENDE un tratto   -> itinerario escursionistico con un passaggio
//                              attrezzato non aggirabile
// In entrambi il grado e' 'eea': il tratto peggiore non si evita.
//
// Scrive `difficultySource` per non ripetere l'errore di non saper piu'
// distinguere un grado rilevato da uno stimato.
//
// Uso:
//   node scripts/trail_ferrata_from_osm.cjs --dry
//   node scripts/trail_ferrata_from_osm.cjs
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const fs = require('fs');
const path = require('path');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const DRY = process.argv.includes('--dry');
const RACCOLTO = path.join(__dirname, '..', '.photo_review', 'osm_way_tags.json');

const NOMI_FERRATA = /\b(ferrata|ferrate|klettersteig|sentiero attrezzato|via attrezzata|sentiero alpinistico attrezzato)/i;

(async () => {
  if (!fs.existsSync(RACCOLTO)) {
    console.error(`Manca ${RACCOLTO}: prima gira trail_osm_tags_harvest.cjs`);
    process.exit(1);
  }
  const raccolto = JSON.parse(fs.readFileSync(RACCOLTO, 'utf8'));
  console.log(`${DRY ? '=== SIMULAZIONE ===' : '=== SCRITTURA ==='}\n`);
  console.log(`relazioni nel raccolto: ${Object.keys(raccolto).length}\n`);

  const snap = await db.collection('public_trails').get();
  let nuove = 0, gia = 0, tutte = 0, parziali = 0, descRitirate = 0, manuali = 0;
  const daFare = [];

  snap.forEach((d) => {
    const x = d.data();
    const r = x.osmId && raccolto[String(x.osmId)];
    if (!r || !r.wayFerrata) return;

    const parziale = r.wayFerrata < r.ways;
    const nome = String(x.name || '');
    const giaNota = NOMI_FERRATA.test(nome) || x.viaFerrata === true;
    if (giaNota) gia++; else nuove++;
    if (parziale) parziali++; else tutte++;

    const upd = {
      viaFerrata: true,
      viaFerrataParziale: parziale,
      difficulty: 'eea',
      difficultySource: 'osm_ferrata',
    };

    // La descrizione generata va ritirata solo se non sapeva della ferrata:
    // quelle rigenerate ieri per le ferrate note lo dicono gia'.
    // DUE valori, non uno: lo script scrive 'ai_facts', ma quando approvi
    // dal web admin diventa 'ai_facts_reviewed'. Controllando solo il primo
    // le descrizioni approvate a mano da te passavano per "scritte a mano"
    // e venivano saltate — comprese quelle che non citano l'attrezzatura.
    const generata = x.description
      && String(x.description).trim().length >= 30
      && ['ai_facts', 'ai_facts_reviewed'].includes(x.descriptionSource);
    const sapeva = generata && /imbrag|casco|set da ferrata|attrezzat/i.test(String(x.description));
    if (generata && !sapeva) {
      upd.description = admin.firestore.FieldValue.delete();
      upd.descriptionSource = admin.firestore.FieldValue.delete();
      descRitirate++;
    } else if (x.description && String(x.description).trim().length >= 30 && !generata) {
      manuali++;
    }
    if (x.aiDraft) upd.aiDraft = admin.firestore.FieldValue.delete();

    daFare.push({ ref: d.ref, upd, nome, km: (x.distance || 0) / 1000,
      era: x.difficulty, parziale, tratti: r.wayFerrata, ways: r.ways, giaNota });
  });

  daFare.sort((a, b) => (a.giaNota ? 1 : 0) - (b.giaNota ? 1 : 0));
  for (const it of daFare.filter((i) => !i.giaNota).slice(0, 25)) {
    console.log(`${DRY ? '·' : '✓'} ${it.nome.slice(0, 44).padEnd(46)}${it.km.toFixed(1).padStart(7)} km  ` +
      `era "${String(it.era || '—').padEnd(9)}"  ${it.tratti}/${it.ways} way  ` +
      `${it.parziale ? 'comprende un tratto' : 'tutta attrezzata'}` +
      `${it.upd.description ? '  + descrizione ritirata' : ''}`);
  }
  if (daFare.filter((i) => !i.giaNota).length > 25) {
    console.log(`  ... e altre ${daFare.filter((i) => !i.giaNota).length - 25}`);
  }

  console.log(`\n=== RIEPILOGO ${DRY ? '(SIMULAZIONE)' : ''} ===`);
  console.log(`vie attrezzate dai tag OSM:      ${daFare.length}`);
  console.log(`  gia' note dal nome:            ${gia}`);
  console.log(`  NUOVE, invisibili dal nome:    ${nuove}`);
  console.log(`interamente attrezzate:          ${tutte}`);
  console.log(`che comprendono un tratto:       ${parziali}`);
  console.log(`descrizioni da ritirare:         ${descRitirate}`);
  console.log(`descrizioni a mano non toccate:  ${manuali}`);

  if (DRY) { console.log('\nNessuna scrittura. Per applicare, togliere --dry.'); process.exit(0); }

  let n = 0;
  for (let i = 0; i < daFare.length; i += 400) {
    const batch = db.batch();
    for (const it of daFare.slice(i, i + 400)) batch.update(it.ref, it.upd);
    await batch.commit();
    n += Math.min(400, daFare.length - i);
    console.log(`  ${n}/${daFare.length}`);
  }
  console.log(`\nFatto. Ora rigenerare: node scripts/trail_ai_descriptions.cjs --ferrate --limit 400`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
