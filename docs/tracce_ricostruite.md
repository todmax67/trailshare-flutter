# Tracce ricostruite dal proprietario

Progetto, non implementazione. Scritto il 2026-08-16 dopo la segnalazione di un
utente che si è ritrovato una linea retta in mezzo a un giro in bici.

## Cosa si vuole ottenere

Quando il sistema sospende l'app, la traccia si ricongiunge con una retta fra
il punto dove si è fermata e quello dove è ripartita. Dalla 2.11.3 quella retta
è tratteggiata e dichiarata, ma resta un buco.

**Il proprietario però sa dove è passato.** L'idea è lasciarglielo dire: togliere
il tratto dritto, e — in un secondo momento — ridisegnare il percorso vero col
pianificatore.

È diverso dall'instradamento automatico su OSM, scartato prima: lì un algoritmo
indovina, qui parla la persona che c'era. Cambia la **provenienza**, che è
l'unica cosa che rende un dato non misurato accettabile.

## Perché non basta aggiungere i punti a `points`

Ventiquattro file leggono i punti di una traccia. Tre di questi non devono
vedere un punto ricostruito **mai**, e non per pignoleria:

| Chi | Dove | Cosa succederebbe |
|---|---|---|
| **Segmenti cronometrati** | `segment_matching_service.dart:83` cammina su `track.points` | un tempo su un segmento che nessuno ha percorso |
| **Classifica e XP** | `functions/index.js:831` somma distanza e dislivello | posizione in classifica gonfiata |
| **Apple Health / Health Connect** | `health_service.dart:218` scrive i punti come percorso dell'allenamento | **dati inventati nella cartella sanitaria** della persona, con orari che non esistono |

E il problema non è chi bara. È che **quasi tutti ridisegnerebbero in buona
fede**, e una classifica che mescola misurato e ricostruito diventa falsa lo
stesso.

Da qui la decisione che regge tutto il progetto:

> **I punti ricostruiti non entrano in `points`.** Vivono accanto, dentro il
> buco a cui appartengono.

Non è un dettaglio di stile. Se si mescolano, ogni consumatore li eredita per
sbaglio e bisogna ricordarsi di escluderli in ventiquattro posti — cioè
dimenticarsene in qualcuno. Tenendoli separati, il comportamento predefinito è
**non averli**, e chi li vuole deve chiederli.

## Il modello

`TrackGap` esiste già e sa dov'è il buco. La ricostruzione lo riempie:

```dart
class TrackGap {
  final DateTime startedAt;      // già c'è
  final DateTime endedAt;        // già c'è
  final String cause;            // già c'è

  /// Il percorso disegnato dal proprietario. Vuoto = buco non ricostruito.
  /// Questi punti NON hanno timestamp: nessuno sa a che ora si è passati di lì.
  final List<LatLng> reconstruction;

  /// Quando è stato disegnato e da chi. Serve a dichiararlo, non a fidarsi.
  final DateTime? reconstructedAt;
  final String? reconstructedBy;
}
```

Tre scelte dentro questo modello:

**Niente timestamp sui punti disegnati.** Interpolarli sembra innocuo e non lo
è: il tempo genera velocità, e la velocità è ciò che alimenta i segmenti. Un
punto senza ora non può produrre un tempo falso.

**`LatLng` e non `TrackPoint`.** Il tipo diverso rende impossibile passarli per
sbaglio a una funzione che si aspetta punti registrati. Il compilatore diventa
un alleato invece di un testimone silenzioso.

**La registrazione originale non si tocca.** `points` resta quello che il GPS ha
misurato, per sempre. "Ripristina l'originale" è cancellare `reconstruction`,
e deve funzionare sempre.

## I punti di contatto, uno per uno

| Area | File | Comportamento |
|---|---|---|
| Mappa dettaglio | `interactive_track_map.dart` | disegna la ricostruzione, **tratteggiata come oggi** — non piena: non è misurata |
| Grafici quota | `track_charts_widget.dart` | **ignora**: non ci sono quote né tempi |
| Statistiche | `track_detail_page.dart` | due numeri: *"18,0 km misurati + 2,3 km ricostruiti"* |
| Segmenti | `segment_matching_service.dart` | **non li vede** (non sono in `points`) — nessuna modifica |
| Classifica / XP | `functions/index.js` | **non li vede** — nessuna modifica |
| Salute | `health_service.dart` | **non li vede** — nessuna modifica |
| GPX | `gpx_service.dart` | `<trkseg>` separato con `<name>ricostruito dal proprietario</name>` |
| Condivisione | `share_card_widget.dart`, web | marchio visibile: chi riceve deve saperlo |
| Miniature | `route_thumbnail.dart`, `trail_route_thumb.dart` | disegnano: serve la forma, non la precisione |

Le tre righe che dicono "nessuna modifica" sono il risultato del progetto, non
una svista: **il modo giusto di non rompere niente è non farsi vedere.**

## Le regole invarianti

Da mettere nei test, non nei commenti:

1. `track.points` contiene **solo** punti misurati. Sempre.
2. `stats.distance` misura **solo** i punti misurati. Il ricostruito si somma a
   parte e si mostra a parte.
3. Una traccia con ricostruzione **non partecipa** a segmenti, classifiche, XP,
   né viene scritta nella salute — perché quei consumatori leggono `points`.
4. L'originale è ripristinabile finché la traccia esiste.
5. La marcatura sopravvive all'esportazione e alla condivisione.

## Le fasi

**Fase 1 — il taglio, senza ridisegno. FATTA il 2026-08-16.**
Il proprietario dice *"quel tratto dritto non è mio percorso"*. Il buco diventa
dichiarato (`TrackGap` con `causeOwnerDeclared`), la retta si tratteggia, la
scheda lo dice, il GPX si spezza. Nessun dato inventato entra da nessuna parte.

Com'è fatta davvero:

- `detectUndeclaredGaps` (track_gap_segments.dart) trova gli archi con la firma
  di un'interruzione — **≥ 5 minuti E ≥ 300 metri** fra due punti consecutivi.
  La doppia soglia distingue il congelamento dalla pausa pranzo: chi si ferma
  resta dov'è. Limite dichiarato: un congelamento durante un anello che riparte
  vicino allo stesso punto non supera la soglia spaziale e non viene proposto.
- Solo il proprietario vede i candidati e può confermarli; la conferma è
  reversibile, e la rimozione ritira **solo** le dichiarazioni — i buchi del
  watchdog sono misure e non si cancellano da nessun percorso.
- Niente cambia in `points`, statistiche, segmenti, classifica, salute:
  verificato da test che confrontano il documento prima e dopo.

La Fase 1 e' passata da una **revisione avversariale** (tre revisori
indipendenti, ogni segnalazione contro-verificata da uno scettico) prima del
commit: sei difetti confermati, tutti corretti. Il piu' importante: tempo e
distanza da soli NON distinguono un congelamento da un rettilineo compresso da
Douglas-Peucker — la semplificazione butta i punti intermedi di un rettilineo
vero, e nell'archivio i due casi sono identici. Il discriminatore giusto e' il
**tempo in movimento**, calcolato sui punti pieni prima della semplificazione:
un buco vero non ha campioni e resta fuori dal movimento, un rettilineo
pedalato ci sta dentro. Il rilevatore ora accetta candidati solo se il
"tempo mancante" (durata − movimento) li copre; e la semplificazione ha una
guardia che impedisce di creare archi da 5+ minuti dove i dati esistevano,
cosi' i salvataggi futuri restano non ambigui.

Due cose scoperte implementando:

1. **Il salvataggio buttava i gaps del watchdog.** `_trackToFirestore`
   costruisce la mappa a mano, non via `toMap()`, e il campo non c'era: il
   watchdog vedeva il buco, il bloc lo metteva sulla Track, il salvataggio lo
   perdeva. I test sul modello non potevano accorgersene perché provavano
   `toMap()`, che era corretta. Sulla 2.11.3+128 i buchi registrati non
   arrivavano mai su Firestore. Corretto, con un test sul percorso vero.
2. **La corda del buco ENTRA in `stats.distance`** (la somma fra punti
   consecutivi non ha un guard sul salto). L'avviso della 2.11.3 sosteneva il
   contrario ed è stato corretto: ora dice che il tratto conta "solo in linea
   retta, quasi certamente meno della strada vera" — che è matematicamente
   garantito (corda ≤ percorso). Escludere la corda è una decisione futura:
   toccherebbe il numero più visibile dell'app e desincronizzerebbe classifica
   e XP già calcolati.

**Fase 2 — il ridisegno col pianificatore.**
Sopra la stessa struttura. Il pianificatore esiste già (`planner_tab.dart`) e sa
disegnare un percorso fra due punti seguendo i sentieri: gli si passano gli
estremi del buco e si salva il risultato in `reconstruction`.

**Fase 3 — la marcatura che viaggia.**
GPX, scheda condivisa, web. Va fatta prima che le tracce ricostruite comincino a
uscire dall'app, non dopo.

Dentro c'è anche un pezzo trovato in Fase 1: **la copia pubblicata perde i
buchi**. `published_tracks` è una collezione separata e `CommunityTrack` non
porta il campo `gaps`, quindi la vista community disegna il ponte pieno anche
quando la scheda del proprietario lo tratteggia. Vale già per i buchi del
watchdog dalla 2.11.3: da chiudere qui, propagando i gaps alla pubblicazione e
usando `trackPolylines` anche nella vista community.

## Come si verifica che non abbia rotto niente

Il criterio non è "i test passano", è **queste asserzioni specifiche**:

- una traccia con `reconstruction` valorizzata produce gli **stessi** risultati
  di segment matching di prima
- la stessa traccia contribuisce alla classifica settimanale con la **stessa**
  distanza di prima
- `health_service` scrive lo **stesso** numero di punti di prima
- il GPX di una traccia **senza** ricostruzione è **identico** byte per byte a
  quello di prima
- `stats.distance` non cambia quando si aggiunge una ricostruzione

Sono tutte verificabili senza far girare l'interfaccia.

## Cosa NON fare

- **Non fondere `reconstruction` in `points` "solo per il disegno"**. È la
  scorciatoia che vanifica l'intero progetto, e sembrerà ragionevole a chi
  toccherà questo codice fra sei mesi.
- **Non dare un orario ai punti disegnati.** Nemmeno interpolato, nemmeno
  "tanto è approssimativo".
- **Non sommare il ricostruito nel totale** per farlo sembrare più bello.
- **Non permettere la ricostruzione a chi non è il proprietario.** Il valore di
  questo dato sta tutto nel fatto che lo dice chi c'era.

## Perché potrebbe non valerne la pena

Va detto, perché è la domanda giusta prima di cominciare.

I buchi sono rari — quello segnalato è il primo arrivato da un utente esterno.
La Fase 1 costa poco e chiude il fastidio principale. La Fase 2 costa
parecchio, e produce un dato che poi va escluso da metà dell'app.

Se dopo qualche settimana di 2.11.3 i buchi registrati risultano pochi, la Fase
2 non si fa: si tiene il tratteggio e si passa oltre. **Il campo `gaps` che
abbiamo appena aggiunto è anche la misura che permette di decidere.**

---

## La Fase 2 si è fatta lo stesso — 2026-08-17

La sezione qui sopra diceva di aspettare e misurare. Il founder ha deciso
diversamente, con un argomento che la misura non poteva contenere:

> «È vero che capita poche volte, e solo su alcuni terminali, però quando
> capita è quella cosa che ti fa innamorare dell'app, crea fiducia.»

La frequenza di un difetto e il valore di ripararlo bene non sono la stessa
grandezza. Restano validi il costo e i rischi elencati sopra: sono diventati
il lavoro da fare, non un motivo per non farlo.

### La regola che tiene in piedi tutto

**I punti ricostruiti non entrano mai in `Track.points`.**

Ventiquattro file leggono i punti di una traccia, e tre non devono vederli
mai: il riconoscimento dei segmenti cronometrati
(`segment_matching_service.dart:83`), la classifica settimanale e l'XP
(`functions/index.js:831`), l'esportazione verso Apple Health
(`health_service.dart:218`). Un punto disegnato che entrasse lì produrrebbe un
tempo su segmento mai corso, XP non guadagnato, un'attività sanitaria falsa.

Il vincolo non è affidato alla disciplina di chi scrive: `reconstruction` è
`List<LatLng>`, non `List<TrackPoint>`. Senza quota e senza orario non c'è modo
di infilarla in una struttura che li pretende — **è il compilatore a impedirlo,
non un commento**.

### Cosa ha trovato la revisione avversariale

Dieci difetti confermati prima del commit, due gravi. Vale la pena tenerli
scritti, perché sono tutti la stessa famiglia di errore.

**Il giro di andata e ritorno del GPX** (grave). L'esportazione era onesta —
segmento separato, marcatura — ma il rientro no: il file riletto trasformava i
punti disegnati in punti misurati, con orari inventati da `DateTime.now()`, e
da lì li avrebbero visti segmenti, classifica, XP e Health. Tutta la disciplina
di cui sopra, aggirata da *esporta e reimporta*. Peggio: la marcatura era un
commento XML, che ogni parser scarta — compreso il nostro. Ora è un `<name>`
leggibile e l'import salta quei segmenti.

**La ricostruzione salvata su un buco che il disegnatore non guardava**
(grave). Il watchdog emette un buco ogni cinque minuti: su un congelamento
lungo sono molti, tutti fra gli stessi due punti. La scheda ne offriva uno e il
disegnatore ne sceglieva un altro — ricostruzione salvata nel database, mappa
identica a prima. Ora la regola di scelta è una sola, `TrackSegment.gap`, e
`gapsRappresentativi()` la espone alla UI; un test blocca le due parti insieme.

**Il ponte non ancorato agli estremi misurati.** Il motore di routing aggancia
i waypoint alla via più vicina, anche a centinaia di metri: disegnando solo la
ricostruzione restavano due raccordi senza alcun segno sulla mappa. Incertezza
sparita proprio nella funzione che esiste per dichiararla.

**Tre testi falsi**, tutti la stessa: dicevano che la distanza mostrata è solo
ciò che il GPS ha misurato. Non è vero — la corda in linea retta fra i due
estremi ci sta dentro, ed è la falsità già corretta in Fase 1, tornata in tre
punti nuovi. Ricostruire aggiunge un disegno, non toglie la corda.

**Cambiare l'attività dalla scheda** ricostruiva l'oggetto traccia campo per
campo e perdeva `gaps`: spariva il tratteggio e spariva il modo di togliere la
ricostruzione. Ora è `copyWith`.

### Cosa resta scoperto, dichiarato

- La ricostruzione **non ha orari**, quindi non c'è un passo né una velocità su
  quel tratto, e non ce ne saranno: inventarli sarebbe esattamente il difetto
  che questa funzione ripara.
- I chilometri disegnati **non entrano in nessun totale**. La scheda lo dice.
- La Fase 3 (marcatura che viaggia su scheda condivisa e web) non è fatta: chi
  guarda una traccia ricostruita **dal web** vede il tratteggio ma non la
  spiegazione.

---

## La seconda revisione, dopo il commit — 2026-08-17

Ottantotto agenti su undici fronti, ognuno seguito da due scettici: uno che
prova a smontare il rilievo leggendo il codice, uno che prova a **riprodurlo**
scrivendo ed eseguendo un test. Ventisette rilievi hanno superato la soglia
(permissiva: basta che uno dei due non riesca a smontarli), dieci non sono
stati smontati da nessuno dei due.

### Il difetto grave che la prima revisione aveva mancato

La prima revisione aveva trovato «tanti buchi su un arco» e l'aveva chiuso.
Nessuno aveva guardato **l'inverso**: un solo buco che copre due archi.

Succede di routine, e la causa è nel watchdog: la finestra parte dall'**ultimo
tick**, non dall'ultimo punto. Un fix GPS arrivato nei secondi fra il tick e il
congelamento cade *dentro* la finestra, e con un confronto per sovrapposizione
lo stesso `TrackGap` finiva su due archi.

Le conseguenze non erano estetiche:

- i chilometri ricostruiti si sommavano **due volte** nella scheda — 15,5 km
  dichiarati per un disegno che ne misura 7,8, cioè esattamente la
  falsificazione di un numero che quella card esiste per evitare;
- e `_estremiDi` prendeva il **primo** arco: il disegnatore riceveva gli
  estremi di 23 secondi di traccia registrata davvero invece dei 37 minuti
  mancanti, e il percorso disegnato veniva poi steso sopra entrambi.

La regola ora è una sola e vale per l'assegnazione, non per il disegno: **un
buco appartiene all'arco con cui si sovrappone di più**. Un buco che non tocca
nessun arco resta fuori — non si può né disegnare né offrire.

### Gli altri, tutti nella stessa famiglia

**La corsa fra risposte di routing.** Ogni tocco faceva partire un calcolo
senza annullare quello in volo, e le risposte non tornano in ordine: una
richiesta più vecchia che arrivava dopo sovrascriveva il percorso giusto, e il
salvataggio riguardava quello. Nessun segnale che qualcosa fosse andato storto.
Ora c'è un contatore di generazione.

**Cambiare sport teneva la difficoltà del vecchio.** Regressione introdotta
dalla *correzione* della prima revisione: passando a `copyWith` per non perdere
i `gaps` si è portata dietro anche la `computedDifficulty`, che prima restava
nulla e faceva ricadere il badge sul calcolo col nuovo sport. Una T3 della
scala trekking su una traccia diventata ciclistica, e chi pubblicava subito la
mandava così in `published_tracks`. Ora c'è `clearComputedDifficulty`.

**«Rimuovi le interruzioni dichiarate» portava via anche il disegno**, senza
avviso, subito dopo che la card aveva promesso che si può tornare indietro:
vero per la dichiarazione, falso per il disegno che se ne andava con lei. Ora
chiede conferma — ma **solo** quando c'è davvero un disegno da perdere, o la
domanda si svuoterebbe di significato.

### Due difetti che non erano della Fase 2, corretti lo stesso

Erano lì da prima, e producevano numeri falsi in classifica.

**Il merge sommava il raccordo fra le due tracce.** Misurato: 60 km salvati per
6 km camminati, e `onTrackCreate` convertiva quella distanza in ~540 XP mai
guadagnati — con le due tracce originali cancellate subito dopo, quindi il
numero gonfiato restava l'unico. Ora la giunzione è un `TrackGap` con causa
propria (`causeMergeJoint`): la mappa la tratteggia, il GPX si spezza lì, e la
sua corda **non** entra né nella distanza né nel dislivello. È l'unica causa la
cui corda non conta — per un buco del watchdog quei metri sono stati percorsi,
qui fra le due gite c'è un viaggio in macchina.

Va tenuta fuori anche dai conteggi di «quante volte la registrazione si è
fermata»: non si è fermata. Da qui `TrackGap.isRecordingInterruption`.

**Lo split distruggeva il disegno** quando il taglio cadeva esattamente sugli
estremi del buco — che è il caso *normale*, perché `detectUndeclaredGaps`
produce buchi i cui estremi sono i timestamp di due punti, e spezzare «in due
gite» proprio sulla retta è il taglio più naturale. Il buco non finiva in
nessuna delle due metà, e l'originale veniva cancellato. Ora lo split si
**rifiuta** invece di distruggere: perdere un buco del watchdog è accettabile,
perdere un percorso disegnato a mano no — non lo ripropone nessun rilevatore.

### Cosa resta aperto, dichiarato

Non sono regressioni di questa release: erano lì prima, e meritano un lavoro
loro invece di una toppa la sera prima di una pubblicazione.

- **`movingTime = duration` dopo split e merge.** È il codice che
  `detectUndeclaredGaps` legge come «tempo in movimento non attendibile», e da
  quel lato è prudenza voluta. Ma la scheda lo mostra come **misura**: «In
  movimento 15:50» include i minuti in cui l'app era congelata. Il numero va
  reso incerto o va tolto, non lasciato lì a sembrare misurato.
- **Il buco dell'uccisione dell'app non diventa mai un `TrackGap`.** È l'unico
  di cui l'app ha certezza assoluta — conosce entrambi gli estremi — e l'unico
  che non registra: `restoreFromBackup` ripristina i buchi già visti dal
  watchdog ma non aggiunge quello fra l'ultimo punto salvato e la ripresa.
  Resta la proposta a posteriori di `detectUndeclaredGaps`, che però ha soglie
  e bilancio, e che il proprietario deve confermare.
- **Il web e la scheda condivisa** disegnano il buco come percorso pieno: la
  marcatura non sopravvive alla condivisione. È la Fase 3, mai fatta.
- **`<name>` dentro `<trkseg>` non è GPX 1.1 valido.** Il giro
  TrailShare → TrailShare è guardato e testato, ma un file che passa da un tool
  conforme perde la marcatura — e in realtà perde anche il confine di
  `<trkseg>` a cui sarebbe appesa, quindi spostarla in `<extensions>`
  risolverebbe solo la validazione, non il giro. Vale una pulizia, non è la
  rottura dell'invariante.
