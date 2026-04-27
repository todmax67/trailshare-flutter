# TrailShare — Roadmap di sviluppo

Ultimo aggiornamento: 2026-04-25  ·  Versione corrente: `1.9.0+52` (in test) · Produzione: `1.7.0+47`

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

## Epic 6 — Monetization & Premium (target v2.0.0 → v2.3.0)

Obiettivo: trasformare TrailShare in **freemium sostenibile** con feature "wow non
indispensabili" che giustificano l'upgrade. Lifeline e tutto il core safety/recording
restano **sempre gratis** — la sicurezza non si paga.

### 6.A — Wow features (pull factor)

| # | Feature | Priorità | Effort | Tier | Status |
|---|---|---|---|---|---|
| 6.1 | Mountain recognition AR live (top 5 cime) | 🟧 | M | Free | ✅ |
| 6.2 | Mountain recognition photo + analisi completa + share | 🟧 | L | Pro | ☐ |
| 6.3 | 3D fly-through replay delle tracce | 🟨 | L | Pro | ☐ |
| 6.4 | Mappe topografiche premium offline (IGM, Swisstopo, Tirol Atlas) | 🟧 | M | Pro | ☐ |
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
| 6.B1 | Subscription manager (StoreKit 2 + Play Billing v6) | 🟥 | L | ☐ |
| 6.B2 | Cloud Functions per receipt validation Apple + Google | 🟥 | M | ☐ |
| 6.B3 | Premium status sync su `user_profiles.proStatus` con TTL | 🟥 | S | ☐ |
| 6.B4 | `PaywallSheet` widget riusabile + 3-4 layout A/B | 🟧 | M | ☐ |
| 6.B5 | Trial 14 giorni gratis con onboarding dedicato | 🟧 | S | ☐ |
| 6.B6 | Discovery prompt "Scopri Pro" con A/B variant | 🟧 | S | ☐ |
| 6.B7 | Restore purchases + family sharing | 🟧 | S | ☐ |
| 6.B8 | Analytics conversion funnel + churn tracking (Firebase) | 🟨 | S | ☐ |

### 6.C — Lifecycle premium

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 6.C1 | Settings "Gestisci abbonamento" + cancellazione | 🟥 | XS | ☐ |
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

## Web Dashboard (parcheggiato)

Obiettivo futuro: dashboard web su `app.trailshare.app` per consultazione tracce,
planner e community da browser.

Piano dettagliato: [`docs/WEB_DASHBOARD_PLAN.md`](docs/WEB_DASHBOARD_PLAN.md)

Status: **parcheggiato** dopo Epic 6. Effort stimato: 8-10 settimane part-time per
MVP completo. Si valuterà se confluire come "TrailShare Pro Web" (premium) o
restare free.

---

## Versioning attuale e prossimi target

### Storico

| Versione | Stato | Contenuto |
|---|---|---|
| v1.5.6 | Produzione storica | Security hardening |
| v1.6.0 | Produzione storica | Unificazione Segui-traccia + community |
| **v1.7.0+47** | **Produzione attuale** | Epic 1 — Sicurezza completa |
| v1.8.0+48 | Test/superato | Epic 2 — POI, tours, sharing, export, dark, onboarding |
| v1.8.1 | Test/superato | Sprint UX audit (profilo, discovery carousel) |
| **v1.8.2+51** | **In review Play Store** | Fix manifest READ_MEDIA |
| **v1.9.0+52** | **In test interno** | Epic 3 — Engagement (compass, sfide, commenti, report, classifiche) |

### Prossimi target

- **v2.0.0** — Epic 6 fase 1: Mountain recognition AR (free, 6.1) + paywall foundation
  (6.B1-B4) senza prodotti acquistabili. Build di scaffolding.
- **v2.1.0** — Prime feature Pro a pagamento: 6.2 (photo recognition) + 6.4 (mappe IGM premium).
  Apertura paywall reale + trial 14gg.
- **v2.2.0** — 6.3 (3D fly-through) + 6.5 (allenamento HR).
- **v2.3.0** — AI features 6.6 / 6.7 + lifecycle 6.C completo.
- **v2.4.0+** — Web Dashboard MVP (se la monetization tiene).

### Criteri di rilascio v2.0.0

1. Mountain recognition AR funzionante in field test reale (Alpi + Appennini)
2. Paywall foundation **disabilitato a livello server** (feature flag) ma compilato e testato
3. Cache cime offline ≤2 MB, query Overpass <500ms
4. Privacy Policy aggiornata per la camera permission

---

## Storico versioni (release notes essenziali)

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
