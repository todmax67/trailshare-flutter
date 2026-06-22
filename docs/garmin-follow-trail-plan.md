# Fase 3 — "Segui i sentieri TrailShare dall'orologio" (modello Wikiloc)

> Piano tecnico per valutare se vale la pena. Stato: **proposta**, non avviato.
> Data: 2026-06-16.

## 1. Obiettivo

Trasformare la watch app TrailShare da "**registra**" (Strava-style, già live) a
"**registra + naviga**". L'utente, **dal polso e senza telefono**, sfoglia i propri
sentieri TrailShare, ne scarica uno e lo **segue con la navigazione nativa Garmin**
(mappa topografica vera, indicazioni di svolta, avvisi "fuori percorso").

È la parità con Wikiloc/Komoot. La Fase 1 (export → Garmin Connect) già permette di
seguire un sentiero, ma il trasferimento è manuale; questa è la versione "nativa".

## 2. Meccanismo tecnico — VERIFICATO

La domanda chiave era: *un'app Connect IQ può passare una traccia alla navigazione
nativa?* **Sì.** È il pattern usato da Wikiloc, Ride with GPS, dynamicWatch:

1. **`Communications.makeWebRequest`** scarica il percorso dal nostro backend
   (GPX per i device outdoor, FIT per i fitness/Edge).
2. **`Toybox.PersistedContent`** (Route/Course) lo salva sul dispositivo.
3. **`Toybox.System.Intent`** lancia la navigazione nativa con quel percorso →
   mappa + turn-by-turn + off-course di sistema.

Requisiti device: PersistedContent richiede **CIQ ≥ 2.2.x** → **tutti i nostri 68
device** (min 3.1.0) lo supportano. Regola: device **outdoor → GPX**, **fitness/Edge
→ FIT**. Nota documentata: in CIQ NON si leggono file GPX/FIT "a mano" — non serve:
si scarica via makeWebRequest e si passa l'oggetto a PersistedContent/Intent.

Conseguenza importante (come Wikiloc): **la mappa la mette il sistema operativo
dell'orologio**, non noi. Sui device con cartografia (fenix/epix/FR9xx) → mappa topo
piena. Sui device senza mappa (Instinct/FR2xx/Venu) → breadcrumb nativo. In entrambi
i casi via lo stesso meccanismo. Noi NON disegniamo mappe.

## 3. Architettura

```
  WATCH APP (Monkey C)                BACKEND (Cloud Functions)         FIRESTORE
  ─────────────────────               ─────────────────────────        ─────────
  [Menu "Naviga"]
     │ makeWebRequest(token) ───────► listTrailsForWatch ────────────► public_trails
     │ ◄─────────── JSON lista ◄──────  (risolve uid dal pairing        / preferiti utente
     │                                   token, ritorna i sentieri
  [Lista sentieri]                       salvati/preferiti)
     │ seleziona
     │ makeWebRequest(id) ───────────► getTrailGpx ───────────────────► geometria sentiero
     │ ◄─────────── file GPX ◄────────  (costruisce GPX dai punti)
     │
  PersistedContent.Route(gpx)
     │
  System.Intent → NAVIGAZIONE NATIVA GARMIN (mappa + svolte + off-course)
```

Autenticazione: **riusa il pairing token già esistente** (quello di syncGarminTrack).
Il token risolve l'utente → mostriamo i SUOI sentieri. Zero nuova infrastruttura auth.

## 4. Lavoro lato WATCH APP (Monkey C) — il grosso

Estendere `TrailShareApp` (repo `/Volumes/Lexar/GarminConnectIQ/Projects/TrailShareApp`):

1. **Voce "Naviga sentieri"** nello start screen (o Menu2 dedicato).
2. **Vista lista**: `makeWebRequest` → parse JSON `[{id, name, km, dplus}]` →
   `WatchUi.Menu2` con loading / vuoto / errore (offline, no token).
3. **Download + lancio**: alla selezione `makeWebRequest` del GPX →
   `PersistedContent` salva la Route → `System.Intent` lancia la nav nativa.
4. **Gestione device**: GPX (outdoor) vs FIT (fitness) in base a `DeviceSettings`;
   degrado pulito dove manca la mappa (ci pensa la nav nativa).
5. **Errori & limiti**: timeout, risposta troppo grande (cap punti), token mancante.
6. **Permessi manifest**: `Communications` (già c'è) + verificare PersistedContent.
7. Test simulatore + device reale (Epix Pro).

Stima: **3-5 giorni** (è la parte nuova e va validata sul device).

## 5. Lavoro lato BACKEND (Cloud Functions) — piccolo

In `functions/index.js`, due endpoint che **riusano il pairing token**:

1. **`listTrailsForWatch`** (onRequest, token-auth): risolve uid → ritorna i sentieri
   salvati/preferiti dell'utente `[{id, name, km, dplus}]`. ~mezza giornata.
2. **`getTrailGpx`** (onRequest, token+id): legge la geometria del sentiero da
   Firestore e ritorna un **GPX** (densità "da navigazione", non i 30 punti
   semplificati). La logica GPX esiste già in Dart (`gpx_service.dart`) → micro-port
   in Node. ~mezza giornata.
3. (v2, opzionale) query "**sentieri vicino a me**" via geohash (i trail hanno già il
   geohash). Rinviabile.

Stima: **1-1.5 giorni**.

## 6. Lavoro lato APP FLUTTER — minimo

- Garantire che esista "salva/preferito sentiero" così la lista ha contenuto
  (i preferiti dovrebbero già esserci → verifica + eventuale fix). ~0.5 giorno.

## 7. Compatibilità device

- **PersistedContent**: tutti i 68 device (CIQ ≥ 3.1.0 ✓).
- **Mappa topo nativa**: solo i device con cartografia (fenix 6/7/8, epix, FR9xx,
  Enduro, MARQ…). Gli altri (Instinct, FR2xx, Venu, Vivoactive) → breadcrumb nativo
  senza mappa di sfondo — **esattamente come fa Wikiloc**, non un nostro limite.

## 8. Scope: MVP vs v2

**MVP (consigliato per validare):**
- Lista dei sentieri **salvati/preferiti** dell'utente (no ricerca geo).
- Download GPX → PersistedContent → lancio nav nativa.
- Funziona su tutti i 68 device (mappa dove c'è).

**v2 (dopo, se la cosa prende):**
- "Sentieri vicino a me" (query geohash).
- Mostra i rifugi lungo il percorso.
- Filtri (difficoltà, lunghezza), preferiti sincronizzati.
- Eventuale vista mappa in-app con `WatchUi.MapTrackView` (solo se serve di più
  della nav nativa — probabilmente NO, vedi Wikiloc).

## 9. Stima effort totale

| Blocco | Giorni |
|---|---|
| Spike di de-risking (vedi §10) | 1 |
| Watch app (lista + download + lancio nav) | 3-5 |
| Backend (2 endpoint, riusa pairing) | 1-1.5 |
| App Flutter (preferiti) | 0.5 |
| Test device + submission store | 1 |
| **Totale** | **~1-1.5 settimane** |

Il grosso è la watch app. Il backend è piccolo perché **riusa** pairing token +
dati sentieri + logica GPX già esistenti.

## 10. Rischio principale e come azzerarlo PRIMA

**Unico vero unknown:** la sequenza esatta `PersistedContent` (salva route) +
`System.Intent` (lancia nav) sul nostro device. Le app showcase dimostrano che si
può, ma va replicato.

**De-risk = spike da 1 giorno:** prototipo che con **un GPX hardcoded** (un sentiero
fisso) fa salva-route → lancia-navigazione sull'Epix Pro. Se funziona, il resto è
"solo" UI + backend e il piano è solido. Se NON funziona come da doc, lo scopriamo
spendendo 1 giorno invece di 1 settimana.

→ **Raccomandazione: partire dallo spike.** Decide tutto.

## 11. Vale la pena? (per la tua decisione)

**Pro:**
- È il differenziatore vero: chiude il loop "registra + naviga" sul polso, parità
  con Wikiloc/Komoot.
- Architettura provata, API documentate, riusa molta infrastruttura nostra.
- Reach: gira su tutti i 68 device già supportati.

**Contro / da pesare:**
- ~1-1.5 settimane di lavoro, gran parte sulla watch app (Monkey C, più lenta da
  iterare di Flutter).
- La mappa la dà comunque il sistema (come Wikiloc) → il nostro valore aggiunto è
  "i sentieri TrailShare + i rifugi", non la cartografia.
- Va mantenuto/aggiornato su 68 device.

**Confronto con le alternative:**
- *Fase 1 (fatta):* segui via Garmin Connect, trasferimento manuale. Costo zero.
- *Garmin Courses API:* trasferimento one-tap, ma serve partnership + non dà il
  browsing dal polso. Complementare, non alternativa.
- *Questa Fase 3:* l'unica che dà il "tutto dal polso" stile Wikiloc.

**Domanda di validazione da farsi:** quanti utenti hanno davvero un Garmin con mappa
E vogliono navigare sentieri TrailShare (vs. usare la nav nativa con un GPX caricato
una volta)? Se la connettività device è "indispensabile per gli sportivi" come da
strategia, questa è la mossa coerente — ma conviene dopo aver visto un minimo di
trazione sugli utenti Garmin.
