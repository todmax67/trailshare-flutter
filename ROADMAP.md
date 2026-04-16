# TrailShare — Roadmap di sviluppo

Ultimo aggiornamento: 2026-04-16  ·  Versione corrente: `1.6.0+45`

Documento vivo. Le voci sono ordinate per priorità all'interno di ogni categoria. Stima sforzo indicativa in giornate uomo.

---

## Legenda

- **Priorità**: 🟥 critica · 🟧 alta · 🟨 media · 🟩 bassa
- **Effort**: XS (<0.5d) · S (1d) · M (2-3d) · L (1 settimana) · XL (>1 settimana)
- **Status**: ☐ da fare · 🔄 in corso · ✅ fatto

---

## Epic 1 — Sicurezza

Target: rendere TrailShare l'app più sicura per chi va in montagna da solo in Italia.

| # | Feature | Priorità | Effort | Status |
|---|---|---|---|---|
| 1.1 | Lifeline (condivisione posizione live con 1-3 contatti via SMS/WhatsApp) | 🟥 | M | ☐ |
| 1.2 | Pulsante SOS accessibile durante registrazione, integrato con 112 | 🟥 | S | ☐ |
| 1.3 | Auto-alert ai contatti se utente fermo >30 min in registrazione | 🟥 | S | ☐ |
| 1.4 | Re-routing automatico quando off-trail >100m per >30s | 🟧 | S | ☐ |
| 1.5 | Modalità "Battery saver" (GPS 10s, schermo off forzato) | 🟧 | S | ☐ |
| 1.6 | Widget lock-screen con stats essenziali (iOS Live Activities / Android foreground) | 🟨 | M | ☐ |

Note tecniche 1.1: sfrutta `LiveTrackService` esistente — serve UI contatti + deep link condivisibile.

---

## Epic 2 — Completezza funzionale

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

## Epic 3 — Engagement

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

- **v1.7.0** — Epic 1 completa (Sicurezza): Lifeline + SOS + battery saver + re-routing
- **v1.8.0** — POI/Highlights + notifiche geolocate + sharing link pubblico
- **v1.9.0** — Challenges personali + heatmap + commenti community
- **v2.0.0** — Multi-day tours + Apple Watch app + dark mode app-wide

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
