// Applica le foto APPROVATE a mano nella pagina di revisione
// (.photo_review/index.html → approvals.json). Copia l'immagine da Wikimedia
// Commons nel nostro Storage e scrive branding.heroPhotoUrl + photoAttribution.
//
// Non tocca mai un rifugio che nel frattempo ha gia' una foto (potrebbe averla
// caricata il gestore dopo la revendicazione: la sua vince sempre sulla nostra).
// Scrive .photo_review/applied.json per poter tornare indietro.
//
// Uso:
//   node scripts/business_photo_apply.cjs --dry          # simulazione
//   node scripts/business_photo_apply.cjs                # applica
//   node scripts/business_photo_apply.cjs --file ~/Downloads/approvals.json
//   node scripts/business_photo_apply.cjs --undo         # annulla l'ultimo giro
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

admin.initializeApp({
  credential: admin.credential.cert(sa),
  storageBucket: 'trailshare-5334b.firebasestorage.app',
});
const db = admin.firestore();
const bucket = admin.storage().bucket();

const UA = { 'User-Agent': 'TrailShare-enrichment/1.0 (info@trailshare.app)' };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const argv = process.argv.slice(2);
const arg = (n, d = null) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
};
const DRY = argv.includes('--dry');
const UNDO = argv.includes('--undo');
const DIR = path.join(__dirname, '..', '.photo_review');
const SRC = arg('--file', path.join(DIR, 'approvals.json'));
const APPLIED = path.join(DIR, 'applied.json');

const strip = (s) => String(s || '').replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();

async function undo() {
  if (!fs.existsSync(APPLIED)) {
    console.error('Niente da annullare: manca ' + APPLIED);
    process.exit(1);
  }
  const rows = JSON.parse(fs.readFileSync(APPLIED, 'utf8')).applied || [];
  console.log(`Annullo ${rows.length} foto…`);
  let ok = 0;
  for (const r of rows) {
    try {
      await db.collection('businesses').doc(r.id).update({
        'branding.heroPhotoUrl': admin.firestore.FieldValue.delete(),
        photoAttribution: admin.firestore.FieldValue.delete(),
      });
      if (r.storagePath) await bucket.file(r.storagePath).delete().catch(() => {});
      ok++;
    } catch (e) {
      console.log(`err ${r.name} ${String(e.message).slice(0, 60)}`);
    }
  }
  console.log(`Annullate: ${ok}/${rows.length}`);
  process.exit(0);
}

(async () => {
  if (UNDO) return undo();

  if (!fs.existsSync(SRC)) {
    console.error(`Manca ${SRC}\n` +
      'Scarica approvals.json dalla pagina di revisione e mettilo li\n' +
      '(oppure passalo con --file).');
    process.exit(1);
  }
  const payload = JSON.parse(fs.readFileSync(SRC, 'utf8'));
  const list = payload.approvals || [];
  if (!list.length) { console.log('Nessuna foto approvata.'); process.exit(0); }

  console.log(`Foto approvate da applicare: ${list.length}${DRY ? '  (SIMULAZIONE)' : ''}`);

  const applied = [];
  let ok = 0, skip = 0, err = 0;

  for (const a of list) {
    try {
      const ref = db.collection('businesses').doc(a.id);
      const snap = await ref.get();
      if (!snap.exists) { skip++; console.log(`· ${a.name}: rifugio sparito`); continue; }
      const cur = snap.data();
      if ((cur.branding || {}).heroPhotoUrl) {
        skip++;
        console.log(`· ${String(a.name).slice(0, 44)}: ha gia' una foto, non la tocco`);
        continue;
      }

      // Ripesco imageinfo adesso: la licenza va letta al momento della copia,
      // non quella congelata nella coda di giorni prima.
      const title = a.file.startsWith('File:') ? a.file : 'File:' + a.file;
      const url = 'https://commons.wikimedia.org/w/api.php?action=query&format=json' +
        '&formatversion=2&prop=imageinfo&iiprop=url%7Cextmetadata&iiurlwidth=1600' +
        '&titles=' + encodeURIComponent(title);
      const j = await (await fetch(url, { headers: UA })).json();
      const page = ((j.query && j.query.pages) || [])[0];
      const ii = page && (page.imageinfo || [])[0];
      if (!ii || !(ii.thumburl || ii.url)) { skip++; console.log(`· ${a.name}: file non trovato`); continue; }
      const meta = ii.extmetadata || {};
      const author = strip(meta.Artist && meta.Artist.value) || 'Wikimedia Commons';
      const license = strip(meta.LicenseShortName && meta.LicenseShortName.value) || 'CC';
      const srcUrl = ii.thumburl || ii.url;

      if (DRY) {
        ok++;
        console.log(`✓ ${String(a.name).slice(0, 44).padEnd(44)} ${title.replace('File:', '').slice(0, 46)} (${license})`);
        await sleep(150);
        continue;
      }

      const img = await fetch(srcUrl, { headers: UA });
      if (!img.ok) { skip++; console.log(`· ${a.name}: download ${img.status}`); continue; }
      const buf = Buffer.from(await img.arrayBuffer());
      if (buf.length < 1000 || buf.length > 8 * 1024 * 1024) {
        skip++; console.log(`· ${a.name}: dimensione sospetta (${buf.length} byte)`); continue;
      }

      const ext = /\.png$/i.test(srcUrl) ? '.png' : '.jpg';
      const storagePath = `business_covers/${a.id}/wikimedia${ext}`;
      const token = crypto.randomUUID();
      await bucket.file(storagePath).save(buf, {
        metadata: {
          contentType: ext === '.png' ? 'image/png' : 'image/jpeg',
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });
      const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
        `${encodeURIComponent(storagePath)}?alt=media&token=${token}`;

      await ref.update({
        'branding.heroPhotoUrl': publicUrl,
        photoAttribution: {
          author, license,
          source: 'Wikimedia Commons',
          sourceUrl: 'https://commons.wikimedia.org/wiki/' + encodeURIComponent(title),
          file: title,
          // marca la provenienza: queste sono passate da revisione umana,
          // non dai tag OSM come quelle di business_commons_photos.cjs
          curated: true,
          strategy: a.strategy || null,
        },
      });
      applied.push({ id: a.id, name: a.name, file: title, storagePath });
      ok++;
      console.log(`✓ ${String(a.name).slice(0, 44).padEnd(44)} ${license}`);
      await sleep(350);
    } catch (e) {
      err++;
      console.log(`err ${String(a.name).slice(0, 40)} ${String(e.message).slice(0, 70)}`);
    }
  }

  if (!DRY && applied.length) {
    fs.writeFileSync(APPLIED, JSON.stringify({
      appliedAt: new Date().toISOString(), applied,
    }, null, 1));
  }

  console.log(`\n=== FOTO APPLICATE ${DRY ? '(SIMULAZIONE)' : ''} ===`);
  console.log(`applicate: ${ok} | saltate: ${skip} | errori: ${err}`);
  if (!DRY && applied.length) {
    console.log(`\nPer tornare indietro:  node scripts/business_photo_apply.cjs --undo`);
  }
  process.exit(0);
})().catch((e) => { console.error('ERR', e); process.exit(1); });
