// Un solo vocabolario per il campo difficulty.
//
// Oggi ci convivono tre alfabeti: i codici CAI maiuscoli prodotti dalla
// vecchia _estimateDifficulty (T/E/EE), quelli minuscoli da sac_scale
// (t/e/ee/eea) e le parole italiane arrivate da promoteFromCommunityTrack
// (facile/media/difficile). Un filtro che confronta stringhe non puo'
// funzionare, e la distinzione maiuscolo/minuscolo aveva finito per
// codificare per caso la provenienza — cosa che ora fa difficultySource.
//
// DUE POPOLAZIONI, DUE TRATTAMENTI:
//
//   CON difficultySource: il grado e' stato confrontato col rilievo OSM e
//   coincideva, quindi sappiamo a quale gradino corrisponde. "media" con
//   provenienza osm_sac vuol dire che OSM diceva mountain_hiking: scrivere
//   'e' e' solo dire meglio la stessa cosa.
//
//   SENZA provenienza: si sistemano solo le MAIUSCOLE dei codici CAI
//   (T->t, EE->ee). Le parole italiane si lasciano stare: sono
//   autovalutazioni di FATICA fatte dagli utenti, e tradurre "difficile" in
//   "ee" promuoverebbe un'impressione personale a valutazione tecnica del
//   terreno. E' la confusione che stiamo smontando, non la si rifa' qui.
//
// Uso:
//   node scripts/trail_difficulty_normalize.cjs --dry
//   node scripts/trail_difficulty_normalize.cjs
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const DRY = process.argv.includes('--dry');

/// Codici CAI: solo un cambio di scatola, nessuna interpretazione.
const SOLO_MAIUSCOLE = {
  T: 't', E: 'e', EE: 'ee', EEA: 'eea',
  turistico: 't', escursionistico: 'e', alpinistico: 'eea',
};
/// Parole italiane: si traducono SOLO se il rilievo OSM ha confermato il
/// gradino, cioe' solo dove difficultySource e' valorizzato.
const CON_PROVA = {
  facile: 't', medio: 'e', media: 'e', difficile: 'ee',
};

(async () => {
  console.log(DRY ? '=== SIMULAZIONE ===\n' : '=== SCRITTURA ===\n');
  const snap = await db.collection('public_trails').get();

  const daFare = [];
  let maiuscole = 0, tradotte = 0, lasciate = 0, gia = 0;
  const dettaglio = {};

  snap.forEach((d) => {
    const x = d.data();
    const v = x.difficulty;
    if (v == null || v === '') return;
    if (['t', 'e', 'ee', 'eea'].includes(v)) { gia++; return; }

    let nuovo = SOLO_MAIUSCOLE[v];
    let tipo = 'maiuscole';
    if (!nuovo && x.difficultySource && CON_PROVA[String(v).toLowerCase()]) {
      nuovo = CON_PROVA[String(v).toLowerCase()];
      tipo = 'tradotta';
    }
    if (!nuovo) {
      lasciate++;
      dettaglio[`lasciata: ${v}`] = (dettaglio[`lasciata: ${v}`] || 0) + 1;
      return;
    }
    if (tipo === 'maiuscole') maiuscole++; else tradotte++;
    dettaglio[`${v} -> ${nuovo}`] = (dettaglio[`${v} -> ${nuovo}`] || 0) + 1;
    daFare.push({ ref: d.ref, nuovo });
  });

  console.log('cosa succede a ogni valore:');
  Object.entries(dettaglio).sort((a, b) => b[1] - a[1])
    .forEach(([k, v]) => console.log(`  ${k.padEnd(22)} ${String(v).padStart(5)}`));

  console.log(`\ngia' canonici:            ${gia}`);
  console.log(`solo maiuscole sistemate: ${maiuscole}`);
  console.log(`tradotte (con prova OSM): ${tradotte}`);
  console.log(`LASCIATE STARE:           ${lasciate}  <- parole di fatica senza rilievo che le confermi`);
  console.log(`documenti da scrivere:    ${daFare.length}`);

  if (DRY) { console.log('\nNessuna scrittura. Per applicare, togliere --dry.'); process.exit(0); }

  let n = 0;
  for (let i = 0; i < daFare.length; i += 400) {
    const batch = db.batch();
    for (const it of daFare.slice(i, i + 400)) batch.update(it.ref, { difficulty: it.nuovo });
    await batch.commit();
    n += Math.min(400, daFare.length - i);
    if (n % 4000 === 0 || n === daFare.length) console.log(`  ${n}/${daFare.length}`);
  }
  console.log(`\nFatto: ${n} sentieri su un vocabolario solo.`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
