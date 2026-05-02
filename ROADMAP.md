# TrailShare — Roadmap di sviluppo

Ultimo aggiornamento: 2026-05-02  ·  Versione corrente: `2.2.0+57` (in Apple Review + Play Store) · Produzione consolidata: `1.9.0+52`

Documento vivo. Le voci sono ordinate per priorità all'interno di ogni categoria. Stima sforzo indicativa in giornate uomo.

---

## Legenda

- **Priorità**: 🟥 critica · 🟧 alta · 🟨 media · 🟩 bassa
- **Effort**: XS (<0.5d) · S (1d) · M (2-3d) · L (1 settimana) · XL (>1 settimana)
- **Status**: ☐ da fare · 🔄 in corso · ✅ fatto · ⚠️ parziale
- **Tier**: Free / Pro / Free+Pro (versione limitata gratis, completa a pagamento)

---

## Epic 1 — Sicurezza (v1.7.0) ✅ rilasciata

Target: rendere TrailShare l'app più sicura per chi va in montagna da solo in Italia.

### 1.A — Feature funzionali

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 1.1 | Lifeline: contatti emergenza + invio link live con token | 🟥 | M | ✅ |
| 1.2 | Pulsante SOS accessibile durante registrazione, integrato con 112 | 🟥 | S | ✅ |
| 1.3 | Auto-alert inattività 2-step (conferma locale → contatti) | 🟥 | S | ✅ |
| 1.4 | Re-routing automatico quando off-trail >100m per >30s | 🟧 | S | ✅ |
| 1.5 | Modalità "Battery saver" (GPS 10s, schermo off forzato) | 🟧 | S | ✅ |
| 1.6 | Widget lock-screen (iOS Live Activities / Android foreground) | 🟨 | M | ⚠️ Android only |

### 1.B — Protezioni tecniche Lifeline

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 1.B1 | Health-check durante Lifeline (ogni 30s) con banner stato 🟢🟡🔴 | 🟥 | S | ✅ |
| 1.B2 | SMS fallback nativo quando manca rete dati ma c'è GSM | 🟧 | S | ✅ |
| 1.B3 | Battery-optimization whitelist prompt al primo avvio Lifeline | 🟧 | S | ✅ |
| 1.B4 | Pulsante 112 sempre accessibile durante registrazione Lifeline | 🟥 | XS | ✅ |
| 1.B5 | Backup locale posizioni (SharedPrefs/SQLite) + retry automatico | 🟧 | S | ✅ |
| 1.B6 | Countdown visuale auto-alert + anti-tap accidentale | 🟥 | XS | ✅ |

### 1.C — Protezioni legali e comunicative

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 1.C1 | Disclaimer obbligatorio al primo uso Lifeline | 🟥 | XS | ✅ |
| 1.C2 | Onboarding testi contatti emergenza | 🟥 | XS | ✅ |
| 1.C3 | Aggiornare ToS con sezione "Limitazioni Lifeline" | 🟥 | XS | ✅ |
| 1.C4 | Aggiornare Privacy Policy | 🟥 | XS | ✅ |
| 1.C5 | Link a GeoResQ in settings Sicurezza | 🟨 | XS | ✅ |
| 1.C6 | Store description priva di claim "salvavita" garantiti | 🟥 | XS | ✅ |

### 1.D — UX mappa registrazione

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 1.D1 | Stats header compatto | 🟧 | S | ✅ |
| 1.D2 | Merge banner guida + lifeline | 🟧 | S | ✅ |
| 1.D3 | Banner lifeline minimizzabile | 🟨 | XS | ✅ |
| 1.D4 | Auto-hide HUD dopo 10s inattività | 🟨 | S | ⚠️ rimandato |

---

## Epic 2 — Completezza funzionale (v1.8.0 / 1.8.1 / 1.8.2) ✅ rilasciata

Target: colmare i gap rispetto a Komoot / AllTrails / Strava.

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 2.1 | POI / Highlights lungo il percorso | 🟧 | M | ✅ |
| 2.2 | Notifica vocale geolocata ai POI durante navigazione | 🟧 | S | ✅ |
| 2.3 | Multi-day tours (aggregazione tracce per "viaggio") | 🟨 | L | ✅ |
| 2.4 | Sharing link pubblico web (`trailshare.app/t/{id}`) | 🟧 | M | ✅ |
| 2.5 | Esportazione TCX / FIT / KML | 🟨 | S | ✅ |
| 2.6 | Dark mode app-wide (con `ThemeColorsExtension`) | 🟨 | M | ✅ |
| 2.7 | Onboarding interattivo + tutorial REC | 🟨 | M | ✅ |

Polish post-1.8.0 (Sprint UX audit Claude Design):
- 1.8.1: profilo riorganizzato (sezioni accordion), Discovery Carousel, theme-aware colors
- 1.8.2: fix manifest READ_MEDIA Play Console + bump versionCode

---

## Epic 3 — Engagement (v1.9.0) ✅ in test

Target: aumentare ritenzione e dwell time.

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 3.1 | Sfide settimanali personali generative | 🟧 | M | ✅ |
| 3.2 | Sfide gruppo / amici | 🟨 | L | ☐ rimandato a v2.x |
| 3.3 | Classifiche regionali (per regione + mese) | 🟨 | M | ✅ |
| 3.4 | Heatmap trail popolari | 🟨 | M | ☐ rimandato a v2.x |
| 3.5 | Commenti sulle tracce community | 🟨 | S | ✅ |
| 3.6 | Mentions/tags utenti nei commenti | 🟩 | S | ☐ rimandato |
| 3.7 | Report mensile automatico "Il mio mese" | 🟨 | M | ✅ |
| 3.8 | Compass-up navigation in registrazione | 🟧 | S | ✅ (fuori roadmap iniziale) |

---

## Epic 4 — Miglioramento funzioni esistenti (target v2.0+ continuo)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 4.1 | Navigazione: preview pre-partenza con ETA | 🟧 | XS | ⚠️ parziale |
| 4.2 | Navigazione: waypoint intermedi | 🟨 | XS | ☐ |
| 4.3 | Navigazione: pausa automatica se fermo >5 min | 🟨 | XS | ☐ |
| 4.4 | Discover: ricerca testuale full-text | 🟧 | S | ☐ |
| 4.5 | Discover: filtro per regione amministrativa | 🟨 | S | ⚠️ parziale (3.3 ha aggiunto regioni) |
| 4.6 | Track detail: grafico HR per zone | 🟨 | S | ☐ |
| 4.7 | Track detail: confronto con PR personale | 🟨 | M | ☐ |
| 4.8 | Track detail: split per km con tempo cumulativo | 🟩 | XS | ☐ |
| 4.9 | Mappe dark reale (Stadia/MapTiler con API key) | 🟩 | S | ☐ |

---

## Epic 5 — Polish & Performance (target v2.x continuo)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 5.1 | Widget home-screen iOS/Android | 🟨 | M | ☐ |
| 5.2 | Apple Watch companion app | 🟩 | XL | ☐ |
| 5.3 | Garmin Connect IQ app | 🟩 | XL | ☐ |
| 5.4 | Merge/split tracce | 🟩 | S | ☐ |
| 5.5 | Tag/categorie personalizzate sulle tracce | 🟩 | S | ☐ |
| 5.6 | Ricerca nelle proprie tracce | 🟨 | XS | ☐ |

---

## Epic 6 — Monetization & Premium (v2.0.0 → v2.3.0) ⚠️ in rilascio

Obiettivo: trasformare TrailShare in **freemium sostenibile** con feature "wow non
indispensabili" che giustificano l'upgrade. Lifeline e tutto il core safety/recording
restano **sempre gratis** — la sicurezza non si paga.

### 6.A — Wow features (pull factor)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 6.1 | Mountain recognition AR live (top 5 cime) | 🟧 | M | Free | ✅ |
| 6.2 | Mountain recognition photo + analisi completa + share | 🟧 | L | Pro | ✅ |
| 6.3 | 3D fly-through replay delle tracce | 🟨 | L | Pro | ☐ |
| 6.4 | Mappe topografiche premium (Topo / Hybrid / Inverno via MapTiler) | 🟧 | M | Pro | ✅ |
| 6.5 | Allenamento HR personalizzato basato su storico | 🟨 | M | Pro | ☐ |
| 6.6 | Trail conditions AI summary (riassunto da commenti recenti) | 🟨 | M | Pro | ☐ |
| 6.7 | Pianificatore IA "trova percorso simile a..." | 🟨 | M | Pro | ☐ |
| 6.8 | Time-lapse video auto della traccia + foto | 🟩 | M | Pro | ☐ |

#### Approfondimento 6.1 / 6.2 — Mountain Recognition

**Approccio ibrido in due fasi:**

**Fase 1 (v2.0.0) — AR overlay live (Free)**
Camera preview + GPS + bussola + giroscopio. Query OSM Overpass per `natural=peak`
nel cono visibile (raggio 50 km), proiezione 2D con bearing + altitude delta + camera FOV.
Limite gratuito: max 5 cime visibili contemporaneamente, niente salvataggio.

Stack:
- `camera` plugin per preview
- `flutter_compass` (già in pubspec) + `sensors_plus` per giroscopio/tilt
- Overpass API + cache offline SQLite (~12.000 cime italiane, <2 MB)
- Math: bearing Haversine + projection con FOV 60° standard

**Fase 2 (v2.1.0) — Photo recognition completa (Pro)**
- Scatto + GPS + heading inviati al backend
- Cloud Function ricalcola l'intero panorama identificabile (cime infinite)
- Restituisce foto annotata + share pubblico + salvataggio in galleria personale
- Backend: Cloud Run + skyline matching (no ML pesante, geometria pura)

### 6.B — Infrastruttura paywall

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 6.B1 | Subscription manager (in_app_purchase 3.x → StoreKit 2 / Play Billing) | 🟥 | L | ✅ |
| 6.B1.5 | PaywallSheet context-aware (3 layout: free / monthly / yearly) | 🟧 | S | ✅ |
| 6.B2 | Cloud Function `validateAppleReceipt` con JWS verification | 🟥 | M | ✅ |
| 6.B3 | Premium status sync su `users/{uid}.proStatus` cross-device | 🟥 | S | ✅ |
| 6.B4 | `PaywallSheet` widget + dinamiche prezzi locale | 🟧 | M | ✅ |
| 6.B5 | Trial 14 giorni gratis (yearly only) con flag isInTrial | 🟧 | S | ✅ |
| 6.B6 | Discovery prompt "Scopri Pro" con A/B variant | 🟧 | S | ☐ |
| 6.B7 | Restore purchases + deep link "Gestisci abbonamento" | 🟧 | S | ✅ |
| 6.B8 | Analytics conversion funnel + churn tracking (Firebase) | 🟨 | S | ☐ |
| 6.B9 | App Store Server Notifications V2 webhook (rinnovi/refund/revoke) | 🟧 | M | ☐ |
| 6.B10 | Cloud Function `validateGoogleReceipt` (quando si apre P.IVA) | 🟥 | M | ☐ |

### 6.C — Lifecycle premium

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 6.C1 | Settings "Gestisci abbonamento" + cancellazione | 🟥 | XS | ✅ |
| 6.C2 | Email "Stai per perdere Pro" 3gg prima scadenza (FCM + email) | 🟧 | S | ☐ |
| 6.C3 | Benefit reminder ogni 30gg ("usato N volte le mappe Pro") | 🟨 | S | ☐ |
| 6.C4 | Lifetime discount per utenti attivi (>50 tracce) | 🟨 | S | ☐ |
| 6.C5 | "Regala Pro a un amico" (referral con sconto reciproco) | 🟩 | M | ☐ |

### Pricing TrailShare Pro

- **€2,99/mese** o **€19,99/anno** (sconto -44%)
- Trial 14gg gratis dal Discovery prompt
- Lifetime discount -30% per utenti attivi >50 tracce al lancio
- Family sharing nativo (Apple/Google) → unico abbonamento, fino a 6 membri

Posizionamento mercato IT outdoor:
- AllTrails Plus: €35.99/anno
- Komoot: €29.99/anno (singola regione)
- Strava: €74.99/anno
- **TrailShare Pro: €19.99/anno** — entry-level accessibile, hook viral
  con mountain recognition free.

---

## Epic 7 — B2B Business (target v2.3.0 → v2.5.0) ⚠️ in sviluppo

Obiettivo: aprire un **secondo flusso di ricavi** vendendo TrailShare a hotel di
montagna, rifugi, noleggi ebike e guide outdoor che vogliono offrire ai propri
clienti tracce consigliate brandizzate. Un singolo abbonamento Business (~€19,99/mese)
sostituisce/affianca decine di abbonamenti Pro consumer e apre potenziale di scaling
viral (ogni hotel = canale di acquisizione utenti free verso l'app).

Demo a primo cliente (B&B Baita del Dutur, MTB MolaMia) → 2026-05-02 → **feedback positivo**.

### 7.A — Visual customization (white-label)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 7.A1 | Group.isBusinessGroup flag + admin panel toggle (super admin) | 🟥 | S | Business | ✅ L1 |
| 7.A2 | Logo personalizzato (avatar quadrato) + badge ✓ verificato | 🟥 | S | Business | ✅ L1 |
| 7.A3 | Cover image 16:9 fullwidth nell'header del detail group | 🟧 | M | Business | ☐ L2 |
| 7.A4 | Brand color picker (sostituisce arancio TS negli accenti dentro al gruppo) | 🟨 | M | Business | ☐ L2 |
| 7.A5 | Welcome screen personalizzato al primo accesso al gruppo | 🟨 | M | Business | ☐ L3 |
| 7.A6 | Card invito QR brandizzata stampabile (PDF con logo + QR + colori) | 🟧 | M | Business | ☐ L3 |

### 7.B — Group management & content

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 7.B1 | Tracce condivise nei gruppi (Track.groupIds + tab Percorsi) | 🟥 | M | Business | ✅ |
| 7.B2 | Statistiche aggregate per admin (visualizzazioni/follow per traccia) | 🟧 | M | Business | ☐ L2 |
| 7.B3 | Member limit configurabile (50 default, 200 Business, custom enterprise) | 🟧 | S | Business | ☐ L2 |
| 7.B4 | Multi-admin: delegare gestione tracce a più persone | 🟨 | S | Business | ☐ |
| 7.B5 | Categorie/tag tracce (es. "Facile", "Famiglia", "Sunset ride") | 🟨 | S | Business | ☐ |
| 7.B6 | Programmazione eventi ricorrenti (es. "Ogni venerdì uscita guidata") | 🟩 | M | Business | ☐ |

### 7.C — Monetization Business tier

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 7.C1 | Definire pricing finale (€9,99 / €19,99 / €29,99/mese — A/B test) | 🟥 | XS | ☐ |
| 7.C2 | Setup IAP `trailshare_business_monthly` + `_yearly` su App Store Connect | 🟥 | S | ☐ |
| 7.C3 | Setup equivalenti su Play Console (richiede P.IVA) | 🟥 | S | ☐ blocked-PIVA |
| 7.C4 | Logica gating: `isBusinessGroup=true` solo se admin ha sub Business | 🟥 | M | ☐ |
| 7.C5 | "Founders pricing": primi 10 clienti €9,99/mese for life | 🟧 | XS | ☐ |
| 7.C6 | Onboarding flow Business (create group + carica logo + setup percorsi) | 🟧 | M | ☐ |
| 7.C7 | Fatturazione: integrazione Stripe / FattureInCloud per ricevute IT | 🟨 | L | ☐ richiede P.IVA |

### 7.D — Acquisition channels

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 7.D1 | Outreach 50 noleggi ebike Lombardia (template email + video 60s) | 🟥 | M | ☐ |
| 7.D2 | Partnership Federalberghi locali (presentazioni meeting mensili) | 🟧 | M | ☐ |
| 7.D3 | Landing page B2B dedicata `trailshare.app/business` | 🟧 | M | ☐ vedi Epic 8 |
| 7.D4 | Case study primo cliente (testimonianza + screenshot reali) | 🟧 | S | ☐ post-demo |
| 7.D5 | Cosmo Bike Show Verona (settembre, demo 30 stand in 3 giorni) | 🟨 | L | ☐ se budget |
| 7.D6 | Reddit/Forum outdoor IT (case study come post organico) | 🟩 | XS | ☐ |

---

## Epic 8 — Web ecosystem (target v2.4.0 → v2.6.0)

Obiettivo: passare da **app-only** a **piattaforma multi-touch**. Sito web pubblico per
SEO/marketing + dashboard personale Pro + dashboard gestionale Business + landing pages
brandizzate per gruppi (vetrina hotel pubblica). Tutto stessa Firebase, single sign-on.

### Stack: marketing site + product apps separati

Verifica fatta 2026-05-02: il sito esistente (`trailshare-website/` submodule) è già
**HTML/CSS/JS vanilla** (non Flutter Web). 8 pagine statiche + 2 dinamiche
(`pages/track.html`, `pages/tour.html`) + `js/main.js` + Firebase Web SDK.

Decisione: **NON migrare quanto esiste** — il vanilla è perfetto per marketing/SEO.
Aggiungere SvelteKit SOLO per le dashboard interattive loggate. Pattern industry
standard: marketing in HTML statico (Apple, Stripe, Linear), product app in framework
SPA.

| Categoria | Pagine | Stack | Repository |
|---|---|---|---|
| Marketing/SEO | `/`, `/help`, `/privacy`, `/terms`, `/pro`, `/business`, `/g/{groupId}` | HTML/CSS/JS vanilla esistente | `trailshare-website/` |
| Product Pro | `app.trailshare.app/...` | SvelteKit + Firebase Web SDK + Tailwind | nuovo `dashboards/app/` |
| Product Business | `business.trailshare.app/...` | SvelteKit + Firebase Web SDK + Tailwind | nuovo `dashboards/business/` |

Hosting: tutti su Firebase Hosting con configurazione **multi-site** in `firebase.json`.

Piano legacy parcheggiato: [`docs/WEB_DASHBOARD_PLAN.md`](docs/WEB_DASHBOARD_PLAN.md) — superato da Epic 8.

### 8.A — Marketing site `trailshare.app` (HTML vanilla, target v2.4.0)

Continua sul codebase esistente `trailshare-website/`. Niente framework, niente
build tooling — solo aggiungere file HTML nuovi e migliorare quelli esistenti.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 8.A1 | Landing pubblica `/` rinnovata: feature carousel + download CTA + screenshot recenti | 🟧 | S | Free | ⚠️ esistente, da rinfrescare |
| 8.A2 | Pagina `/pro.html` (pricing €2.99/€19.99, screenshot, 14gg trial CTA) | 🟥 | S | Free | ☐ blocking-Apple |
| 8.A3 | Pagina `/business.html` (B2B pitch + case study Baita del Dutur + form contatto) | 🟧 | M | Free | ☐ |
| 8.A4 | Blog tecnico (SEO outdoor IT: "5 sentieri Lombardia in autunno" ecc) | 🟨 | M | Free | ☐ |
| 8.A5 | Privacy policy + terms aggiornati per IAP Apple/Google | 🟧 | XS | Free | ⚠️ esistente, da rivedere |
| 8.A6 | OG tags + Twitter card su `/track/{id}` e `/tour/{id}` per condivisioni social | 🟨 | S | Free | ☐ |
| 8.A7 | Sitemap + robots.txt + Schema.org `MobileApplication` per ranking | 🟨 | XS | Free | ☐ |

### 8.B — Pro user dashboard `app.trailshare.app` (target v2.5.0)

Per utenti Pro (consumer) loggati con stesso Firebase Auth. Read-only per ora,
editing è in-app.

**Setup tech (one-time, ~1gg)**: SvelteKit project in `dashboards/app/`, integrazione
Firebase Web SDK, Tailwind CSS, deploy su `app.trailshare.app` via Firebase multi-site
hosting (aggiunge entry in `firebase.json hosting` array). Auth condivisa con app
mobile via stesso Firebase project.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 8.B0 | Setup SvelteKit + Firebase Web SDK + Tailwind + multi-site hosting | 🟥 | M | Free | ☐ |
| 8.B1 | Auth web (Apple Sign-In + Google + email) condivisa con app | 🟥 | M | Free | ☐ |
| 8.B2 | Lista tracce personali + filtri/ricerca + mappa generale | 🟥 | M | Free | ☐ |
| 8.B3 | Track detail web con mappa interattiva + grafici elevazione/HR | 🟥 | M | Free | ☐ |
| 8.B4 | Dashboard analytics Pro: km totali, dislivello, calorie, trend mensili | 🟧 | M | Pro | ☐ |
| 8.B5 | Heatmap personale (dove sono andato di più) | 🟨 | S | Pro | ☐ |
| 8.B6 | Confronto periodo su periodo (mese vs mese, anno vs anno) | 🟨 | S | Pro | ☐ |
| 8.B7 | Export massivo GPX/FIT/TCX in zip | 🟨 | S | Pro | ☐ |
| 8.B8 | Gestione abbonamento web (cancel, fatture, upgrade mensile→annuale) | 🟧 | M | Pro | ☐ |
| 8.B9 | Embed pubblico tracce: `trailshare.app/t/{slug}` per condivisione social | 🟨 | S | Free | ☐ |

### 8.C — Business owner dashboard `business.trailshare.app` (target v2.5.0 → v2.6.0)

Per admin di gruppi Business. Operativa, non solo consultazione.

**Setup tech (one-time, ~0.5gg)**: SvelteKit project in `dashboards/business/`, riusa
le configurazioni Firebase + Tailwind di 8.B0. Layout/branding diverso da `/app`
(più "amministrativo", colori brand del cliente quando dentro un gruppo).

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 8.C0 | Setup SvelteKit project (riusa stack 8.B0) + deploy multi-site | 🟥 | S | Business | ☐ |
| 8.C1 | Onboarding "Crea il tuo gruppo Business" guidato (logo upload, nome, ecc) | 🟥 | M | Business | ☐ |
| 8.C2 | Editor percorsi consigliati: lista + drag&drop ordine + aggiungi/rimuovi | 🟥 | L | Business | ☐ |
| 8.C3 | Statistiche dashboard: utenti attivi/mese, tracce più aperte, churn | 🟥 | L | Business | ☐ |
| 8.C4 | Editor branding (logo, cover, brand color) — alternativa al mobile | 🟧 | M | Business | ☐ |
| 8.C5 | Generatore card invito PDF (logo + QR + colori) — stampa 1 click | 🟧 | M | Business | ☐ |
| 8.C6 | Member management: vedi lista, rimuovi spam, promuovi altri admin | 🟧 | M | Business | ☐ |
| 8.C7 | Bulk import tracce GPX (drag&drop file → crea tracce + condividi nel gruppo) | 🟧 | M | Business | ☐ |
| 8.C8 | Notifiche broadcast ai membri (push via FCM dal web) | 🟨 | S | Business | ☐ |
| 8.C9 | Fatturazione + storico pagamenti (richiede 7.C7) | 🟨 | M | Business | ☐ |

### 8.D — Public group landing pages `trailshare.app/g/{groupId}` (target v2.6.0)

Vetrine pubbliche per gruppi Business: marketing tool gratis che gli hotel possono
condividere su Booking, Instagram, sito proprio.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 8.D1 | Landing brandizzata: cover + logo + descrizione + lista tracce preview | 🟧 | M | Business | ☐ |
| 8.D2 | Map view aggregata di tutti i percorsi del gruppo | 🟧 | S | Business | ☐ |
| 8.D3 | CTA "Scarica TrailShare e unisciti" con codice/QR pre-compilato | 🟥 | S | Business | ☐ |
| 8.D4 | SEO: meta tags, OG image dinamica generata dal logo+nome | 🟨 | S | Business | ☐ |
| 8.D5 | Custom domain support (es. `mtb.baitaduturhotel.it` → trailshare group) | 🟩 | L | Enterprise | ☐ |

### 8.E — Backend complementare (Cloud Functions web-side)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 8.E1 | Function `getGroupAnalytics(groupId)` per dashboard 8.C3 | 🟧 | M | ☐ |
| 8.E2 | Function `generateInviteCardPdf(groupId)` con `pdf-lib` | 🟧 | S | ☐ |
| 8.E3 | Function `searchTracksFulltext(query)` per ricerca cross-app/web | 🟨 | M | ☐ |
| 8.E4 | Webhook handler Stripe (se attivata 7.C7) | 🟧 | S | ☐ |

---

## Versioning attuale e prossimi target

### Storico

| Versione | Stato | Contenuto |
|---|---|---|
| v1.5.6 | Produzione storica | Security hardening |
| v1.6.0 | Produzione storica | Unificazione Segui-traccia + community |
| v1.7.0+47 | Produzione storica | Epic 1 — Sicurezza completa |
| v1.8.0+48 | Test/superato | Epic 2 — POI, tours, sharing, export, dark, onboarding |
| v1.8.1 | Test/superato | Sprint UX audit (profilo, discovery carousel) |
| v1.8.2+51 | Produzione | Fix manifest READ_MEDIA |
| **v1.9.0+52** | **Produzione consolidata** | Epic 3 — Engagement (compass, sfide, commenti, report, classifiche) |
| v2.0.0 | Skipped (mai rilasciato standalone) | Foundation paywall accorpato in 2.1 |
| v2.1.0+55 | Test interno superato | Mountain Recognition AR + Photo Mode + paywall foundation |
| v2.1.1+56 | Apple Review cancellata, Play Store rilasciata | 3 stili mappa Pro (Topo, Hybrid, Inverno) MapTiler |
| **v2.2.0+57** | **Apple Review + Play Store rolling** | B2B Groups L1 (logo + badge verificato), tracce condivise nei gruppi, fix UI |

### Prossimi target

- **v2.2.0+57** ✅ in review Apple + Play Store. Contiene: 6.A1, 6.A2, 6.4 (mappe Pro),
  tutta 6.B salvo B6/B8/B9/B10, 6.C1, 7.A1, 7.A2, 7.B1.
- **Mini-sprint web (~2gg, no version bump app)** — Solo `trailshare-website/`:
  aggiungi `/pro.html` (8.A2) e `/business.html` (8.A3) al sito vanilla esistente.
  Sblocca link da Apple/Play Store per pricing details. Update privacy/terms (8.A5).
- **v2.3.0** — Epic 7 Business L2: cover image + brand color (7.A3, 7.A4) + statistiche
  aggregate (7.B2) + member limit (7.B3). Setup IAP Business (7.C2). Founders pricing
  (7.C5). Discovery prompt Pro (6.B6). Webhook V2 Apple (6.B9).
- **v2.4.0** — Acquisition outreach (7.D1, 7.D2, 7.D4) + landing rinnovo (8.A1) +
  blog tecnico (8.A4) + OG cards (8.A6). Webhook V2 a regime, churn dashboard (6.B8).
- **v2.5.0** — **Setup SvelteKit dashboards (8.B0, 8.C0)** + Pro user dashboard MVP
  (8.B1-B5). Onboarding Business web (8.C1). Member management (8.C6).
- **v2.6.0** — Editor percorsi web (8.C2) + statistiche Business (8.C3) + landing
  pages pubbliche per gruppi (8.D1-D4) + bulk import tracce (8.C7) + card invito
  PDF (8.C5).
- **v2.7.0+** — Lifecycle premium completo (6.C2-C5), AI features (6.6 / 6.7),
  3D fly-through (6.3). Custom domain Business enterprise (8.D5).

### Criteri di rilascio v2.3.0 (next)

1. Almeno 1 cliente Business attivo (anche gratis founders) con feedback raccolto
2. Cover image upload funzionante con compressione lato app (<500 KB target)
3. Brand color picker integrato in Theme dinamico dentro il gruppo
4. Statistiche tracce aperte/seguite calcolate via collectionGroup query
5. Webhook V2 Apple riceve eventi DID_RENEW / EXPIRED in produzione

---

## Storico versioni (release notes essenziali)

### v2.2.0+57 (Apple Review + Play Store, 2026-05-02)
- **B2B Groups L1**: logo personalizzato per gruppi Business (`Group.isBusinessGroup`)
- Badge ✓ verificato accanto al nome del gruppo (lista, header, info tab)
- Pagina Personalizza Gruppo dedicata (visibile solo admin di gruppi Business)
- Admin panel super admin: dialog "Marca come Business" cercando per Group ID
- Tracce condivise nei gruppi via `Track.groupIds` + nuovo tab "Percorsi"
- Force-server fetch su Firestore al return da detail page (no stale cache)
- Fix AppBar truncation con LayoutBuilder + Expanded
- Storage rules per `groups/{gid}/logo.jpg`

### v2.1.1+56 (Play Store rilasciata, Apple Review cancellata, 2026-04-30)
- 3 stili mappa Pro via MapTiler: Topo Pro, Hybrid Satellite Pro, Inverno Pro
- Picker mappa ridisegnato: bottom sheet scrollabile con badge PRO + lock
- API key MapTiler restretta a User-Agent `TrailShareApp` (anti-leak)
- Trigger PaywallSheet `mapStylePro` con copy dedicato
- Cross-device Pro sync via `users/{uid}.proStatus` (Epic 6.B3 closing)

### v2.1.0+55 (test interno superato, 2026-04-28)
- Mountain Recognition AR live (37.000+ cime italiane, free tier max 5 visibili)
- Photo Mode Pro (panorama annotato + share)
- Paywall foundation completa: SubscriptionManager, PaywallSheet context-aware,
  ReceiptValidatorService con JWS verification via @apple/app-store-server-library
- IAP: `trailshare_pro_monthly` €2,99 + `trailshare_pro_yearly` €19,99 con trial 14gg
- Cloud Function `validateAppleReceipt` europe-west3 + Firestore proStatus sync

### v1.9.0+52 (test interno, 2026-04)
- Compass-up navigation con sensor fusion GPS + magnetometro + LPF
- Sfide settimanali personalizzate (4 tipi, generator basato su 8 settimane storiche)
- Commenti sulle tracce community con moderazione owner
- Report mensile automatico "Il mio mese" + Discovery prompt nei primi 7gg
- Classifiche regionali per regione (totale + mese in corso) con denormalizzazione

### v1.8.2+51 (in review Play Store, 2026-04)
- Fix manifest: rimossa READ_MEDIA_IMAGES con `tools:node="remove"` per Play Console policy

### v1.8.0+48 (Aprile 2026)
- POI lungo il percorso + notifiche vocali geolocate
- Multi-day tours (aggregatore post-hoc)
- Sharing link web (`trailshare.app/track/{id}` e `/tour/{id}`)
- Export TCX / FIT / KML (oltre GPX)
- Onboarding rifocalizzato su Lifeline + tutorial REC
- Dark mode con `ThemeColorsExtension` theme-aware

### v1.7.0+47 (produzione, 2026-03)
- Lifeline completa con SOS, auto-alert, SMS fallback, health-check
- Disclaimer + ToS + Privacy aggiornati
- UX mappa registrazione compatta

### v1.6.0 (2026-04-16)
- Unificazione "Segui traccia" su RecordPage
- Auto-detect activity type
- Community + condizioni trail + segmenti + foto + recensioni

### v1.5.6 (2026-04-15)
- Security hardening (hardcoded secrets, BLE leak)

---

*Ogni Epic completata → bump minor version. Ogni voce va marchiata come ✅
quando è in produzione su Store e Crashlytics non mostra regressioni.*
