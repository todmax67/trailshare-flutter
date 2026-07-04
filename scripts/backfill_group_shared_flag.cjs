#!/usr/bin/env node
/**
 * Backfill: popola `isGroupShared` (bool) sulle tracce ESISTENTI che hanno
 * già `groupIds` non vuoto (condivise a un gruppo PRIMA che il flag venisse
 * introdotto). Serve a stringere in futuro la lettura cross-utente delle
 * tracce (oggi aperta a chiunque autenticato) senza rompere il tab Percorsi
 * dei gruppi — vedi audit sicurezza #4.
 *
 * Idempotente: salta le tracce che hanno già isGroupShared === true.
 * Scansiona collectionGroup('tracks') — non serve conoscere gli utenti.
 *
 *   node scripts/backfill_group_shared_flag.cjs           # dry-run
 *   node scripts/backfill_group_shared_flag.cjs --apply   # applica
 */
const admin = require('firebase-admin');
const serviceAccount = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');

(async () => {
  const snap = await db.collectionGroup('tracks').get();
  let scanned = 0;
  let toBackfill = 0;
  let applied = 0;

  for (const doc of snap.docs) {
    scanned++;
    const data = doc.data();
    const groupIds = data.groupIds || [];
    if (groupIds.length === 0) continue;
    if (data.isGroupShared === true) continue; // già a posto

    toBackfill++;
    console.log(`${APPLY ? 'APPLY' : 'DRY-RUN'}: ${doc.ref.path} groupIds=${JSON.stringify(groupIds)}`);
    if (APPLY) {
      await doc.ref.update({ isGroupShared: true });
      applied++;
    }
  }

  console.log(`\nScansionate: ${scanned}, da backfillare: ${toBackfill}, applicate: ${applied}`);
  if (!APPLY && toBackfill > 0) {
    console.log('Dry-run: nessuna scrittura. Rilancia con --apply per applicare.');
  }
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
