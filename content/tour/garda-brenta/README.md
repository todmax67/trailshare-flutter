# Itinerario Garda Brenta — 7 tappe

Anello di 7 tappe nelle Prealpi del Garda Trentino e nelle Giudicarie, dal Garda
al bordo meridionale delle Dolomiti di Brenta e ritorno.

**Percorso ufficiale della SAT** (Società degli Alpinisti Tridentini), segnavia
`ref=GB`, mappato in OSM come 7 relazioni-tappa distinte.

## Attribuzione (obbligatoria)

- **Geometria**: © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors,
  [ODbL](https://opendatacommons.org/licenses/odbl/). Estratta da `italy-latest.osm.pbf`
  (Geofabrik, dati OSM del 2026-07-27) con `osmium getid -r`.
- **Elevazione**: [Open-Elevation](https://www.open-elevation.com/) (dataset SRTM),
  serie smussata e calibrata (vedi sotto).

## Le 7 tappe

| # | File | Da | A | Km | D+ | D- | Quote | OSM |
|---|------|----|----|----|----|----|-------|-----|
| 1 | `gb_stage_01.gpx` | Riva del Garda | Rifugio Nino Pernici | 13,2 | 1895 | 432 | 107→1570 | [2939860](https://www.openstreetmap.org/relation/2939860) |
| 2 | `gb_stage_02.gpx` | Rifugio Nino Pernici | Malga Stabio | 18,0 | 1364 | 1009 | 1610→1965 | [2945926](https://www.openstreetmap.org/relation/2945926) |
| 3 | `gb_stage_03.gpx` | Malga Stabio | Stenico | 15,0 | 648 | 1425 | 1447→670 | [2945917](https://www.openstreetmap.org/relation/2945917) |
| 4 | `gb_stage_04.gpx` | Stenico | Rifugio Al Cacciatore | 20,2 | 2123 | 791 | 668→2000 | [2948294](https://www.openstreetmap.org/relation/2948294) |
| 5 | `gb_stage_05.gpx` | Rifugio Al Cacciatore | Comano Terme | 20,5 | 724 | 1904 | 1829→651 | [2950997](https://www.openstreetmap.org/relation/2950997) |
| 6 | `gb_stage_06.gpx` | Comano Terme | Rifugio San Pietro | 19,9 | 1223 | 943 | 674→954 | [17245007](https://www.openstreetmap.org/relation/17245007) |
| 7 | `gb_stage_07.gpx` | Rifugio San Pietro | Varone | 18,1 | 766 | 1539 | 936→163 | [17245051](https://www.openstreetmap.org/relation/17245051) |
| | | | **Totale** | **124,9** | **8743** | | | |

È un **anello**: Varone è frazione di Riva del Garda, a 2,7 km dalla partenza.

## Rifugi già a catalogo (Spazi Pro)

Tutti `tier: unclaimed`, agganciabili subito come `stageAccommodations`:

| Rifugio | Tappa | businessId |
|---|---|---|
| Rifugio Bocca di Trat "Nino Pernici" | fine T1 / inizio T2 | `Q8YGsUyqQvkgwGneZOU7` |
| Rifugio Cacciatore | fine T4 / inizio T5 | `nIQa7bVQaoYtSXzrEOd8` |
| Rifugio San Pietro | fine T6 / inizio T7 | `hKZecQEjUViSAwdfd7QT` |

Malga Stabio non risulta a catalogo: da aggiungere a mano se serve come tappa.

## Buchi da ricucire col pianificatore

Le relazioni OSM non sono complete. **Le distanze sono affidabili** (derivano
dalla geometria), ma la traccia va ricucita in questi punti:

### Giunzioni fra tappe

| Giunzione | Presso | Distacco | Stato |
|---|---|---|---|
| T1 → T2 | Rif. Nino Pernici | 0 m | ✅ continua |
| T2 → T3 | Malga Stabio | **3,25 km** | ❌ scollegata |
| T3 → T4 | Stenico | 60 m | ✅ continua |
| T4 → T5 | Rif. Al Cacciatore | **3,58 km** | ❌ scollegata |
| T5 → T6 | Comano Terme | 140 m | ✅ continua |
| T6 → T7 | Rif. San Pietro | 580 m | ⚠️ da ricucire |

Le tappe 2 e 4 **oltrepassano** il loro punto d'arrivo nominale: la T2 arriva a
1965 m (la cresta del Cadria, max 2113 m) mentre Malga Stabio sta a ~1447 m; la
T4 arriva a 2000 m con un massimo di 2233 m mentre il Rif. Al Cacciatore sta a
~1820 m. È la stessa causa dei distacchi: nelle due relazioni ci sono rami che
proseguono oltre l'arrivo.

### Buchi interni alle tappe

| Tappa | Buco | Posizione |
|---|---|---|
| 2 | 809 m | [45.9967, 10.7514](https://www.openstreetmap.org/#map=16/45.9967/10.7514) |
| 2 | 2500 m | [46.0178, 10.7782](https://www.openstreetmap.org/#map=16/46.0178/10.7782) |
| 3 | 125 m | [46.0178, 10.7782](https://www.openstreetmap.org/#map=16/46.0178/10.7782) |
| 4 | 56 m | [46.0522, 10.8542](https://www.openstreetmap.org/#map=16/46.0522/10.8542) |
| 4 | 1041 m | [46.1040, 10.8530](https://www.openstreetmap.org/#map=16/46.1040/10.8530) |
| 4 | 2877 m | [46.1301, 10.8801](https://www.openstreetmap.org/#map=16/46.1301/10.8801) |
| 6 | 143 m | [46.0366, 10.8942](https://www.openstreetmap.org/#map=16/46.0366/10.8942) |
| 7 | 584 m | [45.9328, 10.8382](https://www.openstreetmap.org/#map=16/45.9328/10.8382) |

## Come sono stati generati

1. Estrazione delle 7 relazioni da `italy-latest.osm.pbf` in locale con
   `osmium getid -r` (7 secondi; l'API Overpass pubblica era satura su tutti i
   mirror). In locale si ha anche l'**ordine reale dei membri** della relazione,
   quindi la concatenazione segue la sequenza autorevole invece di indovinarla
   col nearest-endpoint.
2. Ricampionamento a un punto ogni ~25 m.
3. Elevazione da Open-Elevation (i nodi OSM non la portano).
4. **Correzione del verso**: le tappe 1 e 5 risultavano invertite rispetto al
   loro `from → to`. Ora ogni tappa parte dove finisce la precedente.
5. **Calibrazione del dislivello** (vedi sotto).

### Nota sul dislivello — leggere prima di usare i numeri

Il D+ grezzo da SRTM campionato ogni 25 m era **18.805 m** (151 m/km): assurdo.
Causa: l'errore verticale del DEM (±5-10 m) è maggiore del dislivello reale fra
due punti così vicini, e sommato lungo migliaia di punti produce dislivello
fantasma.

La serie è stata smussata (media mobile a 9 punti, soglia 5 m) **calibrando sul
riferimento esterno della tappa 1**, per cui esistono due dati indipendenti:
AllTrails 1.886 m e Garda Outdoor ~1.550 m. La calibrazione scelta produce
1.895 m, cioè il valore AllTrails — metodologicamente confrontabile perché
anch'esso derivato da DEM/GPS. Le guide cartacee tendono a dare valori più bassi.

Totale calibrato: **8.743 m** (70 m/km), coerente col terreno prealpino.

**Resta comunque una stima.** All'import in app l'`ElevationProcessor` ricalcola
con smoothing e scarto degli spike: quel numero è l'autorevole, non questo.
