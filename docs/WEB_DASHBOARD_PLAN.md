# TrailShare — Piano Web Dashboard

Stato: **parcheggiato** (da riprendere dopo rifinitura app v1.7.0+)  
Creato: 2026-04-17

---

## Contesto

Attualmente `trailshare.app` ospita solo sito marketing statico (index, privacy,
terms, help, delete-account) più viewer live (`/live`) e pagine condivise
(`/track/**`, `/user/**`). Manca una **dashboard utente web** in stile
Strava / AllTrails / Komoot.

Obiettivo futuro: permettere agli utenti di accedere dal browser per consultare
le proprie tracce, pianificare percorsi, esplorare la community — senza
obbligare l'uso dello smartphone.

---

## Decisioni strategiche

### Stack scelto: **Flutter Web**

Motivazione: si riutilizza la codebase Flutter esistente (modelli, repository,
widget). L'alternativa Next.js/React richiederebbe riscrittura totale di tutta
la logica dati. Flutter Web ha bundle più pesante (~3MB) e SEO più debole, ma
per una dashboard interna (utente autenticato) è accettabile.

### Strategie di deploy

- **Sottodominio**: `app.trailshare.app`
- **Hosting**: Firebase Hosting (già configurato)
- **Codebase**: unica (stesso repo dell'app mobile, branch `kIsWeb` dove serve)

### Limitazioni web accettate

Alcune feature **non** saranno disponibili nella versione web (gestite con
`kIsWeb` per nasconderle):

- ❌ BLE fascia cardio (Web Bluetooth è instabile)
- ❌ Health Connect / Apple Health
- ❌ Camera geotag foto (sostituire con input file)
- ❌ Foreground service / notifiche background
- ❌ Battery monitoring
- ⚠️ Mappe offline (servirebbe cache su IndexedDB)

La versione web sarà quindi **consultativa** (lista/dettaglio/planner),
non **registrativa** (il tracking GPS continua solo su mobile).

---

## Roadmap in 3 fasi

### 📦 Phase 1 — MVP "Read-Only Dashboard" (2 settimane)

Goal: utente può loggarsi da browser e consultare le proprie tracce.

| # | Task | Stima |
|---|---|---|
| 1.1 | Setup build web + routing + Firebase Hosting su `app.trailshare.app` | 1g |
| 1.2 | Guardrail `kIsWeb` per disabilitare BLE/Health/Battery/FG service | 0.5g |
| 1.3 | Login email + Google + Apple | 2g |
| 1.4 | Pagina "Le mie tracce" con filtri e paginazione | 2g |
| 1.5 | Dettaglio traccia read-only (mappa + grafici + stats + export GPX/TCX + foto) | 3g |
| 1.6 | Layout responsive + sidebar navigation + tema coerente col marketing | 2g |

**Milestone:** utente può aprire `app.trailshare.app`, loggarsi, vedere lista
tracce, aprire dettaglio, scaricare GPX.

### 🌍 Phase 2 — Social Dashboard (3 settimane)

| # | Task | Stima |
|---|---|---|
| 2.1 | Dashboard home: stats settimanali, ultima traccia, mini-feed | 2g |
| 2.2 | Discover: trail pubblici + community tracks + filtri + mappa | 4g |
| 2.3 | Profilo pubblico `/user/{username}` con tracce pubbliche e stats | 2g |
| 2.4 | Feed "Seguiti": attività degli amici | 2g |
| 2.5 | Segments: lista + leaderboard | 3g |
| 2.6 | Settings base: account, privacy, contatti emergenza | 2g |

### 🗺️ Phase 3 — Creator Tools (3 settimane)

| # | Task | Stima |
|---|---|---|
| 3.1 | Planner web (il più complesso: ORS, waypoint, elevation) | 5g |
| 3.2 | Import GPX (upload + preview + salva) | 1g |
| 3.3 | Edit traccia (nome, descrizione, privacy, pubblica/rimuovi) | 2g |
| 3.4 | Leaderboards regionali/settimanali | 2g |
| 3.5 | Condivisione pubblica `/t/{id}` SSR statica con Open Graph | 2g |

---

## Dipendenze e prerequisiti

Prima di iniziare Phase 1:

- [ ] v1.7.0 pubblicata e stabile su Play Store e App Store
- [ ] Crashlytics mostra crash rate <1%
- [ ] Firebase Hosting ha almeno 1 mese di dati per verificare comportamento
- [ ] Feedback utenti raccolto per eventuali funzionalità prioritarie diverse
- [ ] Decisione: procedere con `app.trailshare.app` vs `trailshare.app/app`
- [ ] Certificato SSL automatico per sottodominio (Firebase lo gestisce)

## Prerequisiti tecnici (quando si parte)

- Firebase Auth: verificare `authDomain` configurato per il nuovo sottodominio
- Firestore rules: nessuna modifica necessaria (l'utente web usa stesso auth)
- Storage rules: idem
- Google Sign-in: configurare OAuth client web in Google Cloud Console
- Apple Sign-in: creare Service ID + key per web in Apple Developer

---

## Costi stimati (tempo)

- Part-time 20h/settimana: **8-10 settimane** MVP completo (fasi 1+2+3)
- Full-time 40h/settimana: **4-5 settimane** MVP completo

MVP minimo utile (solo fase 1): **2 settimane part-time** o 1 full-time.

---

## Link utili per quando si riprende

- Flutter Web docs: https://flutter.dev/web
- Firebase Hosting multi-site: https://firebase.google.com/docs/hosting/multisites
- Apple Sign-in per web: https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_js
- flutter_map + leaflet.js alternative su web
- OpenRouteService JS SDK (al posto del proxy? valutare)

---

## Note decisionali (parking lot)

### Opzione rinviata: Next.js / React
Se in futuro si vuole SEO forte (per pagine pubbliche condivise come
`/t/{id}`), valutare una **piccola app Next.js solo per le pagine pubbliche**
(SSR/SSG), mentre il dashboard utente resta in Flutter Web. Architettura ibrida.

### Opzione rinviata: PWA mobile-first
Trasformare Flutter Web in PWA (installabile dal browser). Non sostituisce
l'app nativa ma permette uso "veloce" senza installazione. Valutare post-MVP.

### Feature mobile-only che non andranno mai su web
- Lifeline "auto-alert da background" (non ha senso web)
- Recording GPS tracking (batteria, FG service)
- BLE HR, Health sync
- Foto con geotag nativo
