# Motore di crescita — Fase 1: l'analista

**LIVE dal 2026-07-31.** Deployata e verificata end-to-end lo stesso giorno:
raccolta, stesura via Claude e consegna su Telegram funzionano in produzione.
Scritta dopo aver verificato che ogni fonte citata esista e risponda davvero.

Codice nel repo `trailshare-ai-manager`:
`functions/src/services/market/{appStore,brief}.ts` e
`functions/src/scheduled/weeklyMarketBrief.ts`.

Decisioni del founder: keyword e competitor come proposti, **Reddit escluso**
(segnale troppo sottile in Italia per giustificare una sezione sempre vuota),
consegna il **lunedì alle 7:00**.

## Il rischio da evitare, prima di tutto

Un "analista AI" che genera brief di mercato dalle proprie convinzioni è
peggio di niente: produce affermazioni plausibili e sicure di sé che
indirizzano decisioni vere. "Il mercato outdoor si sta spostando verso X" è
una frase che un modello sa scrivere benissimo senza sapere nulla.

Quindi il vincolo di progetto è uno solo, e viene prima dell'architettura:

> **Ogni riga del brief deve risalire a un dato che è stato effettivamente
> scaricato o misurato.** Se una fonte non risponde, il brief lo dice e non
> riempie il buco.

Corollario: **"non è cambiato niente" è un brief valido.** Un analista che
trova sempre qualcosa di interessante è un analista che se lo inventa.

Il ruolo di Claude qui non è sapere cose. È leggere i numeri raccolti,
confrontarli con la settimana prima, e dire cosa merita attenzione.

## Cosa produce

Un documento settimanale, il lunedì mattina, fatto di quattro parti:

1. **Posizionamento negli store** — dove compare TrailShare cercando le
   keyword che contano, e come si è mosso rispetto a sette giorni fa
2. **Mosse dei competitor** — chi ha rilasciato cosa, con le note di rilascio
   vere, e come si muovono i loro voti
3. **Voce degli utenti** — le recensioni nuove, di TrailShare e dei competitor
4. **I nostri numeri** — il funnel da `growth_daily`, quando ci saranno

E si chiude con **1-3 esperimenti candidati**, non con "insight". Un brief su
cui nessuno agisce è lavoro sprecato: la Fase 2 li prende da lì.

## Le fonti, verificate il 2026-07-31

| Fonte | Cosa dà | Stato |
|---|---|---|
| iTunes Search API | Risultati di ricerca ordinati per keyword, storefront IT | ✅ verificata |
| iTunes Lookup API | Versione, data di rilascio, note, voti — nostri e dei competitor | ✅ verificata |
| RSS recensioni Apple | Testo delle recensioni per app id | ✅ verificata |
| `growth_daily` | Il nostro funnel per canale | ✅ esiste (dati dal rilascio 2.9.4) |
| ~~Reddit JSON~~ | ~~Menzioni nelle community~~ | escluso per decisione |

Gratis, senza chiavi, senza scraping.

Sulle recensioni una nota che cambia dove sta il valore: TrailShare ne ha
**zero scritte** (un solo voto). Il segnale quindi è quasi tutto nelle
recensioni dei **competitor**, ed è più ricco di quanto sembri. Nella prima
raccolta reale, otto recensioni Komoot in sette giorni contenevano: due utenti
diversi che chiedono di marcare i percorsi già fatti, lamentele sul
comportamento offline, indicazioni sbagliate per il punto di partenza, e più
di una reazione negativa all'acquisizione da parte di Bending Spoons con
funzioni di pianificazione tolte agli abbonati. Sono aperture competitive, non
statistiche.

### Il baseline, già misurato

Non un esempio ipotetico: la posizione reale di TrailShare nell'App Store
italiano, il 2026-07-31.

| Keyword | Posizione |
|---|---|
| **rifugi** | **11** |
| **wikiloc** | **8** |
| sentieri | 47 |
| trekking | fuori dai 100 |
| escursionismo | fuori dai 100 |
| mappe offline | fuori dai 100 |
| trail running | fuori dai 100 |
| mtb | fuori dai 100 |
| gps outdoor | fuori dai 100 |
| komoot | fuori dai 100 |

Tre cose che questo dice già oggi, e che nessuno aveva guardato:

- **`rifugi` alla 11 è l'asset più vicino alla superficie.** È anche il
  verticale dove il prodotto ha contenuto vero (18.500 POI) e dove passa il
  ground game. È la nicchia da presidiare, non `trekking`.
- **Il trucco delle keyword competitor funziona solo a metà**: `wikiloc`
  porta all'ottava posizione, `komoot` da nessuna parte.
- **Il nome non compra il posizionamento.** L'app si chiama "TrailShare —
  Sentieri GPS" e su `sentieri` è 47ª.

## Architettura

Nel repo `trailshare-ai-manager`, accanto a `growthDaily`:

```
functions/src/services/market/
  ├── appStore.ts      collettore: ranking, versioni, voti, recensioni
  └── brief.ts         confronto con la settimana prima + stesura via Claude

functions/src/scheduled/
  └── weeklyMarketBrief.ts    lunedì 7:00
```

Ogni collettore restituisce dati strutturati **oppure fallisce
esplicitamente**: nessun valore inventato per riempire un campo.

Le osservazioni grezze finiscono in `market_observations/{data}`, il brief in
`market_briefs/{data}`. La separazione serve a una cosa sola ma importante:
**il brief è un diff, non una fotografia**, e senza lo storico grezzo non si
può ricalcolare né correggere a posteriori.

Consegna su Telegram, come gli altri due report.

La prima settimana il brief sarà povero: non c'è un "prima" con cui
confrontare. È previsto, e va detto nel brief stesso invece di mascherarlo.

## Cosa NON entra in v1, e perché

- **Google Play**: nessuna API pubblica per ranking e recensioni. Servirebbe
  scraping, fragile e contro i termini. Metà del quadro manca, e va detto.
- **Google Trends**: nessuna API ufficiale. Le librerie non ufficiali si
  rompono senza preavviso e restituiscono silenziosamente dati vuoti — il
  modo peggiore di sbagliare.
- **Gruppi Facebook**: non accessibili senza login. Fuori portata.
- **Stime di volume di ricerca**: i dati affidabili sono a pagamento. Senza,
  qualunque numero sarebbe inventato.

## Costo

Una chiamata a Claude a settimana su poche migliaia di token: pochi centesimi
al mese. Le API Apple sono gratuite. Firebase, rumore di fondo.

Il costo vero sono i minuti che passi a leggere il brief. Se non lo leggi,
va spento.

## Il testo delle recensioni è dato, non istruzioni

Le recensioni finiscono dentro un prompt, e sono scritte da sconosciuti su app
di terzi. Chiunque può pubblicarne una che contiene istruzioni rivolte a un
modello.

Due difese, entrambe nel codice: il blocco è delimitato da marcatori espliciti
(`<<<DATI_NON_ISTRUZIONI>>>`), e il system prompt dice al modello di trattare
quel testo come contenuto da leggere, mai da eseguire, segnalando semmai
l'anomalia nel brief.

## Stato della verifica

Collettori provati in locale con chiamate vere: dieci keyword, sette app, otto
recensioni, **zero errori**.

Catena completa verificata in produzione il 2026-07-31, forzando il job da
Cloud Scheduler: il brief è arrivato su Telegram. Il secret
`ANTHROPIC_API_KEY`, già in uso da `weeklyAutoPost`, è risultato accessibile
anche a questa funzione.

## Correzioni dopo il primo brief reale (2026-07-31)

Il primo brief ha retto sui vincoli di progetto — nessuna affermazione
inventata, stato zero dichiarato, Android segnalato come non osservato,
recensioni attribuite al competitor giusto, controllo anti-iniezione riportato
in trasparenza. Ha però fatto emergere due difetti del codice.

**Il documento di oggi si ritrovava come "precedente".** La query
`orderBy('date','desc').limit(1)` non escludeva la data corrente, e l'id del
documento è la data: a una seconda esecuzione nello stesso giorno — un retry
dello scheduler, un run forzato a mano — l'osservazione si confrontava con sé
stessa. Diff vuoto per costruzione, finestra recensioni ridotta a "da
mezzanotte", e il documento più ricco sovrascritto dal più povero. Si è visto
subito: 8 recensioni raccolte in prova erano diventate 3. Risolto con
`where('date','<',today)`.

**Le note di rilascio venivano raccolte e buttate.** Finivano nel prompt solo
al cambio di versione, quindi mai alla prima osservazione. Il brief ha
scritto, correttamente, di non sapere cosa contenessero gli aggiornamenti dei
competitor — mentre il testo era già in memoria. Ora le note dell'ultima
versione entrano sempre.

La seconda correzione vale più di quanto sembri: le note di Komoot v2026.30.4
dicono *"Improved the stability of route planning"*, e nelle recensioni della
stessa settimana ci sono utenti che si lamentano proprio della pianificazione.
Il collegamento fra le due cose era invisibile al modello.

## Rifinitura del prompt dopo il secondo brief (2026-07-31)

Con le note di rilascio in mano, il secondo brief ha riportato che PeakVisor
ha aggiunto una ricerca mappa con **filtri rapidi per rifugi e acqua
potabile**, e che Wikiloc ha aggiunto la **condivisione con profilo
altimetrico verso Instagram e WhatsApp Stories**.

Sono i due fatti più rilevanti della settimana — un competitor entra nella
nicchia dove abbiamo la posizione migliore (`rifugi`, 11ª), un altro si
attrezza sul loop social che è il nostro motore di network effect dichiarato —
e nessuno dei due è finito fra le cose da provare. Il brief riportava le
sezioni in modo indipendente senza incrociarle.

Il secondo difetto era un esperimento non testabile: "comunicare la difficoltà
misurata sul campo" senza dire su quale canale, con "dovremmo vedere un
aumento di signup" come verifica — mentre i signup sono a zero perché la build
non è uscita, quindi qualunque movimento avrebbe avuto altre cause.

Due aggiunte al system prompt:

- **Incrociare le sezioni prima di scrivere gli esperimenti**, con tre esempi
  espliciti di incrocio che conta. Un fatto incrociato va detto anche quando
  non produce un esperimento.
- **Un esperimento vale solo se nomina canale, metrica, e perché un movimento
  sarebbe attribuibile a quello e non ad altro.** Se al terzo punto non si sa
  rispondere, non è proponibile. E zero esperimenti è dichiarato legittimo e
  frequente: il modello sa astenersi quando glielo si permette, e nel secondo
  brief lo aveva già fatto correttamente su uno dei due punti.
