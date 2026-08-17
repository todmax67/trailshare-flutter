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
nascosto.

### La misura che mancava, e cosa dice

Fino al 2026-08-17 di Play non sapevamo nulla — il brief del lunedì lo
dichiarava ogni settimana come "non guardato", perché Google non ha un'API di
ricerca pubblica. **Non serve**: la pagina dei risultati porta i pacchetti
nell'ordine di posizionamento dentro l'HTML. Ora c'è `scripts/play_rank.py`,
gemello di `aso_rank.py`.

Prima misura (Play IT, 2026-08-17):

```
sentieri · rifugi · bivacchi · malghe · ciaspole · orobie · ferrate ·
escursioni · trekking · mappe offline · sentieri montagna · rifugi alpini
   → FUORI da tutti, sempre

trailshare
   → 1°
```

**Fuori da tutto il paniere**, comprese `bivacchi` e `rifugi alpini`, dove su
Apple siamo dodicesimi e ottavi. Primi sul nome dell'app: quindi la scheda **è
indicizzata**, e il problema è di posizionamento, non di presenza. Sono due
cose che si curano in modo molto diverso, e distinguerle è costato una ricerca
sola.

### Cosa insegna un'app da 100 installazioni

Cercando `sentieri` su Play compare al 7° posto **Sentieri** di Alfredo Panu:
+100 installazioni, nessun voto, categoria Strumenti. Davanti a noi, che di
installazioni ne abbiamo la metà — ma anche davanti a nessuno di importante,
mentre komoot e Wikiloc restano sopra.

La differenza misurabile fra la sua scheda e la nostra è **il titolo**:

| | titolo | posizione su `sentieri` |
|---|---|---|
| Sentieri | `Sentieri` — la query esatta | 7° |
| TrailShare | `TrailShare: sentieri e rifugi` (29/30) | fuori |

La parola ce l'abbiamo, e sta anche in apertura della descrizione breve
(`Sentieri, rifugi e bivacchi sulla mappa…`, 79/80). Quello che non abbiamo è
**la posizione**: la parte più forte del titolo la spendiamo su un marchio che
nessuno cerca. Wikiloc e komoot possono permetterselo; un'app da cinquanta
utenti no.

**Esperimento proponibile** — il primo dopo settimane di "zero esperimenti
proponibili", e possibile solo ora che sappiamo misurare:

> Invertire il titolo Play in `Sentieri e rifugi: TrailShare` (29/30), lasciando
> tutto il resto identico. Non è keyword stuffing — è lo stesso testo in un
> altro ordine — e non richiede una build: il titolo Play sta nella scheda.
> Rimisurare con `play_rank.py` dopo 7 e 14 giorni.

Onestà su cosa aspettarsi: **potrebbe non bastare.** Con cinquanta
installazioni il volume pesa comunque, e non è dimostrato che l'ordine delle
parole nel titolo conti quanto la corrispondenza esatta. Ma è reversibile in
trenta secondi, è misurabile, e finora non lo era — che è la differenza fra un
esperimento e un'opinione.

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

#### Su Play la conclusione è OPPOSTA, e vale la pena non sbagliarsi

Misurato il 2026-08-17 leggendo `applicationCategory` dal JSON-LD delle schede
Play (otto app su dieci tentate; PeakVisor e Terra Map non trovate con quei
package):

| Categoria Play | Chi c'è |
|---|---|
| **Salute e fitness** | komoot, AllTrails, Strava, **TrailShare** |
| Mappe e navigatori | Wikiloc, Gaia GPS |
| Info e viaggi locali | Outdooractive, OsmAnd |

**Play concede una categoria sola**, non due: non è aggiungere uno slot, è
uscire da una lista per entrare in un'altra. E lì non siamo l'anomalia — siamo
dove stanno i tre concorrenti più vicini.

Il ragionamento di sopra vale per Apple *proprio perché* i posti sono due: si
prende Navigazione senza rinunciare a Salute e benessere. Su Play lo stesso
gesto ci allontanerebbe da komoot e AllTrails per raggiungere Wikiloc.

Aggiungasi che a questi volumi l'argomento delle classifiche di categoria non
morde: si entra per download, e con qualche decina di utenti non si compare in
nessuna delle due liste. Su Play la categoria conta soprattutto per le
superfici "app simili", cioè per l'accostamento — e l'accostamento giusto oggi
è con le app di attività outdoor, non con i navigatori stradali.

**Quindi: si cambia su Apple, non su Play.** Cosa farebbe cambiare idea: se la
proposta diventasse davvero centrata sui rifugi (vedi la nota su un PRO
costruito sui rifugi), *Info e viaggi locali* tornerebbe in gioco — è dove
stanno Outdooractive e OsmAnd, cioè chi vende territorio più che allenamento.
Da rivalutare allora, con i numeri di allora.

**Su Apple il cambio richiede una nuova versione** — verificato in App Store
Connect il 2026-08-17. Non è modificabile al volo come la privacy policy: la
categoria viaggia con la release. Nessun costo aggiuntivo, visto che c'è
comunque una submission da fare, ma va ricordato al momento di prepararla o si
scopre che il campo è bloccato.

### 1b. I tag di Play

Play concede **cinque tag**, separati dalla categoria. Ogni tag porta con sé la
categoria a cui appartiene, quindi la scelta rinforza (o contraddice) il
posizionamento deciso sopra.

Com'erano al 2026-08-17:

```
Allenamento · Allenamento sportivo · Mappe e navigatori ·
Monitoraggio attività · Salute e fitness
```

**Tre slot su cinque descrivevano un'app di allenamento**, e uno era sprecato a
ripetere il nome della categoria. Chi veniva accostato a noi su quei segnali si
aspettava schede di allenamento e progressioni, non rifugi e mappe offline.
`Allenamento sportivo` è il peggiore: in inglese è *Sports training*, cioè
piani e coaching — roba che l'app non fa.

Set proposto:

| Tag | Perché |
|---|---|
| **Monitoraggio attività** | è letteralmente cosa fa: registra e misura |
| **Mappe e navigatori** | mappe offline e navigazione, senza cambiare categoria |
| **In corso** | è *Running* tradotto male da Google — copre il trail running |
| **Sci** | c'è la mappa invernale per lo scialpinismo, ed è poco affollato |
| **Guida turistica** | 21.000 POI e rifugi: l'unico che ci distingue invece di descrivere una categoria |

Da non usare: `Meteo`, `Perdita di peso`, `Dieta`, `Yoga`, `Meditazione` — sono
vicini nella lista perché condividono la categoria, ma descrivono un'app che
non siamo. È lo stesso errore delle keyword `traccia` e `offline` su Apple, che
ci accostavano al tracciamento pacchi. E `Corse` è ambiguo fra corsa e motori.

**Non è verificato che i tag muovano il posizionamento**: Google non lo
documenta, e potrebbero servire solo agli accostamenti "app simili" e ai
consigli. Costano cinque minuti, ma non aspettarsi l'effetto di un cambio di
keyword su Apple. Se dopo il cambio comparissero installazioni da "app simili"
nella Play Console, quello sarebbe il segnale.

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
