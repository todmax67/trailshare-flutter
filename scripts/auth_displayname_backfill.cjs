// Allinea il displayName di FirebaseAuth allo username del profilo.
//
// Il gate all'avvio, se trova un displayName valido, si fida senza leggere
// Firestore. Chi accede con email e password non ce l'ha — glielo popolano
// solo Google e Apple — quindi ogni accesso dipendeva da una lettura dal
// server con timeout di 10 secondi, e se tardava ricompariva la pagina
// "scegli username" a chi lo username ce l'aveva gia'.
//
// Uso:
//   node scripts/auth_displayname_backfill.cjs --dry
//   node scripts/auth_displayname_backfill.cjs
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();
const DRY = process.argv.includes('--dry');

(async () => {
  const snap = await db.collection('user_profiles').get();
  const perUid = new Map();
  snap.forEach((d) => {
    const u = d.data().username;
    if (typeof u === 'string' && u.trim() && u !== 'Utente') perUid.set(d.id, u.trim());
  });
  console.log(`profili con username valido: ${perUid.size}`);

  let daFare = 0, gia = 0, assenti = 0, diversi = 0;
  const esempi = [];
  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    for (const u of page.users) {
      const username = perUid.get(u.uid);
      if (!username) continue;
      const dn = (u.displayName || '').trim();
      // Al gate serve UN displayName valido, non che sia uguale allo
      // username: chi ha gia' il nome vero da Google o Apple passa
      // benissimo. Sovrascriverlo sostituirebbe il nome di una persona col
      // suo nickname, una modifica che nessuno ha chiesto.
      if (dn && dn !== 'Utente') {
        if (dn === username) gia++; else diversi++;
        continue;
      }
      assenti++;
      daFare++;
      if (esempi.length < 8) {
        esempi.push(`${(u.email || u.uid).slice(0, 34).padEnd(36)} "${dn || '(vuoto)'}" -> "${username}"`);
      }
      if (!DRY) {
        try { await admin.auth().updateUser(u.uid, { displayName: username }); }
        catch (e) { console.log(`  errore su ${u.email || u.uid}: ${e.message}`); }
      }
    }
    pageToken = page.pageToken;
  } while (pageToken);

  console.log(`gia' allineati:        ${gia}`);
  console.log(`displayName assente:   ${assenti}`);
  console.log(`displayName diverso dallo username: ${diversi}  <- LASCIATI STARE, funzionano gia'`);
  console.log(`${DRY ? 'da aggiornare' : 'aggiornati'}: ${daFare}`);
  if (esempi.length) { console.log('\nesempi:'); esempi.forEach((e) => console.log('  ' + e)); }
  if (DRY) console.log('\nNessuna scrittura. Per applicare, togliere --dry.');
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
