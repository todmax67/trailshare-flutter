# Screenshot degli store — cosa non va

Esaminati il 2026-08-01 i 18 file in `adv/Screenshot-Store`: 10 per App Store
(1284×2778, tranne uno) e 8 per Play.

Gli screenshot contano più delle parole chiave. Le parole ti fanno **trovare**,
gli screenshot decidono se ti **installano** — e su App Store i primi tre si
vedono nei risultati di ricerca senza nemmeno aprire la scheda.

## I due slot più preziosi sono sprecati

**Apple #1 è la schermata di benvenuto dell'onboarding.** Un'icona generica e un
paragrafo di testo: "La tua app per registrare e condividere avventure outdoor".
È l'immagine più vista di tutta la scheda e non mostra l'app. Chi la guarda non
impara niente che non sapesse già leggendo il nome.

**Apple #10 è la splash screen**, cioè il logo su sfondo. Zero informazione, e
per giunta è l'unico file a **1242×2688** invece di 1284×2778: risoluzione
diversa dagli altri nove.

## `rifugi` non compare in nessuno dei diciotto

Su nessuno dei due negozi. Abbiamo appena costruito nome, sottotitolo, keyword e
descrizione attorno alla nicchia dei rifugi — l'unica dove l'app è dodicesima
invece che fuori dai cento — e nel racconto per immagini quella parola non c'è.
Nessuno screenshot mostra un rifugio, un bivacco o la mappa dei punti in quota.

## Le mappe offline: sepolte su Apple, assenti su Play

Su Apple stanno allo slot **7**. Su Play **non ci sono affatto**: le otto
didascalie sono Registra, Tracking live, Sicurezza, Statistiche, Scopri sentieri,
Community, Pianifica, Tour.

È la prima parola del sottotitolo nuovo e il motivo per cui un'app da montagna
si scarica invece di usare Google Maps.

## Le mappe mostrano paesi, non montagne

| File | Didascalia | Cosa si vede davvero |
|---|---|---|
| Apple #2 | "GPS preciso, ovunque." | Viale Luigi Pasteur, Via Gregor Mendel, Via Briantea — vie di città |
| Apple #6 | "Non sei mai solo." | stesso incrocio urbano |
| Play #1 | "Registra le tue avventure" | le vie del centro di Ardesio |
| Play #2 | "Tracking live con Lifeline" | stesso posto |

Un'app che promette di funzionare dove il telefono non prende, fotografata su
una scacchiera di strade asfaltate. Play #1 almeno porta una statistica vera in
alto — *E-Mountain Bike, 19.9 km, +448 m, 1h 33m* — ma la mappa sotto resta il
paese.

## Due schermate mostrano l'app che non funziona

**Apple #6**, didascalia "Non sei mai solo": il riquadro rosso dice
`SOS attivato` e sotto **`Lifeline non è attiva. Puoi solo chiamare il 112.`**
La funzione di sicurezza è pubblicizzata mostrandola **spenta**.

**Play #2**, didascalia "Tracking live con Lifeline": i contatori segnano
`0.00 km`, `7s`, `0 m`, `0.0 km/h`. Una registrazione appena avviata che non ha
ancora fatto niente, nel secondo screenshot del set.

## Ordine proposto per Apple

Otto slot invece di dieci. Meglio otto che dicono qualcosa che dieci di cui due
vuoti.

| # | Cosa | Da dove |
|---|---|---|
| 1 | **Rifugi e bivacchi sulla mappa** | da girare — è la nicchia e non esiste |
| 2 | **Mappe offline**, con la modalità aereo visibile | oggi #7, da promuovere |
| 3 | Registrazione **in montagna**, con numeri veri | rigirare #2 |
| 4 | Migliaia di sentieri | #5, va bene com'è |
| 5 | Community | #4 |
| 6 | Pianifica il percorso | #3 |
| 7 | Lifeline **attiva** | rigirare #6 |
| 8 | Gruppi privati | #8 |

Fuori: la schermata di benvenuto (#1) e la splash (#10). Il paywall (#9) è una
scelta: mostrare `19,99 €/anno` nella galleria frena l'installazione, e con una
recensione sola non abbiamo margine — ma è legittimo volerlo dire subito.

Per Play vale lo stesso ordine, più uno screenshot di mappe offline che oggi
manca del tutto, e il rigiro di #1 e #2 con la montagna e i numeri veri.

## Da rigirare, in concreto

1. Mappa Scopri centrata sulle Orobie o sulle Dolomiti, con i marker dei rifugi
   visibili — è lo screenshot che manca e serve per primo
2. Registrazione su una traccia vera, con distanza e dislivello diversi da zero
3. Lifeline **attiva**, non l'avviso che è spenta
4. Mappe offline anche per Play

### Perché non si catturano dal simulatore

Provato il 2026-08-01, non funziona. **L'app è interamente dietro il login**:
`lib/app.dart:184` restituisce `LoginPage` finché `authStateChanges` non emette
un utente. Discover, registrazione, Lifeline e mappe offline stanno tutte oltre
quel muro, e le credenziali non le inserisco.

Due ostacoli minori trovati per strada, che restano utili a sapersi:

- `~/Library/Developer/CoreSimulator/Devices` è un **symlink a
  `/Volumes/Lexar`**, e CoreSimulatorService non ha accesso ai volumi esterni:
  `Operation not permitted`. Per questo `simctl` non elenca nessun dispositivo
  benché sul disco ce ne siano 24. Si sblocca dando l'accesso ai volumi
  rimovibili in Impostazioni di Sistema → Privacy e sicurezza.
- Il disco interno è al 100%: creare un dispositivo lì è una via senza uscita.

**La strada praticabile** è catturarli dal telefono del founder, dove account,
tracce e Pro ci sono già. E una nota che semplifica: la registrazione "con
numeri veri" non richiede una registrazione dal vivo — basta aprire una traccia
salvata in montagna, che i numeri veri ce li ha già.
