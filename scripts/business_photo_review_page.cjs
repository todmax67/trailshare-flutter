// Genera .photo_review/index.html dalla coda prodotta da
// business_photo_candidates.cjs. Pagina statica da aprire nel browser:
// nessun server, nessuna scrittura su Firestore. Si sceglie una foto per
// rifugio (o "nessuna"), le scelte restano in localStorage, alla fine si
// scarica approvals.json da dare in pasto a business_photo_apply.cjs.
//
// Uso:  node scripts/business_photo_review_page.cjs
const fs = require('fs');
const path = require('path');

const DIR = path.join(__dirname, '..', '.photo_review');
const SRC = path.join(DIR, 'candidates.json');
const OUT = path.join(DIR, 'index.html');

if (!fs.existsSync(SRC)) {
  console.error('Manca ' + SRC + ' — lancia prima business_photo_candidates.cjs');
  process.exit(1);
}
const data = JSON.parse(fs.readFileSync(SRC, 'utf8'));

// Titoli che quasi mai fanno una buona copertina: cartelli, mappe, dettagli.
// Sta qui e non nello script di scansione perche' e' un elenco che si affina
// guardando i risultati, e la scansione dura un'ora: cosi' basta rigenerare
// la pagina. Non scarta nulla — li marca e li mette in fondo.
const WEAK = new RegExp([
  'panneau', 'panel', 'schild', 'wegweiser', 'tafel', 'cartell', 'segnavia',
  'segnaletic', 'insegna', 'sign', 'signpost', 'balise', 'borne', 'plaque',
  'targa', 'map\\b', 'carte', 'karte', 'mappa', 'plan\\b', 'logo', 'stemma',
  'interno', 'inside', 'indoor', 'innen', 'detail', 'dettaglio', 'menu',
  'book', 'libro', 'timbro', 'stamp', 'ruine', 'rudere', 'baustelle',
].join('|'), 'i');

for (const h of data.huts) {
  for (const c of h.candidates) {
    const wasWeak = c.weak === true;
    c.weak = WEAK.test(c.file);
    if (c.weak && !wasWeak) c.score -= 20;
    if (!c.weak && wasWeak) c.score += 20;
  }
  h.candidates.sort((a, b) => b.score - a.score);
}

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');

const COUNTRY_NAME = {
  IT: 'Italia', FR: 'Francia', CH: 'Svizzera', AT: 'Austria',
  SI: 'Slovenia', HR: 'Croazia', HU: 'Ungheria', DE: 'Germania',
};

const totalImgs = data.huts.reduce((s, h) => s + h.candidates.length, 0);
const countries = [...new Set(data.huts.map((h) => h.country))].sort();

/// "Quasi certa": viene da una categoria Commons omonima le cui coordinate
/// cadono praticamente sul rifugio. Non e' una prova — resta una foto che
/// qualcuno deve guardare — ma e' la classe in cui non ho ancora visto un
/// errore, e permette di approvare in blocco dopo un controllo a campione.
function isSure(c) {
  return c.strategy === 'cat' && c.geoVerified && !c.weak &&
    c.distance != null && c.distance <= 500;
}

function candidateCard(hut, c, idx) {
  const badges = [];
  badges.push(c.strategy === 'cat'
    ? '<span class="b b-cat">categoria omonima</span>'
    : '<span class="b b-geo">foto geolocalizzata</span>');
  if (isSure(c) && idx === 0) badges.push('<span class="b b-sure">quasi certa</span>');
  if (c.distance != null) badges.push(`<span class="b">${c.distance} m</span>`);
  if (c.strategy === 'cat' && !c.geoVerified) {
    badges.push('<span class="b b-warn">posizione non verificata</span>');
  }
  if (c.weak) badges.push('<span class="b b-weak">forse un cartello/dettaglio</span>');

  // Le categorie del file sono il modo piu' rapido per accorgersi di un
  // omonimo: "Montagne Sainte-Victoire" sotto un rifugio degli Ecrins salta
  // all'occhio molto prima di qualunque euristica.
  const cats = (c.categories || []).slice(0, 4).map((x) => esc(x)).join(' · ');

  return `
  <label class="cand" data-hut="${esc(hut.id)}" data-file="${esc(c.file)}" data-idx="${idx}">
    <input type="radio" name="h_${esc(hut.id)}" value="${esc(c.file)}">
    <span class="thumbwrap"><img loading="lazy" src="${esc(c.thumb)}" alt=""></span>
    <span class="meta">
      <span class="fname">${idx + 1}. ${esc(c.file.replace(/^File:/, ''))}</span>
      <span class="badges">${badges.join('')}</span>
      ${cats ? `<span class="cats">${cats}</span>` : ''}
      <span class="lic">${esc(c.license)} — ${esc(c.author).slice(0, 70)}</span>
      <a class="ext" href="${esc(c.pageUrl)}" target="_blank" rel="noopener">apri su Commons ↗</a>
    </span>
  </label>`;
}

function hutCard(hut) {
  const place = [hut.city, hut.region, COUNTRY_NAME[hut.country] || hut.country]
    .filter(Boolean).join(' · ');
  const osm = `https://www.openstreetmap.org/?mlat=${hut.lat}&mlon=${hut.lng}#map=15/${hut.lat}/${hut.lng}`;
  const sure = hut.candidates.length && isSure(hut.candidates[0]);
  return `
<section class="hut${sure ? ' sure' : ''}" id="hut_${esc(hut.id)}" data-hut="${esc(hut.id)}"
         data-name="${esc(hut.name.toLowerCase())}" data-country="${esc(hut.country)}"
         data-sure="${sure ? '1' : ''}" data-surefile="${sure ? esc(hut.candidates[0].file) : ''}">
  <header>
    <div>
      <h2>${esc(hut.name)}</h2>
      <div class="place">${esc(place)} · <a href="${esc(osm)}" target="_blank" rel="noopener">dov'è ↗</a></div>
    </div>
    <div class="hstate"><span class="tick"></span></div>
  </header>
  <div class="cands">
    ${hut.candidates.map((c, i) => candidateCard(hut, c, i)).join('')}
    <label class="cand none">
      <input type="radio" name="h_${esc(hut.id)}" value="">
      <span class="nonebox">nessuna<br><small>(0)</small></span>
    </label>
  </div>
</section>`;
}

const html = `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Foto rifugi — revisione</title>
<style>
:root{
  --bg:#f6f7f9; --card:#fff; --ink:#14181d; --dim:#6b7480; --line:#e2e6ea;
  --accent:#1f7a4d; --accentSoft:#e6f4ec; --warn:#b4530a; --warnSoft:#fdf0e3;
}
@media (prefers-color-scheme:dark){
  :root{ --bg:#101418; --card:#181d23; --ink:#e8ecf1; --dim:#98a2ad; --line:#2a3138;
         --accent:#54c08a; --accentSoft:#17301f; --warn:#e0964c; --warnSoft:#2e2216; }
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
  font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
header.top{position:sticky;top:0;z-index:20;background:var(--card);
  border-bottom:1px solid var(--line);padding:12px 18px;
  display:flex;gap:14px;align-items:center;flex-wrap:wrap}
header.top h1{font-size:16px;margin:0;font-weight:640;letter-spacing:-.01em}
.sub{color:var(--dim);font-size:13px}
.grow{flex:1}
input[type=search],select{font:inherit;padding:6px 10px;border:1px solid var(--line);
  border-radius:8px;background:var(--bg);color:var(--ink)}
button{font:inherit;padding:7px 13px;border:1px solid var(--line);border-radius:8px;
  background:var(--bg);color:var(--ink);cursor:pointer}
button.primary{background:var(--accent);border-color:var(--accent);color:#fff;font-weight:600}
button:disabled{opacity:.45;cursor:default}
.bar{height:4px;background:var(--line);border-radius:3px;width:180px;overflow:hidden}
.bar i{display:block;height:100%;background:var(--accent);width:0;transition:width .2s}
main{padding:18px;max-width:1180px;margin:0 auto}
.hut{background:var(--card);border:1px solid var(--line);border-radius:14px;
  padding:14px 16px;margin-bottom:14px}
.hut.done{border-color:var(--accent)}
.hut.hide{display:none}
.hut header{display:flex;align-items:flex-start;gap:12px;margin-bottom:10px}
.hut h2{font-size:16px;margin:0 0 2px;font-weight:640}
.place{color:var(--dim);font-size:13px}
.place a{color:var(--dim)}
.tick{display:inline-block;width:22px;height:22px;border-radius:50%;
  border:1.5px solid var(--line)}
.hut.done .tick{background:var(--accent);border-color:var(--accent)}
.hut.done .tick::after{content:"✓";color:#fff;display:block;text-align:center;
  line-height:19px;font-size:13px}
.cands{display:flex;gap:10px;overflow-x:auto;padding-bottom:4px}
.cand{flex:0 0 240px;border:2px solid var(--line);border-radius:11px;overflow:hidden;
  cursor:pointer;background:var(--bg);display:flex;flex-direction:column}
.cand input{position:absolute;opacity:0;pointer-events:none}
.cand:has(input:checked){border-color:var(--accent);background:var(--accentSoft)}
.thumbwrap{display:block;height:150px;background:var(--line);overflow:hidden}
.thumbwrap img{width:100%;height:100%;object-fit:cover;display:block}
.meta{display:block;padding:8px 9px 10px;font-size:12px}
.fname{display:block;font-weight:600;line-height:1.3;margin-bottom:5px;
  overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical}
.badges{display:flex;flex-wrap:wrap;gap:4px;margin-bottom:5px}
.b{font-size:10.5px;padding:1.5px 6px;border-radius:20px;background:var(--line);
  color:var(--dim);white-space:nowrap}
.b-geo{background:var(--accentSoft);color:var(--accent)}
.b-cat{background:var(--accentSoft);color:var(--accent);font-weight:600}
.b-warn{background:var(--warnSoft);color:var(--warn);font-weight:600}
.b-weak{background:var(--warnSoft);color:var(--warn)}
.b-sure{background:var(--accent);color:#fff;font-weight:600}
.cats{display:block;color:var(--dim);font-size:10.5px;margin-bottom:4px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.lic{display:block;color:var(--dim);font-size:10.5px;margin-bottom:4px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ext{font-size:11px;color:var(--accent);text-decoration:none}
.cand.none{flex:0 0 92px;align-items:center;justify-content:center}
.nonebox{text-align:center;color:var(--dim);font-size:13px;padding:10px}
.empty{color:var(--dim);text-align:center;padding:40px}
kbd{background:var(--line);border-radius:4px;padding:1px 5px;font-size:11px;
  font-family:ui-monospace,monospace}
</style>

<header class="top">
  <div>
    <h1>Foto rifugi — revisione</h1>
    <div class="sub" id="counts"></div>
  </div>
  <div class="grow"></div>
  <input type="search" id="q" placeholder="cerca un rifugio…" size="18">
  <select id="fCountry"><option value="">tutti i paesi</option>
    ${countries.map((c) => `<option value="${esc(c)}">${esc(COUNTRY_NAME[c] || c)}</option>`).join('')}
  </select>
  <select id="fState">
    <option value="todo">da rivedere</option>
    <option value="all">tutti</option>
    <option value="sure">solo quasi certe</option>
    <option value="ok">approvati</option>
  </select>
  <div class="bar"><i id="barfill"></i></div>
  <button id="bulk">approva le quasi certe</button>
  <button id="copy">copia JSON</button>
  <button class="primary" id="dl">scarica approvals.json</button>
</header>

<main>
  <p class="sub" style="margin:0 0 14px">
    Una foto per rifugio: clic sulla miniatura per approvarla, clic su <b>nessuna</b>
    per archiviare il rifugio senza foto. Le scelte restano salvate nel browser anche
    se chiudi la pagina. Scorciatoie: <kbd>1</kbd>–<kbd>6</kbd> scegli, <kbd>0</kbd>
    nessuna, <kbd>j</kbd>/<kbd>k</kbd> rifugio successivo/precedente.
  </p>
  ${data.huts.map(hutCard).join('')}
  <p class="empty" id="nores" style="display:none">Nessun rifugio con questi filtri.</p>
</main>

<script>
const KEY = 'trailshare_photo_review_v1';
const NAMES = ${JSON.stringify(Object.fromEntries(data.huts.map((h) => [h.id, h.name])))};
const META = ${JSON.stringify(Object.fromEntries(data.huts.map((h) => [h.id,
  Object.fromEntries(h.candidates.map((c) => [c.file, {
    strategy: c.strategy, license: c.license, author: c.author,
    pageUrl: c.pageUrl, geoVerified: c.geoVerified !== false,
  }]))])))};
const TOTAL = ${data.huts.length};

let state = {};
try { state = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (e) { state = {}; }
const save = () => localStorage.setItem(KEY, JSON.stringify(state));

function approvals() {
  return Object.entries(state)
    .filter(([, f]) => f)
    .map(([id, f]) => ({ id, name: NAMES[id], file: f, ...(META[id] || {})[f] }));
}

function refresh() {
  const rev = Object.keys(state).length, ok = approvals().length;
  const pendingSure = [...document.querySelectorAll('.hut[data-sure="1"]')]
    .filter((h) => state[h.dataset.hut] === undefined).length;
  document.getElementById('counts').textContent =
    rev + ' / ' + TOTAL + ' rifugi rivisti — ' + ok + ' foto approvate';
  document.getElementById('barfill').style.width = (rev / TOTAL * 100) + '%';
  document.getElementById('dl').disabled = ok === 0;
  document.getElementById('copy').disabled = ok === 0;
  const b = document.getElementById('bulk');
  b.textContent = 'approva le ' + pendingSure + ' quasi certe';
  b.disabled = pendingSure === 0;
}

document.querySelectorAll('.hut').forEach((h) => {
  const id = h.dataset.hut, cur = state[id];
  if (cur !== undefined) {
    h.classList.add('done');
    // confronto sui valori, non un selettore CSS: i titoli dei file possono
    // contenere virgolette e romperebbero l'attributo
    const inp = [...h.querySelectorAll('input')].find((x) => x.value === cur);
    if (inp) inp.checked = true;
  }
  // Niente applyFilter() qui: se la scheda sparisse appena scelta non si
  // potrebbe piu' correggere un clic sbagliato. Resta visibile con la spunta
  // e si toglie di mezzo al prossimo cambio di filtro.
  h.addEventListener('change', (e) => {
    state[id] = e.target.value || '';
    h.classList.add('done');
    save(); refresh();
  });
});

function applyFilter() {
  const q = document.getElementById('q').value.trim().toLowerCase();
  const co = document.getElementById('fCountry').value;
  const st = document.getElementById('fState').value;
  let shown = 0;
  document.querySelectorAll('.hut').forEach((h) => {
    const id = h.dataset.hut;
    let ok = true;
    if (q && !h.dataset.name.includes(q)) ok = false;
    if (co && h.dataset.country !== co) ok = false;
    if (st === 'todo' && state[id] !== undefined) ok = false;
    if (st === 'ok' && !state[id]) ok = false;
    if (st === 'sure' && !h.dataset.sure) ok = false;
    h.classList.toggle('hide', !ok);
    if (ok) shown++;
  });
  document.getElementById('nores').style.display = shown ? 'none' : '';
}
['q', 'fCountry', 'fState'].forEach((i) =>
  document.getElementById(i).addEventListener('input', applyFilter));

// Approvazione in blocco: tocca SOLO i rifugi non ancora decisi e solo la
// prima proposta quando e' della classe "quasi certa". Chiede conferma
// dicendo quanti sono, cosi' non si preme per sbaglio.
document.getElementById('bulk').onclick = () => {
  const pending = [...document.querySelectorAll('.hut[data-sure="1"]')]
    .filter((h) => state[h.dataset.hut] === undefined);
  if (!pending.length) { alert('Nessuna proposta "quasi certa" ancora da decidere.'); return; }
  const msg = 'Approvo la prima foto di ' + pending.length + ' rifugi con categoria ' +
    'Commons omonima verificata entro 500 m.\\n\\nPuoi sempre correggerne una a mano ' +
    'dopo: restano tutte modificabili.';
  if (!confirm(msg)) return;
  for (const h of pending) {
    const f = h.dataset.surefile;
    const inp = [...h.querySelectorAll('input')].find((x) => x.value === f);
    if (inp) inp.checked = true;
    state[h.dataset.hut] = f;
    h.classList.add('done');
  }
  save(); refresh();
};

function payload() {
  return JSON.stringify({
    reviewedAt: new Date().toISOString(),
    reviewed: Object.keys(state).length,
    approvals: approvals(),
  }, null, 1);
}
document.getElementById('dl').onclick = () => {
  const b = new Blob([payload()], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(b); a.download = 'approvals.json'; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
};
document.getElementById('copy').onclick = async () => {
  try { await navigator.clipboard.writeText(payload());
    document.getElementById('copy').textContent = 'copiato ✓';
    setTimeout(() => document.getElementById('copy').textContent = 'copia JSON', 1500);
  } catch (e) { alert('Copia non riuscita, usa il pulsante di download.'); }
};

// tastiera: si rivedono centinaia di schede, il mouse e' il collo di bottiglia
let cursor = 0;
const visible = () => [...document.querySelectorAll('.hut:not(.hide)')];
function focusHut(i) {
  const v = visible(); if (!v.length) return;
  cursor = Math.max(0, Math.min(i, v.length - 1));
  v[cursor].scrollIntoView({ behavior: 'smooth', block: 'center' });
}
document.addEventListener('keydown', (e) => {
  if (e.target.matches('input[type=search],select')) return;
  const v = visible(); const h = v[cursor];
  if (e.key === 'j') { focusHut(cursor + 1); e.preventDefault(); }
  else if (e.key === 'k') { focusHut(cursor - 1); e.preventDefault(); }
  else if (h && /^[0-9]$/.test(e.key)) {
    const n = parseInt(e.key, 10);
    const inputs = [...h.querySelectorAll('input')];
    const pick = n === 0 ? inputs[inputs.length - 1] : inputs[n - 1];
    if (pick) { pick.checked = true; pick.dispatchEvent(new Event('change', { bubbles: true })); }
    e.preventDefault();
  }
});

refresh(); applyFilter();
</script>
`;

fs.writeFileSync(OUT, html);

const byCountry = {};
for (const h of data.huts) byCountry[h.country] = (byCountry[h.country] || 0) + 1;
const unverified = data.huts.filter((h) =>
  h.candidates.some((c) => c.strategy === 'cat' && !c.geoVerified)).length;

console.log(`Pagina di revisione: ${OUT}`);
console.log(`Rifugi con proposte: ${data.huts.length} su ${data.scanned} interrogati ` +
  `— immagini da vagliare: ${totalImgs}`);
console.log('Per paese: ' + Object.entries(byCountry)
  .sort((a, b) => b[1] - a[1])
  .map(([c, n]) => `${COUNTRY_NAME[c] || c} ${n}`).join(' · '));
console.log(`Da guardare con piu' attenzione (posizione non verificata): ${unverified}`);
console.log(`\nAprila con:  open ${OUT}`);
