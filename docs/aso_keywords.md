# Parole chiave negli store

Misurato il 2026-08-01 interrogando l'API di ricerca App Store (`country=it`,
200 risultati per termine) e cercando la posizione di TrailShare (`6751456265`).
Numeri veri, non stime: rifacibili in qualunque momento con
`scripts/aso_rank.py`.

## Il campo keyword di Apple, com'era

```
escursioni,trekking,mtb,sentieri,montagna,rifugi,gps,offline,outdoor,cammino,traccia,bici,wikiloc
```

97 caratteri su 100. **Otto parole su tredici non producono niente**, e tre di
quelle otto puntano a un pubblico che non è il nostro.

| Parola | Posizione | Chi occupa i primi posti |
|---|---|---|
| `wikiloc` | **10°** su 25 | Wikiloc, komoot, AllTrails |
| `rifugi` | **12°** su 133 | Rifugi e Bivacchi, Rifugi di Lombardia, PeakVisor |
| `sentieri` | 47° su 151 | komoot, Wikiloc, Mapy.com |
| `trekking` | 90° su 178 | komoot, Wikiloc, AllTrails |
| `cammino` | 158° su 175 | app del Cammino di Santiago |
| `escursioni` | fuori | komoot, Wikiloc, AllTrails |
| `montagna` | fuori | komoot, PeakVisor |
| `outdoor` | fuori | Outdooractive, Decathlon |
| `gps` | fuori | Google Maps, Waze |
| `mtb` | fuori | **videogiochi di bici** (Bike 3D, Shred!, Bike Unchained) |
| `bici` | fuori | Strava, poi videogiochi BMX |
| `offline` | fuori | **giochi offline** (Subway Surfers, Block Blast) |
| `traccia` | fuori | **tracciamento pacchi** (17TRACK, Traccia Pacchi) |

Le ultime quattro righe sono il problema più serio. `offline`, `traccia`, `mtb`
e `bici` non sono parole difficili: sono parole che in italiano, sull'App
Store, significano un'altra cosa. Chi cerca "traccia" vuole sapere dov'è il suo
pacco.

**E due parole erano già indicizzate altrove.** Il nome dell'app è
`TrailShare — Sentieri GPS`: Apple indicizza nome e sottotitolo separatamente,
quindi `sentieri` e `gps` nel campo keyword erano 13 caratteri comprati due
volte.

## Dove il campo è sottile

La domanda non è "quanto si cerca" ma "quanti competono". Il conteggio dei
risultati lo dice da solo:

| Parola | App totali | Chi c'è |
|---|---|---|
| `bivacchi` | **2** | Wildhood, Rifugi e Bivacchi |
| `malghe` | **2** | Sentres, Asiago |
| `ciaspole` | **4** | Cuneotrekking, MowiSnow, Orobie Active |
| `orobie` | **5** | Orobie Active, orobie, Passaporto delle Orobie |
| `bivacco` | 7 | Wildhood, Refuge, un bar |
| `alpinismo` | 40 | K2 Story, CAI Adventure, Whympr |

Su `bivacchi` esistono **due** app al mondo. Non è un termine da conquistare, è
un termine da occupare. E il dataset POI bundlato i bivacchi ce li ha già.

Stessa logica su `rifugi`: primi tre posti a *Rifugi e Bivacchi*, *Rifugi di
Lombardia* e PeakVisor — app piccole. È l'unico campo dove i giganti non sono
in testa, e non a caso è l'unico dove siamo già dodicesimi.

## Due trappole trovate misurando

1. **`rifugio` singolare non è `rifugi` plurale.** Al singolare i primi
   risultati sono *Pet World Rifugio per animali* e *The Walking Dead*: in
   italiano "rifugio" da solo vuol dire canile. Vale il plurale, mai il
   singolare.
2. **`cai` è Character AI.** Il Club Alpino Italiano non compare nemmeno:
   i primi tre sono chatbot. Da non usare mai.

## I tre campi vanno progettati insieme

Apple indicizza **nome, sottotitolo e keyword** come un unico spazio da 160
caratteri, e **non conta due volte la stessa parola**. Una parola nel nome è
sprecata nel campo keyword, e viceversa. Il primo nome, `TrailShare — Sentieri
GPS`, rendeva ridondanti `sentieri` e `gps`; il primo sottotitolo,
`Tracking GPS · Mappe · Rifugi`, ripeteva `rifugi` già presente nel nome nuovo.

| Campo | Testo | Parole che porta |
|---|---|---|
| Nome (29/30) | `TrailShare: Sentieri e Rifugi` | trailshare, sentieri, **rifugi** |
| Sottotitolo (30/30) | `Mappe offline · Bivacchi · GPS` | mappe, **offline**, **bivacchi**, gps |
| Keyword (99/100) | vedi sotto | dodici termini di nicchia |

Venti termini distinti, zero doppioni. Il sottotitolo è dove è cambiato di più.

`Rifugi` usciva perché il nome lo copre già. `Tracking` usciva per un motivo
peggiore, che è saltato fuori misurandolo: in Italia `tracking` restituisce
**17TRACK, AfterShip e Parcel**, cioè di nuovo il tracciamento pacchi, e
`tracking gps` porta a Tractive — i localizzatori per cani e gatti. Non era
una parola sprecata: era una parola che ci accostava al settore sbagliato.

Al loro posto `offline` e `bivacchi`: il differenziatore vero, e un termine con
due sole app in classifica.

## Il campo keyword (99 caratteri)

```
malghe,ciaspole,orobie,ferrate,alpinismo,alpini,montagna,trekking,wikiloc,komoot,appennino,dolomiti
```

`rifugi` e `bivacchi` sono usciti da qui perché ora stanno in nome e
sottotitolo: i 16 caratteri liberati sono andati su `appennino` (22 app in
classifica, e i primi tre sono app di sentieri) e `dolomiti`.

Scartato `baite`: al plurale la classifica è inquinata dall'inglese *bait* —
Brain Baits, Bait Car — e passa da 9 app a 104.

<details>
<summary>La versione precedente, prima che il nome cambiasse</summary>

```
rifugi,bivacchi,malghe,ciaspole,orobie,ferrate,alpinismo,alpini,montagna,trekking,wikiloc,komoot
```
</details>

Il criterio: **spendere i caratteri dove il campo è vuoto**, non dove il volume
è alto ma davanti ci sono komoot e Wikiloc con ventimila recensioni contro la
nostra.

- `malghe` `ciaspole` — la nicchia misurata, con contenuto vero dietro (due e
  quattro app in classifica); `rifugi` e `bivacchi` stanno ormai nel nome e nel
  sottotitolo
- `orobie` — cinque app in tutto, ed è dove il ground game coi QR sta partendo
- `ferrate` — le 323 vie attrezzate del catalogo, messe in sicurezza a luglio
- `alpinismo` — quaranta app, tutte piccole
- `alpini` `montagna` — non rendono da sole, ma Apple **combina** le keyword fra
  loro e col nome: danno "rifugi alpini", "rifugi montagna", "sentieri montagna"
- `trekking` — la sola parola generica che si tiene, perché è la categoria e
  novantesimi è comunque meglio di assenti
- `wikiloc` `komoot` — vedi il rischio qui sotto

- `appennino` `dolomiti` — i due sistemi montuosi principali, entrambi con
  contenuto nel catalogo; su `appennino` competono ventidue app e le prime tre
  sono di sentieri

Resta 1 carattere libero.

**Il rischio da sapere, non da nascondere.** I nomi dei concorrenti nei
metadati sono contro le linee guida App Store (marchi di terzi). `wikiloc` è
già lì da mesi ed è passato in revisione più volte, ed è la keyword che rende
di più — decimi. Aggiungere `komoot` segue la stessa logica ma alza di un poco
la probabilità che un revisore lo noti. Se un giorno arriva un rifiuto sui
metadati, si tolgono entrambe e si ricompila: costa un ciclo di revisione, non
di più.

## Play Console non ha un campo keyword

Google indicizza **titolo (30), descrizione breve (80) e descrizione lunga
(4000)**. Le stesse parole vanno fatte entrare nel testo, scritte in frasi
vere: il keyword stuffing su Play è penalizzato, su Apple no perché il campo è
nascosto. Da fare separatamente, non è un copia-incolla di questa riga.

## Altro da ottimizzare, in ordine di valore

### 1. La categoria: siamo gli unici senza Navigazione né Viaggi

Misurato il 2026-08-01 sulle sette app tracciate:

| App | Primaria | Secondaria | Recensioni |
|---|---|---|---|
| **TrailShare** | Salute e benessere | **Sport** | 1 |
| komoot | Salute e benessere | Navigazione | 30.761 |
| Wikiloc | Navigazione | Sport | 21.215 |
| AllTrails | Salute e benessere | Viaggi | 1.913 |
| Outdooractive | Viaggi | Navigazione | 2.900 |
| PeakVisor | Sport | Navigazione | 15.504 |
| Terra Map | Navigazione | Viaggi | 7.031 |

**Sei su sei hanno Navigazione o Viaggi in uno dei due slot. Noi nessuno dei
due.** Non è una convenzione estetica: le classifiche di categoria sono liste
separate, e Salute e benessere in Italia è dove stanno tutte le app di fitness,
dieta e meditazione. Navigazione è un bacino molto più piccolo, e chi lo sfoglia
sta cercando mappe.

Proposta: **secondaria da Sport a Navigazione**. La primaria può restare Salute
e benessere, che è quella di komoot e AllTrails.

### 2. Nessuna scheda in inglese, mentre l'app è tradotta per intero

`lib/l10n/` ha 2.076 chiavi in italiano e **2.076 in inglese**: l'interfaccia è
completa in entrambe. L'app risulta scaricabile da Stati Uniti, Francia,
Germania, Austria e Svizzera — ma in tutti quei negozi la scheda è quella
italiana.

Il pubblico giusto però **non** è "escursionisti del mondo": il dataset POI è
**per il 95% dentro i confini italiani** (1.087 punti su 21.556 stanno appena
oltre). Vendere un catalogo italiano a un austriaco produce recensioni brutte, e
con una recensione sola non ce lo possiamo permettere.

Il pubblico giusto è chi cerca **le montagne italiane in inglese**: turisti che
programmano le Dolomiti, stranieri che vivono qui. Scheda inglese sì, posizionata
su quello.

### 3. Promotional Text (App Store, 170 caratteri)

È l'unico campo che si cambia **senza inviare una nuova versione** né passare da
una revisione. Va sopra la descrizione. **Non è indicizzato**: nome, sottotitolo
e keyword fanno la ricerca, questo lavora solo sulla conversione di chi è già
arrivato sulla scheda.

Testo in uso dal 2026-08-09 (138/170):

```
Agosto è il mese dei rifugi aperti. Trovali sulla mappa, scarica il sentiero prima di partire e seguilo anche dove il telefono non prende.
```

Segue la stagione, che è il senso del campo. Chi arriva da `rifugi` — dodicesimo
posto, l'unico termine senza komoot e Wikiloc davanti — in agosto sta pianificando
una gita adesso, non fra sei mesi.

**Da cambiare a calendario**, perché un testo stagionale scaduto è peggio di uno
generico:

| Quando | Aggancio | Keyword che rinforza |
|---|---|---|
| fine settembre | chiusura rifugi, foliage, giornate corte | `sentieri`, `appennino` |
| prima neve | ciaspole — quattro app in classifica | `ciaspole` |
| aprile-maggio | riapertura, fondovalle, vie attrezzate | `ferrate` |

Evitare di legarlo a una versione (*"da questa versione..."*): il campo resta
finché non lo si tocca, e le novità di release hanno già il loro spazio.

Varianti scritte e misurate, se serve cambiare registro:

- differenziatore offline (144) — `Lassù la rete non c'è, la mappa sì: si scarica
  prima e resta sul telefono. Sentieri, rifugi e bivacchi delle Alpi, dal
  telefono o dall'orologio.`
- per la scheda inglese, quando esisterà (142) — `Italian mountains, mapped
  offline. Download the trail before you go and follow it where there is no
  signal — huts, bivouacs and 21,000 points.`

### 4. Custom Product Page per il traffico dei QR

Chi inquadra il QR di un rifugio arriva sulla scheda generica. Una pagina
variante che apra con gli screenshot dei rifugi convertirebbe meglio, e Apple ne
misura le installazioni separatamente — quindi si saprebbe se funziona invece di
supporlo. Si aggancia ai link `/r/qr_<slug>` già in produzione.

### 5. Gli screenshot

La leva più forte sulla conversione, più delle parole chiave: le parole ti fanno
trovare, gli screenshot decidono se ti installano. Non sono versionati nel repo,
quindi non li ho visti.

## Da rifare

Alla prossima release, e comunque quando il brief del lunedì segnala uno
spostamento. Le posizioni qui sopra sono la baseline: se `rifugi` scende sotto
il ventesimo posto è successo qualcosa.
