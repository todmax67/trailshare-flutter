// Vie attrezzate classificate come passeggiate — correzione.
//
// _estimateDifficulty assegna "T — turistico" a tutto cio' che sta sotto i
// 5 km con meno di 300 m di dislivello. Una ferrata e' corta e ripida, e ci
// finisce dentro: 136 vie attrezzate su 197 risultano "T" o "facile", e 93
// hanno una descrizione pubblicata che le racconta come facili ("ideale per
// escursionisti di ogni livello", "senza difficolta' tecniche").
//
// I "facile" arrivano invece da promoteFromCommunityTrack: un utente
// attrezzato la percorre e la marca facile in buona fede, e quella parola
// finisce nel campo della scala tecnica.
//
// Cosa fa:
//   1. difficulty = 'eea' sulle vie attrezzate vere (il grado CAI per le
//      vie che richiedono attrezzatura)
//   2. difficulty = null sui segmenti di servizio (avvicinamento, attacco,
//      uscita, rientro): non sono attrezzati ma non sono nemmeno "facili",
//      e affermare l'uno o l'altro sarebbe inventare
//   3. cancella la description generata (descriptionSource 'ai_facts') e la
//      relativa aiDraft, cosi' rientrano in coda e si rigenerano con la
//      regola di sicurezza aggiunta a trail_ai_descriptions.cjs
//
// NON tocca le descrizioni scritte a mano (descriptionSource diverso).
//
// LIMITE: il riconoscimento e' sul nome, quindi ha falsi negativi — una
// ferrata che non si chiama cosi' non viene vista. La via autorevole e'
// rileggere i tag OSM (highway=via_ferrata, via_ferrata_scale) partendo da
// osmId, che i documenti conservano.
//
// Uso:
//   node scripts/trail_ferrata_fix.cjs --dry
//   node scripts/trail_ferrata_fix.cjs
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const DRY = process.argv.includes('--dry');

const NOMI_FERRATA = /\b(ferrata|ferrate|klettersteig|sentiero attrezzato|via attrezzata|sentiero alpinistico attrezzato)/i;
const NOMI_SERVIZIO = /\b(approach|zustieg|ausstieg|abstieg|attacco|accesso|avvicinamento|rientro|return|exit|start|uscita|discesa)\b/i;

/// Gradi che su una via attrezzata sono una rassicurazione falsa.
const RASSICURANTI = new Set(['T', 't', 'facile', 'E', 'e', 'media', 'medio']);

(async () => {
  console.log(DRY ? '=== SIMULAZIONE ===\n' : '=== SCRITTURA ===\n');
  const snap = await db.collection('public_trails').get();

  const attrezzate = [], servizio = [];
  snap.forEach((d) => {
    const x = d.data();
    const nome = String(x.name || '');
    if (!NOMI_FERRATA.test(nome)) return;
    (NOMI_SERVIZIO.test(nome) ? servizio : attrezzate).push({ ref: d.ref, x, nome });
  });

  const generata = (x) => x.description
    && String(x.description).trim().length >= 30
    && x.descriptionSource === 'ai_facts';

  let gradi = 0, descRitirate = 0, bozze = 0, manuali = 0;

  for (const it of attrezzate) {
    const upd = {};
    const daCorreggere = it.x.difficulty !== 'eea';
    if (daCorreggere) upd.difficulty = 'eea';
    if (generata(it.x)) {
      upd.description = admin.firestore.FieldValue.delete();
      upd.descriptionSource = admin.firestore.FieldValue.delete();
    } else if (it.x.description && String(it.x.description).trim().length >= 30) {
      manuali++;
    }
    if (it.x.aiDraft) upd.aiDraft = admin.firestore.FieldValue.delete();

    if (!Object.keys(upd).length) continue;
    if (upd.difficulty) gradi++;
    if (upd.description) descRitirate++;
    if (upd.aiDraft) bozze++;

    const era = RASSICURANTI.has(it.x.difficulty) ? ` [era "${it.x.difficulty}" !]` : ` [era "${it.x.difficulty || '—'}"]`;
    console.log(`${DRY ? '·' : '✓'} ferrata  ${it.nome.slice(0, 46).padEnd(48)}${era}` +
      (upd.description ? '  + descrizione ritirata' : ''));
    if (!DRY) await it.ref.update(upd);
  }

  for (const it of servizio) {
    const upd = {};
    if (it.x.difficulty != null) upd.difficulty = admin.firestore.FieldValue.delete();
    if (generata(it.x)) {
      upd.description = admin.firestore.FieldValue.delete();
      upd.descriptionSource = admin.firestore.FieldValue.delete();
      descRitirate++;
    }
    if (it.x.aiDraft) { upd.aiDraft = admin.firestore.FieldValue.delete(); bozze++; }
    if (!Object.keys(upd).length) continue;
    console.log(`${DRY ? '·' : '✓'} servizio ${it.nome.slice(0, 46).padEnd(48)} [era "${it.x.difficulty || '—'}"] -> non classificato`);
    if (!DRY) await it.ref.update(upd);
  }

  console.log(`\n=== RIEPILOGO ${DRY ? '(SIMULAZIONE)' : ''} ===`);
  console.log(`vie attrezzate:            ${attrezzate.length}`);
  console.log(`segmenti di servizio:      ${servizio.length}`);
  console.log(`gradi portati a 'eea':     ${gradi}`);
  console.log(`descrizioni ritirate:      ${descRitirate}`);
  console.log(`bozze in coda azzerate:    ${bozze}`);
  console.log(`descrizioni scritte a mano lasciate stare: ${manuali}`);
  if (DRY) console.log('\nNessuna scrittura. Per applicare, togliere --dry.');
  else console.log('\nOra rigenerare le descrizioni: node scripts/trail_ai_descriptions.cjs --limit 200');
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
