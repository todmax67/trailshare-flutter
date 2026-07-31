# Dichiarazioni privacy negli store

Cosa spuntare in **App Store Connect → App Privacy** e in **Play Console → Sicurezza dei dati**.

Scritto il 2026-07-31 leggendo il codice, poi **riconciliato con la
dichiarazione reale di App Store Connect** (pubblicata cinque mesi prima,
verificata sulle schermate lo stesso giorno).

Esito della riconciliazione: la dichiarazione Apple era già in ordine — dieci
tipologie di dati, posizione e salute comprese. Il lavoro della 2.9.4 non apre
una voragine, sposta due caselle. Le tabelle complete restano qui sotto come
inventario di riferimento; il delta operativo è nella sezione subito seguente.

> Non è consulenza legale. Le categorie e le finalità sono dedotte dal
> comportamento del codice; la valutazione delle basi giuridiche resta tua, se
> serve col tuo consulente.

## Il delta della 2.9.4 — cosa cambiare davvero

### App Store Connect

**Due modifiche necessarie**, entrambe conseguenza del motore di crescita.

1. **Aggiungere `Identificativi → ID dispositivo`**
   Finalità: Analisi **e** Funzionalità dell'app. Collegato all'identità:
   **sì**. Tracciamento: no.

   La voce copre due identificativi diversi, ed è per questo che le finalità
   sono due. L'ID istanza di Firebase Analytics è la novità della 2.9.4 e da
   solo non sarebbe collegato — non lo uniamo mai all'uid. Ma nella stessa
   categoria ricade il **token FCM delle notifiche push**, che
   `push_notification_service.dart` scrive dentro `user_profiles/{uid}.fcmTokens`:
   un identificativo di dispositivo dentro il documento dell'utente, quindi
   collegato per costruzione. C'è da molto prima di questa build.

2. **`Dati sull'utilizzo → Interazione con il prodotto`: da "non collegato" a
   "collegato all'identità"**
   Era dichiarato non collegato, ed era corretto finché non c'era nulla. Ora
   `growth_users` è indicizzato per uid: quei dati d'uso *sono* legati
   all'identità. Apple chiede di rispondere sì se anche una sola delle raccolte
   di quel tipo è collegata.

   Ha un costo visibile: sulla scheda pubblica "Dati sull'utilizzo" si sposta da
   *Dati non collegati a te* a *Dati collegati a te*. L'alternativa sarebbe
   slegare il funnel dall'uid, che distruggerebbe l'analisi per coorti — cioè
   tutto il motivo per cui esiste. Si accetta il costo.

**Una correzione preesistente, trovata verificando le altre.**

`Diagnosi → Dati sui crash` e `Dati sulle prestazioni` erano dichiarati **non**
collegati all'identità. Lo sono invece: `lib/main.dart` passa l'uid a Crashlytics
a ogni cambio di stato dell'autenticazione (`setUserIdentifier`), ed è ciò che
permette di ritrovare i crash di chi scrive al supporto. Vanno portati a
collegato = Sì, monitoraggio = No.

**Due da valutare, preesistenti e indipendenti da questa build.**

3. `Acquisti → Cronologia acquisti` — non dichiarata. Sui vostri server stanno
   stato dell'abbonamento, prodotto attivo e scadenza. Probabilmente va aggiunta.

4. `Contatti` — non dichiarata. Sono i contatti d'emergenza di Lifeline. La
   definizione Apple parla di dati "dalla rubrica dell'utente", e i vostri
   vengono digitati a mano: lettura prudente dichiararli, lettura letterale no.
   Decisione del founder.

5. `Informazioni di contatto → Nome` — non dichiarata, mentre l'email sì. Su
   **Play il Nome è spuntato**: uno dei due store è sbagliato, e con ogni
   probabilità è Apple, visto che il displayName arriva da Google/Apple
   Sign-In e viene salvato. Da allineare.

### Cosa risultava già dichiarato (verificato il 2026-07-31)

Dieci tipologie, tutte con finalità e collegamento coerenti:

| Voce | Finalità | Collegato |
|---|---|---|
| Posizione precisa | Funzionalità app | sì |
| Indirizzo email | Funzionalità app | sì |
| Salute · Fitness | Funzionalità app | sì |
| Foto o video · Altri contenuti dell'utente | Funzionalità app | sì |
| ID utente | Funzionalità app | sì |
| Interazione con il prodotto | Analisi | no → **corretto a sì il 2026-07-31** |
| Dati sui crash · Dati sulle prestazioni | Analisi | no → **da cambiare in sì** |

URL informativa già impostato su `https://trailshare.app/privacy`. Il campo
facoltativo "URL delle scelte sulla privacy dell'utente" è vuoto: ora che
esistono i due interruttori in Impostazioni → Privacy, si potrebbe valorizzare,
ma serve una pagina web che spieghi come esercitare le scelte.

### Play Console

Verificata voce per voce il 2026-07-31. Era messa **meglio** di Apple: `ID
dispositivo o altri ID` risultava già dichiarato, e anche `Nome`, che su Apple
manca.

**Modifica necessaria, causata dalla 2.9.4:**

- `Attività nell'app → Interazioni con l'app` — era vuota, spuntata. È dove
  ricadono schermate aperte, funzioni usate, visualizzazioni del paywall e le
  tappe del funnel. Le altre tre della categoria restano vuote a ragione:
  niente cronologia ricerche, niente lista app installate, e `Altre azioni`
  sarebbe ridondante.

**Correzione preesistente:**

- `Salute e attività fisica → Informazioni sanitarie` — era vuota, con solo
  "Informazioni sull'attività fisica" spuntata. L'app legge però
  `HealthDataType.HEART_RATE` e dichiara `android.permission.health.READ_HEART_RATE`,
  e la frequenza cardiaca arriva anche dalla fascia BLE. È un parametro vitale:
  Health Connect stesso la mette sotto *Vitals*, non *Activity*. Non
  dichiararla contraddiceva sia Apple sia la dichiarazione "App per la salute"
  già compilata su Play.

**Stato verificato delle altre categorie:**

| Categoria | Stato | Nota |
|---|---|---|
| Posizione esatta | ✅ | |
| Informazioni personali 4/9 | ✅ | Nome, Email, ID utente, Altre informazioni — quest'ultima copre i contatti d'emergenza di Lifeline |
| Foto e video 1/2 | ✅ | foto sì, video no |
| File e documenti 1/1 | ✅ | import GPX/TCX/FIT |
| Informazioni e prestazioni 2/3 | ✅ | crash + diagnostica; "Altri dati sulle prestazioni" sarebbe Performance Monitoring, non usato |
| ID dispositivo o altri ID 1/1 | ✅ | |
| Finanziarie, Messaggi, Audio, Calendario, Navigazione web | ✅ | tutte a zero |
| Contatti 0/1 | ⚠️ | stessa ambiguità di Apple, vedi sopra |

**Altre due cose sul modulo Play:**

- **Eliminazione dei dati: dichiarata "non supportata", ed è falso.**
  `delete_account_service.dart` invoca la Cloud Function `deleteMyAccount`, che
  cancella geometria tracce, copie pubbliche con cheers e commenti, foto su
  Storage, token OAuth Strava/Polar revocati, pairing Garmin, l'intero
  documento utente e l'account Auth. Va messa a sì.
#### Il dettaglio per tipo di dato

Dopo la selezione dei tipi, il modulo chiede per **ognuno**: raccolto/condiviso,
trattato temporaneamente, obbligatorio o facoltativo, e le finalità. Compilato
il 2026-07-31, da riusare tale e quale al prossimo aggiornamento.

**Raccolti: sì ovunque. Condivisi: no ovunque. Trattati temporaneamente: no
ovunque** — nessuno di questi dati resta solo in memoria, finiscono tutti su
Firestore o Storage.

Il "condivisi: no" regge perché ogni trasferimento ricade in un'esclusione
prevista da Google: Firebase e Anthropic sono fornitori di servizi, i servizi
di quota e mappe ricevono solo coordinate senza identificativi, e Strava,
Polar, Suunto e Garmin sono trasferimenti **avviati dall'utente**, che collega
l'account via OAuth e attiva lui il caricamento. Quest'ultima è la sola
risposta da rivedere se un domani il caricamento diventasse automatico senza
una connessione esplicita.

| Tipo | Raccolta | Finalità |
|---|---|---|
| Posizione esatta | facoltativa | Funzionalità |
| Nome | facoltativa | Funzionalità |
| Indirizzo email | **richiesta** | Funzionalità |
| ID utente | **richiesta** | Funzionalità + Analisi |
| Altre informazioni | facoltativa | Funzionalità |
| Informazioni sanitarie | facoltativa | Funzionalità |
| Informazioni sull'attività fisica | facoltativa | Funzionalità |
| Foto | facoltativa | Funzionalità |
| File e documenti | facoltativa | Funzionalità |
| Altri contenuti generati dagli utenti | facoltativa | Funzionalità |
| Interazioni con l'app | facoltativa | **Analisi** |
| Log arresti anomali | **richiesta** | Analisi |
| Dati diagnostici | **richiesta** | Analisi |
| ID dispositivo o altri ID | facoltativa | Funzionalità + Analisi (+ Comunicazioni dello sviluppatore) |

Le tre risposte che non sono scontate:

- **Crash e diagnostica sono "richiesti"**, non facoltativi: Crashlytics non ha
  un interruttore utente, parte sempre in release. È l'unico punto in cui la
  risposta onesta è anche la più restrittiva.
- **Posizione facoltativa**: si può negare il permesso GPS e usare comunque
  l'app per sfogliare i sentieri.
- **ID dispositivo** merita anche *Comunicazioni dello sviluppatore*: il token
  FCM serve a mandare le push, e c'è l'invio di aggiornamenti di prodotto col
  suo interruttore in impostazioni.

Nessuna finalità di pubblicità, marketing o personalizzazione, da nessuna parte.

**Fuori dalla Sicurezza dei dati, ma da sapere:**

- `ID pubblicità` era già dichiarato come non utilizzato, dal 24 febbraio. Era
  vero, e la rimozione del permesso AD_ID di oggi è ciò che lo mantiene tale:
  aggiungere Firebase Analytics senza quella rimozione avrebbe reso falsa una
  dichiarazione già pubblicata, e Play confronta proprio il permesso nel
  manifest con questa risposta.
- Avviso norme "Libreria Fatturazione 8.0.0 entro il 31 ago": **l'app è già
  conforme**. `com.android.billingclient:billing 8.0.0` è nei metadati
  dell'AAB, arriva dal plugin `in_app_purchase_android` il cui pin nel lock non
  cambia dal 28 aprile. L'avviso guarda tutti gli artefatti *attivi*: se
  persiste dopo il caricamento della 2.9.4, cercare vecchi rilasci ancora
  attivi sui canali di test.
- `READ_MEDIA_IMAGES` è dichiarato in Contenuti app ma nel manifest è rimosso
  con `tools:node="remove"`. Dichiararlo in più non blocca nulla, si può
  togliere.

> Non è consulenza legale. Le categorie e le finalità sono dedotte dal
> comportamento del codice; la valutazione delle basi giuridiche resta tua, se
> serve col tuo consulente.

## Il punto che semplifica tutto: niente ID pubblicitario

Firebase Analytics si porta dietro `play-services-ads-identifier` come
dipendenza transitiva e dichiara da sé il permesso `AD_ID`. Senza intervento
l'app avrebbe raccolto l'AAID — un identificativo persistente condiviso fra
app — pur non facendo pubblicità.

In `android/app/src/main/AndroidManifest.xml` ora ci sono tre righe che lo
impediscono: rimozione di `com.google.android.gms.permission.AD_ID`, rimozione
di `android.permission.ACCESS_ADSERVICES_AD_ID`, e il meta-data
`google_analytics_adid_collection_enabled=false`. Verificato sul manifest
finale dopo il merge: nessun permesso pubblicitario residuo.

Conseguenze concrete:

- **Nessun prompt ATT su iOS.** Non serve `NSUserTrackingUsageDescription` e non
  va aggiunto: oggi non c'è, e va lasciato così.
- **"Tracking" = No** in tutte le voci App Privacy. Nel senso di Apple, tracking
  è collegare i dati con quelli di terzi per pubblicità o data broker: non
  succede.
- **AdID = non raccolto** nel modulo Play.

Se un domani si attivano Apple Search Ads o campagne Meta, questa parte va
riaperta: cambia la risposta sul tracking e serve il prompt ATT.

### Il caso iOS, che è diverso da Android

Su Android il permesso è stato tolto e il manifest finale è pulito, verificato
sia in debug sia sulla build di release che va sugli store.

Su iOS il meccanismo è un altro. L'IPA 2.9.4+113 **contiene**
`GoogleAppMeasurementIdentitySupport.framework`, cioè la variante di Firebase
Analytics capace di leggere l'IDFA. Non è una svista: è il prodotto SPM che il
plugin `firebase_analytics` dichiara, e sotto Flutter non è sostituibile con
`FirebaseAnalyticsWithoutAdIdSupport` senza toccare un `Package.swift` che
viene rigenerato a ogni build.

Perché non è un problema: da iOS 14.5 l'IDFA è ottenibile **solo** dopo un
consenso ATT concesso, e senza `NSUserTrackingUsageDescription` nell'Info.plist
l'app non può nemmeno mostrare quel prompt. Verificato sull'IPA: la chiave non
c'è. Il framework è presente ma non ha modo di restituire altro che zeri.

Conseguenza pratica: "tracking = No" resta la risposta corretta. Ma se un
giorno qualcuno aggiunge `NSUserTrackingUsageDescription` per fare Search Ads,
la raccolta IDFA parte da sola, perché il framework è già dentro. Da ricordare.

## Inventario completo — App Store Connect → App Privacy

Quello che l'app raccoglie, dedotto dal codice. **Non è la lista da compilare da
zero**: la dichiarazione esistente copre già le righe non evidenziate, e il
delta vero è nella sezione in cima. Questa tabella serve a rileggere l'intero
quadro fra sei mesi, o quando si aggiunge una feature.

Per ogni tipo di dato: raccolto sì/no, collegato all'identità, usato per
tracking, finalità.

| Tipo di dato | Raccolto | Collegato all'utente | Tracking | Finalità |
|---|---|---|---|---|
| Contact Info → Email Address | Sì | Sì | No | App Functionality |
| Contact Info → Name | Sì | Sì | No | App Functionality |
| Contacts | Sì | Sì | No | App Functionality — solo i contatti di emergenza che l'utente inserisce a mano per Lifeline, non la rubrica |
| Health & Fitness → Fitness | Sì | Sì | No | App Functionality |
| Health & Fitness → Health | Sì | Sì | No | App Functionality — frequenza cardiaca da fascia BLE / Apple Salute |
| Location → Precise Location | Sì | Sì | No | App Functionality |
| User Content → Photos or Videos | Sì | Sì | No | App Functionality |
| User Content → Other User Content | Sì | Sì | No | App Functionality — commenti, descrizioni, segnalazioni |
| Identifiers → User ID | Sì | Sì | No | App Functionality, **Analytics** |
| Identifiers → Device ID | Sì | Sì | No | Analytics (ID istanza Firebase) + App Functionality (token FCM in `user_profiles/{uid}.fcmTokens`) |
| Usage Data → Product Interaction | Sì | Sì | No | Analytics · ⚠️ **da correggere: oggi è dichiarato non collegato** |
| Diagnostics → Crash Data | Sì | Sì | No | Analytics · ⚠️ **collegato da correggere** — `main.dart` passa l'uid a Crashlytics |
| Diagnostics → Performance Data | Sì | Sì | No | Analytics · ⚠️ **idem** |
| Purchases → Purchase History | Sì | Sì | No | App Functionality — stato abbonamento Pro · ⚠️ **non dichiarata** |

Le righe senza ⚠️ risultavano già dichiarate correttamente il 2026-07-31, con la
sola eccezione di `Contact Info → Name` e `Contacts`, discusse in cima.

Note per la compilazione:

- **Usage Data / Product Interaction collegato all'utente = Sì.** Il funnel
  `growth_users` è indicizzato per uid. È la risposta scomoda ma corretta:
  dichiararlo non collegato sarebbe falso.
- **Device ID collegato = Sì**, e la ragione non è Analytics. L'ID istanza di
  Firebase non viene mai unito all'uid dai nostri sistemi, ma il token FCM sì:
  vive dentro il profilo utente. Guardare solo l'SDK aggiunto di recente porta
  alla risposta sbagliata — la domanda è su *tutti* gli identificativi di
  dispositivo che l'app raccoglie.
- Apple permette di dichiarare che una raccolta è **opzionale**: valorizzalo per
  Usage Data, visto che dipende dal consenso e dall'opposizione.

## Play Console → Sicurezza dei dati

Per ogni voce: raccolti / condivisi / obbligatori o facoltativi / finalità.
Trasmissione cifrata: **Sì** ovunque (HTTPS, Firestore TLS). Richiesta di
cancellazione dati: **Sì** — esiste già l'eliminazione account in-app.

| Categoria → Tipo | Raccolti | Condivisi | Obbligatori | Finalità |
|---|---|---|---|---|
| Info personali → Nome | Sì | No | Facoltativo | Funzionalità app, Account |
| Info personali → Indirizzo email | Sì | No | Obbligatorio | Funzionalità app, Account |
| Info personali → ID utente | Sì | No | Obbligatorio | Funzionalità app, Analisi |
| Posizione → Posizione precisa | Sì | No | Facoltativo | Funzionalità app |
| Foto e video → Foto | Sì | No | Facoltativo | Funzionalità app |
| Salute e fitness → Info sulla salute | Sì | No | Facoltativo | Funzionalità app |
| Salute e fitness → Info su fitness | Sì | No | Facoltativo | Funzionalità app |
| Messaggi → Altri messaggi in-app | Sì | No | Facoltativo | Funzionalità app — commenti e segnalazioni |
| Attività nell'app → Interazioni con l'app | Sì | No | **Facoltativo** | Analisi |
| Attività nell'app → Altre azioni | Sì | No | **Facoltativo** | Analisi — le tappe del funnel |
| Info e prestazioni app → Log arresti anomali | Sì | No | Facoltativo | Funzionalità app, Diagnostica |
| Info e prestazioni app → Diagnostica | Sì | No | Facoltativo | Diagnostica |
| ID dispositivo o altri ID | Sì | No | Facoltativo | Analisi |
| Acquisti in-app → Cronologia acquisti | Sì | No | Facoltativo | Funzionalità app |

Note per la compilazione:

- **"Condivisi" = No ovunque.** Google agisce come responsabile del trattamento
  (Firebase), non come titolare autonomo: nella definizione di Play non è
  condivisione.
- **"Facoltativo" per le voci di analisi** perché l'utente può rifiutare in
  onboarding e opporsi da Impostazioni.
- Alla domanda sull'**ID pubblicitario** rispondi **No**: vedi sopra.
- **ID dispositivo o altri ID** resta Sì per l'ID istanza di Analytics.

## Dove l'utente esercita i suoi diritti

Sono le voci a cui rimandano entrambi i questionari e la policy.

| Diritto | Dove |
|---|---|
| Revoca del consenso Analytics | Impostazioni → Privacy → Statistiche d'uso |
| Opposizione alla misura del funnel | Impostazioni → Privacy → Misura del percorso utente (cancella anche i dati già raccolti) |
| Cancellazione completa | Impostazioni → elimina account |
| Informativa | Impostazioni → Privacy Policy, e trailshare.app/privacy |

## Da rifare quando cambia qualcosa

- Attivazione di Apple Search Ads o campagne Meta → torna il tracking, serve ATT
- Nuovi eventi che raccolgano campi non previsti qui
- Aggiunta di SDK di terze parti

## Cosa manca ancora prima di pubblicare la 2.9.4

- [x] Riconciliare con App Store Connect — fatto il 2026-07-31: era già a posto,
      restano le due modifiche in cima
- [x] Pubblicare `trailshare-website/privacy.html` aggiornata — deploy hosting
      fatto dal founder
- [x] **App Store Connect**: `Interazione con il prodotto` portata a "collegato
      all'identità" (2026-07-31)
- [x] **App Store Connect**: `ID dispositivo` aggiunto, `Dati sui crash` e
      `Dati sulle prestazioni` portati a "collegato" (2026-07-31). Apple è a posto
- [ ] **App Store Connect**: aggiungere `Nome` (su Play c'è già). Valutare
      `Cronologia acquisti` e `Contatti` — preesistenti, non bloccanti
- [x] **Play Console**: verificata voce per voce (2026-07-31). Spuntate
      `Interazioni con l'app` e `Informazioni sanitarie`
- [ ] **Play Console**: portare l'eliminazione dei dati a "supportata" — oggi
      dichiara il contrario di quello che il codice fa
- [ ] **Play Console**: completare i passaggi dopo i tipi di dati
      (raccolto/condiviso, obbligatorio/**facoltativo** per le analisi, finalità)
- [ ] Redeploy delle rules Firestore: `growth_users` ora ammette la delete
      dell'utente su sé stesso, e senza quella l'opposizione non cancella nulla

## Un buco chiuso alla radice (2.9.5)

Il pacchetto `google_fonts` scaricava la tipografia da `fonts.gstatic.com` alla
prima apertura: senza cache, ogni avvio mandava l'IP dell'utente al CDN dei
font di Google. Non era nell'informativa, non era fra i servizi di terze parti,
non era in nessuno dei due questionari — compilati lo stesso giorno.

L'abbiamo scoperto da un non-fatal Crashlytics della 2.9.4, non dall'audit.

In 2.9.5 i font sono impacchettati e la dipendenza è rimossa, quindi non c'è
niente da aggiungere alle dichiarazioni: la connessione non avviene più.

**La lezione generalizza**: un audit fatto leggendo il codice dell'app non vede
le connessioni che i pacchetti aprono per conto loro. Quando si aggiunge una
dipendenza vale la pena chiedersi non solo cosa fa, ma **con chi parla**.
