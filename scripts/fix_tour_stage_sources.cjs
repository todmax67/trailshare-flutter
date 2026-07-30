// Ripara i tour che hanno tappe dal catalogo ma `stageSources` vuoto.
//
// PERCHE': il campo `stageSources` e' nato il 28/07 alle 19:07 (commit
// 5d39bd0e). I tour creati poco prima con tappe prese dal catalogo lo hanno
// vuoto, e prima dell'irrobustimento di loadTourTracks le loro tappe
// sparivano del tutto dalla scheda: la lista tornava vuota perche' il
// repository cercava `users/{uid}/tracks/wmt_relation_*`, che non esiste.
//
// Il codice ora prova comunque il catalogo, quindi la riparazione non e' piu'
// indispensabile per vedere le tappe. Si fa lo stesso per non lasciare
// documenti che dichiarano una cosa e ne contengono un'altra: l'editor del
// tour e il mirror community leggono `stageSources` per sapere che tipo di
// tappa hanno davanti.
//
// SICUREZZA: tocca solo i trackId che iniziano per `wmt_relation_` e che
// esistono davvero in `public_trails`. Idempotente: se il campo e' gia'
// corretto non scrive.
//
// Uso:
//   node scripts/fix_tour_stage_sources.cjs            (dry-run)
//   node scripts/fix_tour_stage_sources.cjs --apply
const path = require('path');
const admin = require(path.join(__dirname, '../functions/node_modules/firebase-admin'));
const sa = require(path.join(__dirname, '../functions/serviceAccountKey.json'));

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');

(async () => {
  console.log(APPLY ? '*** APPLY: scrive su Firestore ***' : 'dry-run (nessuna scrittura)\n');

  const tours = await db.collectionGroup('tours').get();
  let esaminati = 0, riparati = 0, giaOk = 0, saltati = 0;

  for (const d of tours.docs) {
    const t = d.data();
    const ids = t.trackIds || [];
    const ss = { ...(t.stageSources || {}) };
    const daCatalogo = ids.filter(i => String(i).startsWith('wmt_relation_'));
    if (!daCatalogo.length) continue;
    esaminati++;

    const mancanti = daCatalogo.filter(i => !ss[i]);
    if (!mancanti.length) { giaOk++; continue; }

    // Verifica che esistano davvero prima di dichiararle di catalogo.
    const esistenti = [];
    for (const id of mancanti) {
      const s = await db.collection('public_trails').doc(id).get();
      if (s.exists) esistenti.push(id);
    }
    if (!esistenti.length) {
      console.log(`"${t.title}": ${mancanti.length} tappe senza source ma NESSUNA in catalogo — non tocco`);
      saltati++;
      continue;
    }

    esistenti.forEach(id => { ss[id] = 'public_trail'; });
    const uid = d.ref.parent.parent.id;
    console.log(`"${t.title}" [${d.id}] owner=${uid}`);
    console.log(`   ${esistenti.length}/${mancanti.length} tappe marcate come public_trail`);
    if (esistenti.length < mancanti.length) {
      console.log(`   ATTENZIONE: ${mancanti.length - esistenti.length} non trovate in catalogo, lasciate come sono`);
    }

    if (APPLY) {
      await d.ref.update({ stageSources: ss });
      // Il mirror pubblico va allineato, se il tour e' pubblicato.
      if (t.isPublic) {
        const mirror = db.collection('community_tours').doc(d.id);
        if ((await mirror.get()).exists) {
          await mirror.update({ stageSources: ss });
          console.log(`   mirror community aggiornato`);
        }
      }
      console.log(`   ✔ riparato`);
    }
    riparati++;
  }

  console.log(`\n=== ${APPLY ? 'SCRITTO' : 'SIMULATO'} ===`);
  console.log(`tour con tappe da catalogo: ${esaminati}`);
  console.log(`già a posto:                ${giaOk}`);
  console.log(`${APPLY ? 'riparati' : 'da riparare'}:                ${riparati}`);
  console.log(`saltati (non in catalogo):  ${saltati}`);
  if (!APPLY) console.log(`\nNiente scritto. Rilancia con --apply.`);
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
