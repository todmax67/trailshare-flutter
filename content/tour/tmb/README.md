# Tour du Mont Blanc — tappe 1-7 (versione "cuore italiano")

7 tappe consecutive (Les Houches → Champex-Lac) su 11 totali del giro classico:
esclude il rientro Champex→Forclaz→Tré-le-Champ→La Flégère→Les Houches (tappe
8-11), non ancora coperto da dati a licenza aperta.

## Attribuzione (obbligatoria)

- **Geometria del tracciato**: © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors,
  disponibile sotto [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/) —
  relazioni `route=hiking`, superroute "Tour du Mont-Blanc CCW" (OSM relation 6436417).
- **Elevazione**: [Open-Elevation](https://www.open-elevation.com/) (dataset SRTM).

Va riportata almeno nei crediti/scheda del Tour in-app quando questi tracciati
vengono pubblicati (non solo nel repo).

## Mappatura tappa → tratta

| # | File | Da | A | Paese | Km | D+ | D- | OSM relation |
|---|------|----|----|-------|----|----|----|-----|
| 1 | tmb_stage_01.gpx | Les Houches | Les Contamines-Montjoie | FR | 11,7 | 1207 | 1225 | [6427934](https://www.openstreetmap.org/relation/6427934) |
| 2 | tmb_stage_02.gpx | Les Contamines-Montjoie | Les Chapieux | FR | 15,5 | 1930 | 1554 | [6432158](https://www.openstreetmap.org/relation/6432158) |
| 3 | tmb_stage_03.gpx | Les Chapieux | Rifugio Elisabetta | FR→IT | 8,9 | 1314 | 911 | [6432812](https://www.openstreetmap.org/relation/6432812) |
| 4 | tmb_stage_04.gpx | Rifugio Elisabetta | Courmayeur | IT | 14,6 | 2336 | 1319 | [6432993](https://www.openstreetmap.org/relation/6432993) |
| 5 | tmb_stage_05.gpx | Courmayeur | Rifugio Walter Bonatti | IT | 8,9 | 1054 | 1903 | [6433450](https://www.openstreetmap.org/relation/6433450) |
| 6 | tmb_stage_06.gpx | Rifugio Walter Bonatti | La Fouly | IT→CH | 12,7 | 1953 | 2149 | [6433772](https://www.openstreetmap.org/relation/6433772) |
| 7 | tmb_stage_07.gpx | La Fouly | Champex-Lac | CH | 15,2 | 1318 | 1204 | [6433808](https://www.openstreetmap.org/relation/6433808) |
| | | | **Totale** | | **87,5 km** | **~11.100 m** | **~10.290 m** | |

Rifugi già a schema come Spazio Pro (unclaimed) su Val Veny/Courmayeur/Val
Ferret, agganciabili come `stageAccommodations`: Rifugio Elisabetta (tappa 3→4),
Combal e Monzino (variante alta tappa 4, opzionali), Rifugio Walter Bonatti
(tappa 5→6).

## Come sono stati generati

1. Geometria scaricata via Overpass API dalle relazioni OSM sopra elencate
   (escluse le sotto-relazioni con `role=alternate`).
2. Segmenti scollegati (varianti/rami non attinenti alla tappa) scartati,
   tenuto solo il tratto contiguo più lungo per ciascuna tappa.
3. Ricampionamento a un punto ogni ~25m.
4. Elevazione arricchita via Open-Elevation (i nodi OSM non la includono).

**Nota qualità**: la distanza è affidabile (deriva solo dalla geometria OSM).
Il D+/D- è una stima da DEM satellitare (SRTM) e tende a essere leggermente
gonfiato dal rumore su pendii ripidi rispetto a una traccia GPS reale
registrata sul campo — trattarlo come stima di pianificazione, non come dato
definitivo da marketing.
