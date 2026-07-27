// Funnel Garmin: pairing creati vs sync reali. READ-ONLY.
const admin = require('firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

(async () => {
  // 1. Pairing (token creati)
  const pairSnap = await db.collection('garmin_pairings').get();
  const uids = new Set();
  let pairDocs = 0;
  let sampleShown = false;
  pairSnap.forEach((d) => {
    pairDocs++;
    const data = d.data();
    if (!sampleShown) {
      console.log('  (campi doc pairing:', Object.keys(data).join(', '), ')');
      sampleShown = true;
    }
    const uid = data.uid || data.userId || data.ownerId || data.user;
    if (uid) uids.add(uid);
  });

  // 2. Utenti col campo garminPairingToken (altro segnale di pairing)
  const withTokenSnap = await db.collection('users').where('garminPairingToken', '!=', null).get().catch(() => null);
  const withTokenCount = withTokenSnap ? withTokenSnap.size : 'n/d (serve indice)';

  // 3. Sync reali: tracce source='garmin' per ogni utente con pairing
  let totalGarminTracks = 0;
  const usersWithSync = new Set();
  for (const uid of uids) {
    const snap = await db
      .collection('users').doc(uid).collection('tracks')
      .where('source', '==', 'garmin').get();
    if (snap.size > 0) {
      usersWithSync.add(uid);
      totalGarminTracks += snap.size;
    }
  }

  // 4. Totale utenti (contesto)
  const usersTotal = (await db.collection('users').count().get()).data().count;

  console.log('\n===== FUNNEL GARMIN =====');
  console.log(`Utenti totali (users): ${usersTotal}`);
  console.log(`Pairing token creati (garmin_pairings): ${pairDocs}`);
  console.log(`Utenti distinti con pairing: ${uids.size}`);
  console.log(`Utenti col campo garminPairingToken: ${withTokenCount}`);
  console.log(`Utenti che hanno DAVVERO syncato >=1 traccia Garmin: ${usersWithSync.size}`);
  console.log(`Tracce Garmin totali syncate: ${totalGarminTracks}`);
  console.log('\n--- Netto (tolti te + nipote = 2) ---');
  console.log(`Pairing esterni: ${Math.max(0, uids.size - 2)}`);
  console.log(`Utenti con sync esterni: ${Math.max(0, usersWithSync.size - 2)}`);

  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
