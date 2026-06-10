// Foto Wikimedia Commons per i sentieri "famosi" (relazioni OSM con tag
// wikidata/wikimedia_commons/image). Scrive su public_trails: photoUrl
// (copiata nel nostro Storage, URL con token) + photoAttribution
// {author, license, source, sourceUrl, file}. SOLO dove photoUrl manca.
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(sa), storageBucket: 'trailshare-5334b.firebasestorage.app' });
const db = admin.firestore();
const bucket = admin.storage().bucket();
const crypto = require('crypto');
const UA = { 'User-Agent': 'TrailShare-enrichment/1.0 (info@trailshare.app)' };
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function overpass(q) {
  const eps = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];
  let last;
  for (let a = 0; a < 6; a++) {
    try {
      const r = await fetch(eps[a % 2], { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...UA }, body: 'data=' + encodeURIComponent(q) });
      if (r.ok) return r.json();
      last = new Error('HTTP ' + r.status);
    } catch (e) { last = e; }
    await sleep(12000);
  }
  throw last;
}

(async () => {
  const snap = await db.collection('public_trails').get();
  const trails = [];
  snap.forEach(d => {
    const x = d.data();
    if (x.photoUrl) return; // mai sovrascrivere
    const osmId = String(x.osmId || '').replace(/[^0-9]/g, '');
    if (!osmId || !d.id.startsWith('wmt_relation_')) return; // solo relation certe
    trails.push({ ref: d.ref, id: d.id, name: x.name, osmId });
  });
  console.log('Sentieri candidati (relation, senza foto):', trails.length);

  // tags per relation
  const tagsById = {};
  const ids = trails.map(t => t.osmId);
  for (let i = 0; i < ids.length; i += 400) {
    const chunk = ids.slice(i, i + 400);
    const j = await overpass(`[out:json][timeout:120];rel(id:${chunk.join(',')});out tags;`);
    for (const el of j.elements || []) tagsById[String(el.id)] = el.tags || {};
    process.stdout.write(`${Math.min(i + 400, ids.length)}/${ids.length} `);
    await sleep(8000);
  }
  console.log('\nTag relation scaricati:', Object.keys(tagsById).length);

  // wikidata P18
  const qidByTrail = {};
  for (const t of trails) {
    const q = tagsById[t.osmId] && tagsById[t.osmId].wikidata;
    if (q && /^Q\d+$/.test(q)) qidByTrail[t.id] = q;
  }
  const qids = [...new Set(Object.values(qidByTrail))];
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
  console.log('QID con P18:', Object.keys(p18).length, 'su', qids.length);

  let ok = 0, skip = 0, err = 0;
  for (const t of trails) {
    const tags = tagsById[t.osmId];
    if (!tags) continue;
    let file = qidByTrail[t.id] ? p18[qidByTrail[t.id]] : null;
    if (!file) {
      const wc = tags.wikimedia_commons;
      if (wc && /^File:/i.test(wc)) file = wc.replace(/^File:/i, '');
      else if (tags.image && /^File:/i.test(tags.image)) file = tags.image.replace(/^File:/i, '');
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
      const strip = s => String(s || '').replace(/<[^>]*>/g, '').trim();
      const author = strip(meta.Artist && meta.Artist.value) || 'Wikimedia Commons';
      const license = strip(meta.LicenseShortName && meta.LicenseShortName.value) || 'CC';
      const imgResp = await fetch(srcUrl, { headers: UA });
      if (!imgResp.ok) { skip++; continue; }
      const buf = Buffer.from(await imgResp.arrayBuffer());
      if (buf.length < 1000 || buf.length > 8 * 1024 * 1024) { skip++; continue; }
      const token = crypto.randomUUID();
      const ext = /\.png$/i.test(srcUrl) ? '.png' : '.jpg';
      const ct = ext === '.png' ? 'image/png' : 'image/jpeg';
      const path = `trail_covers/${t.id}/wikimedia${ext}`;
      await bucket.file(path).save(buf, {
        metadata: { contentType: ct, metadata: { firebaseStorageDownloadTokens: token } },
      });
      const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
      await t.ref.update({
        photoUrl: publicUrl,
        photoAttribution: {
          author, license,
          source: 'Wikimedia Commons',
          sourceUrl: 'https://commons.wikimedia.org/wiki/' + encodeURIComponent(title),
          file: title,
        },
      });
      ok++;
      console.log('✓', t.name.slice(0, 50), '(' + license + ')');
      await sleep(350);
    } catch (e) { err++; console.log('err', t.name.slice(0, 40), e.message.slice(0, 80)); }
  }
  console.log(`\n=== FOTO SENTIERI COMPLETO === foto: ${ok} | senza file: ${skip} | errori: ${err}`);
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
