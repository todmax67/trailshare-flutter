// Fonde i gruppi di schede duplicate prodotti da business_dup_clusters.
// Tiene la scheda piu' ricca, le travasa i campi che ha solo l'altra,
// cancella le assorbite dopo averne salvato una copia integrale.
//
// Non fonde niente da solo: legge un file di gruppi APPROVATI. I complessi
// multi-edificio (Lochalm: 4 way entro 74 m) non sono duplicati per OSM e
// la decisione se unificarli e' di prodotto, non di dato.
//
// Uso:
//   node scripts/business_merge_duplicates.cjs --file .photo_review/da_fondere.json --dry
//   node scripts/business_merge_duplicates.cjs --file .photo_review/da_fondere.json
//   node scripts/business_merge_duplicates.cjs --undo
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const fs = require('fs');
const path = require('path');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const arg = (n, d = null) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
};
const DRY = argv.includes('--dry');
const UNDO = argv.includes('--undo');
const DIR = path.join(__dirname, '..', '.photo_review');
const SRC = arg('--file', path.join(DIR, 'da_fondere.json'));
const BACKUP = path.join(DIR, 'merged_backup.json');

// Campi che si travasano sul superstite quando li ha solo l'assorbita.
const CAMPI = ['phone', 'website', 'email', 'description', 'openingHours',
  'amenities', 'services'];
const CAMPI_LOC = ['elevation', 'address', 'city', 'region', 'country'];

/// Le Timestamp non sopravvivono a JSON.stringify: le salvo come stringhe
/// marcate, cosi' --undo puo' ricostruirle.
function serializza(v) {
  if (v instanceof admin.firestore.Timestamp) return { __ts: v.toDate().toISOString() };
  if (Array.isArray(v)) return v.map(serializza);
  if (v && typeof v === 'object') {
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = serializza(x);
    return o;
  }
  return v;
}
function deserializza(v) {
  if (v && typeof v === 'object' && typeof v.__ts === 'string') {
    return admin.firestore.Timestamp.fromDate(new Date(v.__ts));
  }
  if (Array.isArray(v)) return v.map(deserializza);
  if (v && typeof v === 'object') {
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = deserializza(x);
    return o;
  }
  return v;
}

async function svuotaSottocollezioni(ref) {
  // Firestore non cancella le sottocollezioni col documento padre: senza
  // questo passaggio restano orfane e invisibili.
  const subs = await ref.listCollections();
  const salvate = {};
  for (const sub of subs) {
    const snap = await sub.get();
    salvate[sub.id] = [];
    for (const d of snap.docs) {
      salvate[sub.id].push({ id: d.id, data: serializza(d.data()) });
      if (!DRY) await d.ref.delete();
    }
  }
  return salvate;
}

async function undo() {
  if (!fs.existsSync(BACKUP)) {
    console.error('Niente da annullare: manca ' + BACKUP);
    process.exit(1);
  }
  const b = JSON.parse(fs.readFileSync(BACKUP, 'utf8'));
  console.log(`Ripristino ${b.assorbite.length} schede e annullo ${b.travasi.length} travasi…`);
  let ok = 0;
  for (const r of b.assorbite) {
    try {
      await db.collection('businesses').doc(r.id).set(deserializza(r.data));
      for (const [sub, docs] of Object.entries(r.sottocollezioni || {})) {
        for (const d of docs) {
          await db.collection('businesses').doc(r.id).collection(sub)
            .doc(d.id).set(deserializza(d.data));
        }
      }
      ok++;
    } catch (e) {
      console.log(`err ${r.nome}: ${String(e.message).slice(0, 70)}`);
    }
  }
  for (const t of b.travasi) {
    try {
      const upd = {};
      for (const k of t.campi) upd[k] = admin.firestore.FieldValue.delete();
      if (Object.keys(upd).length) await db.collection('businesses').doc(t.id).update(upd);
    } catch (e) {
      console.log(`err travaso ${t.id}: ${String(e.message).slice(0, 60)}`);
    }
  }
  console.log(`Ripristinate: ${ok}/${b.assorbite.length}`);
  process.exit(0);
}

(async () => {
  if (UNDO) return undo();

  if (!fs.existsSync(SRC)) {
    console.error(`Manca ${SRC}: serve il file dei gruppi approvati.`);
    process.exit(1);
  }
  const gruppi = JSON.parse(fs.readFileSync(SRC, 'utf8')).clusters || [];
  console.log(`Gruppi da fondere: ${gruppi.length}${DRY ? '  (SIMULAZIONE)' : ''}`);

  const assorbite = [], travasi = [];
  let fusi = 0, saltati = 0, campiTravasati = 0;

  for (const g of gruppi) {
    const [tenere, ...altre] = g.membri;
    const refT = db.collection('businesses').doc(tenere.id);
    const snapT = await refT.get();
    if (!snapT.exists) { saltati++; console.log(`· ${g.nome}: il superstite non c'e' piu'`); continue; }
    const T = snapT.data();

    // Sicurezza: se nel frattempo una delle assorbite e' stata rivendicata
    // da un gestore, non si tocca il gruppo. Meglio due schede che
    // cancellare quella di un cliente.
    let rivendicata = null;
    const dati = {};
    for (const m of altre) {
      const s = await db.collection('businesses').doc(m.id).get();
      if (!s.exists) continue;
      dati[m.id] = s.data();
      if (dati[m.id].claimedBy) rivendicata = m.id;
    }
    if (rivendicata) {
      saltati++;
      console.log(`· ${g.nome}: una scheda assorbita risulta rivendicata, non tocco niente`);
      continue;
    }

    // travaso dei campi mancanti
    const upd = {}, aggiunti = [];
    for (const m of altre) {
      const A = dati[m.id];
      if (!A) continue;
      for (const k of CAMPI) {
        if ((T[k] == null || T[k] === '') && A[k] != null && A[k] !== '' && upd[k] === undefined) {
          upd[k] = A[k]; aggiunti.push(k);
        }
      }
      const LT = T.location || {}, LA = A.location || {};
      for (const k of CAMPI_LOC) {
        const key = 'location.' + k;
        if ((LT[k] == null || LT[k] === '') && LA[k] != null && LA[k] !== '' && upd[key] === undefined) {
          upd[key] = LA[k]; aggiunti.push(key);
        }
      }
      const BT = T.branding || {}, BA = A.branding || {};
      if (!BT.heroPhotoUrl && BA.heroPhotoUrl && upd['branding.heroPhotoUrl'] === undefined) {
        upd['branding.heroPhotoUrl'] = BA.heroPhotoUrl;
        aggiunti.push('branding.heroPhotoUrl');
        if (A.photoAttribution) { upd.photoAttribution = A.photoAttribution; aggiunti.push('photoAttribution'); }
      }
    }

    console.log(`${DRY ? '·' : '✓'} ${g.nome.slice(0, 34).padEnd(34)} tiene ${tenere.src.padEnd(20)} ` +
      `assorbe ${altre.length}` + (aggiunti.length ? `  travaso: ${aggiunti.join(',')}` : ''));

    if (!DRY) {
      if (Object.keys(upd).length) {
        await refT.update(upd);
        travasi.push({ id: tenere.id, nome: g.nome, campi: Object.keys(upd) });
        campiTravasati += Object.keys(upd).length;
      }
      for (const m of altre) {
        if (!dati[m.id]) continue;
        const ref = db.collection('businesses').doc(m.id);
        const sottocollezioni = await svuotaSottocollezioni(ref);
        assorbite.push({
          id: m.id, nome: g.nome, assorbitaIn: tenere.id,
          data: serializza(dati[m.id]), sottocollezioni,
        });
        await ref.delete();
      }
    } else {
      campiTravasati += Object.keys(upd).length;
    }
    fusi++;
  }

  if (!DRY) {
    fs.writeFileSync(BACKUP, JSON.stringify({
      fusoIl: new Date().toISOString(), assorbite, travasi,
    }, null, 1));
  }

  console.log(`\n=== FUSIONE ${DRY ? '(SIMULAZIONE)' : ''} ===`);
  console.log(`gruppi fusi: ${fusi} | saltati: ${saltati} | schede assorbite: ${DRY ? '—' : assorbite.length} | campi travasati: ${campiTravasati}`);
  if (!DRY && assorbite.length) {
    console.log(`\nPer tornare indietro:  node scripts/business_merge_duplicates.cjs --undo`);
  }
  process.exit(0);
})().catch((e) => { console.error('ERR', e); process.exit(1); });
