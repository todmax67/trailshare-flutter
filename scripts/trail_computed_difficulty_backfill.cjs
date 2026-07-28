// Backfill di `computedDifficulty` sul catalogo public_trails.
//
// Scrive l'IMPEGNO calcolato (T1..T5), che e' cosa diversa dalla difficolta'
// tecnica CAI: il primo si deduce da distanza, dislivello e tipo di
// attivita', la seconda descrive il terreno e si puo' solo rilevare. Il
// campo `difficulty` NON viene toccato da questo script.
//
// Usa functions/difficulty_calculator.js, gemello del Dart: la fedelta' e'
// verificata da scripts/difficulty_parity_check.cjs.
//
// Uso:
//   node scripts/trail_computed_difficulty_backfill.cjs --dry     (simulazione)
//   node scripts/trail_computed_difficulty_backfill.cjs           (scrive)
//   node scripts/trail_computed_difficulty_backfill.cjs --dry --limit 500
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const { compute } = require('../functions/difficulty_calculator');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const DRY = argv.includes('--dry');
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 ? argv[i + 1] : d; };
const LIMIT = Number(opt('limit', 0)) || Infinity;

/// Ripartizione dichiarata nel Dart come obiettivo della taratura, misurata
/// sulle tracce registrate dagli utenti. Il catalogo OSM e' un'altra
/// popolazione (contiene traversate da 2000 km): se la distribuzione si
/// discosta molto, la taratura non regge qui e va rivista PRIMA di scrivere.
const ATTESA = { t1: 15, t2: 15, t3: 40, t4: 25, t5: 5 };

const NOTI = ['Via del Sale', 'Sentiero Italia', 'Jakobsweg Österreich',
  'Steirischer Landesrund', 'Sentiero del Brigante', 'Tour Monte Rosa',
  'Grande Circuito della Romagna'];

(async () => {
  console.log(DRY ? '=== SIMULAZIONE: non scrivo niente ===\n' : '=== SCRITTURA ===\n');
  const snap = await db.collection('public_trails').get();

  const dist = { t1: 0, t2: 0, t3: 0, t4: 0, t5: 0 };
  const incrocio = {};           // difficulty attuale -> { t1..t5 }
  const esempi = [];
  const estremi = [];
  let tot = 0, calcolati = 0, saltati = 0, senzaLoss = 0, giaPresente = 0;
  const daScrivere = [];

  snap.forEach((d) => {
    const x = d.data();
    tot++;
    if (x.computedDifficulty) giaPresente++;

    const gain = Number(x.elevationGain);
    const distanza = Number(x.distance);
    if (!Number.isFinite(gain) || !Number.isFinite(distanza)) { saltati++; return; }
    const lossNoto = Number.isFinite(Number(x.elevationLoss));
    if (!lossNoto) senzaLoss++;

    const res = compute({
      distance: distanza,
      elevationGain: gain,
      elevationLoss: lossNoto ? Number(x.elevationLoss) : undefined,
    }, x.activityType);
    if (!res) { saltati++; return; }

    calcolati++;
    dist[res.key]++;

    const attuale = x.difficulty || '(vuoto)';
    incrocio[attuale] = incrocio[attuale] || { t1: 0, t2: 0, t3: 0, t4: 0, t5: 0 };
    incrocio[attuale][res.key]++;

    const km = distanza / 1000;
    estremi.push({ km, nome: String(x.name), key: res.key, score: res.score, attuale });
    if (NOTI.some((n) => String(x.name).startsWith(n)) && esempi.length < 12) {
      esempi.push({ nome: String(x.name).slice(0, 36), km, gain: Math.round(gain),
        attuale, nuovo: res.code, score: res.score });
    }
    if (daScrivere.length < LIMIT) daScrivere.push({ ref: d.ref, key: res.key });
  });

  console.log(`sentieri totali:            ${tot}`);
  console.log(`calcolabili:                ${calcolati}`);
  console.log(`saltati (dati insufficienti): ${saltati}`);
  console.log(`senza elevationLoss (bonus discesa a 0): ${senzaLoss}`);
  console.log(`avevano gia' computedDifficulty: ${giaPresente}`);

  console.log('\n=== ripartizione che verrebbe scritta ===');
  console.log('livello        quanti      %     attesa dal Dart   scarto');
  for (const k of ['t1', 't2', 't3', 't4', 't5']) {
    const pct = 100 * dist[k] / calcolati;
    const scarto = pct - ATTESA[k];
    const allarme = Math.abs(scarto) > 20 ? '   <-- fuori scala' : '';
    console.log(`${k.toUpperCase().padEnd(8)}${String(dist[k]).padStart(10)}` +
      `${pct.toFixed(1).padStart(8)}%${String(ATTESA[k]).padStart(14)}%` +
      `${(scarto >= 0 ? '+' : '') + scarto.toFixed(1)}`.padStart(10) + allarme);
  }

  console.log('\n=== incrocio con la difficolta\' attuale ===');
  console.log('attuale'.padEnd(12) + ['T1', 'T2', 'T3', 'T4', 'T5'].map((s) => s.padStart(7)).join(''));
  Object.entries(incrocio)
    .sort((a, b) => Object.values(b[1]).reduce((s, v) => s + v, 0)
                  - Object.values(a[1]).reduce((s, v) => s + v, 0))
    .slice(0, 8)
    .forEach(([k, v]) => {
      console.log(k.padEnd(12) + ['t1', 't2', 't3', 't4', 't5']
        .map((t) => String(v[t]).padStart(7)).join(''));
    });

  if (esempi.length) {
    console.log('\n=== casi noti ===');
    console.log('  ' + 'nome'.padEnd(38) + 'km'.padStart(8) + 'D+'.padStart(8) +
      '  attuale'.padEnd(12) + 'impegno'.padStart(9) + 'score'.padStart(8));
    esempi.sort((a, b) => b.km - a.km).forEach((e) => {
      console.log('  ' + e.nome.padEnd(38) + e.km.toFixed(0).padStart(8) +
        String(e.gain).padStart(8) + ('  ' + e.attuale).padEnd(12) +
        e.nuovo.padStart(9) + e.score.toFixed(0).padStart(8));
    });
  }

  estremi.sort((a, b) => b.km - a.km);
  console.log('\n=== i 6 percorsi piu\' lunghi (dove la taratura si vede) ===');
  estremi.slice(0, 6).forEach((e) => {
    console.log(`  ${e.km.toFixed(0).padStart(6)} km  ${e.key.toUpperCase()}  ` +
      `score ${e.score.toFixed(0).padStart(5)}  ${e.nome.slice(0, 44)}`);
  });

  if (DRY) {
    console.log('\nSimulazione conclusa: nessuna scrittura. Per scrivere, togliere --dry.');
    process.exit(0);
  }

  console.log(`\nScrivo ${daScrivere.length} documenti…`);
  let scritti = 0;
  for (let i = 0; i < daScrivere.length; i += 400) {
    const batch = db.batch();
    for (const w of daScrivere.slice(i, i + 400)) {
      batch.update(w.ref, { computedDifficulty: w.key });
    }
    await batch.commit();
    scritti += Math.min(400, daScrivere.length - i);
    console.log(`  ${scritti}/${daScrivere.length}`);
  }
  console.log(`\nFatto: ${scritti} sentieri con l'impegno calcolato.`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
