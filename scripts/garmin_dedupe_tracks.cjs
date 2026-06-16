#!/usr/bin/env node
/**
 * Pulizia tracce Garmin duplicate (create prima del fix idempotenza).
 *
 * Le vecchie app inviavano senza clientId: se l'ACK BLE si perdeva, l'orologio
 * ritentava e il server creava una copia ad ogni tentativo (es. 3 tracce
 * identiche "TrailShare"). Questo script raggruppa le tracce Garmin per
 * "firma" (recordedAt + distanza + nº punti) e, nei gruppi con >1 elemento,
 * TIENE la più vecchia (createdAt) e segna le altre come da cancellare.
 *
 * Sola lettura di default. Cancella SOLO con --apply.
 *
 *   node scripts/garmin_dedupe_tracks.cjs --uid <UID>            # dry-run
 *   node scripts/garmin_dedupe_tracks.cjs --uid <UID> --apply    # cancella
 */
const admin = require('firebase-admin');
const serviceAccount = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : def;
}
const APPLY = process.argv.includes('--apply');
const UID = arg('--uid', null);

if (!UID) {
  console.error('Manca --uid <UID>. Esempio: node scripts/garmin_dedupe_tracks.cjs --uid g4uPvD3VQcMiYb4dDTWs7kJgm4u1');
  process.exit(1);
}

// Chiave di "stessa traccia": SOLO campi che arrivano dal payload
// dell'orologio e sono identici ad ogni retry → distanza al metro + nº punti
// + durata al secondo. NON uso recordedAt: il server lo calcola come
// (Date.now()-durata) al momento dell'elaborazione, quindi i retry — arrivati
// a secondi/minuti di distanza — hanno recordedAt DIVERSI pur essendo lo
// stesso giro. La probabilità che due giri reali distinti coincidano su
// distanza-al-metro + punti + durata-al-secondo è praticamente nulla.
function sig(d) {
  const dist = Math.round(d.distance || (d.stats && d.stats.distance) || 0);
  const npts = Array.isArray(d.points) ? d.points.length : 0;
  const dur = Math.round(d.duration || 0);
  return `${dist}m|${npts}pt|${dur}s`;
}

(async () => {
  const snap = await db.collection('users').doc(UID).collection('tracks')
    .where('source', '==', 'garmin').get();
  console.log(`Tracce Garmin per uid=${UID}: ${snap.size}`);

  const groups = {};
  snap.forEach((doc) => {
    const d = doc.data();
    const k = sig(d);
    (groups[k] = groups[k] || []).push({
      id: doc.id, name: d.name || '',
      createdAt: d.createdAt && d.createdAt.toDate ? d.createdAt.toDate().toISOString() : '?',
      hasClientId: !!d.garminClientId,
    });
  });

  let toDelete = [];
  for (const k of Object.keys(groups)) {
    const arr = groups[k];
    if (arr.length <= 1) continue;
    // Tieni la più VECCHIA (createdAt minore); cancella le altre.
    arr.sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));
    const keep = arr[0];
    const drop = arr.slice(1);
    console.log(`\n● Gruppo «${k}» — ${arr.length} copie`);
    console.log(`   TENGO   ${keep.id}  (${keep.name}, ${keep.createdAt})`);
    drop.forEach((x) => console.log(`   CANCELLO ${x.id}  (${x.name}, ${x.createdAt})`));
    toDelete.push(...drop.map((x) => x.id));
  }

  if (!toDelete.length) {
    console.log('\nNessun duplicato trovato. Niente da fare.');
    return;
  }

  if (!APPLY) {
    console.log(`\n[DRY-RUN] ${toDelete.length} tracce verrebbero cancellate. Rilancia con --apply per procedere.`);
    return;
  }

  let n = 0;
  for (const id of toDelete) {
    await db.collection('users').doc(UID).collection('tracks').doc(id).delete();
    n++;
  }
  console.log(`\n✅ Cancellate ${n} tracce duplicate.`);
})().catch((e) => { console.error(e); process.exit(1); });
