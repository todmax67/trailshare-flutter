// Verifica che functions/elevation_processor.js dia gli STESSI numeri della
// classe Dart lib/core/utils/elevation_processor.dart.
//
// Senza questo controllo la porta JS e' una supposizione: la pipeline ha un
// filtro mediano, una rimozione spike con effetto a cascata e una media
// mobile ponderata, e basta un `~/` tradotto male per divergere.
//
// Prerequisiti (i due file di lavoro):
//   /tmp/trailshare_backfill/cmp_in.json   quote reali del catalogo
//   /tmp/trailshare_backfill/cmp_out.json  risultati della classe Dart
//     prodotti da: dart run scripts/compare_dplus.dart cmp_in.json cmp_out.json
//
// Uso: node scripts/validate_elevation_port.cjs
const fs = require('fs');
const path = require('path');
const ep = require(path.join(__dirname, '../functions/elevation_processor'));

const DIR = process.env.BACKFILL_DIR || '/tmp/trailshare_backfill';
const TOLLERANZA = 1; // metro: differenze solo da arrotondamento

const input = JSON.parse(fs.readFileSync(path.join(DIR, 'cmp_in.json'), 'utf8'));
const dart = JSON.parse(fs.readFileSync(path.join(DIR, 'cmp_out.json'), 'utf8'));

let confrontati = 0, identici = 0;
const divergenti = [];
let maxScarto = 0;

for (const [id, m] of Object.entries(input)) {
  const rif = dart[id];
  if (!rif) continue;
  const eles = m.eles.map(v => (v === null ? null : Number(v)));
  const js = ep.process(eles, m.activity);
  if (!js) continue;
  confrontati++;

  const dGain = Math.abs(Math.round(js.elevationGain) - rif.processor);
  const dLoss = Math.abs(Math.round(js.elevationLoss) - rif.processorLoss);
  const dMin = Math.abs(Math.round(js.minElevation) - rif.min);
  const dMax = Math.abs(Math.round(js.maxElevation) - rif.max);
  const peggio = Math.max(dGain, dLoss, dMin, dMax);
  maxScarto = Math.max(maxScarto, peggio);

  if (peggio <= TOLLERANZA) identici++;
  else if (divergenti.length < 10) {
    divergenti.push({ id, dGain, dLoss, dMin, dMax,
      js: Math.round(js.elevationGain), dart: rif.processor, punti: rif.punti });
  }
}

console.log(`Confrontati:            ${confrontati}`);
console.log(`Entro ${TOLLERANZA} m (ok):        ${identici}  (${(100 * identici / confrontati).toFixed(1)}%)`);
console.log(`Divergenti:             ${confrontati - identici}`);
console.log(`Scarto massimo:         ${maxScarto} m`);

if (divergenti.length) {
  console.log(`\nEsempi di divergenza:`);
  console.log('id                            punti     JS   Dart  dGain dLoss dMin dMax');
  divergenti.forEach(d => console.log(
    `${d.id.padEnd(28)} ${String(d.punti).padStart(6)} ${String(d.js).padStart(6)} ${String(d.dart).padStart(6)} ` +
    `${String(d.dGain).padStart(6)} ${String(d.dLoss).padStart(5)} ${String(d.dMin).padStart(4)} ${String(d.dMax).padStart(4)}`));
}

const ok = confrontati > 0 && identici === confrontati;
console.log(`\n${ok ? '✔ PORTA VALIDATA — si puo usare per il ricalcolo'
                    : '✘ PORTA NON FEDELE — NON usarla, va corretta'}`);
process.exit(ok ? 0 : 1);
