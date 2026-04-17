# TrailShare — Roadmap di sviluppo

Ultimo aggiornamento: 2026-04-17  ·  Versione corrente: `1.6.0+45`

Documento vivo. Le voci sono ordinate per priorità all'interno di ogni categoria. Stima sforzo indicativa in giornate uomo.

---

## Legenda

- **Priorità**: 🟥 critica · 🟧 alta · 🟨 media · 🟩 bassa
- **Effort**: XS (<0.5d) · S (1d) · M (2-3d) · L (1 settimana) · XL (>1 settimana)
- **Status**: ☐ da fare · 🔄 in corso · ✅ fatto · ⚠️ parziale

---

## Epic 1 — Sicurezza (target v1.7.0)

Target: rendere TrailShare l'app più sicura per chi va in montagna da solo in Italia.

### 1.A — Feature funzionali

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 1.1 | Lifeline: contatti emergenza + invio link live con token | 🟥 | M | ✅ |
| 1.2 | Pulsante SOS accessibile durante registrazione, integrato con 112 | 🟥 | S | ☐ |
| 1.3 | Auto-alert inattività 2-step (conferma locale → contatti) | 🟥 | S | ☐ |
| 1.4 | Re-routing automatico quando off-trail >100m per >30s | 🟧 | S | ☐ |
| 1.5 | Modalità "Battery saver" (GPS 10s, schermo off forzato) | 🟧 | S | ☐ |
| 1.6 | Widget lock-screen (iOS Live Activities / Android foreground) | 🟨 | M | ☐ |

### 1.B — Protezioni tecniche Lifeline (prerequisito release v1.7.0)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 1.B1 | Health-check durante Lifeline (ogni 30s: rete? Firestore? GPS?) con banner stato 🟢🟡🔴 | 🟥 | S | ☐ |
| 1.B2 | SMS fallback nativo quando manca rete dati ma c'è GSM | 🟧 | S | ☐ |
| 1.B3 | Battery-optimization whitelist prompt al primo avvio Lifeline | 🟧 | S | ☐ |
| 1.B4 | Pulsante 112 sempre accessibile durante registrazione Lifeline | 🟥 | XS | ☐ |
| 1.B5 | Backup locale posizioni (SharedPrefs/SQLite) + retry automatico | 🟧 | S | ☐ |
| 1.B6 | Countdown visuale auto-alert + anti-tap accidentale (swipe/long-press) | 🟥 | XS | ☐ |

### 1.C — Protezioni legali e comunicative (prerequisito release v1.7.0)

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 1.C1 | Disclaimer obbligatorio al primo uso Lifeline con checkbox "Ho capito" | 🟥 | XS | ☐ |
| 1.C2 | Onboarding testi contatti emergenza (spiegazione limiti + suggerimento satellitare) | 🟥 | XS | ☐ |
| 1.C3 | Aggiornare Terms of Service con sezione "Limitazioni Lifeline" | 🟥 | XS | ☐ |
| 1.C4 | Aggiornare Privacy Policy (condivisione posizione con contatti) | 🟥 | XS | ☐ |
| 1.C5 | Link a GeoResQ (soccorso alpino ufficiale) in settings Sicurezza | 🟨 | XS | ☐ |
| 1.C6 | Store description priva di claim "salvavita" garantiti | 🟥 | XS | ☐ |

### 1.D — UX mappa registrazione (overlay troppo ingombranti)

Problema osservato: in modalità guidata + Lifeline attiva, stats header + banner guida + banner lifeline occupano ~60% dello schermo, lasciando poca mappa visibile.

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 1.D1 | Stats header compatto (3 valori in una riga + tap per espandere) | 🟧 | S | ☐ |
| 1.D2 | Merge banner guida + lifeline in card unica compatta | 🟧 | S | ☐ |
| 1.D3 | Banner lifeline minimizzabile a singolo chip icona | 🟨 | XS | ☐ |
| 1.D4 | Auto-hide HUD dopo 10s inattività touch (tap schermo per riaprire) | 🟨 | S | ☐ |

---

## Epic 2 — Completezza funzionale (target v1.8.0)

Target: colmare i gap rispetto a Komoot / AllTrails / Strava.

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 2.1 | POI / Highlights lungo il percorso (fontane, rifugi, panorami, pericoli) | 🟧 | M | ☐ |
| 2.2 | Notifica vocale geolocata ai POI durante navigazione | 🟧 | S | ☐ |
| 2.3 | Multi-day tours (aggregazione tracce per "viaggio") | 🟨 | L | ☐ |
| 2.4 | Sharing link pubblico web (`trailshare.app/t/{id}` con Open Graph) | 🟧 | M | ☐ |
| 2.5 | Esportazione TCX / FIT / KML (oggi solo GPX) | 🟨 | S | ☐ |
| 2.6 | Dark mode app-wide | 🟨 | M | ☐ |
| 2.7 | Onboarding interattivo (3-4 schermate + tutorial primo record) | 🟨 | M | ☐ |

Note 2.4: richiede piccola web app Flutter o statica hostata su Firebase Hosting.

---

## Epic 3 — Engagement (target v1.9.0)

Target: aumentare ritenzione e dwell time.

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 3.1 | Sfide settimanali personali (es. "10 km entro domenica") | 🟧 | M | ☐ |
| 3.2 | Sfide gruppo / amici | 🟨 | L | ☐ |
| 3.3 | Classifiche mensili regionali | 🟨 | M | ☐ |
| 3.4 | Heatmap trail popolari (aggregata da community tracks) | 🟨 | M | ☐ |
| 3.5 | Commenti + reazioni sulle tracce community | 🟨 | S | ☐ |
| 3.6 | Mentions/tags utenti nei commenti | 🟩 | S | ☐ |
| 3.7 | Report mensile/annuale automatico con trends e record | 🟨 | M | ☐ |

Note 3.4: aggregazione geohash buckets lato Cloud Function, cache Firestore.

---

## Epic 4 — Miglioramento funzioni esistenti

Target: raffinare ciò che c'è già.

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 4.1 | Navigazione: preview pre-partenza con "Percorso X km, D+ Y m, ETA Z" | 🟧 | XS | ☐ |
| 4.2 | Navigazione: waypoint intermedi ("metà percorso raggiunta") | 🟨 | XS | ☐ |
| 4.3 | Navigazione: pausa automatica se fermo >5 min | 🟨 | XS | ☐ |
| 4.4 | Discover: ricerca testuale full-text (toponimi, rifugi) | 🟧 | S | ☐ |
| 4.5 | Discover: filtro per regione amministrativa | 🟨 | S | ☐ |
| 4.6 | Track detail: grafico HR per zone (dati già presenti) | 🟨 | S | ☐ |
| 4.7 | Track detail: confronto con PR personale sullo stesso percorso | 🟨 | M | ☐ |
| 4.8 | Track detail: split per km con tempo cumulativo | 🟩 | XS | ☐ |
| 4.9 | Mappe dark reale (Stadia/MapTiler con API key) | 🟩 | S | ☐ |

---

## Epic 5 — Polish & Performance

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 5.1 | Widget home-screen iOS/Android (stats settimana + ultima traccia) | 🟨 | M | ☐ |
| 5.2 | Apple Watch companion app | 🟩 | XL | ☐ |
| 5.3 | Garmin Connect IQ app | 🟩 | XL | ☐ |
| 5.4 | Merge/split tracce | 🟩 | S | ☐ |
| 5.5 | Tag/categorie personalizzate sulle tracce | 🟩 | S | ☐ |
| 5.6 | Ricerca nelle proprie tracce | 🟨 | XS | ☐ |

---

## Versioning proposto

- **v1.7.0** — Epic 1 completa (Sicurezza):
  - 1.A (Lifeline + SOS + auto-alert + re-routing + battery saver)
  - 1.B (tutte le protezioni tecniche)
  - 1.C (tutte le protezioni legali/comunicative)
  - 1.D (UX compatta overlay)
  - **Release-gate**: tutte le voci 🟥 devono essere ✅ o giustificate
- **v1.8.0** — POI/Highlights + notifiche geolocate + sharing link pubblico
- **v1.9.0** — Challenges personali + heatmap + commenti community
- **v2.0.0** — Multi-day tours + Apple Watch app + dark mode app-wide

### Criterio "safety-ready" per rilascio v1.7.0

Prima di rilasciare la versione "Sicurezza" in produzione:

1. ✅ Tutte le voci 🟥 critiche di Epic 1 implementate
2. ✅ Disclaimer + checkbox "Ho capito" al primo uso Lifeline
3. ✅ ToS e Privacy Policy aggiornati e revisionati
4. ✅ Test sul campo reale con un contatto, in zona con copertura parziale
5. ✅ Store description priva di claim salvavita garantiti
6. ✅ Almeno un banner di stato (🟢🟡🔴) visibile durante Lifeline

---

## Storico versioni

### v1.6.0 (2026-04-16)
- Unificazione "Segui traccia" su RecordPage (Planner + Trail + Community)
- Auto-detect activity type in modalità guidata
- Fix mappa scura (ColorFilter + stili unificati)
- Community: condizioni trail, feed seguiti, segmenti con leaderboard, foto, recensioni
- Weather forecast, discover filters, navigazione vocale

### v1.5.6 (2026-04-15)
- Security hardening (hardcoded secrets, BLE leak)
- Fix vari e stabilizzazione

---

*Ogni Epic completata → bump minor version. Ogni voce va marchiata come ✅ quando è in produzione su Store e Crashlytics non mostra regressioni.*
