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
