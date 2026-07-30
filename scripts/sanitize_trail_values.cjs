// Rimuove dal catalogo i valori numerici impossibili.
//
// PERCHE': alcune schede importate a dicembre 2025 portano sentinelle di
// float32 al posto delle quote — `Vier-Berge-Weg` ha elevationGain 1.7e+39 e
// minAltitude -3.4028234663852886e+38, che e' esattamente -Float.MAX_VALUE.
// Sono numeri che nessuna UI sa disegnare: un grafico con un asse a 1e+39
// schiaccia tutto il resto a una riga piatta, e un "~7e+35 giorni" nella
// scheda e' peggio di nessun dato.
//
// SCELTA: i campi sballati si CANCELLANO, non si azzerano. Zero direbbe
// "pianeggiante", che e' un'informazione falsa; assente dice "non lo sappiamo",
// che e' la verita' — la geometria di queste schede ha tutte le quote a zero.
//
// A CASCATA: se salta elevationGain se ne vanno anche difficolta' e tempi, che
// da quel valore derivano (gainPerKm in DifficultyCalculator, DIN 33466 in
// oreStimate). Lasciarli sarebbe peggio: numeri plausibili calcolati sul nulla.
//
// Uso:
//   node scripts/sanitize_trail_values.cjs            (dry-run)
//   node scripts/sanitize_trail_values.cjs --apply
const path = require('path');
const admin = require(path.join(__dirname, '../functions/node_modules/firebase-admin'));
const sa = require(path.join(__dirname, '../functions/serviceAccountKey.json'));

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();
const APPLY = process.argv.includes('--apply');
const DEL = admin.firestore.FieldValue.delete();

/// Intervalli oltre i quali il valore non descrive più un sentiero terrestre.
/// Larghi di proposito: qui si cercano dati corrotti, non outlier plausibili.
/// Il Sentiero Italia con 125.872 m di dislivello su 10.291 km e' un numero
/// vero, per quanto enorme, e non va toccato.
const LIMITI = {
  elevationGain: [0, 200000],
  elevationLoss: [0, 200000],
  minAltitude: [-500, 9000],   // Mar Morto -430, Everest 8849
  maxAltitude: [-500, 9000],
  oreStimate: [0, 20000],
  giorniStimati: [0, 4000],
  distance: [0, 50000000],     // 50.000 km
};

const fuoriScala = (v, [min, max]) =>
  typeof v === 'number' && (!Number.isFinite(v) || v < min || v > max);

(async () => {
  console.log(APPLY ? '*** APPLY: scrive su Firestore ***\n' : 'dry-run (nessuna scrittura)\n');

  const snap = await db.collection('public_trails')
    .select(...Object.keys(LIMITI), 'name', 'region', 'computedDifficulty', 'piuGiorni', 'importedAt')
    .get();

  const malati = [];
  snap.forEach(d => {
    const x = d.data();
    const rotti = [];
    for (const [campo, range] of Object.entries(LIMITI)) {
      if (fuoriScala(x[campo], range)) rotti.push(campo);
    }
    if (rotti.length) malati.push({ id: d.id, ref: d.ref, x, rotti });
  });

  console.log(`Schede esaminate: ${snap.size}`);
  console.log(`Con valori impossibili: ${malati.length}\n`);
  if (!malati.length) { console.log('Niente da sanificare.'); process.exit(0); }

  let sistemate = 0;
  for (const m of malati) {
    const upd = {};
    for (const campo of m.rotti) upd[campo] = DEL;

    // Difficoltà e tempi derivano dal dislivello: se quello non c'è, non
    // possono restare.
    const perdeDislivello = m.rotti.includes('elevationGain') || m.rotti.includes('distance');
    if (perdeDislivello) {
      if (m.x.computedDifficulty !== undefined) upd.computedDifficulty = DEL;
      if (m.x.oreStimate !== undefined) upd.oreStimate = DEL;
      if (m.x.giorniStimati !== undefined) upd.giorniStimati = DEL;
      if (m.x.piuGiorni !== undefined) upd.piuGiorni = DEL;
    }
    upd.valuesSanitizedAt = admin.firestore.FieldValue.serverTimestamp();

    const valori = m.rotti
      .map(c => `${c}=${String(m.x[c]).slice(0, 16)}`)
      .join('  ');
    console.log(`${String(m.x.name || '?').slice(0, 34).padEnd(36)} [${m.id}]`);
    console.log(`   impossibili: ${valori}`);
    console.log(`   si cancellano: ${Object.keys(upd).filter(k => k !== 'valuesSanitizedAt').join(', ')}`);
    console.log(`   importata il ${m.x.importedAt?.toDate?.().toISOString?.().slice(0, 10) || '?'}`);

    if (APPLY) {
      await m.ref.update(upd);
      console.log(`   ✔ sanificata`);
    }
    sistemate++;
  }

  console.log(`\n=== ${APPLY ? 'SCRITTO' : 'SIMULATO'} ===`);
  console.log(`${APPLY ? 'sanificate' : 'da sanificare'}: ${sistemate}`);
  if (!APPLY) console.log(`\nNiente scritto. Rilancia con --apply.`);
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
