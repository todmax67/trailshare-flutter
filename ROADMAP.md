# TrailShare — Roadmap di sviluppo

Ultimo aggiornamento: 2026-05-16  ·  Versione corrente: `v2.4.5+72` (build artifact pronto per upload Apple+Play; serie hotfix da 2.4.3 per profilo OOM, mappa Positioned, OSM UA, foto post-import EXIF, Spazi Pro discovery, modalità illustrativa percorsi gruppo, vetrina QR web, gating admin "Crea Spazio Pro", ProGate web-safe) · **Epic 12 Home Smart Sections** aggiunto post-confronto con Komoot 2026-05-14

Documento vivo. Le voci sono ordinate per priorità all'interno di ogni categoria. Stima sforzo indicativa in giornate uomo.

> **Nota sulla v2.2.0+57**: introduceva i **gruppi business L1** con tier sul gruppo (`Group.isBusinessGroup` + `businessTier`). Dal 2026-05-10 quel modello è considerato **legacy**: il B2B è stato refattorizzato come entity dedicata (`businesses/{id}` — "Spazi Pro"). Vedi [Epic 7](#epic-7--spazi-pro-business-target-v235--v260) per il nuovo approccio. La transizione gruppi-business → Spazi-Pro è descritta nel [Sprint B](#sprint-b--strategia-3-piani-target-v235).

---

## Legenda

- **Priorità**: 🟥 critica · 🟧 alta · 🟨 media · 🟩 bassa
- **Effort**: XS (<0.5d) · S (1d) · M (2-3d) · L (1 settimana) · XL (>1 settimana)
- **Status**: ☐ da fare · 🔄 in corso · ✅ fatto · ⚠️ parziale · 🚫 deprecato
- **Tier**: Free / Pro / Business / Free+Pro

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
| 1.D4 | Auto-hide HUD dopo N s inattività + chip mini reshow + pref Settings | 🟨 | S | ✅ |

---

## Epic 2 — Completezza funzionale (v1.8.x) ✅ rilasciata

Target: colmare i gap rispetto a Komoot / AllTrails / Strava.

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 2.1 | POI / Highlights lungo il percorso | 🟧 | M | ✅ |
| 2.2 | Notifica vocale geolocata ai POI durante navigazione (TTS) | 🟧 | S | ✅ |
| 2.3 | Multi-day tours (aggregazione tracce per "viaggio") | 🟨 | L | ✅ |
| 2.4 | Sharing link pubblico web (`trailshare.app/t/{id}`) | 🟧 | M | ✅ |
| 2.5 | Esportazione TCX / FIT / KML | 🟨 | S | ✅ |
| 2.6 | Dark mode app-wide (con `ThemeColorsExtension`) | 🟨 | M | ✅ |
| 2.7 | Onboarding interattivo + tutorial REC | 🟨 | M | ✅ |

### 2.D — Admin tools (Import sentieri)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 2.D1 | Dropdown 20 regioni italiane ufficiali con bbox auto (no Nominatim) | 🟧 | S | ✅ |
| 2.D2 | Import singolo da URL/ID relation Waymarked (1 trail diretto) | 🟧 | S | ✅ |
| 2.D3 | Storico import (Firestore `trail_imports/{id}`, lista ultimi 10 in admin page) | 🟨 | S | ✅ |
| 2.D4 | Activity-type smart da tag OSM `route` (hiking/mtb/bicycle/ski → activityType TrailShare) | 🟧 | S | ✅ |
| 2.D5 | Difficoltà CAI smart da tag `sac_scale` (hiking/mountain_hiking/etc. → T/E/EE/EEA) | 🟨 | XS | ✅ |
| 2.D6 | Update mode: re-import sovrascrive geometria + stats invece di skip | 🟧 | S | ✅ |
| 2.D7 | Mass-delete trail importati per regione (cleanup admin) | 🟨 | S | ☐ |
| 2.D8 | Stats per regione (tabella "Italia: 1247 · Lombardia: 234 · ...") | 🟨 | S | ☐ |
| 2.D9 | Bulk GPX upload dal web admin (zip o multi-file) | 🟨 | M | ☐ |
| 2.D10 | Multi-fonte: Overpass API per riempire i buchi di Waymarked | 🟩 | M | ☐ |
| 2.D11 | Termini predefiniti per categoria (chip "Rifugi · Vie ferrate · Alte vie") | 🟩 | S | ☐ |

---

## Epic 3 — Engagement (v1.9.0) ✅ in produzione consolidata

Target: aumentare ritenzione e dwell time.

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 3.1 | Sfide settimanali personali generative | 🟧 | M | ✅ |
| 3.2 | Sfide gruppo / amici | 🟨 | L | ✅ (auto-update standings su track save + Cloud Function completion + FCM broadcast vincitore + badge UI) |
| 3.3 | Classifiche regionali (per regione + mese) | 🟨 | M | ✅ |
| 3.4 | Heatmap trail popolari | 🟨 | M | ✅ (Cloud Function weekly aggregator geohash p4 + toggle Discover) |
| 3.5 | Commenti sulle tracce community | 🟨 | S | ✅ |
| 3.6 | Mentions/tags utenti nei commenti | 🟩 | S | ✅ (parsing @ + autocomplete + render tappable + FCM ai menzionati) |
| 3.7 | Report mensile automatico "Il mio mese" | 🟨 | M | ✅ |
| 3.8 | Compass-up navigation in registrazione | 🟧 | S | ✅ |

---

## Epic 4 — Miglioramento funzioni esistenti (target v2.4.0+ continuo)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 4.1 | Navigazione: preview pre-partenza con ETA + ETA dinamico real-time | 🟧 | XS | ✅ |
| 4.2 | Navigazione: waypoint intermedi | 🟨 | XS | ✅ (planner mobile già supporta multi-waypoint senza limite, web cap 10) |
| 4.3 | Navigazione: pausa automatica se fermo >5 min | 🟨 | XS | ✅ (TrackingBloc._autoPause già live, snackbar autoPauseTriggered/Resumed) |
| 4.4 | Discover: ricerca testuale full-text | 🟧 | S | ✅ (TextSearch accent-insensitive su nome/ref/network/operator/regione/difficoltà/attività; community migrato dalla `contains` basic) |
| 4.5 | Discover: filtro per regione amministrativa | 🟨 | S | ✅ (bbox 20 regioni + sezione filter sheet) |
| 4.6 | Track detail: grafico HR per zone (cardiac zones) | 🟨 | S | ✅ (HeartRateZonesWidget live in track_detail_page, 5 zone Z1-Z5 con avg/peak header + fallback maxHR stimata + CTA impostazioni) |
| 4.7 | Track detail: confronto con PR personale | 🟨 | M | ✅ (PersonalRecordsCard: best distance/duration/elevation per activityType, badge "Nuovo PR" o % vs best) |
| 4.8 | Track detail: split per km con tempo cumulativo | 🟩 | XS | ✅ |
| 4.9 | Mappe dark reale (Stadia/MapTiler con API key) | 🟩 | S | ✅ ("Notte Pro" MapTiler streets-v2-dark; free "Notte" CartoDB dark_all+filtro mobile resta) |

---

## Epic 5 — Polish & Performance (target v2.x continuo)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 5.1 | Widget home-screen iOS/Android | 🟨 | M | ☐ |
| 5.2 | Apple Watch companion app | 🟩 | XL | ☐ |
| 5.3 | **Garmin Connect IQ app** | 🟩 | XL | ✅ in produzione (vedi Epic 9.C) |
| 5.4 | Merge/split tracce | 🟩 | S | ✅ (track detail menu: spezza con slider, unisci con picker; stats ricomputate) |
| 5.5 | Tag/categorie personalizzate sulle tracce | 🟩 | S | ✅ (Track.tags lowercase + TrackTagsEditor + autocomplete da getAllUserTags) |
| 5.6 | Ricerca nelle proprie tracce | 🟨 | XS | ✅ (search bar tracks_page accent-insensitive su nome/attività/tag) |

---

## Epic 6 — Monetization & Premium Pro (v2.0.0 → v2.7.0)

Obiettivo: trasformare TrailShare in **freemium sostenibile** con feature "wow non
indispensabili" che giustificano l'upgrade Consumer Pro €2,99/€19,99.
Lifeline e tutto il core safety/recording restano **sempre gratis**.

### 6.A — Wow features (pull factor)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 6.1 | Mountain recognition AR live (top 5 cime) | 🟧 | M | Free | ✅ |
| 6.2 | Mountain recognition photo + analisi completa + share | 🟧 | L | Pro | ✅ |
| 6.3 | **3D fly-through replay delle tracce** | 🟨 | L | Pro | ☐ — viral feature |
| 6.4 | Mappe topografiche premium (Topo / Hybrid / Inverno via MapTiler) | 🟧 | M | Pro | ✅ |
| 6.5 | **Allenamento HR personalizzato basato su storico** | 🟨 | M | Pro | ✅ MVP (TrainingHrPage: 4 settimane rolling, zona prevalente, suggerimento next session) |
| 6.5.1 | HR — auto-detect FCmax bassa (banner se >50% Z5 per 3+ sessioni → suggerisce calibrazione) | 🟨 | S | Free+Pro | ☐ — UX critica, "evita allarmi falsi" |
| 6.5.2 | HR — pulsante "Stima FCmax dai miei dati" (max HR ultime 30gg + offset) | 🟨 | S | Free+Pro | ☐ — coppia con 6.5.1 |
| 6.5.3 | HR — onboarding dialog prima apertura Allenamento HR (età + livello fitness → FCmax suggerita, non solo 220−età) | 🟩 | S | Free+Pro | ☐ |
| 6.5.4 | **VO2 Max running** stimata da pace+HR (formula Daniels/Riegel) — il numero "magico" Garmin/Strava | 🟧 | S | Pro | ☐ — recap card track detail |
| 6.5.5 | **Training Load (TRIMP)** + grafico 7/28 giorni (form. Banister 1991) — fondamenta fitness/fatigue | 🟧 | M | Pro | ☐ — recap mensile Pro |
| 6.5.6 | **Recovery time** stimato (TRIMP ultime 72h → ore consigliate prima del prossimo sforzo intenso) | 🟨 | S | Pro | ☐ — coppia con 6.5.5 |
| 6.5.7 | **Lactate Threshold detection** (HR deflection from pace, alla Garmin) — usa LT come riferimento alternativo per le zone | 🟩 | L | Pro | ☐ — quando avremo HRV stream da wearable |
| 6.6 | Trail conditions AI summary (riassunto da commenti recenti) | 🟨 | M | Pro | ✅ |
| 6.7 | **Pianificatore IA "trova percorso simile a..."** | 🟨 | M | Pro | ☐ — AI differenziator |
| 6.8 | **Time-lapse video auto della traccia + foto** | 🟩 | M | Pro | ☐ — viral feature |
| 6.9 | **Viewshed Peak Filter** — solo cime non occluse da crinali (PeakFinder-style, DEM AWS Open Terrain + skyline 360°) | 🟧 | L | Free+Pro | ✅ MVP — Free 20km/10 cime, Pro 100km/illimitato + Hive cache + auto-refresh on-move. Toggle 👁️ in Mountain Finder. |

### 6.B — Infrastruttura paywall

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 6.B1 | Subscription manager (in_app_purchase 3.x → StoreKit 2 / Play Billing) | 🟥 | L | ✅ |
| 6.B1.5 | PaywallSheet context-aware (3 layout: free / monthly / yearly) | 🟧 | S | ✅ |
| 6.B2 | Cloud Function `validateAppleReceipt` con JWS verification | 🟥 | M | ✅ |
| 6.B3 | Premium status sync su `users/{uid}.proStatus` cross-device | 🟥 | S | ✅ |
| 6.B4 | `PaywallSheet` widget + dinamiche prezzi locale | 🟧 | M | ✅ |
| 6.B5 | Trial 14 giorni gratis (yearly only) con flag isInTrial | 🟧 | S | ✅ |
| 6.B6 | Discovery prompt "Scopri Pro" con A/B variant | 🟧 | S | ✅ MVP (card discover per free utenti con trackCount>=5, tap apre paywall discoveryUpsell) |
| 6.B7 | Restore purchases + deep link "Gestisci abbonamento" | 🟧 | S | ✅ |
| 6.B8 | Analytics conversion funnel + churn tracking (Firebase) | 🟨 | S | ☐ |
| 6.B9 | **App Store Server Notifications V2 webhook** (rinnovi/refund/revoke) | 🟧 | M | ☐ — critico per conversioni |
| 6.B10 | **Cloud Function `validateGoogleReceipt`** (sblocca Android billing) | 🟥 | M | ☐ blocked-PIVA |

### 6.C — Lifecycle premium

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 6.C1 | Settings "Gestisci abbonamento" + cancellazione | 🟥 | XS | ✅ |
| 6.C2 | Email "Stai per perdere Pro" 3gg prima scadenza (FCM + email) | 🟧 | S | ☐ |
| 6.C3 | Benefit reminder ogni 30gg ("usato N volte le mappe Pro") | 🟨 | S | ✅ (proBenefitReminderMonthly scheduled, FCM con #tracce mese precedente) |
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

> **Decisione aperta**: il pricing €2.99 è competitivo ma forse percepito come "troppo basso = poco valore". Da rivalutare quando aggiungeremo 6.3, 6.5, 6.7, 6.8 e quando dal refactor 3-piani le feature avanzate dei gruppi diventeranno Consumer Pro perks. Vedi `project_three_tier_strategy.md` in memoria.

---

## Epic 7 — Spazi Pro Business (target v2.3.5 → v2.6.0) 🔄 in sviluppo

Obiettivo: aprire un **secondo flusso di ricavi B2B** vendendo TrailShare a hotel di
montagna, rifugi, noleggi ebike, guide outdoor, scuole alpinismo e tour operator.
Un "Spazio Pro" è una **vetrina pubblica** sull'app: profilo brandizzato, posizione
sulla mappa, follower (asimmetrici), reviews, listino servizi, post/aggiornamenti
e — opzionalmente — un linked group privato per la community VIP del business.

> **Architettura aggiornata 2026-05-10**: l'approccio originale "gruppi con `businessTier`"
> della v2.2.0 è stato **superato**. Adesso `businesses/{id}` è una entity di
> primo livello separata dai gruppi. I gruppi business legacy rimangono per
> backward compat ma in stato deprecato — il refactor di transizione è
> nello [Sprint B v2.3.5](#sprint-b--strategia-3-piani-target-v235).

### 7.A — Spazio Pro entity & profilo pubblico (v2.3.5) 🔄 codice live in dev

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 7.A1 | Schema Firestore `businesses/{id}` + sub-collections (followers, posts, services, reviews) | 🟥 | M | Business | ✅ |
| 7.A2 | Firestore rules: read pubblico, write owner, counter immutabili lato client | 🟥 | S | Business | ✅ |
| 7.A3 | Storage rules per `businesses/{id}/{kind}` con CORS pubblico per web | 🟥 | XS | Business | ✅ |
| 7.A4 | Profilo pubblico mobile (hero, logo, contatti, mappa, listino, post, orari, follow) | 🟥 | L | Business | ✅ |
| 7.A5 | Edit profilo (anagrafica, contatti, indirizzo, orari giorno-per-giorno, foto) | 🟥 | M | Business | ✅ |
| 7.A6 | Galleria foto multi-upload con long-press remove | 🟧 | S | Business | ✅ |
| 7.A7 | Posts/aggiornamenti business (testo + foto) — text-style come Twitter | 🟧 | M | Business | ✅ |
| 7.A8 | Listino servizi (CRUD voci con prezzo/unità + foto opzionale) | 🟧 | M | Business | ✅ |
| 7.A9 | Discovery tab "Spazi Pro" mobile con list + mappa + filtri tipo + bottom sheet pin | 🟥 | M | Free | ✅ |
| 7.A10 | Follow toggle con counter denormalizzato (transactional) | 🟧 | S | Free | ✅ |
| 7.A11 | Empty state CTA owner-only ("Aggiungi descrizione", "Pubblica primo aggiornamento", ecc.) | 🟨 | S | Business | ✅ |
| 7.A12 | Creazione admin-only via Settings (B-flow: super admin crea, owner rifinisce) | 🟧 | S | Business | ✅ |
| 7.A13 | Tier badges (Verified / Pro / Enterprise) | 🟨 | XS | Business | ✅ |

### 7.B — Web admin Spazi Pro (v2.3.5) 🔄 codice live in dev

Riusa pagine mobile in dialog. Decisione strategica 2026-05-02: Flutter Web monocodebase, no SvelteKit.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 7.B1 | Sidebar entry "Spazi Pro" (storefront icon) tab dedicata web | 🟥 | XS | Business | ✅ |
| 7.B2 | WebBusinessPickerPage: grid 3-col degli Spazi Pro dell'utente | 🟥 | M | Business | ✅ |
| 7.B3 | WebBusinessDashboardPage: hero brandizzato + 4 KPI cards + quick actions | 🟥 | M | Business | ✅ |
| 7.B4 | Routing path-based `/business` + `/business/{id}` deep-linkable | 🟧 | S | Business | ✅ |
| 7.B5 | Quick actions: Nuovo post / Listino / Edit / Anteprima profilo (riusa pagine mobile in dialog) | 🟧 | S | Business | ✅ |

### 7.C — Espansione funzionale (target v2.4.0)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 7.C1 | **Percorsi consigliati** sul profilo business (track già esistenti + curate dal business) | 🟥 | M | Business | ✅ (BusinessRecommendedTracksManager + Picker live) |
| 7.C2 | **Reviews & rating system** (1-5 stelle + commento, moderation lato owner) | 🟥 | L | Business | ✅ (BusinessReviewsPage con avg rating + distribuzione + composer + owner moderation) |
| 7.C3 | **Statistiche profilo business** (visite, click contatti, conversion follow) | 🟧 | M | Business | ✅ (BusinessAnalyticsPage: 4 KPI + fl_chart line + breakdown contatti) |
| 7.C4 | Mappa-picker per riposizionare business (oggi solo create-time) | 🟧 | S | Business | ✅ (BusinessLocationPickerPage center-pin pattern) |
| 7.C5 | Push notifiche FCM ai follower per business posts | 🟧 | S | Business | ✅ (Cloud Function onBusinessPostCreated multicast) |
| 7.C6 | Self-serve onboarding wizard B2B web (oltre B-flow admin) | 🟧 | M | Business | ☐ |
| 7.C7 | Linked group opzionale Pro tier (community VIP clienti) | 🟨 | S | Business | ✅ (BusinessCommunitySheet: crea/collega/scollega; gating Pro-equivalent bidirezionale) |
| 7.C8 | Bulk import tracce GPX dal web admin (drag&drop) | 🟨 | M | Business | ☐ |
| 7.C9 | Generatore card invito QR PDF (logo + colori) | 🟨 | M | Business | ✅ (BusinessQrCardPage 9:16 brandizzata + share PNG via RepaintBoundary 3x; deep link trailshare://b/{id} + https://trailshare.app/b/{slug}) |

### 7.D — Pagine pubbliche e SEO (target v2.6.0)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 7.D1 | Landing pubblica `/b/{slug}` brandizzata (hero, listino, post, mappa) | 🟧 | M | Free | ✅ (WebBusinessPublicPage no AuthGate: hero brandizzato + descrizione + contatti + mappa + recensioni + recommended + CTA "Apri TrailShare") |
| 7.D2 | OG tags + Twitter card + Schema.org `LocalBusiness` per ranking | 🟨 | S | Free | ⚠️ MVP (OG/Twitter/JSON-LD generici Organization in index.html; per-business via SSR Cloud Function = follow-up) |
| 7.D3 | Map view aggregata di tutte le tracce consigliate del business | 🟧 | S | Free | ✅ (marker punti partenza tracce sulla mappa landing + lista card sotto; bbox auto-fit) |
| 7.D4 | CTA "Scarica TrailShare e segui" con QR pre-popolato | 🟥 | S | Free | ✅ (inglobata in 7.C9: la card QR contiene CTA "Apri TrailShare per seguire") |
| 7.D5 | Custom domain support (es. `mtb.baitaduturhotel.it` → Spazio Pro) | 🟩 | L | Enterprise | ☐ |

### 7.E — Monetization Spazi Pro (target v2.4.0, dipende P.IVA + commercialista)

Pricing confermato 2026-05-02:

- **Verified** — €19.99/mese o €199/anno (-17%): 10 tracce condivise, 4 eventi attivi, stats base, 1 gruppo, trial 14gg
- **Pro** — €49.99/mese o €499/anno (-17%): tutto Verified senza cap, featured discovery, pinned post, stats avanzate, 5 admin extra, no trial
- **Enterprise** — custom (multi-spazio, white-label, API, priority support)
- **Promo Early Adopter**: -30% lifetime sui primi 20 clienti Verified annuali nei primi 6 mesi → €139/anno effettivi

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 7.E1 | Stripe products `business_verified_monthly/yearly` + `business_pro_monthly/yearly` | 🟥 | M | ☐ blocked-PIVA |
| 7.E2 | Stripe checkout flow + customer portal embedded | 🟥 | L | ☐ blocked-PIVA |
| 7.E3 | Webhook `stripeCheckoutComplete` → set tier su business doc | 🟥 | M | ☐ blocked-PIVA |
| 7.E4 | Webhook `stripeSubscriptionEvents` (renew/cancel/refund) | 🟥 | M | ☐ blocked-PIVA |
| 7.E5 | Logica gating cap (tracce condivise, eventi attivi) per tier Verified | 🟧 | M | ☐ |
| 7.E6 | Featured placement Pro nella discovery (campo `featuredScore`) | 🟧 | S | ☐ |
| 7.E7 | Stats base vs avanzate gating | 🟧 | S | ☐ |
| 7.E8 | Manual override admin: setBusinessTier per seed clients gratuiti | 🟧 | XS | ☐ |
| 7.E9 | Fatturazione FattureInCloud / Stripe Invoice per ricevute IT | 🟨 | L | ☐ blocked-PIVA |

### 7.F — Acquisition & Seed clients

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 7.F1 | **Programma seed clients**: 5-7 design partner Pro free 6 mesi (rifugio + guida + hotel + noleggio + consorzio) | 🟥 | M | 🔄 2 in attivazione (rifugio Curò + noleggio ebike) |
| 7.F2 | **Outreach 50 noleggi ebike Lombardia** (template email + video 60s) | 🟥 | M | ☐ |
| 7.F3 | Partnership Federalberghi locali (presentazioni meeting mensili) | 🟧 | M | ☐ |
| 7.F4 | Case study primo cliente (testimonianza + screenshot reali) | 🟧 | S | ☐ post-demo |
| 7.F5 | Cosmo Bike Show Verona (settembre, demo 30 stand in 3 giorni) | 🟨 | L | ☐ se budget |
| 7.F6 | Reddit/Forum outdoor IT (case study come post organico) | 🟩 | XS | ☐ |

### 7.G — Migrazione gruppi business legacy (deprecato dopo v2.5.0)

Percorso di transizione dai gruppi business L1 della v2.2.0 al nuovo modello Spazi Pro.

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 7.G1 | Cloud Function migrate one-shot: `isBusinessGroup=true` → suggerimento Spazio Pro o downgrade | 🟧 | M | ☐ |
| 7.G2 | Wizard UI 2-step per owner gruppo business legacy | 🟧 | S | ☐ |
| 7.G3 | Email/notifica utenti coinvolti | 🟨 | S | ☐ |
| 7.G4 | Cleanup schema: rimuovi `Group.isBusinessGroup` + `businessTier` dopo migrazione (v2.5.0) | 🟨 | S | ☐ |

---

## Epic 8 — Web ecosystem (target v2.4.0 → v2.7.0)

Obiettivo: passare da **app-only** a **piattaforma multi-touch** con sito pubblico
per SEO/marketing + dashboard interna in Flutter Web.

### Stack consolidato 2026-05-10

Decisione 2026-05-02: marketing site vanilla HTML, dashboard **Flutter Web monocodebase**
(no SvelteKit). Riuso TUTTO il codice mobile (modelli, repository, pagine in dialog).

| Categoria | Pagine | Stack | Repository |
|---|---|---|---|
| Marketing/SEO | `/`, `/help`, `/privacy`, `/terms`, `/pro`, `/business`, `/g/{groupId}` | HTML/CSS/JS vanilla | `trailshare-website/` submodule |
| Dashboard autenticata (Pro consumer + Business + Free) | `app.trailshare.app/...` | Flutter Web (mono codebase) | `lib/web/` |
| Pagine pubbliche profilo | `/track/{slug}`, `/b/{slug}`, `/collection/{slug}` | Vanilla HTML con SSR/CSR ibrido | `trailshare-website/` |

### 8.A — Marketing site `trailshare.app` (HTML vanilla, target v2.4.0)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 8.A1 | Landing pubblica `/` rinnovata (feature carousel + download CTA + screenshot recenti) | 🟧 | S | Free | ⚠️ esistente, da rinfrescare |
| 8.A2 | Pagina `/pro.html` (pricing €2.99/€19.99, screenshot, 14gg trial CTA) | 🟥 | S | Free | ☐ blocking-Apple |
| 8.A3 | Pagina `/business.html` (B2B pitch + case study + form contatto) | 🟧 | M | Free | ☐ |
| 8.A4 | Blog tecnico (SEO outdoor IT: "5 sentieri Lombardia in autunno" ecc.) | 🟨 | M | Free | ☐ |
| 8.A5 | Privacy policy + terms aggiornati per IAP Apple/Google + Spazi Pro | 🟧 | XS | Free | ⚠️ esistente, da rivedere |
| 8.A6 | OG tags + Twitter card su `/track/{id}` e `/tour/{id}` per condivisioni social | 🟨 | S | Free | ☐ |
| 8.A7 | Sitemap + robots.txt + Schema.org per ranking | 🟨 | XS | Free | ☐ |

### 8.B — Dashboard Flutter Web (`app.trailshare.app`)

#### 8.B.0 — Foundations ✅ live

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 8.B0.1 | Setup Flutter Web entry point dedicato (`lib/main_web.dart`) senza plugin mobile-only | 🟥 | M | Free | ✅ |
| 8.B0.2 | Routing path-based con `WebRoutes` + deep link `/track/{id}`, `/business/{id}` | 🟥 | M | Free | ✅ |
| 8.B0.3 | Sidebar con tab Dashboard, Tracce, Pianificatore, Profilo, Spazi Pro, Gruppi (legacy) | 🟥 | S | Free | ✅ |
| 8.B0.4 | Auth gate condivisa con app mobile (Firebase Auth Stream) | 🟥 | M | Free | ✅ |
| 8.B0.5 | Login web con Apple/Google/email | 🟥 | M | Free | ✅ |

#### 8.B.1 — Sezioni utente generale (consumer)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 8.B1.1 | Le mie tracce (lista + filtri + mappa generale) | 🟥 | M | Free | ✅ |
| 8.B1.2 | Track detail web con mappa interattiva + grafici elevazione/HR | 🟥 | M | Free | ✅ |
| 8.B1.3 | Pianificatore (ORS proxy + waypoint + export GPX) | 🟥 | M | Free | ✅ (snap radius 5km + errori strutturati con waypoint problematico evidenziato) |
| 8.B1.4 | Profilo + statistiche personali (km, dislivello, calorie, trend) | 🟥 | M | Free | ✅ (fix layout 2026-05-10) |
| 8.B1.5 | Sfide settimanali + classifiche regionali (mirror app mobile) | 🟨 | M | Free | ⚠️ parziale |

#### 8.B.2 — Pro features web (target v2.5.0)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 8.B2.1 | Heatmap personale (dove sono andato di più) | 🟨 | S | Pro | ☐ |
| 8.B2.2 | Confronto periodo su periodo (mese vs mese, anno vs anno) | 🟨 | S | Pro | ☐ |
| 8.B2.3 | Export massivo GPX/FIT/TCX in zip | 🟨 | S | Pro | ☐ |
| 8.B2.4 | Gestione abbonamento web (cancel, fatture, upgrade mensile→annuale) | 🟧 | M | Pro | ☐ |

### 8.C — Pagine pubbliche per SEO (target v2.5.0 → v2.6.0)

Long-tail SEO da contenuti utente. 1000 utenti che condividono = 1000 landing organiche.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 8.C1 | Pagina pubblica `/track/{slug}` (mappa + meta + autore + foto + share) | 🟧 | M | Free | ☐ |
| 8.C2 | Pagina pubblica `/b/{slug}` Spazio Pro (vedi 7.D1) | 🟧 | M | Free | ☐ |
| 8.C3 | Pagina pubblica `/collection/{slug}` (Tour Collections curate) | 🟨 | M | Free | ☐ |
| 8.C4 | OG image dinamica generata server-side (track preview / business hero) | 🟨 | M | Free | ☐ |
| 8.C5 | Schema.org markup (`SportsActivityLocation`, `LocalBusiness`, `TouristTrip`) | 🟨 | S | Free | ☐ |

### 8.D — Backend complementare (Cloud Functions web-side)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 8.D1 | Function `getBusinessAnalytics(businessId)` per dashboard 7.C3 | 🟧 | M | ☐ |
| 8.D2 | Function `generateInviteCardPdf(businessId)` con `pdf-lib` | 🟧 | S | ☐ |
| 8.D3 | Function `searchTracksFulltext(query)` per ricerca cross-app/web | 🟨 | M | ☐ |
| 8.D4 | Webhook handler Stripe (vedi 7.E3-E4) | 🟧 | S | ☐ blocked-PIVA |
| 8.D5 | Function `renderBusinessOgImage(businessId)` per OG card dinamica | 🟨 | S | ☐ |

---

## Epic 9 — Wearable Integrations (v2.3.5) 🔄 codice live in dev

Obiettivo: TrailShare diventa il punto di raccolta di tutte le attività outdoor
dell'utente, anche se registrate con altri device. **Differenziatore chiave** vs
Komoot e AllTrails.

### 9.A — Apple HealthKit / Health Connect

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 9.A1 | `HealthService` con configure + permission request HealthKit/HC | 🟥 | M | ✅ |
| 9.A2 | Lettura HR samples per range temporale (post-recording) | 🟥 | M | ✅ |
| 9.A3 | Lettura calorie + steps per range temporale | 🟧 | S | ✅ |
| 9.A4 | **Scrittura workout completo con route GPS** (`startWorkoutRoute` + `insertWorkoutRouteData` + `finishWorkoutRoute`) | 🟥 | L | ✅ |
| 9.A5 | Filtro fonti prioritarie (Garmin > Samsung > Polar > Fitbit > Google Fit) | 🟧 | S | ✅ |
| 9.A6 | Toggle in Settings + dashboard Health con metriche aggregate | 🟧 | M | ✅ |

### 9.B — Strava bidirezionale (upload + import)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 9.B1 | OAuth `stravaCallback` Cloud Function (token exchange + storage) | 🟥 | M | ✅ |
| 9.B2 | Auto-upload end-of-session via `stravaUploadActivity` callable | 🟥 | L | ✅ |
| 9.B3 | Badge real-time sul track detail (processing/done/error con link) | 🟧 | S | ✅ |
| 9.B4 | Pulsante "Riprova" client-side su error/pending | 🟧 | S | ✅ |
| 9.B5 | Cron `stravaReconcilePending` ogni 10 min (ripolla pending, dopo 1h marchia error) | 🟧 | S | ✅ |
| 9.B6 | Switch "Carica su Strava" nel save dialog (override per singola attività) | 🟨 | S | ✅ |
| 9.B7 | **Webhook Strava → import attività esterne** (`stravaWebhook` + `importStravaActivity`) | 🟥 | XL | ✅ |
| 9.B8 | Mappa STRAVA_TO_TRAILSHARE_ACTIVITY (Hike→trekking, TrailRun→trailRunning, ecc.) | 🟧 | S | ✅ |
| 9.B9 | Toggle Settings "Importa attività da Strava" (default OFF, opt-in) | 🟧 | XS | ✅ |
| 9.B10 | Badge "Importata da Strava" su track detail | 🟨 | XS | ✅ |
| 9.B11 | Strava "Richiedi più atleti" (oltre limite 1 default) | 🟥 | XS | ☐ — bloccante per scaling |
| 9.B12 | Sync bidirezionale eventi delete (oggi: ignorati) | 🟩 | S | ☐ |

### 9.C — Garmin (ConnectIQ + Connect)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 9.C1 | Garmin ConnectIQ companion app | 🟧 | XL | ✅ |
| 9.C2 | `GarminSyncService` Bluetooth sync watch → phone | 🟧 | M | ✅ |
| 9.C3 | Cloud Function `syncGarminTrack` per ricezione tracce | 🟧 | M | ✅ |
| 9.C4 | Garmin Connect Developer Program API (alternativa a Strava-mediato) | 🟩 | XL | ☐ — rinviato, copertura via Strava sufficiente al 90% |

### 9.D — Future wearables (rinviati)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 9.D1 | Apple Watch native standalone app | 🟩 | XL | ☐ |
| 9.D2 | COROS API integration (trail running niche) | 🟩 | L | ☐ |
| 9.D3 | TCX/FIT export per portare HR su Strava (oggi GPX = solo geografico) | 🟩 | M | ☐ |

---

## Epic 10 — AI Manager Social (v2.3.5, runtime già live su Firebase project separato) 🔄

Obiettivo: automazione contenuto social per TrailShare con safety net umana.
Pipeline drafting → bridging → publishing su IG + FB. Repository standalone:
`/Volumes/Lexar/Sviluppo/trailshare-ai-manager/` su Firebase project `trailshare-ai-manager`.

### 10.A — Manager runtime ✅ live

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 10.A1 | Pesca trail utente da Firestore TrailShare cross-project via SA | 🟥 | M | ✅ |
| 10.A2 | Brand voice generator (3 voci) con Anthropic Claude | 🟥 | L | ✅ |
| 10.A3 | Pipeline pubblicazione IG + FB | 🟥 | L | ✅ |
| 10.A4 | Bot Telegram cockpit per approve/reject post | 🟧 | M | ✅ |
| 10.A5 | Dashboard Firebase per review code visuale | 🟧 | M | ✅ |
| 10.A6 | Pool sorgenti contenuti: trail_user (60%), trail_public (30%), product_news (10%) | 🟧 | M | ✅ |

### 10.B — Bridge social_lab ↔ manager ✅ live

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 10.B1 | `social_lab/scripts/bridge.mjs` push draft → post Firestore | 🟥 | M | ✅ |
| 10.B2 | Sub-agent `social-manager` per drafting markdown con frontmatter | 🟥 | M | ✅ |
| 10.B3 | Idempotency via `bridged_post_id` + `bridged_at` | 🟧 | S | ✅ |
| 10.B4 | Watcher chokidar `watch-drafts.mjs` su LaunchAgent (autostart) | 🟧 | S | ✅ |
| 10.B5 | Notifica Telegram automatica post-bridge | 🟨 | XS | ✅ |
| 10.B6 | Integrazione claude.ai/design per slide deck IG carousel (workflow umano) | 🟧 | M | ✅ |

### 10.C — Estensioni post-launch

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 10.C1 | **`socialFeaturingOptIn` flag su track/user_profile** | 🟥 | S | ☐ — bloccante per autopilot senza review umano |
| 10.C2 | Auto-resize immagini per IG (sharp, ratios 1:1 / 4:5 / 1.91:1) | 🟧 | S | ☐ |
| 10.C3 | Library `social_lab/assets/` come content pool su manager Storage | 🟧 | M | ☐ |
| 10.C4 | TikTok OAuth setup post-deploy (codice già pronto) | 🟨 | S | ☐ |
| 10.C5 | Pool POI segnalati ("5 panorami in Lombardia") | 🟨 | M | ☐ |
| 10.C6 | Pool reviews 1-5★ con quote utente | 🟨 | M | ☐ |
| 10.C7 | Pool leaderboard regionali ("Top trail running Lombardia maggio") | 🟨 | M | ☐ |
| 10.C8 | Tab TikTok preview verticale 9:16 in dashboard | 🟩 | S | ☐ |
| 10.C9 | Tab "Sorgenti contenuti" per editare pesi senza Firestore manuale | 🟩 | S | ☐ |

---

## Epic 11 — Routing Intelligence (target v2.5.0 → v2.8.0+) 🔵 esplorativo

Obiettivo: alzare qualità delle tracce e routing **vs Komoot** in zone IT dove
abbiamo dati utente sufficienti. Approccio pragmatico, non ML enterprise-scale.

> **Decisione strategica aperta**: l'Epic 11.D (routing engine ML) va attivato solo
> se confermato dal founder. Vedi `project_routing_engine_ml.md` in memoria per
> dettaglio tecnico. Costo infrastructure ~€30-80/mese, sviluppo 3-5 settimane.

### 11.A — Komoot Foundations (target v2.5.0)

Inserimento progressivo di feature Komoot-flavor che NON richiedono ML.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 11.A1 | Highlights inline su track (POI estesi con `linkedTrackId`, auto-suggest da Spazi Pro vicini) | 🟧 | M | Free | ☐ |
| 11.A2 | Difficulty rating computed (formula tipo Komoot: distance + elevation + grade) | 🟧 | S | Free | ☐ |
| 11.A3 | Surface profile da OSM way tags + speed/cadence estimation | 🟧 | M | Free | ☐ |

### 11.B — Tour Collections curate (target v2.6.0)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 11.B1 | Schema `trail_collections/{id}` (curatorId, items[], region, hero, type) | 🟧 | S | Free | ☐ |
| 11.B2 | Pagina collezione brandizzabile (curator admin OR Spazio Pro) | 🟧 | M | Free | ☐ |
| 11.B3 | Discovery tab "Collezioni" (carousel curate community + curate business) | 🟧 | M | Free | ☐ |
| 11.B4 | Workflow business: dalla dashboard "I miei consigli" → crea collezione con tracce proprie/community | 🟧 | M | Business | ☐ |

### 11.C — Multi-day Tour Planner integrato (target v2.6.0)

> **Killer feature**: Komoot multi-day Premium + integrazione Spazi Pro. Nessun
> competitor lo fa.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 11.C1 | Estendi `tours/{id}` con `stops[{businessId, date, ...}]` linkati a Spazi Pro | 🟧 | M | Free | ☐ |
| 11.C2 | Planner UI con suggerimenti rifugi sul percorso | 🟧 | L | Free | ☐ |
| 11.C3 | Bottone "Contatta per prenotare" → WhatsApp pre-popolato verso Spazio Pro | 🟧 | XS | Free | ☐ |
| 11.C4 | Tour pubblici discoverabili come content "3 giorni Alta Via 1" | 🟧 | M | Free | ☐ |

### 11.D — Routing engine ML (target v2.8.0+, distribuito)

Approccio: ML sui PESI degli edge OSM (NON neural routing).

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 11.D1 | Data pipeline: Cloud Function nightly aggrega track utente → `edge_metrics/{wayId}` | 🟨 | L | Free | ☐ Fase 0: decisione strategica |
| 11.D2 | Map matching OSM (OSRM lib o python) | 🟨 | L | Free | ☐ |
| 11.D3 | Modello v1 (XGBoost o linear regression) per predire peso reale edge | 🟨 | L | Free | ☐ |
| 11.D4 | Re-rank routing: ORS top-3 → riordina con pesi appresi | 🟨 | M | Free | ☐ |
| 11.D5 | Shadow mode: misura discrepanza vs ORS prima di public rollout | 🟨 | M | Free | ☐ |
| 11.D6 | Public rollout per regione quando ML batte ORS in test A/B | 🟨 | continua | Free | ☐ |

---

## Epic 13 — Trail Connectivity Graph (target v2.7.0 → v2.8.0) 🔵 esplorativo

**Razionale** (ispirato 2026-05-16 dal sito CAI BG): un rifugio
non è una scheda statica ma un **nodo della rete sentieristica**.
Dalla Rifugio Curò partono il CAI 305, 309, 311a, ecc. Stesso
schema per ogni bivacco, passo, parcheggio, cima.

Aggregare questa connettività **automaticamente** dai doc esistenti
trasforma:
- gli **escursionisti** in decisori real-time ("arrivato, dove
  proseguo?")
- gli **Spazi Pro** in nodi di selling point ("da noi parti per 5
  sentieri")
- la **piattaforma** in un grafo di valore esponenziale: ogni
  trail aggiunto arricchisce N nodi automaticamente, niente staff
  curation

**Materiale già disponibile** (niente schema migration richiesta):
- `public_trails.startPoint` (GeoPoint)
- `public_trails.simplifiedPoints` (max 30 pt, da refactor f063df3)
- `public_trails.geoHash` (precision 7 ≈ 153m)
- `public_trails.ref` (numero CAI letto da OSM import)
- Coordinate POI / Business / OSM features

### 13.A — Query engine (target v2.7.0)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 13.A1 | `PublicTrailsRepository.getTrailsConnectedTo(lat, lng, radiusMeters=500)` — bbox geohash + filter haversine su startPoint OR endPoint OR simplifiedPoints intermedi | 🟧 | M | Free | ☐ |
| 13.A2 | Dedupe + ordinamento per direzione dal nodo (azimuth: N/NE/E/...) + distanza progressiva | 🟨 | S | Free | ☐ |
| 13.A3 | Cache LRU client-side: 1 query per nodo per sessione (i nodi sono stabili, no invalidation) | 🟨 | S | Free | ☐ |
| 13.A4 | Indicatore "tipo connessione" sul risultato: STARTS_HERE / ENDS_HERE / PASSES_THROUGH (utile per UI "sentieri che PARTONO da qui" vs "che ATTRAVERSANO") | 🟨 | S | Free | ☐ |

### 13.B — UX su Spazi Pro / Business detail (target v2.7.0)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 13.B1 | Sezione "Sentieri da qui" sul detail page di un Business (mobile + web) con card orizzontali scrollabili: ref CAI + nome + distanza + dislivello + difficoltà | 🟧 | M | Free | ☐ |
| 13.B2 | Filtro per difficoltà / lunghezza nella sezione (chip group) | 🟨 | S | Free | ☐ |
| 13.B3 | Auto-hide se nessun sentiero in 500m (consistency con NearbyBusinessesSection) | 🟧 | XS | Free | ☐ |

### 13.C — UX su POI mappa (target v2.7.0)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 13.C1 | Bottom sheet su tap di un POI (alpine_hut, peak, ...) con elenco sentieri collegati + bottone "Naviga al POI" | 🟧 | M | Free | ☐ |
| 13.C2 | Visual su mappa: highlight di tutti i sentieri connessi quando il POI è selezionato (polyline arancioni leggere) | 🟨 | M | Free | ☐ |

### 13.D — Multi-tappa & itinerari ad anello (target v2.8.0)

Sinergia con Epic 11.C (Multi-day Tour Planner). Quando l'utente
fa pianificare un'escursione punto A → B, la sezione "Sentieri
collegati a B" può suggerire automaticamente il ritorno via un
sentiero ad anello.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 13.D1 | Detect anello automatico: se da B parte un sentiero che torna a meno di N km da A, suggerisci come "ritorno ad anello" | 🟨 | L | Pro | ☐ |
| 13.D2 | "Trail suggestions" auto-curate per multi-giorno: A→rifugio1→rifugio2→A | 🟩 | XL | Pro | ☐ |

**Dipendenze**:
- 13.A: nessuna, data già presente
- 13.B-C: dipendono da 13.A
- 13.D: dipende da Epic 11.C (Multi-day Tour Planner)

**Non-goal**:
- ❌ Linking manuale staff-curated → defeats lo scopo (deve essere
  automatico dal grafo OSM)
- ❌ Aggregator continuativo: i nodi sono stabili, niente Cloud
  Function periodica. Cache client + on-demand basta.

---

## Epic 12 — Home & Discovery Smart Sections (target v2.6.0 → v2.8.0) 🔵 esplorativo

**Razionale** (2026-05-14, dopo confronto con Komoot): Komoot ha un feed home misto efficace, ma diventa rumoroso e l'utente si perde. La home TrailShare oggi è frammentata (community / scopri / tour separati) e mostra poco al new user (cold start problem).

Obiettivo: **una home a 5-6 sezioni intent-based** che si auto-adattano al contesto utente, mantenendo focus outdoor e mettendo in vetrina i nostri differenziatori (AI Trail Conditions, Spazi Pro, POI italiani 20.4k).

**Principi guida**:
- **Niente feed unico algoritmico** — distrae, perde identità outdoor, richiede ranking ML che non abbiamo dati per addestrare
- **Sezioni con intent chiaro** — l'utente capisce subito cosa sta guardando
- **Geo-rilevanza first** — ogni elemento deve avere senso nella zona dell'utente
- **Mix dei creator** — 40% affermati, 30% rising, 20% chi seguo, 10% staff-picks (no monopolio top 1%)
- **Differenziatori in vetrina** — AI Summary, Spazi Pro, POI curati come citizen di prima classe

### 12.A — MVP sezioni curate (target v2.6.0, dopo Sprint F)

Niente algoritmi: composizioni deterministiche basate su geohash + signal semplici (recency, popolarità, follow).

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 12.A1 | **Per te oggi** (top section contestuale): se hai registrato ieri → "Continua nelle tue zone", se inattivo 7gg → "Riprendi facile", se weekend → "Suggerimenti weekend" | 🟧 | M | Free | ☐ |
| 12.A2 | **Trend nella tua zona** (riusa heatmap weekly aggregator 3.4 ma rendendolo card-grid in home invece di toggle Discover) | 🟧 | S | Free | ☐ |
| 12.A3 | **Tour della settimana** (1 tour staff-pick visibile sopra il feed, gestito da admin) | 🟧 | S | Free | ☐ |
| 12.A4 | **Persone da scoprire** (top 5 creator attivi geo-filtered + activity-filtered) | 🟨 | M | Free | ☐ |
| 12.A5 | **Spazi Pro vicino a te** (card grid dai marker mappa community: 3 spazi più vicini, sinergia 7.D) | 🟧 | S | Free | ☐ |
| 12.A6 | **Dai tuoi contatti** (feed Following già esistente, riorganizzato come card-grid coerente) | 🟨 | S | Free | ☐ |
| 12.A7 | Refactor HomePage mobile: tab Home diventa "Smart Home", tab Discover resta per ricerca esplicita | 🟧 | M | Free | ☐ |

### 12.B — Telemetria & A/B test (target v2.7.0)

Non aggiungere altre sezioni finché non sappiamo quali funzionano davvero.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 12.B1 | Firebase Analytics events per ogni sezione: `home_section_impression`, `home_section_tap`, `home_section_dwell` | 🟧 | S | — | ☐ |
| 12.B2 | Funnel dashboard custom: impression → tap → conversion (es. follow utente, visita spazio, salva tour) | 🟨 | M | — | ☐ |
| 12.B3 | A/B test rotazione sezioni (ordering) via Firebase Remote Config | 🟨 | S | — | ☐ |
| 12.B4 | Heatmap di scroll sulla home (proxy engagement) | 🟩 | M | — | ☐ |

### 12.C — Algoritmico (target v2.8.0+, dipende da ≥1000 utenti attivi)

Solo quando avremo dati di engagement reale per fare ranking informed.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 12.C1 | Ranking personalizzato dentro ogni sezione (es. "Trend nella tua zona" ordina per recency × geo-vicinanza × popolarità weighted dal profilo attività utente) | 🟨 | L | Free | ☐ |
| 12.C2 | Mix algoritmico creator (40/30/20/10) con anti-monopolio top 1% | 🟨 | L | Free | ☐ |
| 12.C3 | Suggerimenti "Trail simili a quelli che hai amato" basato su similarity activityType + dislivello + distance | 🟩 | L | Free | ☐ |

### 12.D — Differenziatori in vetrina (cross-Epic, target v2.6.0 → v2.7.0)

Spinge sui nostri 3 USP unici vs Komoot.

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 12.D1 | Card "AI Trail Conditions" sulla home: se hai 1+ tracce salvate, mostra summary AI delle condizioni recenti di un trail vicino (sinergia 6.6 + Epic 6.A4) | 🟧 | M | Pro | ☐ |
| 12.D2 | Sezione "Italian Hidden Gems" — POI italiani curati (riusa 20.4k POI bundled) con foto staff/community | 🟨 | M | Free | ☐ |
| 12.D3 | Card promo Spazi Pro contestuale: se passi vicino ripetutamente a uno spazio non ancora seguito, suggerisci di seguirlo | 🟨 | S | Free+Business | ☐ |

**Bloccanti / dipendenze**:
- 12.A1-A5: dipende da Sprint A-B-C (consolidamento Spazi Pro + Tour) — non prima di v2.6.0
- 12.B: utile solo dopo 12.A live + traffico minimo
- 12.C: pessimo investimento sotto 1.000 utenti attivi giornalieri (rischio overfitting)
- 12.D1: dipende da 6.6 (Trail Conditions AI già live)

**Non-goal (non lo facciamo)**:
- ❌ Feed unico stile Instagram/Komoot con scroll infinito misto — perde identità outdoor
- ❌ "Stories" effimere — non hanno senso fuori dal social
- ❌ Ranking ML pesante early stage — overengineering senza dati

---

## Sprint plans v2.3.5 — operativo

> Pianificazione di lavoro a 1-2 settimane, integrata con Epic. Aggiornato 2026-05-10.

### Sprint A — Polish + chiusura valore Spazi Pro (settimana corrente, in corso)

Goal: i seed clients (rifugio Curò + noleggio ebike) dicono "vale 200€/anno facili".

| Task | Epic ref | Effort |
|---|---|---|
| Fix bug planner web "scegliere punti più vicini" | 8.B1.3 | XS |
| Fix bug click sidebar "Gruppi Business" legacy | — | XS |
| `socialFeaturingOptIn` flag track + user_profile | 10.C1 | S |
| Percorsi consigliati su business profile | 7.C1 | M |
| Reviews & rating system | 7.C2 | L |
| Statistiche profilo business (visite, click contatti) | 7.C3 | M |
| Mappa-picker per riposizionare business | 7.C4 | S |
| Push notif business posts | 7.C5 | S |

### Sprint B — Strategia 3 piani (target v2.3.5)

Goal: tassonomia pulita, schema Spazi Pro come canonical, gruppi business legacy deprecati.

| Task | Epic ref | Effort |
|---|---|---|
| Refactor gruppi business legacy → Consumer Pro features | 7.G1-G4 | L |
| Cap consumer free vs Pro (rivedere `project_consumer_caps_open`) | — | M |
| Linked group opzionale Pro tier | 7.C7 | S |
| Self-serve onboarding wizard B2B web | 7.C6 | M |

### Sprint C — Acquisition + quick wins consumer (target v2.4.0)

| Task | Epic ref | Effort |
|---|---|---|
| Outreach 50 noleggi ebike Lombardia | 7.F2 | M |
| Case study primo cliente | 7.F4 | S |
| Discover ricerca testuale full-text | 4.4 | S |
| Filtro regione amministrativa | 4.5 | S |
| Discovery prompt "Scopri Pro" A/B | 6.B6 | S |
| Mini-sprint web vanilla: `/pro.html` + `/business.html` | 8.A2-A3 | S |

### Sprint D — Sblocco monetizzazione (dipende da P.IVA + commercialista)

| Task | Epic ref | Effort |
|---|---|---|
| Stripe B2B subscription products + checkout + portal | 7.E1-E2 | L |
| Stripe webhooks (renew/cancel/refund) | 7.E3-E4 | M |
| App Store Server Notifications V2 webhook | 6.B9 | M |
| Cloud Function `validateGoogleReceipt` (sblocca Android billing) | 6.B10 | M |
| Email "Stai per perdere Pro" | 6.C2 | S |
| Analytics conversion funnel | 6.B8 | S |

### Sprint E — Komoot Foundations + Pro consumer (target v2.5.0)

| Task | Epic ref | Effort |
|---|---|---|
| Highlights su track | 11.A1 | M |
| Difficulty rating computed | 11.A2 | S |
| Surface profile | 11.A3 | M |
| Track detail HR per zone | 4.6 | S |
| Confronto con PR personale | 4.7 | M |
| Benefit reminder ogni 30gg | 6.C3 | S |
| Lifetime discount per attivi >50 tracce | 6.C4 | S |

### Sprint F — Tour Collections + Public landings (target v2.6.0)

| Task | Epic ref | Effort |
|---|---|---|
| Schema `trail_collections` + Discovery tab | 11.B1-B3 | M |
| Workflow business curation collezioni | 11.B4 | M |
| Pagina pubblica `/track/{slug}` | 8.C1 | M |
| Pagina pubblica `/b/{slug}` Spazio Pro | 7.D1, 8.C2 | M |
| Bulk import tracce GPX dal web | 7.C8 | M |
| Generatore card invito QR PDF | 7.C9 | M |

### Sprint G — Multi-day + Wow Pro (target v2.6.0 → v2.7.0)

| Task | Epic ref | Effort |
|---|---|---|
| Multi-day tour planner con Spazi Pro stops | 11.C1-C4 | XL |
| 3D fly-through replay | 6.3 | L |
| Time-lapse video auto | 6.8 | M |
| "Regala Pro a un amico" referral | 6.C5 | M |

### Sprint H+ — Routing ML (target v2.8.0+, in background)

| Task | Epic ref | Effort |
|---|---|---|
| Decisione Fase 0 routing ML | 11.D | — |
| Data pipeline + map matching | 11.D1-D2 | XL |
| Modello v1 + shadow rollout | 11.D3-D5 | XL |
| Public rollout per regione | 11.D6 | continua |

---

## Versioning attuale e prossimi target

### Storico

| Versione | Stato | Contenuto principale |
|---|---|---|
| v1.5.6 | Produzione storica | Security hardening |
| v1.6.0 | Produzione storica | Unificazione Segui-traccia + community |
| v1.7.0+47 | Produzione storica | Epic 1 — Sicurezza completa |
| v1.8.0+48 | Produzione | Epic 2 — POI, tours, sharing, export, dark, onboarding |
| v1.8.1 | Produzione | Sprint UX audit (profilo, discovery carousel) |
| v1.8.2+51 | Produzione | Fix manifest READ_MEDIA |
| **v1.9.0+52** | **Produzione consolidata** | Epic 3 — Engagement (compass, sfide, commenti, report, classifiche) |
| v2.0.0 | Skipped | Foundation paywall accorpato in 2.1 |
| v2.1.0+55 | Test interno superato | Mountain Recognition AR + Photo Mode + paywall foundation |
| v2.1.1+56 | Apple Review cancellata, Play Store rilasciata | 3 stili mappa Pro (Topo, Hybrid, Inverno) MapTiler |
| v2.2.0+57 | Produzione | B2B Groups L1 (logo + badge verificato) — schema poi superseded da v2.3.5 |
| **v2.3.0** | **Produzione (Pro Apple LIVE)** | Sblocco subscription Pro consumer su App Store — Apple Review approvata |
| **v2.3.5** | **In sviluppo (next release)** | Spazi Pro entity B2B + Wearable bidirezionale + AI Manager + refactor gruppi legacy |

### Prossimi target

- **v2.3.5** (in sviluppo) — Sprint A + B chiusi:
  - Epic 7 (Spazi Pro mobile + web admin) → store
  - Epic 9 (Wearable: Health + Strava bidirezionale) → store
  - Epic 10 (AI Manager) integrazione lato app TrailShare
    (manager runtime già live su Firebase project separato)
  - Polish residuo + percorsi consigliati + reviews + stats business
  - Refactor gruppi business legacy
- **v2.4.0** — Sprint C + D:
  - Acquisition outreach (Sprint C)
  - Stripe B2B (Sprint D, dipende da P.IVA)
  - Webhook V2 Apple + Google receipt validate
  - Mini-sprint web vanilla (`/pro.html`, `/business.html`)
- **v2.5.0** — Sprint E:
  - Komoot Foundations (highlights, difficulty, surface)
  - Pro features consumer (HR per zone, PR personale)
  - Lifecycle premium (benefit reminder, lifetime discount)
- **v2.6.0** — Sprint F + G iniziale:
  - Tour Collections curate (Epic 11.B)
  - Pagine pubbliche `/track/{slug}` e `/b/{slug}` (Epic 8.C)
  - Bulk import + card invito PDF (Epic 7)
- **v2.7.0** — Sprint G chiuso:
  - Multi-day Tour Planner integrato Spazi Pro (Epic 11.C)
  - 3D fly-through, time-lapse video, AI route recommendation (Epic 6.3, 6.7, 6.8)
  - Referral Pro (Epic 6.C5)
- **v2.8.0+** — Sprint H:
  - Routing engine ML in shadow mode (Epic 11.D)
  - Custom domain Spazi Pro Enterprise (Epic 7.D5)

### Criteri di rilascio v2.3.5

1. Spazi Pro: 2 seed clients onboardati (rifugio + noleggio) con feedback positivo raccolto
2. Wearable: Strava bidirezionale verificato end-to-end con utenti reali
3. AI Manager: `socialFeaturingOptIn` flag in app + 4 settimane di pubblicazione automatica IG+FB senza intervento umano
4. Web admin: nessun crash su login + dashboard + creazione/edit business
5. Refactor gruppi legacy: zero clienti business attivi paganti coinvolti (zero rischio)
6. Polish UX: percorsi consigliati + reviews + stats business funzionanti dal mobile e web

---

## Storico versioni (release notes essenziali)

### v2.3.5 (in sviluppo, 2026-05-10)

**Epic 7 — Spazi Pro Business**
- Nuova entity `businesses/{id}` separata dai gruppi
- Profilo pubblico con hero, logo, contatti, mappa, listino, post, orari, follow
- Galleria foto multi-upload con long-press remove
- Discovery tab "Spazi Pro" (list + mappa + filtri + bottom sheet pin)
- Web admin: sidebar tab + picker + dashboard riusando pagine mobile in dialog
- Storage rules `businesses/{id}/{kind}` con CORS pubblico
- CORS Cloud Function `orsProxy` aperto a `localhost:*` in dev

**Epic 9 — Wearable Integrations**
- HealthKit + Health Connect: workout + route GPS + HR auto-associato
- Strava bidirezionale: upload end-of-session (badge real-time, retry) + import via webhook
- Cron `stravaReconcilePending` per pending uploads
- Toggle "Carica/Importa Strava" in Settings
- Strava scope esteso a `activity:read_all` + opt-in checkbox

**Epic 10 — AI Manager Social**
- Manager `trailshare-ai-manager` LIVE su Firebase project dedicato
- Pipeline cross-project Firestore SA → caption gen → IG+FB publish
- Bridge `social_lab/scripts/bridge.mjs` con LaunchAgent watcher
- Telegram bot cockpit per approve/reject

### v2.3.0 (Apple + Play Store, produzione)
- **Sblocco subscription Pro consumer su App Store** (Apple Review approvata)
- IAP `trailshare_pro_monthly` €2,99 + `trailshare_pro_yearly` €19,99 attivi su Apple
- Receipt validation server-side via `validateAppleReceipt`
- Cross-device Pro sync via `users/{uid}.proStatus`
- (Schema B2B `Group.businessTier` di v2.2.0 ancora presente — sarà superseded da v2.3.5)

### v2.2.0+57 (Apple Review + Play Store, 2026-05-02)
- B2B Groups L1: logo personalizzato + badge ✓ verificato (schema poi rivisto in v2.3.5)
- Tracce condivise nei gruppi via `Track.groupIds`
- Force-server fetch su Firestore al return da detail page
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

### v1.9.0+52 (produzione consolidata, 2026-04)
- Compass-up navigation con sensor fusion GPS + magnetometro + LPF
- Sfide settimanali personalizzate (4 tipi, generator basato su 8 settimane storiche)
- Commenti sulle tracce community con moderazione owner
- Report mensile automatico "Il mio mese" + Discovery prompt nei primi 7gg
- Classifiche regionali per regione (totale + mese in corso) con denormalizzazione
- Trail Conditions AI summary (Pro feature)

### v1.8.x (Aprile 2026)
- POI lungo il percorso + notifiche vocali geolocate (TTS via `voice_guidance_service.dart`)
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
