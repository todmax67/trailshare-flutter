# Motore di crescita — Fase 0: la spina dorsale della misura

**Stato:** implementata il 2026-07-31. Non ancora in produzione (serve una build
pubblicata sugli store) e rules non ancora deployate.

## Perché esiste

Prima del 2026-07-31 l'app non misurava nulla di acquisizione: zero `logEvent`
in tutto `lib/`, solo Crashlytics e la collection `save_diagnostics`. Il manager
social misurava like, reach e follower.

Conseguenza pratica: si poteva pubblicare per un anno senza sapere se un solo
post avesse portato un utente. Qualunque strategia costruita su quei numeri
ottimizza reach, che non è l'obiettivo.

Questa fase non aggiunge intelligenza. Aggiunge il **denominatore**: senza,
nessun esperimento della Fase 2 sarà dimostrabile, perché non esiste un "prima"
registrato con cui confrontare il "dopo".

## Architettura

```
App Flutter                          ai-manager (Firebase)
───────────                          ─────────────────────
GrowthAnalyticsService
  ├─► Firebase Analytics (GA4)       coorti e retention in console,
  │                                  attribuzione store / Search Ads
  │
  └─► growth_users/{uid}  ──────────► growthDaily (7:30)
      (1 doc per utente)   read-only  └─► growth_daily/{YYYY-MM-DD}
                          cross-proj      + report Telegram
```

**Perché due sink.** Analytics ha fino a 24h di ritardo e per interrogarlo
davvero serve l'export BigQuery: inadatto a una Cloud Function che deve
decidere stamattina. Firestore dà il dato subito ed è già raggiungibile dal
manager via il service account cross-project esistente (`prodFirestore.ts`).
Analytics resta per le coorti esplorative e perché è il sink su cui si
agganciano gli store.

**Perché un doc per utente e non uno per evento** (a differenza di
`save_diagnostics`): gli eventi che contano qui sono per-vita-utente ("la prima
traccia salvata"), e la forma naturale per funnel e coorti è la riga-utente.
Costo: al massimo una scrittura al giorno per utente attivo.

## Consenso e basi giuridiche

I due sink hanno regimi diversi, e questo è deliberato.

**Firebase Analytics — consenso.** Terza parte, con un identificativo di
istanza persistente. Spento fino a che l'utente non risponde alla schermata di
consenso mostrata dopo l'onboarding (`analytics_consent` assente ≠ rifiutato:
assente significa "da chiedere"). Revocabile da Impostazioni → Privacy; alla
revoca si chiama anche `resetAnalyticsData()`, perché smettere di raccogliere
senza buttare l'identificativo già generato non è una revoca.

**`growth_users` — legittimo interesse.** Primo party, sul nostro backend,
legato a un account che l'utente ha creato. Attivo per tutti, con opposizione
da Impostazioni → Privacy che ferma la raccolta **e cancella il documento**.

La conseguenza pratica che rende il tutto sostenibile: il motore di crescita
legge `growth_users`, non Analytics. Se metà degli utenti rifiuta il consenso,
`growth_daily` resta completo — si perdono le coorti esplorabili in console,
non i numeri su cui si decide.

Nessun ID pubblicitario: rimosso dal manifest e disattivato lato SDK. Vedi
[store_privacy.md](store_privacy.md) per il perché e per le dichiarazioni.

## Il funnel

| Milestone | Evento GA4 | Campo Firestore | Dove viene registrata |
|---|---|---|---|
| Prima apertura | `ts_first_open` | `firstOpenAtClient` ¹ | `main.dart` |
| Metodo di accesso scelto | `signup_started` | — ² | `auth_service.dart` |
| Registrazione | `signup_completed` | `signupAt` | `auth_service.dart` |
| Onboarding | `onboarding_completed` | `onboardingDoneAt` | `onboarding_page.dart` |
| Primo Discover | `discover_first_open` | `firstDiscoverAt` | `onboarding_checklist_service.dart` |
| Primo preferito | `trail_first_favorited` | `firstFavoriteAt` | `wishlist_repository.dart` |
| **Attivazione** | `activation_track_saved` | `firstTrackSavedAt` | `tracks_repository.dart` |
| Prima traccia pubblica | `track_made_public` | `firstTrackPublicAt` | `tracks_repository.dart` |
| Paywall visto | `paywall_viewed` | `paywallViews` (contatore) | `paywall_sheet.dart` |
| Acquisto Pro | `pro_purchase_completed` | `proPurchaseAt` | `subscription_manager.dart` |

¹ Stringa ISO, non Timestamp: alla prima apertura non esiste ancora un uid su
cui scrivere. L'app la tiene in locale e la riporta sul doc al signup — la
differenza con `signupAt` è la latenza installazione → account.

² Solo Analytics: serve a misurare quanto perde il login stesso, non è una
tappa raggiunta.

**L'attivazione è la metrica nord di questa fase.** Un canale che porta
installazioni che non arrivano alla prima traccia salvata non sta portando
niente, e il tasso di attivazione per canale è ciò che lo rende visibile.

### Nomi riservati

GA4 scarta in silenzio gli eventi che riusano nomi riservati (`first_open`,
`in_app_purchase`, `session_start`, `screen_view`…). Da qui `ts_first_open` e
`pro_purchase_completed`.

## Attribuzione: da dove arriva un utente

Regola: vince il **primo tocco**. Chi arriva dal QR di un rifugio e due giorni
dopo riapre da un link Instagram resta attribuito al rifugio — altrimenti
l'ultimo canale toccato si prenderebbe il merito del lavoro fatto dal primo.

Tre percorsi, con coperture diverse:

| Percorso | Copre | Come |
|---|---|---|
| Deep link | Chi ha già l'app | `?src=` o `?utm_source=` su qualunque link gestito da `DeepLinkService` |
| Install referrer | Installazioni nuove **Android** | Il Play Store trasporta `referrer` fino alla prima apertura |
| Campaign link | Installazioni nuove **iOS** | Solo aggregato, in App Store Connect → App Analytics |

**Il buco da conoscere:** su iOS non esiste attribuzione per-utente del
traffico organico. Apple espone i dati di campagna solo aggregati. Per un QR in
rifugio questo significa che su Android sai *quale* utente arriva da lì, su iOS
sai solo *quanti* download ha prodotto quella campagna. Non è aggirabile senza
tecniche di fingerprinting che non useremo.

### I link tracciabili

Un solo formato da ricordare, per QR, bio social e stampa:

```
https://trailshare.app/r/<etichetta>
```

Dietro c'è `trailshare-website/pages/go.html` (rewrite `/r/**` in
`firebase.json`), che manda allo store giusto **portandosi dietro
l'etichetta**: su Android il `referrer` del Play Store, su iOS il token `ct`
di campagna. Il mezzo si deduce dal prefisso dell'etichetta, così non va
ripetuto su ogni cartoncino stampato — dove un refuso non si corregge più.

**I rifugi non hanno bisogno di un'etichetta a mano.** Ogni Spazio Pro genera
già il suo QR da `BusinessQrCardPage` (ed è nell'Outreach Kit) verso
`trailshare.app/b/<slug>`; da quella pagina il bottone di download porta a
`/r/qr_<slug>`. L'etichetta nasce dallo slug, quindi ogni rifugio è misurato
separatamente senza registri da tenere allineati.

Il registro `scripts/growth_links.json` serve solo ai canali che un link
proprio non ce l'hanno — bio social, stampa, partner. I QR si
generano da lì, in PNG per la stampa e SVG per gli ingrandimenti:

```bash
node scripts/make_qr.cjs
```

Escono in `adv/qr/`, con correzione errori a livello H: un cartoncino sul
bancone di un rifugio si sporca, si piega e si consuma agli angoli, e con H
resta leggibile anche con quasi un terzo della superficie rovinata.

Convenzione per l'etichetta: `qr_<rifugio>`, `ig_bio`, `ig_post_<data>`,
`press_<testata>`, `cai_<sezione>`. Solo minuscole, cifre, `_` e `-`: la
pagina scarta tutto il resto, perché l'etichetta finisce dentro un URL verso
gli store e arriva da un QR che chiunque può aver ristampato.

**Due limiti da conoscere.** Il token `ct` per iOS è inerte finché non si
valorizza `APPLE_PROVIDER_TOKEN` in `go.html`, che si trova in App Store
Connect → App Analytics → Campagne: senza, Apple ignora il parametro e
l'attribuzione iOS non esiste. E `/r/` non apre l'app a chi ce l'ha già —
gli universal link coprono `/app`, `/track`, `/user`, `/sfide` e l'app non
intercetta `/r`. È deliberato: chi scansiona il QR in rifugio, che è il caso
per cui la pagina esiste, l'app non ce l'ha.

Restano validi anche i parametri diretti su qualunque deep link gestito
(`?src=` o `?utm_source=`), per i casi in cui si vuole mandare a una
destinazione precisa dentro l'app invece che allo store.

## Schema dati

### `growth_users/{uid}` (Firestore TrailShare prod)

```jsonc
{
  "uid": "…",
  "acquisition": { "source": "qr_arlaud", "medium": "qr", "campaign": "estate2026" },
  "firstOpenAtClient": "2026-08-02T09:14:22.000Z",
  "signupAt": Timestamp,
  "onboardingDoneAt": Timestamp,
  "firstDiscoverAt": Timestamp,
  "firstFavoriteAt": Timestamp,
  "firstTrackSavedAt": Timestamp,
  "firstTrackPublicAt": Timestamp,
  "proPurchaseAt": Timestamp,
  "paywallViews": 3,
  "lastSeenAt": Timestamp,      // aggiornato al massimo una volta al giorno
  "activeDaysCount": 12,
  "platform": "android",
  "appVersion": "2.9.3+112"
}
```

**Le milestone sono immutabili**, imposto dalle rules. Non è diffidenza verso
l'utente: al reinstall o al cambio dispositivo il guardiano locale
(SharedPreferences) riparte vergine e il client rimanda la milestone. Se
potesse sovrascrivere, chi si è attivato sei mesi fa risulterebbe attivato oggi
e le coorti — l'unica cosa per cui questi dati esistono — diventerebbero
finzione. La rules rifiuta la scrittura, il client la ingoia, il timestamp
originale resta.

Il client non può **leggere** questa collection: non gli serve. La legge solo
l'aggregatore con l'admin SDK.

### `growth_daily/{YYYY-MM-DD}` (Firestore ai-manager)

Prodotto da `growthDaily` alle 7:30, mezz'ora prima di `dailyAnalysis`, così i
due report Telegram si leggono nell'ordine giusto: prima quanti utenti, poi
quanto hanno reso i post.

```jsonc
{
  "date": "2026-08-02",
  "funnel":  { "signup": 0, "onboarding": 0, "discover": 0, "favorite": 0,
               "activation": 0, "publicTrack": 0, "pro": 0 },
  "daily":   { "signups": 0, "activations": 0, "publicTracks": 0, "proPurchases": 0 },
  "bySource": {
    "qr_arlaud": { "signups": 12, "activated": 7, "activationRate": 0.583,
                   "eligibleD7": 9, "retainedD7": 4, "retentionD7": 0.444,
                   "publicContributors": 2, "proPurchases": 0 }
  },
  "measuredUsers": 0,
  "computedAt": "…"
}
```

**Retention D7:** il denominatore sono i soli iscritti da almeno 7 giorni.
Includere chi si è iscritto ieri farebbe crollare il tasso ogni volta che
arriva traffico nuovo — cioè proprio quando le cose vanno bene.

## Limiti dichiarati

1. **I numeri partono da zero.** Gli utenti registrati prima di questa build
   entrano in `measuredUsers` quando riaprono l'app (si crea un doc con il solo
   `lastSeenAt`), ma senza `signupAt` restano fuori dal funnel e da ogni tasso —
   della loro registrazione non sappiamo nulla, e non è recuperabile a ritroso:
   i dati non sono mai stati raccolti. La differenza fra `measuredUsers` e
   `funnel.signup` è comunque leggibile come "vecchi utenti ancora vivi".
   Serviranno alcune settimane prima che i tassi siano rappresentativi.
2. **Niente misura in debug.** `initialize()` e `milestone()` escono subito
   quando `kDebugMode`: decine di hot restart al giorno renderebbero la
   retention finzione. Stessa scelta già fatta per Crashlytics.
   Conseguenza da ricordare quando si prova la schermata di consenso in
   locale: la scelta viene salvata, ma non produce comunque eventi.
3. **iOS senza attribuzione per-utente** sul traffico organico (vedi sopra).
4. **Scan completo** della collection a ogni esecuzione dell'aggregatore. Giusto
   ai volumi attuali; sopra i ~50.000 utenti va spezzato in aggregati
   incrementali.

## Cosa serve prima che produca dati

- [ ] Deploy delle rules: `firebase deploy --only firestore:rules` — **da rifare**
      dopo l'aggiunta della `delete` su `growth_users`, senza cui l'opposizione
      dell'utente non cancella niente
- [ ] Dichiarazioni privacy nei due store e policy pubblicata — vedi
      [store_privacy.md](store_privacy.md)
- [ ] Deploy della function: `firebase deploy --only functions:growthDaily`
      (nel repo `trailshare-ai-manager`)
- [ ] Verificare che il secret `TRAILSHARE_PROD_SA_JSON` sia accessibile a
      `growthDaily` — è già usato altrove, ma i secret si dichiarano per funzione
- [ ] Una build pubblicata sugli store con la strumentazione
- [ ] Primi link tracciabili in circolazione (QR, bio social)

## Fasi successive

- **Fase 1 — l'analista:** job settimanale che produce un brief di mercato
  (ranking keyword ASO, mosse competitor, ascolto community, stagionalità).
  Numeri e fatti, non contenuti.
- **Fase 2 — lo stratega:** backlog di esperimenti con ipotesi, metrica, soglia
  e durata. L'AI propone uno alla volta, il founder approva, il sistema misura
  contro la serie storica di `growth_daily` e archivia il verdetto.
- **Fase 3 — autonomia a livelli, per canale:** L1 propone / esegue il founder →
  L2 esegue e notifica → L3 esegue entro budget e guardrail. Si sale solo dove i
  dati mostrano che funziona.
