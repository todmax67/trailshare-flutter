// Foto Wikimedia Commons per i BUSINESS (rifugi) importati da OSM.
// Gemello di trail_commons_photos.cjs, che fa lo stesso sui sentieri.
//
// Lo script che aveva fotografato i rifugi italiani non era mai stato
// committato (le ~389 foto esistono in produzione ma la pipeline era
// andata persa): questo lo sostituisce ed è riutilizzabile ad ogni
// espansione geografica.
//
// Scrive su businesses: branding.heroPhotoUrl (immagine copiata nel
// nostro Storage, URL con token) + photoAttribution {author, license,
// source, sourceUrl, file}. SOLO dove la foto manca — mai sovrascrive.
//
// Uso:
//   node scripts/business_commons_photos.cjs --bbox 45.6,6.5,46.1,7.3 [--limit 50] [--dry]
//   node scripts/business_commons_photos.cjs --country FR
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(sa),
  storageBucket: 'trailshare-5334b.firebasestorage.app',
});
const db = admin.firestore();
const bucket = admin.storage().bucket();
const crypto = require('crypto');
const UA = { 'User-Agent': 'TrailShare-enrichment/1.0 (info@trailshare.app)' };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const argv = process.argv.slice(2);
const arg = (n, d = null) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
};
const DRY = argv.includes('--dry');
const LIMIT = parseInt(arg('--limit', '0'), 10) || 0;
const BBOX = arg('--bbox') ? arg('--bbox').split(',').map(Number) : null; // s,w,n,e
const COUNTRY = arg('--country');
const TYPE = arg('--type', 'rifugio');

async function overpass(q) {
  const eps = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];
  let last;
  for (let a = 0; a < 6; a++) {
    try {
      const r = await fetch(eps[a % 2], {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...UA },
        body: 'data=' + encodeURIComponent(q),
      });
      if (r.ok) return r.json();
      last = new Error('HTTP ' + r.status);
    } catch (e) { last = e; }
    await sleep(12000);
  }
  throw last;
}

/// `sourceUrl` OSM → {type, id}. I doc importati hanno la forma
/// https://www.openstreetmap.org/{node|way}/{id}
function parseOsm(sourceUrl) {
  const m = /openstreetmap\.org\/(node|way|relation)\/(\d+)/.exec(sourceUrl || '');
  return m ? { type: m[1], id: m[2] } : null;
}

(async () => {
  const snap = await db.collection('businesses')
    .where('status', '==', 'active')
    .where('type', '==', TYPE)
    .get();

  const targets = [];
  snap.forEach((d) => {
    const x = d.data();
    const b = x.branding || {};
    if (b.heroPhotoUrl) return; // mai sovrascrivere
    const osm = parseOsm(x.sourceUrl);
    if (!osm) return; // solo i doc importati da OSM
    const L = x.location || {};
    if (BBOX) {
      const [s, w, n, e] = BBOX;
      if (L.lat == null || L.lat < s || L.lat > n || L.lng < w || L.lng > e) return;
    }
    if (COUNTRY && (L.country || 'IT') !== COUNTRY) return;
    targets.push({ ref: d.ref, id: d.id, name: x.name, osm });
  });

  const list = LIMIT ? targets.slice(0, LIMIT) : targets;
  console.log(`Rifugi candidati (senza foto, da OSM): ${targets.length}${LIMIT ? ` — ne elaboro ${list.length}` : ''}`);
  if (!list.length) return process.exit(0);

  // 1. Tag OSM, separati per tipo (node/way non si mescolano in una query)
  const tags = {};
  for (const t of ['node', 'way']) {
    const ids = list.filter((x) => x.osm.type === t).map((x) => x.osm.id);
    for (let i = 0; i < ids.length; i += 400) {
      const chunk = ids.slice(i, i + 400);
      const j = await overpass(`[out:json][timeout:120];${t}(id:${chunk.join(',')});out tags;`);
      for (const el of j.elements || []) tags[`${t}/${el.id}`] = el.tags || {};
      process.stdout.write(`${t} ${Math.min(i + 400, ids.length)}/${ids.length} `);
      await sleep(8000);
    }
  }
  console.log(`\nTag scaricati: ${Object.keys(tags).length}`);

  // 2. Wikidata P18 per chi ha il tag wikidata
  const qidOf = {};
  for (const t of list) {
    const q = (tags[`${t.osm.type}/${t.osm.id}`] || {}).wikidata;
    if (q && /^Q\d+$/.test(q)) qidOf[t.id] = q;
  }
  const qids = [...new Set(Object.values(qidOf))];
  const p18 = {};
  for (let i = 0; i < qids.length; i += 50) {
    const chunk = qids.slice(i, i + 50);
    const url = 'https://www.wikidata.org/w/api.php?action=wbgetentities&props=claims&format=json&ids=' + chunk.join('|');
    const j = await (await fetch(url, { headers: UA })).json();
    for (const q of chunk) {
      const c = j.entities && j.entities[q] && j.entities[q].claims;
      const v = c && c.P18 && c.P18[0] && c.P18[0].mainsnak && c.P18[0].mainsnak.datavalue;
      if (v && v.value) p18[q] = String(v.value);
    }
    await sleep(700);
  }
  console.log(`QID con immagine P18: ${Object.keys(p18).length} su ${qids.length}`);

  // 3. Commons → Storage → Firestore
  let ok = 0, skip = 0, err = 0;
  for (const t of list) {
    const tg = tags[`${t.osm.type}/${t.osm.id}`] || {};
    let file = qidOf[t.id] ? p18[qidOf[t.id]] : null;
    if (!file) {
      const wc = tg.wikimedia_commons;
      if (wc && /^File:/i.test(wc)) file = wc.replace(/^File:/i, '');
      else if (tg.image && /^File:/i.test(tg.image)) file = tg.image.replace(/^File:/i, '');
    }
    if (!file) { skip++; continue; }
    try {
      const title = 'File:' + file.replace(/^File:/i, '');
      const iiUrl = 'https://commons.wikimedia.org/w/api.php?action=query&format=json&prop=imageinfo&iiprop=url%7Cextmetadata&iiurlwidth=1600&titles=' + encodeURIComponent(title);
      const j = await (await fetch(iiUrl, { headers: UA })).json();
      const page = j.query && j.query.pages && Object.values(j.query.pages)[0];
      const ii = page && page.imageinfo && page.imageinfo[0];
      if (!ii || !(ii.thumburl || ii.url)) { skip++; continue; }
      const srcUrl = ii.thumburl || ii.url;
      const meta = ii.extmetadata || {};
      const strip = (s) => String(s || '').replace(/<[^>]*>/g, '').trim();
      const author = strip(meta.Artist && meta.Artist.value) || 'Wikimedia Commons';
      const license = strip(meta.LicenseShortName && meta.LicenseShortName.value) || 'CC';

      if (DRY) { console.log(`· ${t.name.slice(0, 46)} → ${title} (${license})`); ok++; await sleep(250); continue; }

      const imgResp = await fetch(srcUrl, { headers: UA });
      if (!imgResp.ok) { skip++; continue; }
      const buf = Buffer.from(await imgResp.arrayBuffer());
      if (buf.length < 1000 || buf.length > 8 * 1024 * 1024) { skip++; continue; }
      const token = crypto.randomUUID();
      const ext = /\.png$/i.test(srcUrl) ? '.png' : '.jpg';
      const path = `business_covers/${t.id}/wikimedia${ext}`;
      await bucket.file(path).save(buf, {
        metadata: {
          contentType: ext === '.png' ? 'image/png' : 'image/jpeg',
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });
      const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
      await t.ref.update({
        'branding.heroPhotoUrl': publicUrl,
        photoAttribution: {
          author, license,
          source: 'Wikimedia Commons',
          sourceUrl: 'https://commons.wikimedia.org/wiki/' + encodeURIComponent(title),
          file: title,
        },
      });
      ok++;
      console.log(`✓ ${t.name.slice(0, 46)} (${license})`);
      await sleep(350);
    } catch (e) {
      err++;
      console.log(`err ${t.name.slice(0, 40)} ${String(e.message).slice(0, 70)}`);
    }
  }
  console.log(`\n=== FOTO RIFUGI ${DRY ? '(SIMULAZIONE)' : ''} === foto: ${ok} | senza immagine: ${skip} | errori: ${err}`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
