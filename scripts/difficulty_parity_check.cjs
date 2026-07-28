// Prova di fedelta' del porting JS della difficolta' computata.
//
// Ricalcola con functions/difficulty_calculator.js le tracce che hanno gia'
// un `computedDifficulty` scritto dal codice Dart, e confronta.
//
// Da rieseguire ogni volta che si tocca UNO dei due calcolatori: sono
// gemelli, e questa e' l'unica cosa che se ne accorge se divergono.
//
// NOTA sul dato mancante: i doc di published_tracks non conservano
// `elevationLoss` (4 su 233 ce l'hanno). Senza discesa il bonus discesa
// vale 0, e le tappe che scendono molto piu' di quanto salgono risultano
// un livello sotto. Non e' una divergenza del porting: e' un ingresso
// assente. Il controllo le isola verificando se un bonus discesa pieno
// (+30, il tetto della formula) riconcilierebbe il risultato.
//
// NON ricavare la discesa sommando i punti grezzi: il rumore GPS la
// gonfia di parecchio. Il dislivello vero passa da elevation_processor
// (filtro mediano, despiking, smoothing, isteresi) e nei documenti e' gia'
// calcolato — quando c'e' va letto, non ricostruito.
//
// Uso:
//   node scripts/difficulty_parity_check.cjs
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const { compute } = require('../functions/difficulty_calculator');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const BONUS_MAX = 30; // tetto del bonus discesa nella formula

(async () => {
  const snap = await db.collection('published_tracks').get();
  let confrontate = 0, uguali = 0;
  const spiegate = [], diverse = [];

  snap.forEach((d) => {
    const x = d.data();
    const atteso = x.computedDifficulty;
    if (!atteso) return;
    confrontate++;

    const lossNoto = Number.isFinite(Number(x.elevationLoss));
    const base = { distance: x.distance, elevationGain: x.elevationGain };
    const res = compute(
      lossNoto ? { ...base, elevationLoss: Number(x.elevationLoss) } : base,
      x.activityType);

    if (res && res.key === atteso) { uguali++; return; }

    const riga = {
      nome: String(x.name || x.title || d.id).slice(0, 36),
      attivita: String(x.activityType),
      km: (x.distance / 1000).toFixed(1),
      gain: Math.round(x.elevationGain || 0),
      atteso,
      ottenuto: res ? res.key : 'null',
      score: res ? res.score.toFixed(1) : '—',
    };

    // Discesa ignota: il bonus pieno riconcilierebbe? Si satura mettendo
    // una discesa tale che (loss - gain) / km superi il tetto.
    if (!lossNoto && res) {
      const conBonus = compute({
        ...base,
        elevationLoss: Number(x.elevationGain) + BONUS_MAX * (x.distance / 1000),
      }, x.activityType);
      if (conBonus && conBonus.key === atteso) { spiegate.push(riga); return; }
    }
    diverse.push(riga);
  });

  const stampa = (titolo, righe) => {
    if (!righe.length) return;
    console.log(`\n${titolo}`);
    console.log('  ' + 'nome'.padEnd(38) + 'attivita'.padEnd(15) +
      'km'.padStart(7) + 'D+'.padStart(7) + '  atteso'.padEnd(9) + 'ottenuto'.padStart(9) + 'score'.padStart(8));
    for (const r of righe) {
      console.log('  ' + r.nome.padEnd(38) + r.attivita.padEnd(15) +
        r.km.padStart(7) + String(r.gain).padStart(7) +
        ('  ' + r.atteso).padEnd(9) + r.ottenuto.padStart(9) + r.score.padStart(8));
    }
  };

  console.log(`confrontate:                    ${confrontate}`);
  console.log(`coincidono:                     ${uguali}`);
  console.log(`spiegate dalla discesa assente: ${spiegate.length}`);
  console.log(`DIVERGENTI DAVVERO:             ${diverse.length}`);

  stampa('spiegate dalla discesa assente (non e\' il porting):', spiegate);
  stampa('DIVERGENTI — da capire prima di usare il modulo:', diverse);

  console.log(diverse.length === 0
    ? `\nPORTING FEDELE: ${uguali}/${confrontate} identiche, ` +
      `${spiegate.length} riconciliate dal bonus discesa, 0 divergenze.`
    : `\nATTENZIONE: ${diverse.length} divergenze reali.`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
