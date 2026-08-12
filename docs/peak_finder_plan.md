# Peak Finder — analisi dello stato attuale e piano di risalita

**Data**: 2026-08-12
**Moduli**: `lib/presentation/pages/mountain_finder/`, `lib/core/utils/viewshed_compute.dart`,
`lib/core/utils/mountain_projection.dart`, `lib/core/services/viewshed_service.dart`,
`lib/core/services/terrain_tile_service.dart`
**Obiettivo**: portare la funzione al livello dei migliori competitor (PeakFinder, PeakVisor,
PeakLens), coerente con il fatto che è venduta come feature Pro.

---

## 1. Sintesi in un paragrafo

La feature non è "poco rifinita": ha **quattro difetti strutturali** che si sommano e che
spiegano esattamente la sensazione di "impreciso e difficile da usare".

1. **Il puntamento è sbagliato in modo sistematico**, non casuale. Si legge il canale bussola
   sbagliato per un'app AR, su Android manca la correzione di declinazione magnetica
   (+3,5–4,5° nelle Alpi), il roll del telefono è del tutto ignorato e la proiezione
   angolo→pixel è lineare invece che prospettica. Sono errori che si accumulano fino a
   **~100 px di scostamento** su uno schermo da 1080 px.
2. **L'unico strumento di correzione dato all'utente è il FOV**, cioè una *scala*. Ma
   l'errore dominante è un *offset*. Con una manopola di scala non si corregge un offset:
   l'utente gira gli slider, non converge mai, e conclude che l'app non funziona.
3. **Il filtro viewshed è tarato per nascondere troppo.** Confronta ogni cima con lo skyline
   campionato a 1–2° di distanza angolare e pretende che sporga di 0,5° (= 436 m di stacco a
   50 km). Il risultato è che spariscono cime realmente visibili.
4. **Non funziona offline**, cioè non funziona dove si usa. Senza rete il DEM non arriva e la
   modalità degrada silenziosamente a "mostra tutte le cime", esattamente il comportamento che
   il viewshed doveva eliminare.

A monte di tutto c'è una scelta di impianto: oggi l'unica superficie è **l'overlay sulla
camera live**. I competitor migliori hanno fatto l'opposto — la superficie principale è il
**panorama disegnato dal DEM**, con la camera come sfondo opzionale. È quella scelta che rende
la feature usabile (e vendibile), e la sezione 5 spiega perché.

---

## 2. Cosa fanno i competitor (il metro di paragone)

| | **PeakFinder** (5 €) | **PeakVisor** (abbonamento) | **PeakLens** (free) | **TrailShare oggi** |
|---|---|---|---|---|
| Superficie principale | Panorama 3D disegnato, camera opzionale | Rilievo 3D texturizzato | Overlay su camera | Overlay su camera |
| Offline | Totale (mondo intero) | Mappe 3D offline | Sì | ❌ serve rete per il DEM |
| Allineamento | Drag manuale sul panorama | Drag manuale | **Automatico** (CV: match skyline reale↔DEM) | ❌ nessuno |
| Punto di vista virtuale | Ovunque sul pianeta | Ovunque | No | ❌ |
| Sole / luna | Traiettoria per data e ora | Sì | No | ❌ |
| Cerca "dov'è il monte X" | Sì, con freccia | Sì | No | ❌ |
| Dati escursionistici | No | Sentieri, peak bagging | No | ✅ **(non sfruttati)** |

Due letture importanti:

- **Nessuno si affida alla sola bussola.** Chi non fa computer vision (PeakFinder, PeakVisor)
  dà il trascinamento manuale. Non è un ripiego: il magnetometro di uno smartphone sbaglia
  regolarmente di 5–15° vicino a rocce ferrose, zaini con magneti, funivie, ferrate. Nessuna
  sensor fusion lo risolve. **Il drag manuale non è un extra, è il requisito minimo.**
- **L'unica colonna dove TrailShare parte avanti è l'ultima**, ed è completamente inutilizzata:
  sappiamo quali cime l'utente ha già conquistato, quali sentieri ci salgono, quali rifugi
  stanno intorno. Oggi la scheda cima mostra quota, distanza, bearing e un link a OSM — le
  stesse informazioni che ha chiunque.

---

## 3. Difetti verificati nel codice

### 3.1 Allineamento AR (la causa n°1 di "non ci si capisce niente")

**A. Si usa il canale bussola sbagliato.**
`mountain_finder_page.dart:256` legge `event.heading`. La documentazione di `flutter_compass`
è esplicita: `heading` è *"where the top of the device is pointing"*, mentre esiste
`headingForCameraMode` = *"where the back of the device is pointing"*. Per un overlay sulla
camera serve il secondo. Su iOS il plugin lo calcola dallo yaw di `CMDeviceMotion` (stabile e
fuso), mentre `heading` è `CLHeading.trueHeading` ruotato per l'orientamento **della UI** —
un valore pensato per disegnare una rosa dei venti, non per proiettare il mondo.
Su Android il plugin non popola affatto `headingForCameraMode` (resta 0.0) e ricava `heading`
da `TYPE_ROTATION_VECTOR` con un rimappaggio degli assi che **cambia di riferimento quando il
pitch supera ±45°** → discontinuità proprio nel gesto tipico (alzare il telefono verso la cima).
*Conseguenza*: il comportamento è diverso fra iOS e Android e degrada quando si inclina.

**B. Su Android manca la declinazione magnetica.**
`TYPE_ROTATION_VECTOR` è riferito al **nord magnetico**; `CLHeading.trueHeading` di iOS al
**nord geografico**. Nessuno dei due viene corretto lato app. Nelle Alpi la declinazione 2026
vale circa **+3,5–4,5° Est**: con FOV 60° su 1080 px sono **~72 px di traslazione costante** di
tutte le etichette, solo su Android. È l'errore che l'utente "vede" come "i nomi sono spostati
di un dito".

**C. Il roll è ignorato.**
`mountain_projection.dart:41-86` usa solo heading e pitch. Se il telefono è inclinato
lateralmente di 10° — cosa che capita sempre, a mano libera — il mondo ruota ma le etichette
no. Ai bordi dello schermo lo scostamento supera i 100 px.

**D. La proiezione è lineare, la camera è prospettica.**
`mountain_projection.dart:75-76`: `screenX = w/2 + (relBearing/hHalf)*(w/2)`. Una camera
rettilinea mappa `x ∝ tan(angolo)`, non l'angolo. L'errore è nullo al centro e ai bordi, e
**massimo a metà campo** — cioè dove si punta di solito:

| | errore orizzontale (FOV 60°) | errore verticale (FOV 80°) |
|---|---|---|
| a 10° dal centro | ~1,4 % della larghezza (≈15 px) | — |
| a 20° dal centro | ~1,8 % (≈20 px) | **~3,3 % dell'altezza (≈72 px)** |

Stessa radice nel calcolo dello zoom (`:818-819`, `:904-907`): si divide il FOV per il fattore
di zoom, ma la relazione corretta è `tan(FOV'/2) = tan(FOV/2)/zoom`. A 2× l'errore raddoppia.

**E. Il pitch viene da un accelerometro grezzo.**
`mountain_finder_page.dart:286-304` calcola il pitch da `sensors_plus` con un filtro passa-basso.
L'accelerometro da solo misura la gravità **più** l'accelerazione lineare: camminando o
semplicemente muovendo il braccio, il pitch sbanda. Il filtro passa-basso lo stabilizza ma
introduce ritardo — è il compromesso che l'`_adaptiveAlpha` cerca di gestire, ma il problema è
la sorgente, non il filtro. La soluzione è l'attitude già fusa dal sistema operativo
(gyro + accel + magnetometro), che entrambe le piattaforme espongono.

**F. La quota dell'osservatore è quella GPS.**
`:827`, `:843`, `:913` passano `pos.altitude`. L'altitudine GPS su Android sbaglia
tipicamente di 20–50 m; sono ~1° di errore verticale su una cima a 3 km, che sposta i pin
verticalmente. Il viewshed invece usa già (correttamente) la quota del DEM
(`viewshed_compute.dart:151`): **le due parti del sistema non concordano su dove sia l'utente.**

**G. La calibrazione offre la manopola sbagliata.**
`mountain_finder_calibration_page.dart` espone solo FOV H e FOV V, cioè due **scale**. Gli
errori A, B, C sono **offset e rotazioni**. Un utente che prova a compensare un offset di 4°
allargando il FOV allinea il centro e sballa i bordi, o viceversa: non converge mai. Questo,
da solo, spiega "è difficile da usare".

### 3.2 Precisione del viewshed

**H. Confronto con lo skyline quantizzato per settori.**
`viewshed_compute.dart:190` sceglie il raggio dello skyline con
`azIdx = round(az / (360/steps))`. Free usa 180 step (**2° per settore**), Pro 360 (**1°**).
La cima viene giudicata contro il profilo di un raggio che può passare **700 m di lato a 20 km,
1,7 km a 100 km**. Su un crinale articolato è un raggio completamente diverso.
*Il rimedio corretto è banale*: fare il ray-march **direttamente lungo la linea di vista verso
ogni cima**. Con 200 cime × 400 passi sono 80.000 lookup — millisecondi. Lo skyline resta utile
solo per disegnare l'orizzonte, non per decidere la visibilità.

**I. Margine di visibilità troppo severo.**
`visibilityMarginDeg` vale 0.5 e non viene mai sovrascritto dai tier. Mezzo grado significa
**175 m di stacco richiesti a 20 km, 436 m a 50 km**. Sommato al fatto che lo skyline è il
**massimo** lungo tutto il raggio (stima per eccesso), il filtro è **sbilanciato verso il
nascondere**: spariscono cime che nella realtà si vedono benissimo. È la spiegazione più
diretta del "riconoscimento scarso".

**J. Passo del raggio più grosso della cella DEM.**
`rayStepMeters = 250` con DEM a zoom 10 = **~107 m/pixel** a 45°N. Si campiona un terreno con
passo 2,3× la sua risoluzione: le creste sottili vengono scavalcate senza vederle (falsi
positivi). Peggio: il primo campione è a 250 m, quindi **un dosso a 100 m davanti all'utente è
invisibile all'algoritmo** — ed è proprio il campo vicino a determinare la maggior parte delle
occlusioni reali.

**K. I buchi del DEM valgono 0 m sul livello del mare.**
`terrain_tile_service.dart` (`_mosaic`) alloca `Float32List(rows*cols)` — quindi zeri — e
riempie solo le celle coperte da un tile effettivamente scaricato. Se un tile fallisce (rete
lenta, 404), resta un buco a quota 0 che `elevationAt` restituisce come quota valida: **si vede
attraverso la montagna**. I tile mancanti vanno marcati NaN, e la bbox del mosaico va calcolata
sulla richiesta, non sui tile riusciti (oggi `_mosaic(fetched)` restringe la griglia in
silenzio, e in caso estremo può non contenere nemmeno l'osservatore → `eyeElev` = NaN → zero
cime visibili → fallback muto a "mostra tutto").

**L. Le vette non vengono agganciate al DEM.**
La quota della cima arriva da OSM, quella del terreno dal DEM a 107 m: il pixel che contiene la
vetta è quasi sempre più basso della vetta reale (media di un'area di 107×107 m). Nel calcolo
dello skyline la cima "affonda" sotto il proprio crinale e può risultare occlusa da se stessa.
Serve un max locale 3×3 attorno alla vetta.

**M. Il mosaico butta via il 30% del dettaglio verticale.**
Sempre in `_mosaic`: il passo delle righe è calcolato con la spaziatura in gradi della
*longitudine* (`px = lngRangePerTile/width`). A 45,5°N una cella risulta 152 m in latitudine
contro i 108 m nativi del tile → si sottocampiona di 1,4× una direzione sola.

### 3.3 Prestazioni e freschezza

**N. Il viewshed si aggiorna ogni 5 km, non ogni 500 m.**
`_recomputeViewshedIfNeeded` (`:554`) ha la regola dei 500 m, ma il suo **unico chiamante nel
flusso live** è `_refreshCandidatePeaksIfNeeded` (`:493`), che esce prima se lo spostamento è
`< _candidateRefreshThresholdMeters = 5000` (`:503`). La logica dei 500 m — e il commit
`075abc6` "auto-refresh on-move solo per tier Pro" — sono **codice morto in pratica**.
In cresta l'occlusione cambia radicalmente in 300 m: l'utente vede una lista stantia.

**O. Il DEM Pro costa decine di MB e viene copiato fra isolate.**
Con raggio 100 km: bbox 200×200 km → **64 tile** scaricati, **64 spawn di isolate** per il
decode PNG (uno per tile, via `compute`), mosaico da **~3 milioni di celle**. Poi
`elevations: out.toList(growable: false)` converte la `Float32List` in una **`List<double>`**
(~20–24 byte per elemento → **50–70 MB**) che `compute(computeViewshed, request)` **copia
integralmente** oltre il confine dell'isolate. Il target dichiarato di "cime visibili entro 2 s"
non è raggiungibile così. Rimedi: `Float32List` end-to-end + `TransferableTypedData`
(zero-copy), un solo isolate persistente per i decode, e DEM **multi-risoluzione** (z12–13 nel
raggio vicino dove serve, z9–10 lontano dove non serve).

**P. Nessuna cache offline reale.**
La cache Hive su disco (`enableDiskCache`) è solo Pro e si popola **solo dopo** che l'utente ha
già scaricato i tile online. Al primo utilizzo in quota, senza campo, non c'è niente. La memoria
di progetto lo annota già come limite noto — ma è il limite che uccide la feature: **si paga per
qualcosa che non funziona dove serve**.

### 3.4 Prodotto: cosa manca del tutto

- **Lo skyline è già calcolato e viene buttato via.** `ViewshedResult.skylineAngles`
  (`viewshed_compute.dart:117`) contiene il profilo dell'orizzonte a 360°;
  `viewshed_service.dart` legge solo `result.peaks`. È il pezzo più prezioso ed è a costo zero.
- Nessun **panorama / punto di vista virtuale** ("cosa vedrò dalla vetta X?"). Oggi la feature
  si può valutare solo stando su una cima: pessimo per la conversione, perché il momento in cui
  si paga è sul divano.
- Nessuna **traiettoria di sole e luna** (feature di punta per i fotografi).
- Nessuna ricerca **"dov'è il Monte X"** con freccia di puntamento.
- Nessun aggancio ai **dati TrailShare**: conquistate, sentieri per la vetta, rifugi vicini.
- **Dataset limitato**: `peaks_italy.json`, 37.209 cime, bbox lat 35,55–47,20 / lng 6,00–17,16.
  Dalle Alpi occidentali e dal confine nord si vedono regolarmente cime **fuori da questo
  riquadro** (Vallese oltre 47,2°N, Delfinato oltre 6°E), che quindi non compaiono mai.
  Nessun dato di **prominenza**: il decluttering delle etichette (`:401-467`) ordina per quota
  assoluta, quindi una vetta secondaria di un massiccio vicino batte una cima iconica lontana.

---

## 4. Piano

Ordinato per rapporto valore/costo. Le fasi 0–2 sono quelle che cambiano il giudizio
dell'utente; le 3–5 sono quelle che giustificano il prezzo.

### Fase 0 — Raddrizzare il puntamento (3–5 giorni)

L'obiettivo non è "migliorare un po'", è **azzerare gli errori sistematici** in modo che la
correzione manuale della Fase 2 debba compensare solo il rumore residuo.

| # | Intervento | File |
|---|---|---|
| 0.1 | Sorgente unica di orientamento: attitude fusa dell'OS (quaternione → yaw/pitch/roll della direzione **camera**), al posto di `flutter_compass` + accelerometro separati | nuovo `core/services/device_attitude_service.dart` |
| 0.2 | Declinazione magnetica applicata quando la sorgente è magnetica (tabella su griglia 1° per l'arco alpino + Italia, <5 KB, interpolata) | nuovo `core/utils/magnetic_declination.dart` |
| 0.3 | Roll nella proiezione: ruotare le coordinate schermo attorno al centro | `mountain_projection.dart` |
| 0.4 | Proiezione rettilinea `tan()` + zoom corretto `tan(FOV'/2)=tan(FOV/2)/zoom` | `mountain_projection.dart:75-76`, `mountain_finder_page.dart:818,904` |
| 0.5 | Quota osservatore dal DEM (fallback GPS), condivisa fra AR e viewshed | `mountain_finder_page.dart:827,843,913` |
| 0.6 | Viewshed davvero ogni 500 m: scollegare il trigger dalla soglia dei 5 km delle candidate | `mountain_finder_page.dart:493-551` |
| 0.7 | Buchi DEM = NaN, bbox del mosaico = bbox richiesta, e stato d'errore **visibile** invece del fallback muto a "tutte le cime" | `terrain_tile_service.dart`, `mountain_finder_page.dart:615` |

**Criterio di accettazione**: su tre cime note a distanza diversa (2 km, 15 km, 50 km),
l'etichetta cade entro **1° dalla vetta reale** con telefono fermo su treppiede, su iOS e su
Android, senza toccare la calibrazione.

**Nota su 0.1**: `flutter_compass` non basta (su Android non popola `headingForCameraMode`).
Le opzioni sono un package di attitude assoluta o ~40 righe di platform channel per lato
(Android `TYPE_ROTATION_VECTOR` → matrice → vettore camera; iOS `CMDeviceMotion.attitude` con
riferimento `xTrueNorthZVertical`, che dà **direttamente il nord geografico** e risolve anche
0.2 su iOS). Consiglio il platform channel: è poco codice, senza dipendenze nuove, e ci lascia
il controllo del riferimento nord — che è esattamente la cosa che oggi ci sfugge.

### Fase 1 — Rendere onesto il viewshed (3–4 giorni)

| # | Intervento | Effetto |
|---|---|---|
| 1.1 | Ray-march **diretto verso ogni cima** al posto del confronto con lo skyline per settori | elimina falsi positivi e negativi da quantizzazione |
| 1.2 | Margine: da 0,5° fisso a **soglia in metri di stacco** (es. 15–25 m) più realistica alle lunghe distanze; margine grande solo entro pochi km | fa riapparire le cime che si vedono davvero |
| 1.3 | Passo del raggio ≤ risoluzione DEM, con **passo crescente** con la distanza (25 m nei primi 2 km, 100 m oltre) | cattura le occlusioni del campo vicino |
| 1.4 | DEM multi-risoluzione: z13 entro 5 km, z11 entro 25 km, z9 oltre | più preciso **e** più leggero di oggi |
| 1.5 | Snap della vetta al max locale 3×3 del DEM | niente più cime che occludono se stesse |
| 1.6 | `Float32List` + `TransferableTypedData` end-to-end, isolate di decode riutilizzato | dai secondi ai millisecondi, senza picchi di RAM |
| 1.7 | Mosaico: passo righe con la spaziatura nativa in latitudine | recupera il 30% di dettaglio verticale |

**Criterio di accettazione**: da un punto di test noto (es. Grigna, Resegone, Presolana), la
lista delle cime visibili coincide con il panorama reale — **zero cime dietro un crinale**,
**zero cime mancanti** fra quelle riconoscibili a occhio. Compute < 500 ms a 50 km su Android
mid-range. Test unitari con DEM sintetici (muro, valle, cresta obliqua) accanto a
`test/core/utils/viewshed_compute_test.dart`.

### Fase 2 — Allineamento assistito: **la fase che cambia il giudizio** (5–7 giorni)

Anche con la Fase 0 perfetta, un magnetometro disturbato sbaglia. Qui si dà all'utente il
controllo, come fanno tutti i competitor.

| # | Intervento |
|---|---|
| 2.1 | **Overlay dello skyline**: disegnare il profilo dell'orizzonte calcolato dal DEM sopra la camera. È già calcolato e buttato via (`skylineAngles`). Diventa il riferimento visivo che oggi manca completamente |
| 2.2 | **Drag-to-align**: si trascina l'overlay finché il profilo disegnato combacia con le montagne vere. Salva l'offset (bearing + pitch), con decadimento temporale e reset a un tap |
| 2.3 | Indicatore di **accuratezza bussola** (`CompassEvent.accuracy`, oggi ignorato) + prompt "muovi il telefono a otto" quando è inaffidabile |
| 2.4 | FOV **letto dall'hardware** (iOS `AVCaptureDevice.activeFormat.videoFieldOfView`, Android `CameraCharacteristics` focale+sensore) invece che calibrato a mano; gli slider restano come regolazione fine per chi vuole |
| 2.5 | Etichette ordinate per **prominenza**, non per quota assoluta (vedi Fase 4.4) |

**Criterio di accettazione**: un utente che apre la funzione con la bussola sfasata di 10° la
riallinea in **meno di 5 secondi** senza istruzioni, e l'allineamento regge per tutta la sessione.

### Fase 3 — Offline (5–7 giorni)

Senza questa fase la feature non è vendibile: chi paga la usa in quota, dove non c'è campo.

- 3.1 **Pacchetti DEM regionali** scaricabili (Alpi Occidentali / Centrali / Orientali,
  Appennino Settentrionale / Centrale / Meridionale, Sicilia-Sardegna). A z11 un pacchetto
  alpino sta in **~15–25 MB** in Float16 compresso — accettabile, e si scarica una volta sola.
- 3.2 **Pre-cache automatica** attorno al percorso quando si scarica una traccia offline: chi
  scarica il sentiero ha già il terreno per il Peak Finder quando arriva in cima.
- 3.3 Stato esplicito in HUD: "terreno disponibile offline / solo online / non disponibile",
  al posto del degrado silenzioso di oggi.

### Fase 4 — Differenziazione (7–10 giorni, incrementale)

- 4.1 **Panorama mode / punto di vista virtuale**: renderizzare il profilo del terreno a 360°
  senza camera, da una posizione qualsiasi. Sblocca "cosa vedrò dalla vetta X?" — usabile dal
  divano, quindi **valutabile prima di pagare**. È il riuso diretto del motore della Fase 2.1
  con osservatore arbitrario.
- 4.2 **Sole e luna**: traiettoria per data/ora sopra il profilo. Alba/tramonto dietro quale
  cima. Costo basso (formule astronomiche standard), valore percepito alto.
- 4.3 **"Dov'è il Monte X"**: ricerca nel dataset + freccia che guida il puntamento.
- 4.4 **Prominenza nel dataset**: calcolata offline dal DEM una volta sola e imbustata nel JSON.
  Migliora il decluttering, l'ordinamento e permette un filtro "solo cime importanti".
- 4.5 **Dati TrailShare nella scheda cima** — il differenziale che nessun competitor può copiare:
  «l'hai conquistata il 12/07/2024», «3 sentieri salgono in vetta», «Rifugio X a 40 min»,
  «12 foto della community da questa vetta».
- 4.6 **Estensione del dataset** oltre la bbox italiana: Vallese, Delfinato, Tirolo, Carinzia,
  Slovenia. Si aggancia al lavoro già fatto su `GeoRegions`/espansione Alpi.

### Fase 5 — Auto-allineamento visivo (opzionale, 2–3 settimane)

Il salto che farebbe di TrailShare il migliore e non "uno dei buoni": estrarre lo skyline
dall'immagine della camera e correlarlo con quello calcolato dal DEM, correggendo l'offset da
solo — l'approccio di PeakLens. Fattibile senza rete neurale (edge detection sulla banda
dell'orizzonte + cross-correlazione 1D con il profilo DEM) perché sappiamo già quale profilo
cercare. **Da valutare solo dopo che le fasi 0–3 sono in produzione e misurate.**

---

## 5. La raccomandazione strategica

**Spostare il baricentro dalla camera al panorama disegnato.**

Oggi l'unica superficie è l'overlay sulla camera live. Ha tre problemi che nessuna correzione
tecnica elimina: si può usare solo in quota, solo con bel tempo, solo di giorno — e non offre
alcun riferimento visivo per capire se l'allineamento è giusto o sbagliato.

PeakFinder ha fatto la scelta opposta e non a caso: la superficie principale è il **panorama
disegnato dal DEM**, con la camera come sfondo opzionale. Ne conseguono tre cose:

1. L'utente **vede** se il disegno combacia con la realtà → l'allineamento diventa
   auto-evidente e correggibile (è la Fase 2).
2. La funzione si usa **anche nella nebbia, di notte, e da casa** → si può provare prima di
   comprare, cosa oggi impossibile.
3. Sblocca il punto di vista virtuale e sole/luna **senza altro lavoro di motore**.

Le fasi 2.1 + 4.1 sono esattamente questo spostamento, e sono economiche perché il calcolo
dello skyline **c'è già**: viene prodotto a ogni run e scartato.

---

## 6. Sequenza consigliata

| Sprint | Contenuto | Giorni | Cosa cambia per l'utente |
|---|---|---|---|
| **1** | Fase 0 completa | 3–5 | Le etichette stanno sulle cime |
| **2** | Fase 1 completa | 3–4 | Le cime mostrate sono quelle che si vedono |
| **3** | Fase 2 (2.1 → 2.4) | 5–7 | Quando sbaglia, si corregge in 3 secondi |
| **4** | Fase 3 | 5–7 | Funziona senza campo |
| **5+** | Fase 4 a incrementi | 7–10 | Diventa un motivo per pagare |

Totale per arrivare "al livello dei migliori": **circa 4–6 settimane** di lavoro effettivo,
di cui le prime due settimane (sprint 1–2) risolvono da sole la lamentela di partenza.

---

## 7. Stato: Sprint 1 (Fase 0) — fatto

Tutti e sette gli interventi della Fase 0 sono implementati. `flutter analyze`
pulito, 25 test unitari nuovi/aggiornati verdi, build Android e iOS compilano.

| # | Intervento | Dove |
|---|---|---|
| 0.1 | Sorgente unica di orientamento dalla sensor fusion nativa | `core/services/device_attitude_service.dart`, `DeviceAttitudeChannel.kt`, `AppDelegate.swift` |
| 0.2 | Declinazione magnetica (Android `GeomagneticField`, iOS `xTrueNorthZVertical`) | come sopra |
| 0.3 | Roll nella proiezione | `core/utils/camera_orientation.dart` |
| 0.4 | Proiezione rettilinea + zoom per tangente | `core/utils/camera_orientation.dart`, `mountain_projection.dart` |
| 0.5 | Quota osservatore dal DEM | `terrain_tile_service.groundElevationAt`, pagine AR |
| 0.6 | Viewshed ogni 500 m | `mountain_finder_page.dart` |
| 0.7 | Buchi DEM = NaN, bbox richiesta, stato visibile | `terrain_tile_service.dart`, `viewshed_service.dart`, `viewshed_compute.dart` |

### Scelte di impianto

**L'orientamento non è più una coppia di angoli ma una terna di versori.**
Heading e pitch separati non sanno rappresentare il roll, e la proiezione va
fuori posto appena il telefono non è in bolla. Con la terna la proiezione è
quella vera di una fotocamera — cambio di base più divisione prospettica — e
azimut, pitch, roll e curvatura terrestre entrano tutti insieme, senza casi
particolari. Il codice è puro e sta sotto test con angoli noti, invece che
verificabile solo puntando il telefono verso una montagna.

**La convenzione della matrice iOS si deduce a runtime.** Apple non documenta
se `CMAttitude.rotationMatrix` mappa corpo→riferimento o il contrario, e le due
letture sono l'una la trasposta dell'altra: sbagliare significa etichette
completamente fuori posto. Invece di scommettere, `AppDelegate.swift` confronta
le due candidate con `gravity` (che è espressa nel sistema del device, quindi
non ambigua) e tiene quella che coincide. La decisione si prende una volta sola,
e solo quando il telefono è abbastanza inclinato da rendere le due distinguibili.

**"Non so" non è "non c'è".** Il passaggio dei buchi DEM da 0 m a NaN, da solo,
non risolveva il problema: saltare un campione sconosciuto abbassa lo skyline
esattamente come leggerlo a livello del mare, e la cima dietro risulta visibile
in entrambi i casi. È emerso scrivendo il test. Ora il calcolo tiene traccia
della distanza del primo campione ignoto su ogni raggio, e una cima dichiarata
visibile con terreno sconosciuto *davanti* a lei viene marcata `uncertain`: la
mostriamo — non possiamo dimostrare che sia nascosta — ma l'interfaccia lo dice,
invece di spacciare per certezza quello che è un vuoto di dati.

### Prova sul campo, 2026-08-12 (Motorola edge 60 pro, release, Valtellina)

Confermato dai log del telefono:

| | Esito |
|---|---|
| Sorgente orientamento | `nativa` — la sensor fusion risponde, niente ripiego |
| Nord | `geografico` — **declinazione 4,06° applicata**: era l'errore sistematico, ~73 px a FOV 60° |
| Bussola | `±5°` (accuratezza alta) |
| Roll | riportato e usato (era proprio assente dal modello) |
| Allineamento verticale | **corretto** — quota DEM + curvatura + proiezione verticale funzionano |
| Viewshed | 23 cime su 200 candidate, `status=ok`, 722 ms con cache calda |
| Allineamento orizzontale | **residuo di alcuni gradi**, causa da isolare (bias magnetometro vs FOV non calibrato) |

Due difetti emersi dall'esecuzione reale, invisibili leggendo il codice:

- **Il tetto delle 200 candidate.** `PeaksDatasetService.findWithinRadius` tiene le
  200 cime **più vicine**: in un raggio di 60 km sulle Alpi scarta le montagne
  lontane a favore dei dossi vicini, cioè il contrario di quello che si cerca
  guardando un panorama. Peggio: il viewshed Pro gira con raggio 100 km ma riceve
  solo candidate entro 60 km, quindi **il raggio pieno del tier Pro non esiste**.
  Da correggere in Fase 1 ordinando per importanza invece che per vicinanza.
- **Doppio calcolo del viewshed** — visto nei log come due `[Viewshed] start`
  identici in fila, con il tempo raddoppiato da 722 a 1547 ms. Vedi sotto.

### Revisione avversariale, 2026-08-12 (63 agenti, 5 lenti, doppia verifica)

Dieci difetti confermati. Il più grave non era nello Sprint 1 ma sotto di esso, ed
è stato trovato indipendentemente da due lenti diverse e poi verificato con uno
script numerico:

**Il DEM veniva riletto specchiato nord-sud.** `_mosaic` riempiva la griglia con
riga 0 = nord, `DemGrid.elevationAt` la leggeva con riga 0 = sud. Verifica su
terreno sintetico crescente verso nord: a lat 45,95 la quota vera è 950 m, quella
letta 55 m. **Il viewshed guardava verso nord e trovava il terreno che sta a sud**:
dichiarava visibili le cime dietro un crinale e occlusi i panorami aperti — cioè
produceva sistematicamente l'insieme sbagliato, che è il cuore della funzione.

Perché non se n'era accorto nessuno: l'osservatore sta al **centro** della bbox,
cioè sull'asse dello specchio, dove la quota risulta corretta. Tutti i controlli
"la mia quota è giusta" passavano. E i test costruiscono `DemGrid` a mano senza
passare dal mosaico, quindi non potevano vederlo.

Rimedio: la griglia si costruisce prima e si riempie attraverso i suoi stessi
`latForRow`/`lngForCol`, così le due parti non possono più divergere; più tre test
che bloccano la convenzione. Lo stesso difetto colpiva `ElevationDemCorrector`
(profili altimetrici corretti con le quote del capo opposto della bbox).

Altri difetti confermati e corretti:

| Gravità | Difetto |
|---|---|
| alta | Il guard `_computingViewshed` stava **prima** di un `await`: durante il controllo admin su Firestore ogni fix GPS lo superava e lanciava un calcolo parallelo. Osservato dal vivo |
| alta | Un `return` per `!mounted` lasciava il flag alzato per sempre → nessun ricalcolo successivo. Ora `finally` |
| alta | Posizione non consumata sui fallimenti → retry a ogni fix GPS (5 m): tempesta di richieste offline. Ora backoff 30 s |
| alta | Due scrittori della quota osservatore a zoom diversi (z12 e z10) si sovrascrivevano → pin che saltano in verticale a ogni ricalcolo |
| media | "Zero cime visibili" con `status=ok` disattivava il filtro in silenzio mostrando **tutte** le cime, icona del filtro accesa e nessun avviso |
| bassa | Il messaggio del terreno lacunoso diceva "mostro tutte le cime" mentre il filtro era invece applicato |
| media | AR lock premuto prima del primo campione di assetto azzerava l'AR fino allo sblocco |

### Misura conclusiva sul campo — l'errore residuo è ambientale

Foto AR con il campanile come riferimento fisso, e tre cime note nel fotogramma.
Ricavando da ciascuna quale azimut della camera la giustificherebbe:

```
Cima Vaccaro    (bordo sinistro, −22°)  →  A = 253,2°
Anticima Secco  (centro)                →  A = 254,4°
Monte Secco     (centro)                →  A = 254,8°
```

I tre valori stanno dentro **1,6°** su un campo di 80°. Se il FOV fosse
sbagliato divergerebbero molto, perché Vaccaro sta a 22° dal centro e una scala
errata si amplifica ai bordi: **non è un problema di scala**. Anche l'ordine
delle cime e la loro spaziatura (3,2° fra Anticima e Monte Secco) coincidono con
la realtà: proiezione, dataset, roll, quota e FOV fanno il loro lavoro.

Il campanile dà la verità assoluta: l'app crede di puntare a 254,4°, la realtà è
243,0° → **offset puro di 11,4°**. Ma la foto è scattata **dentro casa, dietro un
vetro, con il telaio metallico nell'inquadratura**: per un magnetometro è
l'ambiente peggiore. All'aperto, sulla stessa uscita, l'errore misurato verso
Cima del Fop era **1,7°**.

Conclusione: **il residuo è ambientale, non di codice**, e si annulla con il
trascinamento manuale — verificato dal founder («con la correzione manuale arrivo
alla perfezione»). È la conferma sperimentale del perché tutti i concorrenti seri
hanno quella manopola: nessuna fusione di sensori corregge un campo magnetico
locale falsato.

Due conseguenze recepite subito:

- **Il flag di accuratezza di Android non è affidabile**: dichiarava `±5°`
  mentre l'errore reale era 11°. Non ci si può appoggiare per avvisare l'utente;
  il segnale onesto è quanto offset manuale serve.
- **Una correzione manuale persistente è una trappola.** Tarata in casa vale
  −11°, all'aperto diventa essa stessa un errore di 11° nell'altro verso, con
  l'utente convinto di aver già allineato. Ora scade da sola dopo 1 km
  (`alignValidityMeters`) e il pulsante resta acceso finché una correzione è
  attiva.

### Da verificare sul campo (non verificabile in simulatore)

Tre cose dipendono da sensori reali e vanno controllate su un telefono vero.
Sono tutte a un parametro di distanza dalla correzione, se qualcosa non torna:

1. **Allineamento su iOS e su Android** puntando una cima nota a distanze
   diverse (2 km, 15 km, 50 km), telefono fermo. Atteso: etichetta entro ~1°
   dalla vetta reale, senza toccare la calibrazione. Se su iOS l'errore fosse
   grande e sistematico, il sospetto numero uno è la deduzione della convenzione
   della matrice: il log di `resolveConvention` dice quale ha scelto.
2. **Landscape**: ruotando il telefono le etichette devono restare sulle cime,
   e i due versi di rotazione devono comportarsi in modo speculare. Se si
   muovessero al contrario, si scambiano le righe 90 e 270 nella tabella di
   `CameraBasis.fromDeviceToEnu` — è l'unico grado di libertà rimasto.
3. **Roll**: inclinando il telefono di lato le etichette devono ruotare con il
   mondo, non restare orizzontali.

---

## 8. Domande aperte (decisione del founder)

1. **Packaging.** Oggi il viewshed è attivo per tutti con limiti Free e l'unica cosa davvero
   Pro è lo scatto della foto annotata (`mountain_finder_page.dart:730`). Se la funzione deve
   *sembrare* premium, la linea va ridisegnata. Proposta: **Free** = riconoscimento a 20 km,
   online, con drag-to-align; **Pro** = raggio pieno, pacchetti offline, panorama/punto di vista
   virtuale, sole e luna, foto annotata.
2. **Fase 5 sì o no.** L'auto-allineamento visivo è l'unico modo per battere PeakFinder invece
   di pareggiarlo, ma costa quanto le fasi 0–2 insieme. Da decidere dopo aver misurato l'uso
   reale post-Fase 3.
3. **Estensione geografica** (4.6): fermarsi all'arco alpino o coprire tutta l'Europa? Incide
   sulla dimensione del dataset e sui pacchetti offline.
4. **Priorità rispetto al resto della roadmap.** Le 4–6 settimane vanno collocate rispetto a
   Stripe/B2B, che al momento risultano prioritari.
