#!/usr/bin/env node
/**
 * STEP 5 — Backfill: migra i punti GPS delle tracce dal formato INLINE
 * (campo `points` nel doc traccia) alla sub-collezione geometria
 * users/{uid}/tracks/{trackId}/geometry/data (campo `pointsJson`), e rimuove
 * i punti inline dal doc principale per risolvere l'OOM.
 *
 * Per traccia (batch atomico): scrive geometry/data {pointsJson, pointsCount,
 * heartRateData?} + aggiorna il doc principale {hasGeometryDoc:true,
 * pointsCount, points:DELETE, heartRateData:DELETE}.
 * Idempotente: salta le tracce già migrate (hasGeometryDoc === true).
 * Il reader Dart (_parsePointsList) tollera i vari formati di punto, quindi i
 * punti vengono copiati così come sono in pointsJson — nessuna normalizzazione.
 *
 * ⚠️ SEQUENZA: applicare SOLO dopo che la nuova app (che legge la geometria) è
 * rilasciata e adottata. Rimuovere i punti inline rompe le app vecchie.
 *
 *   node scripts/backfill_track_geometry.cjs                 # dry-run TUTTI
 *   node scripts/backfill_track_geometry.cjs --uid <UID>     # dry-run 1 utente
 *   node scripts/backfill_track_geometry.cjs --uid <UID> --apply
 *   node scripts/backfill_track_geometry.cjs --apply         # APPLY a tutti
 */
const admin = require('firebase-admin');
const serviceAccount = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();
const { FieldValue } = admin.firestore;

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null;
}
const APPLY = process.argv.includes('--apply');
const ONLY_UID = arg('--uid');
// --limit N: migra al massimo N tracce (per un collaudo a raggio ridotto).
const LIMIT = arg('--limit') ? parseInt(arg('--limit'), 10) : Infinity;
let appliedCount = 0;

async function migrateUserTracks(uid) {
  const snap = await db.collection('users').doc(uid).collection('tracks').get();
  let toMigrate = 0, migrated = 0, alreadyDone = 0, noPoints = 0, samplePts = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.hasGeometryDoc === true) { alreadyDone++; continue; }
    const points = Array.isArray(data.points) ? data.points : [];
    if (points.length === 0) { noPoints++; continue; }
    toMigrate++;
    samplePts += points.length;

    if (!APPLY) continue;
    if (appliedCount >= LIMIT) continue; // raggiunto il --limit

    const geoRef = doc.ref.collection('geometry').doc('data');
    const geoData = {
      pointsJson: JSON.stringify(points),
      pointsCount: points.length,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (data.heartRateData && Object.keys(data.heartRateData).length > 0) {
      geoData.heartRateData = data.heartRateData;
    }
    const batch = db.batch();
    batch.set(geoRef, geoData);
    batch.update(doc.ref, {
      hasGeometryDoc: true,
      pointsCount: points.length,
      points: FieldValue.delete(),
      heartRateData: FieldValue.delete(),
    });
    await batch.commit();
    migrated++;
    appliedCount++;
  }
  return { total: snap.size, toMigrate, migrated, alreadyDone, noPoints, samplePts };
}

(async () => {
  console.log(APPLY ? '=== APPLY ===' : '=== DRY-RUN (nessuna scrittura) ===');
  let uids;
  if (ONLY_UID) {
    uids = [ONLY_UID];
  } else {
    const usersSnap = await db.collection('users').get();
    uids = usersSnap.docs.map((d) => d.id);
  }
  console.log(`Utenti da scandire: ${uids.length}`);

  let totTracks = 0, totMigrate = 0, totMigrated = 0, totDone = 0, totNoPts = 0, totPts = 0;
  for (const uid of uids) {
    const r = await migrateUserTracks(uid);
    totTracks += r.total; totMigrate += r.toMigrate; totMigrated += r.migrated;
    totDone += r.alreadyDone; totNoPts += r.noPoints; totPts += r.samplePts;
    if (r.toMigrate > 0 || r.migrated > 0) {
      console.log(`  ${uid.slice(0, 8)}…  tracce=${r.total}  da-migrare=${r.toMigrate}` +
        (APPLY ? `  migrate=${r.migrated}` : '') +
        `  già=${r.alreadyDone}  senza-punti=${r.noPoints}`);
    }
  }
  console.log('\n── TOTALI ──');
  console.log(`Tracce totali:            ${totTracks}`);
  console.log(`Da migrare:               ${totMigrate}`);
  if (APPLY) console.log(`Migrate (scritte):        ${totMigrated}`);
  console.log(`Già migrate (saltate):    ${totDone}`);
  console.log(`Senza punti (saltate):    ${totNoPts}`);
  if (totMigrate > 0) {
    console.log(`Punti medi/traccia:       ${Math.round(totPts / totMigrate)}`);
  }
  if (!APPLY && totMigrate > 0) {
    console.log('\n[DRY-RUN] Rilancia con --apply per migrare. ⚠️ Solo dopo il rilascio app!');
  }
})().catch((e) => { console.error(e); process.exit(1); });
