// Cerca foto CANDIDATE per i rifugi che ne sono ancora privi e le mette in
// una coda di revisione umana. Non scrive NULLA su Firestore: produce
// .photo_review/candidates.json + .photo_review/index.html.
//
// Perche' una coda e non l'automatismo: business_commons_photos.cjs usa i tag
// OSM (wikidata P18 / wikimedia_commons), che sono affidabili ma coprono solo
// ~30% dei rifugi. Le fonti alternative — foto geolocalizzate vicine e
// categorie Commons omonime — sono molto piu' ampie ma NON verificabili in
// automatico: "vicino al rifugio" non vuol dire "e' il rifugio" (accanto al
// Vittorio Sella Commons ha foto di cince). Una copertina sbagliata la vede
// subito l'utente, quindi la decide una persona.
//
// Due strategie, entrambe mostrate in revisione con l'etichetta di provenienza:
//   A. geosearch: file geotaggati entro RADIUS il cui titolo/categorie
//      contengono le parole DISTINTIVE del nome (tolte rifugio/hutte/refuge...).
//   B. categoria: categoria Commons omonima; accettata solo se contiene tutte
//      le parole distintive, e marcata "geo non verificato" se nessuno dei suoi
//      file e' geotaggato vicino (omonimi: di Rifugio Battisti ce n'e' piu' d'uno).
//
// Uso:
//   node scripts/business_photo_candidates.cjs [--type rifugio] [--country IT]
//        [--bbox s,w,n,e] [--limit 50] [--radius 1500] [--resume]
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const fs = require('fs');
const path = require('path');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const UA = { 'User-Agent': 'TrailShare-enrichment/1.0 (info@trailshare.app)' };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const argv = process.argv.slice(2);
const arg = (n, d = null) => {
  const i = argv.indexOf(n);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
};
const TYPE = arg('--type', 'rifugio');
const COUNTRY = arg('--country');
const BBOX = arg('--bbox') ? arg('--bbox').split(',').map(Number) : null; // s,w,n,e
const LIMIT = parseInt(arg('--limit', '0'), 10) || 0;
const RADIUS = parseInt(arg('--radius', '1500'), 10);
const RESUME = argv.includes('--resume');
// Commons risponde 429 con 4 richieste in volo: a 2 regge, e un rifugio perso
// per rate limit e' un rifugio che nessuno rivedra' mai.
const CONCURRENCY = parseInt(arg('--concurrency', '2'), 10);

const OUT_DIR = path.join(__dirname, '..', '.photo_review');
const OUT_JSON = path.join(OUT_DIR, 'candidates.json');

// ---------------------------------------------------------------- vocabolario
// Parole che NON identificano un rifugio: se restano nel confronto, "Casa
// Bastone" fa match con "casa semiutilizzata" di un paese qualsiasi.
const GENERIC = new Set([
  // italiano
  'rifugio', 'rifugi', 'bivacco', 'capanna', 'baita', 'malga', 'alpe', 'alpeggio',
  'casa', 'casera', 'ostello', 'albergo', 'hotel', 'locanda', 'agriturismo',
  'ristorante', 'trattoria', 'osteria', 'bar', 'chalet', 'residence', 'camping',
  'campeggio', 'monte', 'monti', 'cima', 'punta', 'colle', 'passo', 'lago',
  'valle', 'val', 'alta', 'alto', 'alte', 'alti', 'nuovo', 'nuova', 'vecchio',
  'vecchia', 'della', 'delle', 'dello', 'degli', 'dei', 'del', 'di', 'da',
  'il', 'lo', 'la', 'le', 'gli', 'un', 'una', 'ed', 'al', 'ai', 'agli', 'alla',
  'alle', 'con', 'per', 'su', 'in', 'nel', 'nella', 'sul', 'sulla', 'sotto',
  'sopra', 'cai', 'sat', 'cas', 'ricovero', 'ristoro', 'capanne', 'casolare',
  'cascina', 'stalla', 'ospizio', 'foresteria', 'dormitorio', 'posto', 'tappa',
  // tedesco
  'hutte', 'huette', 'berghutte', 'alphutte', 'almhutte', 'schutzhutte',
  'schutzhaus', 'alm', 'haus', 'hause', 'gasthaus', 'gasthof', 'berggasthaus',
  'jausenstation', 'unterkunft', 'biwak', 'biwakschachtel', 'berghaus',
  'alpengasthof', 'alpengasthaus', 'berggasthof', 'alpenhaus', 'alpenhotel',
  'berghotel', 'sporthotel', 'jugendherberge', 'herberge', 'hospiz', 'huetten',
  'huetterl', 'hutterl', 'kaser', 'stube', 'wirtshaus', 'raststation',
  'der', 'die', 'das', 'dem', 'den', 'am', 'im', 'zum', 'zur', 'auf', 'und',
  'von', 'vom', 'bei', 'ober', 'unter', 'neue', 'neuer', 'alte', 'alter',
  'gross', 'grosse', 'klein', 'kleine', 'hoch', 'hohe', 'nieder', 'vorder',
  'hinter', 'mittel',
  // francese
  'refuge', 'cabane', 'gite', 'auberge', 'abri', 'hutte', 'halte', 'maison',
  'ferme', 'chambre', 'hotellerie', 'du', 'de', 'des', 'les', 'aux', 'au',
  'et', 'sur', 'sous', 'vieux', 'vieille', 'grand', 'grande', 'petit', 'petite',
  'buvette', 'restaurant', 'relais', 'haut', 'haute', 'bas', 'basse', 'nouveau',
  'nouvelle', 'vieil',
  // inglese
  'hut', 'shelter', 'lodge', 'bothy', 'mountain', 'house', 'the', 'of', 'and',
  'inn', 'hostel', 'upper', 'lower', 'old', 'new', 'big', 'little', 'refugio',
  'refugi', 'chata', 'schronisko',
  // sloveno / croato
  'koca', 'koce', 'dom', 'domu', 'planinski', 'planinska', 'planinskem',
  'planinarski', 'planinarska', 'planinarskom', 'planina', 'planini', 'planine',
  'zavetisce', 'bivak', 'sklonisce', 'kuca', 'gora', 'gori', 'vrh',
  'na', 'pri', 'pod', 'nad', 'stara', 'stari', 'novi', 'nova', 'novo',
  'mali', 'mala', 'malo', 'veliki', 'velika', 'veliko', 'gornji', 'donji',
  'srednji', 'spodnji', 'zgornji',
  // ungherese
  'menedekhaz', 'turistahaz', 'kunyho', 'haz', 'esohaz', 'also', 'felso',
]);

// Titoli che raramente fanno una buona copertina: non li scarto, li ordino dopo.
const WEAK = /(panneau|panel|schild|cartell|segnavia|sign|plaque|targa|map|carte|karte|mappa|plan |logo|interno|inside|indoor|detail|dettaglio|menu|book|libro|timbro|stamp)/i;
const BAD_EXT = /\.(svg|pdf|ogg|ogv|oga|webm|mid|tif|tiff|gif|xcf|djvu)$/i;

const norm = (s) => String(s || '')
  .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .toLowerCase()
  .replace(/[^a-z0-9]+/g, ' ')
  .trim();

/// Le parole del nome che valgono davvero come identificativo.
function distinctiveTokens(name) {
  return [...new Set(norm(name).split(' '))]
    .filter((t) => t.length >= 3 && !GENERIC.has(t) && !/^\d+$/.test(t));
}

/// Quante e quali parole distintive compaiono nel testo (parola intera).
function matchedTokens(tokens, text) {
  const words = new Set(norm(text).split(' '));
  return tokens.filter((t) => words.has(t));
}

/// Soglia: una parola lunga basta, due corte anche. Una sola parola di 3-4
/// lettere no — sono quelle che generano i falsi positivi.
function isStrongMatch(matched) {
  if (matched.some((t) => t.length >= 5)) return true;
  return matched.filter((t) => t.length >= 4).length >= 2;
}

function haversine(a, b, c, d) {
  const R = 6371000, r = Math.PI / 180;
  const dLat = (c - a) * r, dLng = (d - b) * r;
  const x = Math.sin(dLat / 2) ** 2 +
    Math.cos(a * r) * Math.cos(c * r) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

async function commons(params, attempt = 0) {
  const url = 'https://commons.wikimedia.org/w/api.php?format=json&formatversion=2&' +
    new URLSearchParams(params).toString();
  try {
    const r = await fetch(url, { headers: UA });
    if (r.status === 429 || r.status >= 500) {
      const wait = parseInt(r.headers.get('retry-after') || '0', 10);
      const e = new Error('HTTP ' + r.status);
      e.retryAfter = wait > 0 ? wait * 1000 : 0;
      throw e;
    }
    return await r.json();
  } catch (e) {
    if (attempt >= 5) throw e;
    // esponenziale, ma se il server dice quanto aspettare si fa come dice lui
    await sleep(e.retryAfter || 2000 * Math.pow(2, attempt));
    return commons(params, attempt + 1);
  }
}

const strip = (s) => String(s || '').replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();

function fileInfo(page) {
  const ii = (page.imageinfo || [])[0] || {};
  const meta = ii.extmetadata || {};
  return {
    file: page.title,
    thumb: ii.thumburl || null,
    width: ii.width || null,
    height: ii.height || null,
    author: strip(meta.Artist && meta.Artist.value) || 'Wikimedia Commons',
    license: strip(meta.LicenseShortName && meta.LicenseShortName.value) || 'CC',
    description: strip(meta.ImageDescription && meta.ImageDescription.value).slice(0, 200),
    pageUrl: 'https://commons.wikimedia.org/wiki/' + encodeURIComponent(page.title),
    categories: (page.categories || []).map((c) => c.title.replace(/^Category:/, '')),
  };
}

// --------------------------------------------------------------- strategia A
async function viaGeosearch(hut, tokens) {
  const j = await commons({
    action: 'query',
    generator: 'geosearch',
    ggscoord: `${hut.lat}|${hut.lng}`,
    ggsradius: String(RADIUS),
    ggsnamespace: '6',
    ggslimit: '50',
    prop: 'imageinfo|categories|coordinates',
    iiprop: 'url|extmetadata|size',
    iiurlwidth: '480',
    cllimit: '20',
    clshow: '!hidden',
  });
  const pages = (j.query && j.query.pages) || [];
  const out = [];
  for (const p of pages) {
    if (BAD_EXT.test(p.title)) continue;
    const info = fileInfo(p);
    const hay = p.title + ' ' + info.categories.join(' ');
    const matched = matchedTokens(tokens, hay);
    if (!isStrongMatch(matched)) continue;
    const inCategory = isStrongMatch(matchedTokens(tokens, info.categories.join(' ')));
    const co = (p.coordinates || [])[0];
    out.push({
      ...info,
      strategy: 'geo',
      matched,
      distance: co ? Math.round(haversine(hut.lat, hut.lng, co.lat, co.lon)) : null,
      score: matched.join('').length + (inCategory ? 12 : 0) + (WEAK.test(p.title) ? -20 : 0),
      weak: WEAK.test(p.title),
      geoVerified: true,
    });
  }
  return out;
}

// --------------------------------------------------------------- strategia B
/// Dove sta una categoria Commons, quando nessuno dei suoi file e' geotaggato.
/// Serve contro gli omonimi: "Refuge Cezanne" e' negli Ecrins da noi e sulla
/// Montagne Sainte-Victoire su Commons — 180 km di distanza, stesso nome.
/// Prima le coordinate della pagina categoria, poi il P625 dell'elemento
/// Wikidata collegato.
async function categoryCoords(cat) {
  try {
    const j = await commons({ action: 'query', prop: 'coordinates', titles: cat });
    const p = ((j.query && j.query.pages) || [])[0];
    const co = p && (p.coordinates || [])[0];
    if (co) return { lat: co.lat, lng: co.lon, from: 'categoria' };
  } catch (_) { /* si prosegue con Wikidata */ }
  try {
    const url = 'https://www.wikidata.org/w/api.php?action=wbgetentities&format=json' +
      '&sites=commonswiki&props=claims&titles=' + encodeURIComponent(cat);
    const j = await (await fetch(url, { headers: UA })).json();
    const ent = j.entities && Object.values(j.entities)[0];
    const v = ent && ent.claims && ent.claims.P625 && ent.claims.P625[0] &&
      ent.claims.P625[0].mainsnak && ent.claims.P625[0].mainsnak.datavalue;
    if (v && v.value) return { lat: v.value.latitude, lng: v.value.longitude, from: 'wikidata' };
  } catch (_) { /* resta non verificata */ }
  return null;
}

/// Le categorie Commons disambiguano col comune fra parentesi:
/// "Rifugio Le Malghe (Lizzano in Belvedere)". Quella parentesi e' un LUOGO,
/// non il nome del rifugio, e va tolta prima del confronto — altrimenti tre
/// "Rifugio Belvedere" sparsi fra Marche, Valle d'Aosta e Calabria si prendono
/// tutti la foto di un rifugio dell'Appennino bolognese.
const senzaParentesi = (s) => String(s || '').replace(/\s*\([^)]*\)\s*/g, ' ');

async function viaCategory(hut, tokens) {
  const search = await commons({
    action: 'query', list: 'search', srnamespace: '14',
    srsearch: hut.name, srlimit: '5',
  });
  const hits = ((search.query && search.query.search) || [])
    .map((s) => s.title)
    // qui pretendo TUTTE le parole distintive: la categoria e' un'affermazione
    // forte ("questo E' il rifugio"), non una vicinanza.
    .filter((t) => matchedTokens(tokens, senzaParentesi(t)).length === tokens.length);
  if (!hits.length) return [];

  const cat = hits[0];
  const j = await commons({
    action: 'query', generator: 'categorymembers',
    gcmtitle: cat, gcmtype: 'file', gcmlimit: '12',
    prop: 'imageinfo|categories|coordinates',
    iiprop: 'url|extmetadata|size', iiurlwidth: '480',
    cllimit: '20', clshow: '!hidden',
  });
  const pages = (j.query && j.query.pages) || [];
  // Verifica geografica: almeno un file della categoria vicino al rifugio.
  let nearest = null;
  for (const p of pages) {
    const co = (p.coordinates || [])[0];
    if (!co) continue;
    const d = haversine(hut.lat, hut.lng, co.lat, co.lon);
    if (nearest == null || d < nearest) nearest = d;
  }
  let geoFrom = nearest != null ? 'file' : null;
  if (nearest == null) {
    const cc = await categoryCoords(cat);
    if (cc) {
      nearest = haversine(hut.lat, hut.lng, cc.lat, cc.lng);
      geoFrom = cc.from;
    }
  }
  if (nearest != null && nearest > 8000) return []; // omonimo altrove
  const geoVerified = nearest != null;

  return pages.filter((p) => !BAD_EXT.test(p.title)).slice(0, 6).map((p) => {
    const info = fileInfo(p);
    const co = (p.coordinates || [])[0];
    return {
      ...info,
      strategy: 'cat',
      category: cat.replace(/^Category:/, ''),
      categoryUrl: 'https://commons.wikimedia.org/wiki/' + encodeURIComponent(cat),
      matched: tokens,
      distance: co ? Math.round(haversine(hut.lat, hut.lng, co.lat, co.lon))
        : (geoVerified ? Math.round(nearest) : null),
      geoFrom,
      score: 30 + tokens.join('').length + (geoVerified ? 15 : 0) + (WEAK.test(p.title) ? -20 : 0),
      weak: WEAK.test(p.title),
      geoVerified,
    };
  });
}

// -------------------------------------------------------------------- runner
(async () => {
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const snap = await db.collection('businesses')
    .where('status', '==', 'active')
    .where('type', '==', TYPE)
    .get();

  const usedFiles = new Set(); // file gia' in produzione su un altro rifugio
  const targets = [];
  snap.forEach((d) => {
    const x = d.data();
    const L = x.location || {};
    const already = (x.photoAttribution || {}).file;
    if (already) usedFiles.add(norm(already));
    if ((x.branding || {}).heroPhotoUrl) return;
    if (L.lat == null || L.lng == null) return;
    if (COUNTRY && (L.country || 'IT') !== COUNTRY) return;
    if (BBOX) {
      const [s, w, n, e] = BBOX;
      if (L.lat < s || L.lat > n || L.lng < w || L.lng > e) return;
    }
    const tokens = distinctiveTokens(x.name);
    if (!tokens.length) return; // "Rifugio" e basta: niente su cui fare match
    targets.push({
      id: d.id, name: x.name, tokens,
      lat: L.lat, lng: L.lng,
      city: L.city || L.address || '',
      region: L.region || '', country: L.country || 'IT',
    });
  });

  // Ripresa: serve l'elenco di TUTTI gli id interrogati, non solo di quelli con
  // proposte — altrimenti si rifarebbe il 73% del lavoro (i rifugi senza
  // candidate sono la maggioranza e nel json non compaiono). Gli errori invece
  // non si registrano apposta: al giro dopo si riprovano.
  const doneIds = new Set();
  const results = [];
  if (RESUME && fs.existsSync(OUT_JSON)) {
    const prev = JSON.parse(fs.readFileSync(OUT_JSON, 'utf8'));
    if (!prev.scannedIds) {
      console.log('Il json esistente e\' di una versione precedente e non dice ' +
        'quali rifugi ha gia\' visto: riparto da zero.');
    } else {
      for (const h of prev.huts || []) results.push(h);
      for (const id of prev.scannedIds) doneIds.add(id);
      console.log(`Riprendo: ${doneIds.size} rifugi gia' interrogati, ` +
        `${results.length} con proposte`);
    }
  }

  const list = (LIMIT ? targets.slice(0, LIMIT) : targets).filter((t) => !doneIds.has(t.id));
  console.log(`Rifugi senza foto da interrogare: ${list.length} (raggio ${RADIUS} m)`);

  let i = 0, withCand = results.length, errs = 0;

  const save = () => {
    const huts = results.filter((r) => r.candidates.length)
      .sort((a, b) => b.candidates[0].score - a.candidates[0].score);
    fs.writeFileSync(OUT_JSON, JSON.stringify({
      generatedAt: new Date().toISOString(),
      type: TYPE, radius: RADIUS,
      scanned: doneIds.size, totalWithoutPhoto: targets.length,
      scannedIds: [...doneIds],
      huts,
    }, null, 1));
  };

  async function worker() {
    while (i < list.length) {
      const hut = list[i++];
      const n = i;
      try {
        const [a, b] = await Promise.all([
          viaGeosearch(hut, hut.tokens),
          viaCategory(hut, hut.tokens),
        ]);
        const seen = new Set();
        const candidates = [...b, ...a]
          .filter((c) => {
            const k = norm(c.file);
            if (seen.has(k) || usedFiles.has(k)) return false;
            seen.add(k);
            return !!c.thumb;
          })
          .sort((x, y) => y.score - x.score)
          .slice(0, 6);
        doneIds.add(hut.id);
        if (candidates.length) {
          results.push({ ...hut, candidates });
          withCand++;
          console.log(`✓ ${String(n).padStart(4)}/${list.length} ${hut.name.slice(0, 42).padEnd(42)} ${candidates.length} candidate (${candidates[0].strategy})`);
        }
      } catch (e) {
        // niente doneIds.add: al prossimo --resume questo rifugio si rifa'
        errs++;
        console.log(`err  ${hut.name.slice(0, 42)} ${String(e.message).slice(0, 60)}`);
      }
      if (n % 50 === 0) { save(); process.stdout.write(`   … ${n}/${list.length} — con proposte: ${withCand}\n`); }
      await sleep(120);
    }
  }

  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  save();

  const tot = results.reduce((s, r) => s + r.candidates.length, 0);
  console.log(`\n=== CANDIDATE FOTO ===`);
  console.log(`Rifugi interrogati : ${doneIds.size} su ${targets.length}`);
  console.log(`Con almeno una proposta: ${withCand} (${(withCand / Math.max(1, doneIds.size) * 100).toFixed(1)}%)`);
  console.log(`Immagini proposte  : ${tot}   errori: ${errs}`);
  if (errs) console.log(`\n${errs} falliti: rilancia con --resume per riprovare solo quelli.`);
  console.log(`\nJSON: ${OUT_JSON}`);
  console.log(`Ora genera la pagina:  node scripts/business_photo_review_page.cjs`);
  process.exit(0);
})().catch((e) => { console.error('ERR', e); process.exit(1); });
