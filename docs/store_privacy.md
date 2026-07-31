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
   Finalità: Analisi. Collegato all'identità: **no**. Tracciamento: no.
   È l'ID istanza di Firebase Analytics, che prima della 2.9.4 non esisteva.

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

**Due da valutare, preesistenti e indipendenti da questa build.**

3. `Acquisti → Cronologia acquisti` — non dichiarata. Sui vostri server stanno
   stato dell'abbonamento, prodotto attivo e scadenza. Probabilmente va aggiunta.

4. `Contatti` — non dichiarata. Sono i contatti d'emergenza di Lifeline. La
   definizione Apple parla di dati "dalla rubrica dell'utente", e i vostri
   vengono digitati a mano: lettura prudente dichiararli, lettura letterale no.
   Decisione del founder.

Anche `Informazioni di contatto → Nome` non è dichiarata, mentre l'email sì. Se
il displayName arriva da Google/Apple Sign-In e viene salvato, andrebbe aggiunta;
se in pratica salvate solo lo username, resta coperta da `ID utente`.

### Cosa risultava già dichiarato (verificato il 2026-07-31)

Dieci tipologie, tutte con finalità e collegamento coerenti:

| Voce | Finalità | Collegato |
|---|---|---|
| Posizione precisa | Funzionalità app | sì |
| Indirizzo email | Funzionalità app | sì |
| Salute · Fitness | Funzionalità app | sì |
| Foto o video · Altri contenuti dell'utente | Funzionalità app | sì |
| ID utente | Funzionalità app | sì |
| Interazione con il prodotto | Analisi | no → **da cambiare in sì** |
| Dati sui crash · Dati sulle prestazioni | Analisi | no |

URL informativa già impostato su `https://trailshare.app/privacy`. Il campo
facoltativo "URL delle scelte sulla privacy dell'utente" è vuoto: ora che
esistono i due interruttori in Impostazioni → Privacy, si potrebbe valorizzare,
ma serve una pagina web che spieghi come esercitare le scelte.

### Play Console

**Non ancora verificata.** Se rispecchia lo stato di Apple sarà anch'essa quasi
completa, e il delta sarà lo stesso: aggiungere *ID dispositivo o altri ID* e
rivedere le voci di *Attività nell'app*. Da controllare prima di pubblicare.

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
| Identifiers → Device ID | Sì | **No** | No | Analytics — l'ID istanza di Firebase Analytics · ⚠️ **da aggiungere** |
| Usage Data → Product Interaction | Sì | Sì | No | Analytics · ⚠️ **da correggere: oggi è dichiarato non collegato** |
| Diagnostics → Crash Data | Sì | Sì | No | App Functionality (dichiarato come Analytics: accettabile, non lo cambierei) |
| Diagnostics → Performance Data | Sì | Sì | No | App Functionality (idem) |
| Purchases → Purchase History | Sì | Sì | No | App Functionality — stato abbonamento Pro · ⚠️ **non dichiarata** |

Le righe senza ⚠️ risultavano già dichiarate correttamente il 2026-07-31, con la
sola eccezione di `Contact Info → Name` e `Contacts`, discusse in cima.

Note per la compilazione:

- **Usage Data / Product Interaction collegato all'utente = Sì.** Il funnel
  `growth_users` è indicizzato per uid. È la risposta scomoda ma corretta:
  dichiararlo non collegato sarebbe falso.
- **Device ID collegato = No.** L'ID istanza di Analytics non viene mai unito
  all'uid dai nostri sistemi.
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
- [ ] **App Store Connect**: aggiungere `ID dispositivo`, correggere
      `Interazione con il prodotto` a "collegato". Valutare `Cronologia acquisti`
- [ ] **Play Console**: verificare lo stato attuale, poi lo stesso delta
- [ ] Redeploy delle rules Firestore: `growth_users` ora ammette la delete
      dell'utente su sé stesso, e senza quella l'opposizione non cancella nulla
