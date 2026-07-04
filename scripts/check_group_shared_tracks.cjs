// Verifica READ-ONLY: quante tracce hanno oggi groupIds non vuoto (candidate
// al backfill isGroupShared)? Scansiona collectionGroup('tracks').
const admin = require('firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

(async () => {
  const snap = await db.collectionGroup('tracks').get();
  let total = 0;
  let withGroupIds = 0;
  let withIsGroupShared = 0;
  let mismatch = 0;
  snap.forEach((d) => {
    total++;
    const data = d.data();
    const groupIds = data.groupIds || [];
    if (groupIds.length > 0) withGroupIds++;
    if (data.isGroupShared !== undefined) withIsGroupShared++;
    if (groupIds.length > 0 && data.isGroupShared !== true) mismatch++;
  });
  console.log(`Tracce totali: ${total}`);
  console.log(`Con groupIds non vuoto: ${withGroupIds}`);
  console.log(`Con isGroupShared già scritto: ${withIsGroupShared}`);
  console.log(`Da backfillare (groupIds non vuoto MA isGroupShared!=true): ${mismatch}`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
