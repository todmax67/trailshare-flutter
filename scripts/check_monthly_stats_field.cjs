// Verifica READ-ONLY: monthlyDistanceCurrent/monthlyStatsMonthId/totalElevation
// sono MAI stati scritti su user_profiles? (sospetto: rules li rifiutano)
const admin = require('firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

(async () => {
  const snap = await db.collection('user_profiles').get();
  let withMonthlyStatsMonthId = 0;
  let withMonthlyDistanceCurrent = 0;
  let withTotalElevation = 0;
  let withLastTrackAt = 0;
  let withTotalDistance = 0;
  let withTotalTracks = 0;
  let withXp = 0;
  snap.forEach((d) => {
    const data = d.data();
    if (data.monthlyStatsMonthId !== undefined) withMonthlyStatsMonthId++;
    if (data.monthlyDistanceCurrent !== undefined) withMonthlyDistanceCurrent++;
    if (data.totalElevation !== undefined) withTotalElevation++;
    if (data.lastTrackAt !== undefined) withLastTrackAt++;
    if (data.totalDistance !== undefined) withTotalDistance++;
    if (data.totalTracks !== undefined) withTotalTracks++;
    if (data.xp !== undefined) withXp++;
  });
  console.log(`Profili totali: ${snap.size}`);
  console.log(`Con monthlyStatsMonthId: ${withMonthlyStatsMonthId}`);
  console.log(`Con monthlyDistanceCurrent: ${withMonthlyDistanceCurrent}`);
  console.log(`Con totalElevation (non totalElevationGain): ${withTotalElevation}`);
  console.log(`Con lastTrackAt: ${withLastTrackAt}`);
  console.log(`Con totalDistance: ${withTotalDistance}`);
  console.log(`Con totalTracks: ${withTotalTracks}`);
  console.log(`Con xp: ${withXp}`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
