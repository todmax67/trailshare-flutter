// Difficolta' tecnica dai sac_scale rilevati sulle way OSM.
//
// Sostituisce la stima di _estimateDifficulty (lunghezza + dislivello, che
// del terreno non sanno nulla) dove esiste un dato rilevato da chi ha
// mappato il sentiero.
//
// LA REGOLA ASIMMETRICA, che e' il cuore di questo script:
//
//   ALZARE si puo' sempre. Il nostro valore e' il MASSIMO fra le way: se
//   anche una sola porta demanding_mountain_hiking, quel tratto esiste ed e'
//   duro. Una prova basta.
//
//   ABBASSARE no. Se un percorso ha 50 segmenti e solo 10 sono taggati, e
//   quei 10 sono facili, il massimo risulta basso — ma gli altri 40
//   potrebbero essere peggio e semplicemente non mappati. L'assenza di prova
//   non e' prova di assenza. Misurato: la copertura mediana e' 68% sui
//   sentieri da alzare e 19% su quelli da abbassare, cioe' i sovrastimati
//   sono in larga parte un artefatto della mappatura rada.
//
// Percio' si abbassa solo con COPERTURA >= SOGLIA_GIU. Sotto quella soglia
// si tiene il valore piu' prudente che avevamo.
//
// Le vie attrezzate non si toccano: hanno gia' 'eea' da trail_ferrata_from_osm.
//
// Uso:
//   node scripts/trail_difficulty_from_sac.cjs --dry
//   node scripts/trail_difficulty_from_sac.cjs --dry --soglia 0.9
//   node scripts/trail_difficulty_from_sac.cjs
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const fs = require('fs');
const path = require('path');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const DRY = argv.includes('--dry');
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 ? argv[i + 1] : d; };
const SOGLIA_GIU = Number(opt('soglia', 0.8));
// --marca-concordi: dove la stima gia' coincideva col rilievo, scrive solo
// la provenienza. Nessun grado cambia, nessuna descrizione si tocca.
const MARCA_CONCORDI = argv.includes('--marca-concordi');
const RACCOLTO = path.join(__dirname, '..', '.photo_review', 'osm_way_tags.json');

const SAC_A_CAI = {
  hiking: 't', mountain_hiking: 'e', demanding_mountain_hiking: 'ee',
  alpine_hiking: 'eea', demanding_alpine_hiking: 'eea', difficult_alpine_hiking: 'eea',
};
/// I tre vocabolari che convivono nel campo, su una scala sola.
const RANGO_NOSTRO = {
  t: 0, turistico: 0, facile: 0,
  e: 1, escursionistico: 1, media: 1, medio: 1,
  ee: 2, difficile: 2, eea: 3, alpinistico: 3,
};
const RANGO_CAI = { t: 0, e: 1, ee: 2, eea: 3 };
const NOME = { t: 'T', e: 'E', ee: 'EE', eea: 'EEA' };

/// Una descrizione che dichiara una difficolta' ormai superata va rifatta:
/// se il sentiero passa da E a EE, il testo che dice "difficolta' E" e'
/// una sottovalutazione pubblicata.
const CITA_DIFFICOLTA = /difficolt|\bEE\b|\bEEA\b|escursionisti esperti|turistic|alpinistic/i;
const GENERATA = ['ai_facts', 'ai_facts_reviewed'];

(async () => {
  if (!fs.existsSync(RACCOLTO)) {
    console.error(`Manca ${RACCOLTO}: prima gira trail_osm_local_harvest.cjs`);
    process.exit(1);
  }
  const raccolto = JSON.parse(fs.readFileSync(RACCOLTO, 'utf8'));
  console.log(`${DRY ? '=== SIMULAZIONE ===' : '=== SCRITTURA ==='}`);
  console.log(`soglia di copertura per abbassare: ${(SOGLIA_GIU * 100).toFixed(0)}%\n`);

  const snap = await db.collection('public_trails').get();
  const daFare = [];
  let alzati = 0, abbassati = 0, giuScartati = 0, gia = 0, senzaDato = 0, ferrate = 0;
  let descRitirate = 0, marcati = 0;
  const perSalto = { 1: 0, 2: 0, 3: 0 };
  const esempi = [];

  snap.forEach((d) => {
    const x = d.data();
    if (x.viaFerrata === true) { ferrate++; return; }
    const r = x.osmId && raccolto[String(x.osmId)];
    if (!r || !r.sac || !r.ways) { senzaDato++; return; }

    const cai = SAC_A_CAI[r.sac];
    const vero = RANGO_CAI[cai];
    const nostro = RANGO_NOSTRO[String(x.difficulty || '').toLowerCase()];
    if (nostro === vero) {
      gia++;
      // Concordi: la stima azzeccava. Il grado non cambia, ma senza
      // provenienza resterebbe indistinguibile da una tirata a indovinare —
      // ed e' proprio quella confusione il difetto da cui siamo partiti.
      if (MARCA_CONCORDI && x.difficultySource !== 'osm_sac') {
        marcati++;
        daFare.push({ ref: d.ref, upd: { difficultySource: 'osm_sac' } });
      }
      return;
    }

    const copertura = r.conSac / r.ways;
    const inSu = nostro === undefined || nostro < vero;

    if (!inSu && copertura < SOGLIA_GIU) { giuScartati++; return; }

    const upd = { difficulty: cai, difficultySource: 'osm_sac' };

    // Solo in salita la descrizione e' pericolosa se resta com'e'.
    const desc = x.description && String(x.description).trim();
    const generata = desc && desc.length >= 30 && GENERATA.includes(x.descriptionSource);
    if (inSu && generata && CITA_DIFFICOLTA.test(desc)) {
      upd.description = admin.firestore.FieldValue.delete();
      upd.descriptionSource = admin.firestore.FieldValue.delete();
      descRitirate++;
    }
    if (x.aiDraft) upd.aiDraft = admin.firestore.FieldValue.delete();

    if (inSu) {
      alzati++;
      if (nostro !== undefined) perSalto[Math.min(3, vero - nostro)]++;
      if (esempi.length < 15 && vero - nostro >= 2) {
        esempi.push({ n: String(x.name).slice(0, 42), km: (x.distance || 0) / 1000,
          da: x.difficulty, a: NOME[cai], sac: r.sac, cop: copertura });
      }
    } else abbassati++;

    daFare.push({ ref: d.ref, upd });
  });

  console.log(`vie attrezzate saltate (gia' eea):     ${ferrate}`);
  console.log(`senza dato rilevato:                   ${senzaDato}`);
  console.log(`gia' corretti:                         ${gia}`);
  if (MARCA_CONCORDI) console.log(`  di cui da marcare come rilevati:     ${marcati}`);
  console.log(`\nDA ALZARE:                             ${alzati}`);
  console.log(`  di 1 grado: ${perSalto[1]}   di 2: ${perSalto[2]}   di 3: ${perSalto[3]}`);
  console.log(`DA ABBASSARE (copertura sufficiente):  ${abbassati}`);
  console.log(`  scartati per copertura troppo rada:  ${giuScartati}  <- restano com'erano`);
  console.log(`\ndescrizioni da ritirare e rifare:      ${descRitirate}`);
  console.log(`documenti da aggiornare:               ${daFare.length}`);

  if (esempi.length) {
    console.log('\n=== esempi di salto grosso (2+ gradi) ===');
    esempi.forEach((e) => console.log(
      `  ${e.n.padEnd(44)} ${e.km.toFixed(1).padStart(6)} km  ${String(e.da).padEnd(9)} -> ${e.a.padEnd(4)} ` +
      `(${e.sac}, way mappate ${(100 * e.cop).toFixed(0)}%)`));
  }

  if (DRY) { console.log('\nNessuna scrittura. Per applicare, togliere --dry.'); process.exit(0); }

  let n = 0;
  for (let i = 0; i < daFare.length; i += 400) {
    const batch = db.batch();
    for (const it of daFare.slice(i, i + 400)) batch.update(it.ref, it.upd);
    await batch.commit();
    n += Math.min(400, daFare.length - i);
    if (n % 2000 === 0 || n === daFare.length) console.log(`  ${n}/${daFare.length}`);
  }
  console.log(`\nFatto. Ora rigenerare le descrizioni ritirate:`);
  console.log(`  node scripts/trail_ai_descriptions.cjs --limit ${descRitirate + 50}`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
