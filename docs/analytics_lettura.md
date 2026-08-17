# Leggere Analytics: cosa c'è dentro e cosa no

Nasce da una domanda del founder il 2026-08-17, guardando la dashboard
Firebase: *«l'app sembra girare, ma non capisco cosa fa chi»*.

Non leggeva male. **L'app non gliel'aveva mai detto.**

## Perché il report Schermate era vuoto

In Flutter `screen_view` **non è automatico**. Su Android e iOS nativi l'SDK
vede cambiare Activity o ViewController e manda l'evento da solo; qui c'è una
Activity sola per tutta la vita dell'app, quindi senza un
`FirebaseAnalyticsObserver` non parte niente.

Vuoto non perché nessuno usasse l'app: vuoto perché nessuno aveva mai parlato.
È la regola 3 di `CLAUDE.md` applicata a noi stessi.

E c'era una seconda metà, meno ovvia: l'osservatore nomina le schermate
leggendo `RouteSettings.name`, e **su 187 aperture di pagina solo 5 avevano un
nome**. Attaccare l'osservatore da solo sarebbe stata una modifica che compila,
si committa, sembra fatta — e non produce un dato. Da qui i 170 push nominati e
il presidio in `test/core/services/screen_names_test.dart`, che fallisce se
qualcuno aggiunge una pagina senza nome.

## Le due domande, e perché ce n'era una sola

| | domanda | dove |
|---|---|---|
| **Milestone** | «questa persona ha mai attraversato questa linea?» | `growth_users` + GA4 |
| **Azioni** | «cosa fa la gente il martedì?» | GA4 |

Le milestone (`firstTrackSaved`, `firstDiscover`, `proPurchase`…) scattano
**una volta per persona**, di proposito: misurano acquisizione e attivazione,
ed erano la Fase 0 del motore di crescita. Non possono dire cosa succede
martedì, perché martedì non scattano più.

## Le azioni, dal 2026-08-17

Sei eventi ripetibili. Pochi di proposito: ognuno è un dato da tenere onesto, e
trenta mediocri valgono meno di sei buoni. **La regola per aggiungerne uno è
che ci sia una decisione che oggi si prende a naso e che quel numero renderebbe
informata.**

| evento | risponde a | dove |
|---|---|---|
| `recording_started` | — | `tracking_bloc.dart` |
| `recording_finished` | **quante registrazioni cominciano e non finiscono mai** | `record_page.dart` (×2) |
| `track_opened` | l'app serve a rivedere le proprie uscite o a guardare quelle degli altri? | `track_detail_page.dart` |
| `search_performed` | quante ricerche escono a vuoto — cioè dove è bucato il catalogo | `discover_page.dart` |
| `hut_opened` | quante schede sono di qualcuno e quante sono POI OSM orfani | `business_profile_page.dart` |
| `offline_map_downloaded` | la funzione che ci distingue dai web-first: la usa qualcuno? | `offline_maps_service.dart` |
| `gap_reconstructed` | la 2.11.4 la usa qualcuno? | `track_detail_page.dart` |

Il rapporto **avviate ÷ concluse** è il numero più importante dell'elenco: la
differenza sono le registrazioni cominciate e mai chiuse, cioè il guasto più
grave che questa app possa avere, e di cui oggi sappiamo solo per segnalazione.
Per questo `recording_finished` è agganciato **anche** al salvataggio
automatico: contarne uno solo gonfierebbe proprio quel rapporto.

## Tre regole rispettate, e vale la pena sapere perché

**Nessun testo scritto dall'utente finisce in Analytics.** Non solo privacy:
GA4 tronca a 100 caratteri e tratta ogni valore distinto come una riga di
report, quindi il testo libero produce insieme un problema di dati personali e
un report illeggibile. Della ricerca si manda *se ha prodotto risultati*, mai
cosa è stato cercato. Della mappa offline si manda il numero di tile, mai il
nome della regione.

**Le grandezze continue vanno a fasce** (`_fascia`, testata in
`test/core/services/growth_buckets_test.dart`). Mandare i minuti esatti
darebbe mille righe da un evento ciascuna. E la domanda vera non è mai «1.732
tile» ma «tanti o pochi».

**Un campo che non sappiamo riempire non si mette.** `track_opened` doveva
avere un «da dove sei arrivato» (feed, Discover, ricerca, profilo). Servirebbe
passarlo da undici punti di apertura diversi: finché non lo si fa davvero, un
campo che dice *non attribuito* nove volte su dieci è peggio che non averlo,
perché invita a leggere come «diretto» ciò che è solo «non misurato». Quando
servirà si aggiunge il parametro ai push, non un valore di comodo.

## Il consenso, e la finestra che era aperta

Analytics **nasce spento** e lo riaccende il codice solo dopo il sì:

- Android — `firebase_analytics_collection_enabled=false` nel manifest
- iOS — `FIREBASE_ANALYTICS_COLLECTION_ENABLED=false` nell'`Info.plist`

Prima non c'erano, e l'SDK partiva acceso all'inizializzazione di Firebase per
essere spento qualche istante dopo dal Dart. In quella finestra `first_open` e
`session_start` erano già partiti, **per chiunque** — anche per chi al consenso
avrebbe risposto no. La privacy policy prometteva il contrario, e il difetto
non lasciava traccia: nei report quegli eventi sono indistinguibili dagli
altri.

Il valore impostato a runtime da `setAnalyticsCollectionEnabled(true)` è
persistente e vince sul flag, quindi dopo il sì la raccolta resta accesa fra un
avvio e l'altro.

**Conseguenza sui numeri, da tenere a mente leggendo:** GA4 vede solo chi ha
acconsentito. Non è la popolazione degli utenti, è un suo sottoinsieme, e
quanto grande non lo sappiamo finché non misuriamo il tasso di consenso. Il
funnel first-party in `growth_users` invece copre tutti (legittimo interesse
con opposizione): quando i due numeri divergono, non è un errore.

## Dove guardare, in pratica

1. **DebugView** — eventi entro pochi secondi, per verificare che arrivino e
   coi nomi giusti. È il primo posto dopo una build nuova.
2. **Realtime** — ultimi 30 minuti.
3. **Coinvolgimento → Pagine e schermate** — le schermate.
4. **Coinvolgimento → Eventi** — le azioni.

Due cose che sorprendono chi ci arriva la prima volta:

- i report standard hanno **~24 h di latenza**: guardare oggi i numeri di oggi
  non funziona, e il vuoto non vuol dire zero;
- i parametri personalizzati (`had_gaps`, `claimed`, `km_bucket`…) **non
  compaiono nei report finché non li registri come dimensioni personalizzate**
  in GA4 (*Amministrazione → Definizioni personalizzate*). L'evento arriva
  comunque, ma il campo resta invisibile: è il passaggio che fa credere che la
  strumentazione non funzioni.

## Cosa resta non misurato

Detto perché il silenzio non venga scambiato per uno zero:

- **da dove si arriva a una traccia** (vedi sopra);
- **il tasso di consenso** ad Analytics: senza, non si sa quanto valga il
  campione;
- **il pianificatore, i gruppi, i segmenti cronometrati e i Tour** non hanno
  eventi propri: di loro sappiamo solo le schermate aperte;
- **il web** (Firebase Hosting) non manda niente di tutto questo.
