// Toglie dalle classifiche gli sforzi con attivita' incompatibile.
//
// Il confronto ignorava il tipo di attivita': una pedalata in e-bike entrava
// nella classifica di un segmento di corsa, e vincendo sempre — in bici si va
// molto piu' forte — trasformava ogni passaggio in un "record personale".
// Su 16 sforzi registrati, 13 erano cosi'.
//
// NON CANCELLA: marca `activityMismatch: true`. Il dato resta, e se la
// famiglia di attivita' verra' rivista bastera' togliere il marchio invece
// di aver perso tutto. Le query di classifica dovranno escluderli.
//
// Uso:
//   node scripts/segment_efforts_cleanup.cjs --dry
//   node scripts/segment_efforts_cleanup.cjs
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const { attivitaCompatibili } = require('../functions/segment_matching');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();
const DRY = process.argv.includes('--dry');

(async () => {
  console.log(DRY ? '=== SIMULAZIONE ===\n' : '=== SCRITTURA ===\n');
  const segs = await db.collection('segments').get();
  let tot = 0, marcati = 0;

  for (const d of segs.docs) {
    const seg = d.data();
    const eff = await d.ref.collection('efforts').get();
    for (const e of eff.docs) {
      const y = e.data();
      tot++;
      if (!y.userId || !y.trackId) continue;
      const t = await db.collection('users').doc(y.userId)
        .collection('tracks').doc(y.trackId).get();
      if (!t.exists) continue;
      const att = t.data().activityType;
      if (attivitaCompatibili(att, seg.activityType)) continue;
      marcati++;
      console.log(`${DRY ? '·' : '✓'} ${String(seg.name).slice(0, 26).padEnd(28)} ` +
        `${String(att).padEnd(14)} su segmento ${String(seg.activityType).padEnd(12)} ` +
        `${String(y.durationSeconds).padStart(4)}s  ${y.username}`);
      if (!DRY) {
        await e.ref.update({ activityMismatch: true, trackActivityType: att || null });
      }
    }
  }
  console.log(`\nsforzi esaminati: ${tot}`);
  console.log(`${DRY ? 'da marcare' : 'marcati'}: ${marcati}`);
  if (DRY) console.log('\nNessuna scrittura. Per applicare, togliere --dry.');
  else console.log('\nLe classifiche devono ora escludere activityMismatch == true.');
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
