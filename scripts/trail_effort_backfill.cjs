// Impegno calcolato (T1-T5) e tempo di percorrenza per il catalogo.
//
// L'IMPEGNO e' cosa diversa dalla difficolta' tecnica: la fatica si deduce
// eccome da distanza e dislivello, ed e' proprio quello che la vecchia
// _estimateDifficulty calcolava — sbagliando solo a chiamarla "difficolta'
// CAI". Qui va in un campo suo, col suo nome, e non pretende di descrivere
// il terreno.
//
// GLI ITINERARI DI PIU' GIORNI NON RICEVONO UN LIVELLO.
//
// La scala T1-T5 e' tarata su una singola uscita: i commenti nel Dart
// parlano di "mezza giornata", "giornata piena", "impresa". Applicata a un
// cammino di settimane satura e smette di informare — il Sentiero Italia
// totalizza 11.653 contro una soglia T5 di 200, e finisce indistinguibile
// dalla Via del Sale che di km ne fa 258. Dire "T5 Estremo" sarebbe come
// dare lo stesso voto a una maratona e al Giro d'Italia.
//
// Percio' sopra le 8 ore si scrive `piuGiorni` e i giorni stimati, e basta.
// Sono 1.012 sentieri su 16.350: il 6%, non un caso limite trascurabile ma
// nemmeno la norma.
//
// Il tempo viene dalla formula escursionistica classica (DIN 33466 / SAC),
// col passo scelto in base all'ATTIVITA' (vedi PASSO): con la velocita' di
// un camminatore applicata a tutti, un giro di 46 km in eMTB risultava di
// tre giorni. I giorni sono ore/6 arrotondati per eccesso — una CONVENZIONE,
// non un dato, e come tale va presentata nell'interfaccia.
//
// Uso:
//   node scripts/trail_effort_backfill.cjs --dry
//   node scripts/trail_effort_backfill.cjs
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const { compute } = require('../functions/difficulty_calculator');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const DRY = argv.includes('--dry');
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 ? argv[i + 1] : d; };
const ORE_GIORNATA = Number(opt('ore', 8));   // oltre = non fattibile in giornata
const ORE_PER_GIORNO = 6;                     // convenzione per stimare i giorni

/// Parole di FATICA finite nel campo della scala tecnica, arrivate dalle
/// autovalutazioni degli utenti via promoteFromCommunityTrack. Ora che
/// l'impegno ha un campo suo, li' dentro non hanno piu' ragione di stare:
/// non sono gradi CAI e non lo sono mai stati.
const PAROLE_FATICA = new Set(['facile', 'media', 'medio', 'difficile']);

/// Passo per tipo di attivita': [km/h in piano, m/h in salita].
///
/// Applicare la velocita' di un camminatore a un'uscita in bici gonfia il
/// tempo di tre o quattro volte: un giro di 46 km in eMTB diventava "12 ore,
/// ~3 giorni" invece di un pomeriggio. E' lo stesso errore di categoria che
/// stiamo smontando da giorni — un modello applicato a una popolazione per
/// cui non e' stato pensato.
const PASSO = {
  trekking: [4, 400],
  walking: [4, 400],
  escursionismo: [4, 400],
  running: [8, 600],
  trailRunning: [8, 600],
  cycling: [15, 600],
  gravelBiking: [13, 600],
  eBike: [16, 750],
  eMountainBike: [13, 750],
  mountainBiking: [11, 600],
  skiTouring: [3.5, 350],
  snowshoeing: [3, 300],
  nordicSkiing: [8, 400],
  alpineSkiing: [10, 500],
  snowboarding: [10, 500],
};

/// Formula escursionistica classica (DIN 33466 / SAC), con il passo scelto
/// in base all'attivita': si somma il maggiore fra tempo orizzontale e
/// verticale piu' meta' del minore.
function oreDiPercorrenza(km, gain, attivita) {
  const [vOriz, vVert] = PASSO[attivita] || PASSO.trekking;
  const orizzontale = km / vOriz;
  const verticale = (gain || 0) / vVert;
  return Math.max(orizzontale, verticale) + Math.min(orizzontale, verticale) / 2;
}

(async () => {
  console.log(DRY ? '=== SIMULAZIONE ===\n' : '=== SCRITTURA ===\n');
  const snap = await db.collection('public_trails').get();

  const daFare = [];
  const livelli = { t1: 0, t2: 0, t3: 0, t4: 0, t5: 0 };
  const giorni = {};
  let piuGiorni = 0, senzaDati = 0, paroleTolte = 0;
  const esempi = [];

  snap.forEach((d) => {
    const x = d.data();
    const km = (x.distance || 0) / 1000;
    const gain = Number(x.elevationGain);
    if (!km || !Number.isFinite(gain)) { senzaDati++; return; }

    const ore = oreDiPercorrenza(km, gain, x.activityType);
    const upd = { oreStimate: Math.round(ore * 10) / 10 };

    if (ore > ORE_GIORNATA) {
      const gg = Math.ceil(ore / ORE_PER_GIORNO);
      upd.piuGiorni = true;
      upd.giorniStimati = gg;
      // Niente livello: su un cammino di settimane non significherebbe nulla.
      upd.computedDifficulty = admin.firestore.FieldValue.delete();
      piuGiorni++;
      giorni[gg] = (giorni[gg] || 0) + 1;
      if (esempi.length < 8 && gg >= 3) {
        esempi.push({ n: String(x.name).slice(0, 40), km, ore, gg });
      }
    } else {
      const r = compute({
        distance: x.distance,
        elevationGain: gain,
        elevationLoss: Number.isFinite(Number(x.elevationLoss)) ? Number(x.elevationLoss) : undefined,
      }, x.activityType);
      if (!r) { senzaDati++; return; }
      upd.computedDifficulty = r.key;
      upd.piuGiorni = false;
      livelli[r.key]++;
    }

    // Le parole di fatica lasciano il campo tecnico: ora hanno casa altrove.
    if (PAROLE_FATICA.has(String(x.difficulty || '').toLowerCase())
        && !x.difficultySource) {
      upd.difficulty = admin.firestore.FieldValue.delete();
      paroleTolte++;
    }

    daFare.push({ ref: d.ref, upd });
  });

  const tot = Object.values(livelli).reduce((s, v) => s + v, 0);
  console.log('impegno per le uscite in giornata:');
  for (const k of ['t1', 't2', 't3', 't4', 't5']) {
    console.log(`  ${k.toUpperCase()}  ${String(livelli[k]).padStart(6)}  (${(100 * livelli[k] / (tot || 1)).toFixed(1)}%)`);
  }
  console.log(`\nitinerari di piu' giorni (nessun livello): ${piuGiorni}`);
  Object.entries(giorni).sort((a, b) => a[0] - b[0]).slice(0, 8)
    .forEach(([g, n]) => console.log(`  ~${g} giorni: ${n}`));
  console.log(`\nparole di fatica tolte dal campo tecnico: ${paroleTolte}`);
  console.log(`senza dati sufficienti:                  ${senzaDati}`);
  console.log(`documenti da aggiornare:                 ${daFare.length}`);

  if (esempi.length) {
    console.log('\nesempi di piu\' giorni:');
    esempi.forEach((e) => console.log(
      `  ${e.n.padEnd(42)} ${e.km.toFixed(0).padStart(5)} km  ${e.ore.toFixed(0).padStart(4)} h  ~${e.gg} giorni`));
  }

  if (DRY) { console.log('\nNessuna scrittura. Per applicare, togliere --dry.'); process.exit(0); }

  let n = 0;
  for (let i = 0; i < daFare.length; i += 400) {
    const batch = db.batch();
    for (const it of daFare.slice(i, i + 400)) batch.update(it.ref, it.upd);
    await batch.commit();
    n += Math.min(400, daFare.length - i);
    if (n % 4000 === 0 || n === daFare.length) console.log(`  ${n}/${daFare.length}`);
  }
  console.log(`\nFatto: ${n} sentieri con impegno e tempo di percorrenza.`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
